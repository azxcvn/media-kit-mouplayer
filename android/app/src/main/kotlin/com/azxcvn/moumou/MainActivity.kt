package com.azxcvn.moumou

import android.database.Cursor
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.util.LruCache
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "moumou/video_info"

    /**
     * 任意时刻抓帧的内存缓存（约 24 MB）：key = path|timeBucketMs|maxWidth。
     * MediaMetadataRetriever 解码较慢，拖动进度条预览时靠它避免重复解码。
     */
    private val frameCache = object : LruCache<String, ByteArray>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ByteArray): Int = value.size
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 崩溃日志自动记录（未捕获异常 → files/crash_logs/）
        CrashHandler.init(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVideoInfo" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_ARG", "path is null", null)
                        } else {
                            // 耗时解码放到后台线程，避免阻塞 UI 线程
                            Thread {
                                val info = getVideoInfo(path)
                                runOnUiThread { result.success(info) }
                            }.start()
                        }
                    }
                    // 列表字段「帧率 / 字幕指示器」：MediaInfoLib 快速解析 + 磁盘缓存
                    "getVideoBasicMetadata" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_ARG", "path is null", null)
                        } else {
                            Thread {
                                val meta = getVideoBasicMetadata(path)
                                runOnUiThread { result.success(meta) }
                            }.start()
                        }
                    }
                    // 媒体信息页：MediaInfoLib 完整解析（通用/视频/音频/字幕流）
                    "getMediaInfo" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_ARG", "path is null", null)
                        } else {
                            Thread {
                                val info = MediaInfoHelper.getMediaInfo(this, path)
                                runOnUiThread { result.success(info) }
                            }.start()
                        }
                    }
                    "getVideos" -> result.success(getVideos())
                    "getSystemVolume" -> result.success(getSystemVolume())
                    "setSystemVolume" -> {
                        setSystemVolume(call.argument<Double>("volume") ?: 0.0)
                        result.success(null)
                    }
                    "getBrightness" -> result.success(getBrightness())
                    "setWindowBrightness" -> {
                        setWindowBrightness(call.argument<Double>("brightness") ?: -1.0)
                        result.success(null)
                    }
                    "getVideoFrameAt" -> {
                        val path = call.argument<String>("path")
                        // 注意：Dart 小整数经 MethodChannel 编码后是 Integer 而非 Long，
                        // 用 Number 兼容，避免 ClassCastException（历史 bug 根因）
                        val timeMs = call.argument<Number>("timeMs")?.toLong() ?: 0L
                        val maxWidth = call.argument<Int>("maxWidth") ?: 320
                        if (path == null) {
                            result.error("INVALID_ARG", "path is null", null)
                        } else {
                            // 硬解解码耗时，后台线程执行
                            Thread {
                                val key = "$path|$timeMs|$maxWidth"
                                val cached = frameCache.get(key)
                                val bytes = if (cached != null) {
                                    cached
                                } else {
                                    extractFrameAt(path, timeMs, maxWidth)
                                        ?.also { frameCache.put(key, it) }
                                }
                                Log.d(
                                    "MoumouThumb",
                                    "getVideoFrameAt path=$path timeMs=$timeMs w=$maxWidth" +
                                        " -> ${if (bytes == null) "NULL" else "${bytes.size}B"}",
                                )
                                runOnUiThread { result.success(bytes) }
                            }.start()
                        }
                    }
                    "getCacheSizes" -> result.success(getCacheSizes())
                    "clearCache" -> {
                        clearCache(call.argument<String>("category") ?: "")
                        result.success(null)
                    }
                    "clearAllCaches" -> {
                        clearAllCaches()
                        result.success(null)
                    }
                    "getCrashLogDir" -> result.success(logDir().absolutePath)
                    "listCrashLogs" -> result.success(listLogs())
                    "readCrashLog" -> {
                        result.success(readLog(call.argument<String>("path") ?: ""))
                    }
                    "deleteCrashLog" -> {
                        result.success(deleteLog(call.argument<String>("path") ?: ""))
                    }
                    "clearCrashLogs" -> result.success(clearLogs())
                    "exportCrashLog" -> {
                        result.success(exportLog(call.argument<String>("path") ?: ""))
                    }
                    // Dart 侧未捕获异常 → 追加到崩溃日志目录（flutter_*.log）
                    "appendDartLog" -> {
                        val content = call.argument<String>("content") ?: ""
                        appendDartLog(content)
                        result.success(null)
                    }
                    // 包（video_thumbnail_plus）成功抓到的帧也写入磁盘缓存，
                    // 保证「进度条缩略图」磁盘占用非 0、重开视频零解码
                    "putVideoFrame" -> {
                        val path = call.argument<String>("path")
                        // 与 getVideoFrameAt 相同：Dart 小整数是 Integer，用 Number 兼容
                        val timeMs = call.argument<Number>("timeMs")?.toLong() ?: 0L
                        val maxWidth = call.argument<Int>("maxWidth") ?: 320
                        val bytes = call.argument<ByteArray>("bytes")
                        // 捕获到 lambda 前先落成非空局部，避免智能转换失效
                        val safePath = path
                        val safeBytes = bytes
                        if (safePath != null && safeBytes != null && safeBytes.size > 0) {
                            Log.d(
                                "MoumouThumb",
                                "putVideoFrame ${safeBytes.size}B path=$safePath t=$timeMs w=$maxWidth",
                            )
                            Thread {
                                writeThumbToDisk(thumbCacheFile(safePath, timeMs, maxWidth), safeBytes)
                                runOnUiThread { result.success(null) }
                            }.start()
                        } else {
                            Log.d("MoumouThumb", "putVideoFrame SKIPPED bytes=${bytes?.size}")
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── 错误日志（崩溃日志自动记录）────────────────────────

    /** 日志目录：files/crash_logs/ */
    private fun logDir(): File = CrashHandler.logDir(this)

    /** 列出全部日志文件（按修改时间倒序） */
    private fun listLogs(): List<Map<String, Any>> {
        val dir = logDir()
        if (!dir.exists() || !dir.isDirectory) return emptyList()
        return dir.listFiles()
            ?.filter { it.isFile && it.name.endsWith(".txt") }
            ?.sortedByDescending { it.lastModified() }
            ?.map { f ->
                mapOf(
                    "name" to f.name,
                    "path" to f.absolutePath,
                    "size" to f.length(),
                    "lastModified" to f.lastModified(),
                )
            }
            ?: emptyList()
    }

    /** 读取日志文件内容（UTF-8，失败返回错误信息） */
    private fun readLog(path: String): String {
        return try {
            File(path).readText()
        } catch (e: Exception) {
            "读取日志失败：${e.message}"
        }
    }

    /** 删除单个日志文件 */
    private fun deleteLog(path: String): Boolean {
        return try {
            File(path).delete()
        } catch (e: Exception) {
            false
        }
    }

    /** 清空全部日志 */
    private fun clearLogs(): Boolean {
        return try {
            val dir = logDir()
            if (!dir.exists() || !dir.isDirectory) return true
            var ok = true
            dir.listFiles()?.forEach { f ->
                if (f.isFile && !f.delete()) ok = false
            }
            ok
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 导出日志到系统公共 Download 目录（App 有「管理所有文件」权限，
     * 可直写 /storage/emulated/0/Download/moumou_logs/），返回新路径。
     */
    private fun exportLog(path: String): String? {
        return try {
            val src = File(path)
            if (!src.exists()) return null
            val downloads =
                android.os.Environment.getExternalStoragePublicDirectory(
                    android.os.Environment.DIRECTORY_DOWNLOADS
                )
            val outDir = File(downloads, "moumou_logs")
            if (!outDir.exists()) outDir.mkdirs()
            val dst = File(outDir, src.name)
            src.copyTo(dst, overwrite = true)
            dst.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Dart 侧未捕获异常日志：写入 `files/crash_logs/flutter_yyyy-MM-dd.log`，
     * 与原生崩溃日志同一目录（错误日志页统一展示）。
     */
    private fun appendDartLog(content: String) {
        try {
            val dir = logDir()
            if (!dir.exists()) dir.mkdirs()
            val timestamp = java.text.SimpleDateFormat(
                "yyyy-MM-dd", java.util.Locale.getDefault()
            ).format(java.util.Date())
            val file = File(dir, "flutter_$timestamp.log")
            file.appendText("\n$content\n")
        } catch (e: Exception) {
            Log.w("DartLog", "appendDartLog failed: ${e.message}")
        }
    }

    // ── 音量（系统媒体音量，0 – 100 百分比）────────────────

    private fun getSystemVolume(): Double {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        return if (max > 0) {
            am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max * 100.0
        } else {
            0.0
        }
    }

    /** 写入系统媒体音量（0 – 100）；[AudioManager.setStreamVolume] 需 MODIFY_AUDIO_SETTINGS（normal 权限） */
    private fun setSystemVolume(percent: Double) {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return
        val target = (percent.coerceIn(0.0, 100.0) / 100.0 * max).toInt().coerceIn(0, max)
        am.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
    }

    // ── 亮度（窗口亮度，只影响当前 Activity，无需任何权限）──

    /**
     * 读取当前有效亮度：窗口已设亮度优先，否则读系统亮度。
     * 返回 0 – 1；读取失败返回 -1（表示未知，调用方按系统默认处理）。
     */
    private fun getBrightness(): Double {
        val attrs = window.attributes
        if (attrs.screenBrightness >= 0f) return attrs.screenBrightness.toDouble()
        return try {
            Settings.System.getInt(
                contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
            ).toDouble() / 255.0
        } catch (e: Exception) {
            -1.0
        }
    }

    /** 设置窗口亮度（0 – 1）；传 < 0 恢复系统默认。退出播放后必须恢复。 */
    private fun setWindowBrightness(value: Double) {
        val attrs = window.attributes
        attrs.screenBrightness = if (value < 0) -1f else value.toFloat().coerceIn(0f, 1f)
        window.attributes = attrs
    }

    // ── 任意时刻抓帧（本地视频）────────────────────────────

    /**
     * 提取本地视频 [path] 在 [timeMs]（毫秒）时刻的画面，压缩为 JPEG 字节。
     *
     * - **磁盘缓存**：按 视频路径 hash + lastModified + 秒桶 + 宽度 落盘
     *   （`cacheDir/thumbs/`），命中即读文件，零解码；
     * - **解码**：先 OPTION_CLOSEST_SYNC（快），失败/异常再 OPTION_CLOSEST
     *   （精确、可靠）——两者必须**各自独立 try/catch**，否则 SYNC 抛异常会
     *   跳过 CLOSEST（历史 bug：表现为永远转圈）；
     * - 成功后落盘；写入后按写入次数触发自动清理（>200MB 清到 50MB）。
     */
    private fun extractFrameAt(path: String, timeMs: Long, maxWidth: Int): ByteArray? {
        val cacheFile = thumbCacheFile(path, timeMs, maxWidth)
        if (cacheFile.exists()) {
            val cached = runCatching { cacheFile.readBytes() }.getOrNull()
            if (cached != null && cached.isNotEmpty()) {
                Log.d("MoumouThumb", "extractFrameAt DISK-HIT ${cached.size}B path=$path t=$timeMs")
                return cached
            }
            // 空/损坏缓存：删除后重新解码（否则该桶永久转圈）
            runCatching { cacheFile.delete() }
            Log.d("MoumouThumb", "extractFrameAt DISK-EMPTY-DELETED path=$path t=$timeMs")
        }

        val bitmap = grabFrameWithRetriever(path, timeMs, maxWidth)
        if (bitmap == null) {
            Log.d("MoumouThumb", "extractFrameAt DECODE-NULL path=$path t=$timeMs")
            return null
        }

        val out = ByteArrayOutputStream()
        // 压缩质量 60：进度条缩略图只用于拖动预览（宽 160 显示），
        // 降质后单帧更小（约 40%），缓存体积随之缩小（参考项目为 384×216 + q85）
        bitmap.compress(Bitmap.CompressFormat.JPEG, 60, out)
        val bytes = out.toByteArray()
        bitmap.recycle()
        writeThumbToDisk(cacheFile, bytes)
        Log.d("MoumouThumb", "extractFrameAt OK ${bytes.size}B path=$path t=$timeMs")
        maybeAutoCleanCache()
        return bytes
    }

    /** 缩略图磁盘缓存文件（key 带 lastModified：文件被替换/修改后自动失效） */
    private fun thumbCacheFile(path: String, timeMs: Long, maxWidth: Int): File {
        val dir = File(cacheDir, "thumbs")
        if (!dir.exists()) dir.mkdirs()
        return File(
            dir,
            "${path.hashCode()}_${File(path).lastModified()}_${timeMs}_$maxWidth.jpg",
        )
    }

    /** 写缩略图到磁盘（失败静默；先写临时文件再改名，避免中断产生半截坏文件） */
    private fun writeThumbToDisk(cacheFile: File, bytes: ByteArray) {
        runCatching {
            val tmp = File(cacheFile.parentFile, cacheFile.name + ".tmp")
            FileOutputStream(tmp).use { o ->
                o.write(bytes)
                o.flush()
            }
            if (!tmp.renameTo(cacheFile)) {
                // 改名失败（极少数）：直接写目标文件兜底
                tmp.delete()
                FileOutputStream(cacheFile).use { o ->
                    o.write(bytes)
                    o.flush()
                }
            }
        }
    }

    /** MediaMetadataRetriever 抓帧：SYNC 快、CLOSEST 稳，各自独立容错 */
    private fun grabFrameWithRetriever(
        path: String,
        timeMs: Long,
        maxWidth: Int,
    ): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val timeUs = timeMs * 1000
            // 各自独立 try/catch：SYNC 抛异常不能跳过 CLOSEST
            @Suppress("DEPRECATION")
            var bitmap = try {
                retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            } catch (e: Exception) {
                null
            }
            if (bitmap == null) {
                @Suppress("DEPRECATION")
                bitmap = try {
                    retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                } catch (e: Exception) {
                    null
                }
            }
            if (bitmap == null) return null
            if (bitmap.width <= maxWidth) {
                bitmap
            } else {
                val scale = maxWidth.toFloat() / bitmap.width
                val scaled = Bitmap.createScaledBitmap(
                    bitmap,
                    maxWidth,
                    (bitmap.height * scale).toInt().coerceAtLeast(1),
                    true,
                )
                if (scaled !== bitmap) bitmap.recycle()
                scaled
            }
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    // ── 缩略图缓存管理（自动清理 + 手动清理）───────────────

    /** 自动清理阈值：超过 200MB 开始清理，清到 50MB 为止 */
    private val autoCleanMaxBytes = 200L * 1024 * 1024
    private val autoCleanTargetBytes = 50L * 1024 * 1024

    /** 每写入 N 帧检查一次总量（避免每次写都扫目录） */
    private var autoCleanWriteCount = 0

    private fun thumbsDir(): File =
        File(cacheDir, "thumbs").apply { if (!exists()) mkdirs() }

    /** 缩略图分类：文件名下划线段数 ≥3 为进度条缩略图（hash_mod_bucket_width.jpg），否则为列表封面 */
    private fun isScrubThumb(name: String): Boolean = name.count { it == '_' } >= 3

    private fun maybeAutoCleanCache() {
        if (++autoCleanWriteCount % 30 != 0) return
        val files = thumbsDir().listFiles()?.filter { it.isFile } ?: return
        if (files.isEmpty()) return
        var total = files.sumOf { it.length() }
        if (total <= autoCleanMaxBytes) return
        // 按最后修改时间从旧到新删除，直到低于目标
        files.sortedBy { it.lastModified() }.forEach { f ->
            if (total <= autoCleanTargetBytes) return
            if (f.delete()) total -= f.length()
        }
    }

    /** 各类别缓存占用（字节） */
    private fun getCacheSizes(): Map<String, Long> {
        var scrub = 0L
        var list = 0L
        thumbsDir().listFiles()?.forEach { f ->
            if (f.isFile) {
                if (isScrubThumb(f.name)) scrub += f.length() else list += f.length()
            }
        }
        // 未来类别（弹幕/字幕等）尚未启用，恒为 0
        return mapOf("scrubThumbs" to scrub, "listThumbs" to list, "other" to 0L)
    }

    /** 清除指定类别缓存 */
    private fun clearCache(category: String) {
        when (category) {
            "scrubThumbs" -> thumbsDir().listFiles()?.forEach {
                if (it.isFile && isScrubThumb(it.name)) it.delete()
            }
            "listThumbs" -> thumbsDir().listFiles()?.forEach {
                if (it.isFile && !isScrubThumb(it.name)) it.delete()
            }
            // "other"：未来类别（弹幕/字幕），暂无可清
        }
    }

    /** 一键清除所有缓存（缩略图 + 内存帧缓存；未来类别同清） */
    private fun clearAllCaches() {
        thumbsDir().listFiles()?.forEach { it.delete() }
        frameCache.evictAll()
    }

    // ── 列表基本元数据（帧率 / 字幕，MediaInfoLib + 磁盘缓存）───────

    /** 基本元数据磁盘缓存目录（JSON 按 path+lastModified 分文件） */
    private fun metaCacheFile(path: String): File {
        val dir = File(cacheDir, "metainfo")
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "${path.hashCode()}_${File(path).lastModified()}.json")
    }

    /**
     * 列表字段「帧率 / 字幕指示器」数据：MediaInfoLib 快速解析，
     * 结果落盘缓存（重开视频零解析）。失败返回空 Map（字段不显示）。
     */
    private fun getVideoBasicMetadata(path: String): Map<String, Any> {
        val cacheFile = metaCacheFile(path)
        if (cacheFile.exists()) {
            val cached = runCatching { cacheFile.readText() }.getOrNull()
            if (cached != null && cached.isNotEmpty()) {
                // 缓存是 JSON：反序列化为 Map
                val parsed = runCatching {
                    org.json.JSONObject(cached)
                }.getOrNull()
                if (parsed != null) {
                    return mapOf(
                        "frameRate" to parsed.optDouble("frameRate", 0.0),
                        "hasSubtitles" to parsed.optBoolean("hasSubtitles", false),
                        "subtitleCodec" to parsed.optString("subtitleCodec", ""),
                    )
                }
            }
        }

        val meta = MediaInfoHelper.extractBasicMetadata(this, path)
        if (meta.isNotEmpty()) {
            runCatching {
                val obj = org.json.JSONObject()
                obj.put("frameRate", meta["frameRate"] as? Number ?: 0.0)
                obj.put("hasSubtitles", meta["hasSubtitles"] as? Boolean ?: false)
                obj.put("subtitleCodec", meta["subtitleCodec"] as? String ?: "")
                // 原子写入：先写临时文件再改名
                val tmp = File(cacheFile.parentFile, cacheFile.name + ".tmp")
                java.io.FileOutputStream(tmp).use { o ->
                    o.write(obj.toString().toByteArray())
                    o.flush()
                }
                if (!tmp.renameTo(cacheFile)) {
                    tmp.delete()
                    java.io.FileOutputStream(cacheFile).use { o ->
                        o.write(obj.toString().toByteArray())
                        o.flush()
                    }
                }
            }
        }
        return meta
    }

    // ── 列表缩略图（优化：等比缩放 + 16:9 居中裁剪 + 低质量 JPEG）──────

    /**
     * 列表封面缩略图目标尺寸（参考项目 ThumbnailCacheManager 的 384×216，
     * 等比缩放填满后居中裁剪为 16:9，宽高比一致的卡片封面观感统一）。
     */
    private val coverThumbWidth = 384
    private val coverThumbHeight = 216

    private fun getVideoInfo(path: String): Map<String, Any?> {
        val dir = File(cacheDir, "thumbs")
        if (!dir.exists()) dir.mkdirs()
        // 以 path + lastModified 作为缓存 key：文件被替换/修改后自动失效。
        // 带 `_v2` 标记：v2 起封面改为 等比缩放+居中裁剪，旧版拉伸封面自动失效重建
        val cacheFile = File(dir, "${path.hashCode()}_${File(path).lastModified()}_v2.jpg")
        // 磁盘缓存命中：直接返回，完全跳过 MediaMetadataRetriever 解码
        // （时长由 MediaStore 提供，列表不需要这里的 duration）
        if (cacheFile.exists()) {
            return mapOf("durationMs" to 0L, "thumbPath" to cacheFile.absolutePath)
        }

        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L

            @Suppress("DEPRECATION")
            val bitmap = retriever.getFrameAtTime(
                0,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            )
            val thumbPath = if (bitmap != null) {
                val cover = cropCover(bitmap)
                if (cover !== bitmap) bitmap.recycle()
                FileOutputStream(cacheFile).use { out ->
                    cover.compress(Bitmap.CompressFormat.JPEG, 70, out)
                }
                cover.recycle()
                cacheFile.absolutePath
            } else {
                null
            }

            mapOf(
                "durationMs" to durationMs,
                "thumbPath" to thumbPath,
            )
        } catch (e: Exception) {
            mapOf("durationMs" to 0L, "thumbPath" to null)
        } finally {
            retriever.release()
        }
    }

    /**
     * 等比缩放填满 16:9 目标区后居中裁剪（与参考项目封面算法一致）。
     *
     * 关键：先按「被填满的那个维度」等比缩放（高度填满或宽度填满），
     * 再居中裁剪超出部分——保证画面不变形（横屏/竖屏/超宽屏均不失真）。
     */
    private fun cropCover(src: Bitmap): Bitmap {
        val srcWidth = src.width
        val srcHeight = src.height
        if (srcWidth <= 0 || srcHeight <= 0) return src
        val targetRatio = coverThumbWidth.toFloat() / coverThumbHeight // 384/216 ≈ 1.7778
        val srcRatio = srcWidth.toFloat() / srcHeight

        val scaledWidth: Int
        val scaledHeight: Int
        if (srcRatio > targetRatio) {
            // 源更宽（横屏/超宽屏）：按高度填满，宽度等比放大后居中裁剪
            scaledHeight = coverThumbHeight
            scaledWidth = (srcWidth * coverThumbHeight.toFloat() / srcHeight).toInt()
        } else {
            // 源更高（竖屏/方屏）：按宽度填满，高度等比放大后居中裁剪
            scaledWidth = coverThumbWidth
            scaledHeight = (srcHeight * coverThumbWidth.toFloat() / srcWidth).toInt()
        }

        val scaled = Bitmap.createScaledBitmap(src, scaledWidth, scaledHeight, true)
        val x = ((scaledWidth - coverThumbWidth) / 2).coerceAtLeast(0)
        val y = ((scaledHeight - coverThumbHeight) / 2).coerceAtLeast(0)
        val final = Bitmap.createBitmap(
            scaled, x, y,
            minOf(coverThumbWidth, scaledWidth),
            minOf(coverThumbHeight, scaledHeight),
        )
        if (scaled !== final) scaled.recycle()
        return final
    }

    /** 通过 MediaStore 查询所有本地视频（快，系统索引） */
    private fun getVideos(): List<Map<String, Any>> {
        val videos = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
            MediaStore.Video.Media.DATE_MODIFIED,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.RELATIVE_PATH,
        )
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }
        val cursor: Cursor? = contentResolver.query(
            collection, projection, null, null,
            "${MediaStore.Video.Media.DATE_ADDED} DESC"
        )
        cursor?.use { c ->
            val nameCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
            val durCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
            val sizeCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
            val widthCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.WIDTH)
            val heightCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.HEIGHT)
            val dateCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_MODIFIED)
            val dataCol = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                c.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
            } else -1
            val relCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                c.getColumnIndexOrThrow(MediaStore.Video.Media.RELATIVE_PATH)
            } else -1

            while (c.moveToNext()) {
                val name = c.getString(nameCol) ?: continue
                val duration = c.getLong(durCol)
                val size = c.getLong(sizeCol)
                val width = c.getInt(widthCol)
                val height = c.getInt(heightCol)
                val dateModified = c.getLong(dateCol) * 1000L // 秒 → 毫秒

                val path = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val rel = if (relCol >= 0) c.getString(relCol) ?: "" else ""
                    "/storage/emulated/0/$rel$name"
                } else {
                    c.getString(dataCol) ?: continue
                }

                videos.add(
                    mapOf(
                        "path" to path,
                        "name" to name,
                        "durationMs" to duration,
                        "size" to size,
                        "width" to width,
                        "height" to height,
                        "dateModifiedMs" to dateModified,
                    )
                )
            }
        }
        return videos
    }
}
