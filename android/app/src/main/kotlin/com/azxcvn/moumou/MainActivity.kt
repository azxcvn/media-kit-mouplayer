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
        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
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

    // ── 列表缩略图（原有逻辑，未改动）──────────────────────

    private fun getVideoInfo(path: String): Map<String, Any?> {
        val dir = File(cacheDir, "thumbs")
        if (!dir.exists()) dir.mkdirs()
        // 以 path + lastModified 作为缓存 key：文件被替换/修改后自动失效
        val cacheFile = File(dir, "${path.hashCode()}_${File(path).lastModified()}.jpg")
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
                FileOutputStream(cacheFile).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
                }
                bitmap.recycle()
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
