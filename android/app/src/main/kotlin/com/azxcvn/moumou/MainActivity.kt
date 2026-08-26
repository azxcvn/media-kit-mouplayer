package com.azxcvn.moumou

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.database.Cursor
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import android.util.Rational
import android.view.View
import androidx.documentfile.provider.DocumentFile
import com.yubyf.truetypeparser.TTFFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "moumou/video_info"

    /**
     * 系统文件选择器（ACTION_OPEN_DOCUMENT）的待回结果：
     * invokeMethod 无法同步跨 onActivityResult 返回，先把 result 暂存，
     * onActivityResult 里再 complete（返回 content:// uri 字符串或 null）。
     */
    private var pendingDocumentPickerResult: MethodChannel.Result? = null

    /** 字体目录选择器（ACTION_OPEN_DOCUMENT_TREE）的待回结果。 */
    private var pendingFontDirPickerResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Flutter 首帧前按 App 主题设置系统导航栏（三大金刚键区域）颜色，
        // 避免深色/AMOLED 下启动阶段露出白底；首帧后由 Dart 侧 SystemChrome 接管
        applySystemBarStyle()
    }

    // ── 系统导航栏颜色（三大金刚键区域）────────────

    /**
     * 按 App 主题模式设置系统导航栏颜色：深色/AMOLED → 黑底白键；浅色 → 浅底深键。
     *
     * 主题模式读取 Dart 侧 ThemeController 持久化的 theme_mode
     * （shared_preferences 在 Android 存于 FlutterSharedPreferences，
     * 键带 `flutter.` 前缀；0=system 1=light 2=dark 3=amoled），
     * system/未设置时跟随系统深色模式。
     *
     * 注意：targetSdk 35+ 强制 edge-to-edge 时该颜色被系统忽略（系统栏透明），
     * 这里作为启动闪屏期与旧系统路径的兜底；实际可见效果由 Dart 侧
     * SystemChrome.setSystemUIOverlayStyle 保证。
     */
    private fun applySystemBarStyle() {
        // 启动路径绝不允许崩溃：读取失败/类型异常一律降级为 system 模式，
        // 否则 onCreate 抛异常会形成「每次启动必崩」的崩溃循环（debug/release 同理）。
        try {
            // API 29+ 默认 isNavigationBarContrastEnforced=true：系统会在导航栏上
            // 叠加半透明对比度 scrim，把纯黑底刷成灰白（深色/AMOLED 下三大金刚键
            // 区域发灰的根因）。关闭后 navigationBarColor 精确生效（内联 SDK 判断
            // 防 lint NewApi 报错）。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                window.isNavigationBarContrastEnforced = false
            }
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            // 关键坑：shared_preferences 在 Android 把 Dart 的 int 一律存为 Long
            // （Dart int 是 64 位，插件 setInt → putLong）。若用 prefs.getInt(...) 读，
            // SharedPreferencesImpl 直接抛 ClassCastException: Long cannot be cast to
            // Integer（历史启动崩溃根因）。这里从 all 取值做类型兼容读取：
            // Int / Long 都接受，其余类型/缺失按「未设置(-1)」处理。
            val mode = when (val v = prefs.all["flutter.theme_mode"]) {
                is Int -> v
                is Long -> v.toInt()
                else -> -1
            }
            val isDark = when (mode) {
                2, 3 -> true // dark / amoled
                1 -> false // light
                else -> { // system / 未设置：跟随系统
                    val night = resources.configuration.uiMode and
                        Configuration.UI_MODE_NIGHT_MASK
                    night == Configuration.UI_MODE_NIGHT_YES
                }
            }
            @Suppress("DEPRECATION")
            window.navigationBarColor = if (isDark) {
                android.graphics.Color.BLACK
            } else {
                android.graphics.Color.WHITE
            }
            // 导航键图标亮度（API 26+；浅色主题用深色键，深色主题用浅色键）
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val flags = window.decorView.systemUiVisibility
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = if (isDark) {
                    flags and View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR.inv()
                } else {
                    flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
                }
            }
        } catch (e: Exception) {
            // 导航栏配色只是视觉效果：任何异常（prefs 损坏/类型异常等）都静默降级，
            // 保证 onCreate 永不因主题读取崩溃（debug/release 一致）
            Log.w("MainActivity", "applySystemBarStyle failed, fallback to system: ${e.message}")
        }
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
                    "getVideos" -> {
                        val includeNoMedia = call.argument<Boolean>("includeNoMedia") ?: false
                        val includeHidden = call.argument<Boolean>("includeHidden") ?: false
                        result.success(getVideos(includeNoMedia, includeHidden))
                    }
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
                    // 播放界面顶部电量显示（工作.md 第 12 点）
                    "getBatteryLevel" -> result.success(getBatteryLevel())
                    // 播放界面顶部网络类型显示（工作.md 阶段1 第 1 点）
                    "getNetworkType" -> result.success(getNetworkType())
                    // 听视频后台播放前台服务启停（工作.md 阶段1 第 2 点）
                    "startBackgroundPlayback" -> {
                        startBackgroundPlayback(call.argument<String>("title") ?: "")
                        result.success(true)
                    }
                    "stopBackgroundPlayback" -> {
                        stopBackgroundPlayback()
                        result.success(true)
                    }
                    // ── 字幕功能（工作.md 阶段1 第 3 点）────────────
                    "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "listDirectory" -> result.success(listDirectory(call.argument<String>("path") ?: ""))
                    "getSystemFonts" -> result.success(getSystemFonts())
                    "copySubtitleFromUri" -> {
                        val path = copySubtitleFromUri(
                            call.argument<String>("uri") ?: "",
                            call.argument<String>("name") ?: "subtitle.srt",
                        )
                        result.success(path)
                    }
                    // 字幕字体导入：content:// 拷贝到 filesDir/fonts/（返回真实路径）
                    "copyFontFromUri" -> {
                        val path = copyFontFromUri(
                            call.argument<String>("uri") ?: "",
                            call.argument<String>("name") ?: "font.ttf",
                        )
                        result.success(path)
                    }
                    // 字幕字体导入：文件路径拷贝到 filesDir/fonts/（返回真实路径）
                    "copyFontFromFile" -> {
                        val path = copyFontFromFile(
                            call.argument<String>("path") ?: "",
                            call.argument<String>("name") ?: "font.ttf",
                        )
                        result.success(path)
                    }
                    // 获取内部字体目录绝对路径
                    "getFontsDirectory" -> {
                        val fontDir = File(filesDir, "fonts")
                        if (!fontDir.exists()) fontDir.mkdirs()
                        ensureFallbackFont(fontDir)
                        result.success(fontDir.absolutePath)
                    }
                    // 读取字体内部家族名（libass 的 sub-font 按家族名匹配，不能直接用文件名）
                    "getFontFamilyName" -> {
                        result.success(getFontFamilyName(call.argument<String>("path") ?: ""))
                    }
                    "openDocumentPicker" -> {
                        if (pendingDocumentPickerResult != null) {
                            result.error("BUSY", "picker already open", null)
                        } else {
                            pendingDocumentPickerResult = result
                            try {
                                startActivityForResult(buildDocumentPickerIntent(), 2002)
                            } catch (e: Exception) {
                                pendingDocumentPickerResult = null
                                result.success(null) // 失败 → Dart 侧回退自建选择器
                            }
                        }
                    }
                    // 音频选择器（MIME 含 audio 类型，系统选择器不再置灰 .mp3/.m4a/.flac）
                    "openAudioPicker" -> {
                        if (pendingDocumentPickerResult != null) {
                            result.error("BUSY", "picker already open", null)
                        } else {
                            pendingDocumentPickerResult = result
                            try {
                                startActivityForResult(
                                    buildDocumentPickerIntent(audioPickerMimeTypes),
                                    2002,
                                )
                            } catch (e: Exception) {
                                pendingDocumentPickerResult = null
                                result.success(null)
                            }
                        }
                    }
                    // 音轨导入：content:// 拷贝到 filesDir/audio/（返回真实路径）
                    "copyAudioFromUri" -> {
                        val path = copyAudioFromUri(
                            call.argument<String>("uri") ?: "",
                            call.argument<String>("name") ?: "audio.mp3",
                        )
                        result.success(path)
                    }
                    // 字体选择器（MIME 含 font 类型，系统选择器不再置灰 .ttf/.otf）
                    "openFontPicker" -> {
                        if (pendingDocumentPickerResult != null) {
                            result.error("BUSY", "picker already open", null)
                        } else {
                            pendingDocumentPickerResult = result
                            try {
                                startActivityForResult(
                                    buildDocumentPickerIntent(fontPickerMimeTypes),
                                    2002,
                                )
                            } catch (e: Exception) {
                                pendingDocumentPickerResult = null
                                result.success(null)
                            }
                        }
                    }
                    // 字体目录选择器（ACTION_OPEN_DOCUMENT_TREE）：返回 tree uri
                    "openFontDirectoryPicker" -> {
                        if (pendingFontDirPickerResult != null) {
                            result.error("BUSY", "picker already open", null)
                        } else {
                            pendingFontDirPickerResult = result
                            try {
                                startActivityForResult(buildOpenDocumentTreeIntent(), 2003)
                            } catch (e: Exception) {
                                pendingFontDirPickerResult = null
                                result.success(null)
                            }
                        }
                    }
                    // 批量拷贝字体目录里的所有字体到私有 fonts/（返回成功拷贝数）
                    "copyFontsFromDirectory" -> {
                        result.success(copyFontsFromDirectory(call.argument<String>("uri") ?: ""))
                    }
                    // 列出私有 fonts/ 目录内的字体条目（族名 + 文件名）
                    "listFontEntries" -> result.success(listFontEntries())
                    // 清空私有 fonts/ 目录
                    "clearFontsDirectory" -> {
                        clearFontsDirectory()
                        result.success(null)
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
                    // ── 画中画（小窗播放）────────────────────
                    "isPipSupported" -> result.success(isPipSupported())
                    "enterPip" -> {
                        // Dart 小整数经 MethodChannel 编码是 Integer 而非 Long，
                        // 用 Number 兼容，避免 ClassCastException（与抓帧同一坑）
                        val aspectWidth = call.argument<Number>("aspectWidth")?.toInt() ?: 16
                        val aspectHeight = call.argument<Number>("aspectHeight")?.toInt() ?: 9
                        result.success(enterPip(aspectWidth, aspectHeight))
                    }
                    "setAutoPipEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setAutoPipEnabled(enabled)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── 错误日志（崩溃日志自动记录）────────────────────────

    /** 日志目录：files/crash_logs/ */
    private fun logDir(): File = CrashHandler.logDir(this)

    /** 日志文件判定：原生崩溃日志 *.txt 与 Dart 侧 flutter_*.log 均计入 */
    private fun isLogFile(name: String): Boolean =
        name.endsWith(".txt") || name.endsWith(".log")

    /** 列出全部日志文件（按修改时间倒序；.txt 与 .log 都算） */
    private fun listLogs(): List<Map<String, Any>> {
        val dir = logDir()
        if (!dir.exists() || !dir.isDirectory) return emptyList()
        return dir.listFiles()
            ?.filter { it.isFile && isLogFile(it.name) }
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

    /** 清空全部日志（与 listLogs 同一过滤规则：.txt 与 .log 都清） */
    private fun clearLogs(): Boolean {
        return try {
            val dir = logDir()
            if (!dir.exists() || !dir.isDirectory) return true
            var ok = true
            dir.listFiles()?.forEach { f ->
                if (f.isFile && isLogFile(f.name) && !f.delete()) ok = false
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

    // ── 画中画（小窗播放）────────────────────────

    /** 设备是否支持画中画（API 26+ 且系统具备该特性） */
    private fun isPipSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    /**
     * 进入画中画小窗；宽高比由调用方传入（默认 16:9）。
     * 已在画中画时直接返回 true；不支持时返回 false。
     * （内联 SDK 判断：让 lint NewApi 能识别 API 26+ 调用路径）
     */
    private fun enterPip(aspectWidth: Int, aspectHeight: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!isPipSupported()) return false
        if (isInPictureInPictureMode) return true
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(aspectWidth.coerceAtLeast(1), aspectHeight.coerceAtLeast(1)))
            .build()
        return enterPictureInPictureMode(params)
    }

    /**
     * 设置「返回桌面/上滑手势时自动进入画中画」（仅 API 31+ 生效，
     * 旧系统静默忽略，返回桌面即为普通退后台）。
     */
    private fun setAutoPipEnabled(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && isPipSupported()) {
            val params = PictureInPictureParams.Builder()
                .setAutoEnterEnabled(enabled)
                .build()
            setPictureInPictureParams(params)
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

    // ── 电量（播放界面顶部信息行，工作.md 第 12 点）──────────

    /**
     * 读取当前电池电量百分比（0 – 100）。
     * BatteryManager.BATTERY_PROPERTY_CAPACITY 无需任何权限（API 21+）；
     * 异常时返回 -1，Dart 侧按「未知」隐藏电量显示。
     */
    private fun getBatteryLevel(): Int {
        return try {
            val bm = getSystemService(BATTERY_SERVICE) as? BatteryManager
            bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        } catch (e: Exception) {
            -1
        }
    }

    // ── 网络类型（播放界面顶部「数据类型」图标，工作.md 阶段1 第 1 点）────

    /**
     * 读取当前活动网络类型：返回 "wifi" / "cellular" / "ethernet" / "none"。
     * 需 ACCESS_NETWORK_STATE（normal 权限，安装即授予）；异常/无网络返回 "none"。
     */
    private fun getNetworkType(): String {
        return try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return "none"
            val network = cm.activeNetwork ?: return "none"
            val caps = cm.getNetworkCapabilities(network) ?: return "none"
            when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                else -> "none"
            }
        } catch (e: Exception) {
            "none"
        }
    }

    // ── 听视频后台播放（前台服务保活，工作.md 阶段1 第 2 点）──────

    /**
     * 启动后台播放前台服务（保活进程，使 mpv 音频在退后台后继续播放）。
     * Android 13+ 会先请求通知权限（未授予不影响服务运行，仅不显示通知）。
     */
    private fun startBackgroundPlayback(title: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED
                ) {
                    requestPermissions(
                        arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                        2001,
                    )
                }
            }
            BackgroundPlaybackService.createNotificationChannel(this)
            val intent = Intent(this, BackgroundPlaybackService::class.java)
                .putExtra("media_title", title)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            Log.w("MainActivity", "startBackgroundPlayback failed: ${e.message}")
        }
    }

    /** 停止后台播放前台服务（退出听视频界面时调用） */
    private fun stopBackgroundPlayback() {
        try {
            stopService(Intent(this, BackgroundPlaybackService::class.java))
        } catch (e: Exception) {
            Log.w("MainActivity", "stopBackgroundPlayback failed: ${e.message}")
        }
    }

    // ── 字幕功能（工作.md 阶段1 第 3 点）────────────────────

    /** 外挂字幕文件选择器的 MIME 白名单（额外的 octet-stream 兑底） */
    private val subtitlePickerMimeTypes = arrayOf(
        "text/plain",
        "text/vtt",
        "text/x-ssa",
        "application/x-subrip",
        "application/octet-stream",
    )

    /** 字体选择器的 MIME 白名单（含 font 类型，避免系统选择器把 .ttf/.otf 置灰） */
    private val fontPickerMimeTypes = arrayOf(
        "font/ttf",
        "font/otf",
        "font/sfnt",
        "font/collection",
        "application/x-font-ttf",
        "application/x-font-otf",
        "application/x-font-truetype",
        "application/vnd.ms-opentype",
        "application/octet-stream",
    )

    /** 音频选择器的 MIME 白名单（工作.md 音频功能：.mp3/.m4a/.flac 等不置灰） */
    private val audioPickerMimeTypes = arrayOf(
        "audio/*",
        "application/octet-stream",
    )

    /**
     * 系统文件选择器 Intent（ACTION_OPEN_DOCUMENT，无需权限）。
     * @param mimeTypes 允许选择的文件类型白名单（默认字幕类型）。
     */
    private fun buildDocumentPickerIntent(
        mimeTypes: Array<String> = subtitlePickerMimeTypes,
    ): Intent {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
        intent.type = "*/*"
        intent.putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes)
        intent.addCategory(Intent.CATEGORY_OPENABLE)
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        return intent
    }

    /**
     * 系统目录选择器 Intent（ACTION_OPEN_DOCUMENT_TREE，无需权限）。
     * 带上读/写 + 持久化 + 前缀授权标志，便于 takePersistableUriPermission。
     */
    private fun buildOpenDocumentTreeIntent(): Intent {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
        )
        return intent
    }

    /** 系统文件选择器结果回传（content:// uri 字符串或 null） */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            2002 -> {
                val pending = pendingDocumentPickerResult
                pendingDocumentPickerResult = null
                val uri = if (resultCode == Activity.RESULT_OK) data?.data?.toString() else null
                pending?.success(uri)
            }
            2003 -> {
                val pending = pendingFontDirPickerResult
                pendingFontDirPickerResult = null
                val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
                if (uri != null) {
                    // 持久化目录读权限，否则重启后 tree uri 失效无法刷新
                    try {
                        contentResolver.takePersistableUriPermission(
                            uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                    } catch (e: Exception) {
                        Log.w("MainActivity", "takePersistableUriPermission failed: ${e.message}")
                    }
                }
                pending?.success(uri?.toString())
            }
        }
    }

    /**
     * 列举目录内容（自建字幕文件选择器用，工作.md 阶段1 第 3 点）：
     * 返回 name/path/isDirectory/size/modifiedMs 列表（排序在 Dart 侧完成）。
     * 失败/不可读返回空列表。
     */
    private fun listDirectory(path: String): List<Map<String, Any>> {
        val dir = File(path)
        if (!dir.exists() || !dir.isDirectory) return emptyList()
        return try {
            dir.listFiles()
                ?.sortedBy { it.name.lowercase() }
                ?.map { f ->
                    mapOf(
                        "name" to f.name,
                        "path" to f.absolutePath,
                        "isDirectory" to f.isDirectory,
                        "size" to (if (f.isFile) f.length() else 0L),
                        "modifiedMs" to f.lastModified(),
                    )
                }
                ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * 系统字体列表（字幕字体设置用）：扫描 /system/fonts 下的 .ttf/.otf/.ttc
     * 文件，返回去重后的字体名（文件主名，如 "NotoSansCJK"）。失败返回空列表。
     */
    private fun getSystemFonts(): List<String> {
        val dir = File("/system/fonts")
        if (!dir.exists() || !dir.isDirectory) return emptyList()
        return try {
            dir.listFiles()
                ?.map { it.name }
                ?.filter { n ->
                    val lower = n.lowercase()
                    lower.endsWith(".ttf") || lower.endsWith(".otf") ||
                        lower.endsWith(".ttc")
                }
                ?.map { n -> n.substringBeforeLast('.') }
                ?.distinct()
                ?.sorted()
                ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * 把 content:// 字幕 uri 拷贝到 filesDir/subtitles/<name>（libmpv 无法直接
     * 读 content://，参考小喵 player SubtitleManager.copyContentUriToFile），
     * 返回真实绝对路径；失败返回 null。
     */
    private fun copySubtitleFromUri(uriString: String, name: String): String? {
        return try {
            val uri = Uri.parse(uriString)
            val subtitleDir = File(filesDir, "subtitles")
            if (!subtitleDir.exists()) subtitleDir.mkdirs()
            val safeName = name.replace(Regex("[^a-zA-Z0-9.\\-_]|\\s"), "_")
            val target = File(subtitleDir, "${uri.hashCode()}_$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            if (target.exists() && target.length() > 0) target.absolutePath else null
        } catch (e: Exception) {
            Log.w("MainActivity", "copySubtitleFromUri failed: ${e.message}")
            null
        }
    }

    /**
     * 把 content:// 音轨 uri 拷贝到 filesDir/audio/<name>（libmpv 无法直接读
     * content://，工作.md 音频功能：外部音轨临时、退出播放后不再引用），
     * 返回真实绝对路径；失败返回 null。
     */
    private fun copyAudioFromUri(uriString: String, name: String): String? {
        return try {
            val uri = Uri.parse(uriString)
            val audioDir = File(filesDir, "audio")
            if (!audioDir.exists()) audioDir.mkdirs()
            // 优先用真实文件名（DISPLAY_NAME），回退到 Dart 传入的 name
            val displayName = queryDisplayName(uri) ?: name
            val safeName = displayName.replace(Regex("[^a-zA-Z0-9.\\-_]|\\s"), "_")
            val target = File(audioDir, "${uri.hashCode()}_$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            if (target.exists() && target.length() > 0) target.absolutePath else null
        } catch (e: Exception) {
            Log.w("MainActivity", "copyAudioFromUri failed: ${e.message}")
            null
        }
    }

    /**
     * 把 content:// 字体文件（.ttf/.otf）拷贝到 filesDir/fonts/<name>，返回真实绝对路径。
     * 用户自导入字幕字体用（工作.md 阶段1 第 3 点：字幕字体支持自导入）。
     */
    private fun copyFontFromUri(uriString: String, name: String): String? {
        return try {
            val uri = Uri.parse(uriString)
            val fontDir = File(filesDir, "fonts")
            if (!fontDir.exists()) fontDir.mkdirs()
            // 优先用真实文件名（DISPLAY_NAME），回退到 Dart 传入的 name
            // （后者可能是 document ID 而非文件名，如 "msf%3A..."）。
            val displayName = queryDisplayName(uri) ?: name
            val safeName = displayName.replace(Regex("[^a-zA-Z0-9.\\-_]|\\s"), "_")
            val target = File(fontDir, safeName)
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            if (target.exists() && target.length() > 0) target.absolutePath else null
        } catch (e: Exception) {
            Log.w("MainActivity", "copyFontFromUri failed: ${e.message}")
            null
        }
    }

    /** 查询 content:// 的真实显示文件名（DISPLAY_NAME），失败返回 null。 */
    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * 把文件路径的字体文件（.ttf/.otf/.ttc）拷贝到 filesDir/fonts/<name>，返回真实绝对路径。
     * 自建选择器选择字体后安全复制到私有目录，确保 libass 始终能读取。
     */
    private fun copyFontFromFile(sourcePath: String, name: String): String? {
        return try {
            val src = File(sourcePath)
            if (!src.exists()) return null
            val fontDir = File(filesDir, "fonts")
            if (!fontDir.exists()) fontDir.mkdirs()
            val safeName = name.replace(Regex("[^a-zA-Z0-9.\\-_]|\\s"), "_")
            val target = File(fontDir, safeName)
            src.copyTo(target, overwrite = true)
            if (target.exists() && target.length() > 0) target.absolutePath else null
        } catch (e: Exception) {
            Log.w("MainActivity", "copyFontFromFile failed: ${e.message}")
            null
        }
    }

    private fun ensureFallbackFont(fontsDir: File) {
        try {
            val systemCandidates = listOf(
                File("/system/fonts/NotoSansCJK-Regular.ttc"),
                File("/system/fonts/NotoSansSC-Regular.otf"),
                File("/system/fonts/NotoSansHans-Regular.otf"),
                File("/system/fonts/DroidSansFallback.ttf")
            )
            for (candidate in systemCandidates) {
                if (!candidate.exists() || !candidate.canRead()) continue
                val target = File(fontsDir, candidate.name)
                if (target.exists() && target.length() > 0) return
                try {
                    // 直接复制系统字库（不用 symlink + 隐藏文件名）：
                    // fontconfig 可能跳过 `.` 开头的隐藏文件、且不 follow symlink，
                    // 导致兜底字体不被识别 → sub-fonts-dir 指向私有目录后
                    // ASS 字幕整条空白。复制成普通文件名可被 fontconfig 稳定识别。
                    candidate.copyTo(target, overwrite = true)
                    return
                } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            Log.w("MainActivity", "ensureFallbackFont failed: ${e.message}")
        }
    }

    /**
     * 读取字体文件的内部家族名（family name，name 表 nameID=1 / 16 / 4）。
     * libass 的 sub-font / ASS 样式 Fontname 均按家族名匹配。
     * 支持 TTF/OTF/TTC（TTC 取第一个 face）；解析失败返回文件名无后缀。
     */
    /**
     * 读取字体文件的家族名（family name），用 truetypeparser（对齐小喵 player）。
     * libass 的 sub-font / ASS 样式 Fontname 均按家族名匹配。
     * 解析失败返回文件名无后缀。
     */
    private fun getFontFamilyName(fontPath: String): String {
        return try {
            val file = File(fontPath)
            if (!file.exists() || file.length() < 12) return ""
            val family = file.inputStream().use { input ->
                TTFFile.open(input).families.values.firstOrNull()
            }
            family?.ifBlank { null } ?: file.nameWithoutExtension
        } catch (e: Exception) {
            Log.w("MainActivity", "getFontFamilyName failed: ${e.message}")
            try {
                File(fontPath).nameWithoutExtension
            } catch (_: Exception) {
                ""
            }
        }
    }

    /** 是否为字体文件（.ttf/.otf/.ttc/.otc，大小写不敏感）。 */
    private fun isFontFile(name: String): Boolean {
        val lower = name.lowercase()
        return lower.endsWith(".ttf") || lower.endsWith(".otf") ||
            lower.endsWith(".ttc") || lower.endsWith(".otc")
    }

    /** 兜底系统字库文件名（列表里隐藏，仅用于渲染时缺字兜底）。 */
    private val fallbackFontNames = setOf(
        "NotoSansCJK-Regular.ttc",
        "NotoSansSC-Regular.otf",
        "NotoSansHans-Regular.otf",
        "DroidSansFallback.ttf",
    )

    /**
     * 把用户选中的目录（SAF tree uri）里所有 .ttf/.otf/.ttc/.otc 字体一次性
     * 拷贝到 filesDir/fonts/（仅顶层文件，不递归），并补兜底字库；返回成功拷贝数。
     */
    private fun copyFontsFromDirectory(treeUriString: String): Int {
        return try {
            val treeUri = Uri.parse(treeUriString)
            val fontDir = File(filesDir, "fonts")
            if (!fontDir.exists()) fontDir.mkdirs()
            var count = 0
            val doc = DocumentFile.fromTreeUri(this, treeUri) ?: return 0
            doc.listFiles()?.forEach { file ->
                if (!file.isFile) return@forEach
                val name = file.name ?: return@forEach
                if (!isFontFile(name)) return@forEach
                try {
                    contentResolver.openInputStream(file.uri)?.use { input ->
                        File(fontDir, name).outputStream().use { out -> input.copyTo(out) }
                    }
                    count++
                } catch (e: Exception) {
                    Log.w("MainActivity", "copyFont ${file.name} failed: ${e.message}")
                }
            }
            ensureFallbackFont(fontDir)
            count
        } catch (e: Exception) {
            Log.w("MainActivity", "copyFontsFromDirectory failed: ${e.message}")
            0
        }
    }

    /**
     * 列出 filesDir/fonts/ 内的自定义字体（族名 + 文件名），按族名去重、按族名排序；
     * 隐藏兜底字库（fallbackFontNames）。
     */
    private fun listFontEntries(): List<Map<String, String>> {
        val fontDir = File(filesDir, "fonts")
        if (!fontDir.exists() || !fontDir.isDirectory) return emptyList()
        val seen = mutableSetOf<String>()
        val result = mutableListOf<Map<String, String>>()
        fontDir.listFiles()
            ?.filter { it.isFile && isFontFile(it.name) && it.name !in fallbackFontNames }
            ?.sortedBy { it.name.lowercase() }
            ?.forEach { f ->
                val family = getFontFamilyName(f.absolutePath)
                if (family.isNotEmpty() && seen.add(family)) {
                    result.add(mapOf("family" to family, "file" to f.name))
                }
            }
        return result
    }

    /** 清空 filesDir/fonts/ 下的全部文件（含兜底字库，下次拷贝会重建）。 */
    private fun clearFontsDirectory() {
        try {
            val fontDir = File(filesDir, "fonts")
            if (!fontDir.exists() || !fontDir.isDirectory) return
            fontDir.listFiles()?.forEach { if (it.isFile) it.delete() }
        } catch (e: Exception) {
            Log.w("MainActivity", "clearFontsDirectory failed: ${e.message}")
        }
    }

    // ── 缩略图缓存管理（列表封面，手动清理）───────────────
    // 进度条缩略图已切换为 FFmpeg 快速引擎（libmpv.so 内核）+ Dart 内存缓存，
    // 不再产生磁盘缓存；此处仅管理列表封面（cacheDir/thumbs/）。

    private fun thumbsDir(): File =
        File(cacheDir, "thumbs").apply { if (!exists()) mkdirs() }

    /** 各类别缓存占用（字节）：thumbs 目录全部计入列表封面（含历史进度条缩略图残留） */
    private fun getCacheSizes(): Map<String, Long> {
        var list = 0L
        thumbsDir().listFiles()?.forEach { f ->
            if (f.isFile) list += f.length()
        }
        // 未来类别（弹幕/字幕等）尚未启用，恒为 0
        return mapOf("listThumbs" to list, "other" to 0L)
    }

    /** 清除指定类别缓存（listThumbs 清空 thumbs 目录，顺带清掉历史残留） */
    private fun clearCache(category: String) {
        when (category) {
            "listThumbs" -> thumbsDir().listFiles()?.forEach {
                if (it.isFile) it.delete()
            }
            // "other"：未来类别（弹幕/字幕），暂无可清
        }
    }

    /** 一键清除所有缓存 */
    private fun clearAllCaches() {
        thumbsDir().listFiles()?.forEach { it.delete() }
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

    /** 通过 MediaStore 查询所有本地视频（可配置是否包含 .nomedia 与隐藏文件夹） */
    private fun getVideos(
        includeNoMedia: Boolean = false,
        includeHidden: Boolean = false
    ): List<Map<String, Any>> {
        val videos = mutableListOf<Map<String, Any>>()
        val visitedPaths = mutableSetOf<String>()
        val noMediaDirCache = mutableMapOf<String, Boolean>()

        fun checkDirectoryHasNoMedia(dir: File): Boolean {
            val dirPath = dir.absolutePath
            noMediaDirCache[dirPath]?.let { return it }
            var curr: File? = dir
            var hasNoMedia = false
            while (curr != null && curr.path != "/" && curr.path != "/storage/emulated") {
                val test = File(curr, ".nomedia")
                if (test.exists()) {
                    hasNoMedia = true
                    break
                }
                curr = curr.parentFile
            }
            noMediaDirCache[dirPath] = hasNoMedia
            return hasNoMedia
        }

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
            val dataCol = c.getColumnIndex(MediaStore.Video.Media.DATA)
            val relCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                c.getColumnIndex(MediaStore.Video.Media.RELATIVE_PATH)
            } else -1

            while (c.moveToNext()) {
                val origName = c.getString(nameCol) ?: continue
                val duration = c.getLong(durCol)
                val width = c.getInt(widthCol)
                val height = c.getInt(heightCol)

                // 优先读取 DATA 绝对路径（兼容 SD 卡与内置存储），找不到再通过 RELATIVE_PATH 拼接
                val dataPath = if (dataCol >= 0) c.getString(dataCol) else null
                val path = if (!dataPath.isNullOrEmpty()) {
                    dataPath
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && relCol >= 0) {
                    val rel = c.getString(relCol) ?: ""
                    "/storage/emulated/0/$rel$origName"
                } else {
                    continue
                }

                // 核心防脏数据校验：
                // 1. 检查物理文件是否真实存在且大小非空
                val file = File(path)
                if (!file.exists() || !file.isFile || file.length() == 0L) {
                    continue
                }

                val realName = file.name

                // 2. 隐藏文件/隐藏目录过滤策略（根据开关判断）
                val isHiddenItem = realName.startsWith(".") || path.split("/").any { it.startsWith(".") && it.isNotEmpty() }
                if (!includeHidden && isHiddenItem) {
                    continue
                }

                // 3. .nomedia 目录过滤策略（根据开关判断）
                if (!includeNoMedia && file.parentFile != null && checkDirectoryHasNoMedia(file.parentFile!!)) {
                    continue
                }

                val realSize = file.length()
                val realDateModified = file.lastModified()
                val normPath = file.absolutePath

                if (visitedPaths.add(normPath)) {
                    videos.add(
                        mapOf(
                            "path" to normPath,
                            "name" to realName,
                            "durationMs" to duration,
                            "size" to realSize,
                            "width" to width,
                            "height" to height,
                            "dateModifiedMs" to if (realDateModified > 0) realDateModified else (c.getLong(dateCol) * 1000L),
                        )
                    )
                }
            }
        }

        // 4. 如果开启了 includeNoMedia 或 includeHidden，针对文件系统进行补充扫描（因为 MediaStore 绝不会自动索引 .nomedia 目录）
        if (includeNoMedia || includeHidden) {
            val supportedExts = setOf("mp4", "mkv", "avi", "mov", "wmv", "flv", "ts", "m4v", "webm", "3gp", "mpg", "mpeg")
            fun scanFsFolder(folder: File, depth: Int) {
                if (depth > 6 || !folder.exists() || !folder.isDirectory || !folder.canRead()) return
                val folderName = folder.name
                val isHiddenFolder = folderName.startsWith(".")
                if (!includeHidden && isHiddenFolder) return

                val files = folder.listFiles() ?: return
                for (f in files) {
                    if (f.isDirectory) {
                        scanFsFolder(f, depth + 1)
                    } else if (f.isFile && f.length() > 0) {
                        val ext = f.extension.lowercase()
                        if (ext in supportedExts) {
                            val fName = f.name
                            if (!includeHidden && fName.startsWith(".")) continue
                            val normPath = f.absolutePath
                            if (visitedPaths.add(normPath)) {
                                videos.add(
                                    mapOf(
                                        "path" to normPath,
                                        "name" to fName,
                                        "durationMs" to 0L,
                                        "size" to f.length(),
                                        "width" to 0,
                                        "height" to 0,
                                        "dateModifiedMs" to f.lastModified(),
                                    )
                                )
                            }
                        }
                    }
                }
            }

            try {
                @Suppress("DEPRECATION")
                val primaryStorage = Environment.getExternalStorageDirectory()
                if (primaryStorage != null && primaryStorage.exists()) {
                    scanFsFolder(primaryStorage, 0)
                }
            } catch (_: Exception) {}
        }

        return videos
    }
}
