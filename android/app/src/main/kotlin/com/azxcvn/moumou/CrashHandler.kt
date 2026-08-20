package com.azxcvn.moumou

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import java.io.File
import java.io.FileWriter
import java.io.PrintWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 全局异常处理器：自动捕获未处理的崩溃，保存日志到
 * `files/crash_logs/`（Android/data/包名/files/crash_logs/）。
 *
 * 在 [MainActivity.configureFlutterEngine] 中初始化；
 * 日志文件可在「关于 → 工具 → 错误日志」中查看 / 导出 / 复制。
 */
class CrashHandler private constructor(private val context: Context) :
    Thread.UncaughtExceptionHandler {

    private val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()

    companion object {
        private const val TAG = "CrashHandler"

        @Volatile
        private var instance: CrashHandler? = null

        /** 日志目录（与错误日志页共用）：Android/data/包名/files/crash_logs/ */
        fun logDir(context: Context): File =
            File(context.getExternalFilesDir(null), "crash_logs")

        fun init(context: Context) {
            if (instance == null) {
                synchronized(this) {
                    if (instance == null) {
                        instance = CrashHandler(context.applicationContext)
                        Thread.setDefaultUncaughtExceptionHandler(instance)
                        Log.d(TAG, "全局异常处理器已初始化")
                    }
                }
            }
        }
    }

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        try {
            saveCrashLog(throwable)
            showCrashToast()
            Thread.sleep(2000)
        } catch (e: Exception) {
            Log.e(TAG, "处理崩溃异常失败", e)
        } finally {
            defaultHandler?.uncaughtException(thread, throwable)
        }
    }

    /** 保存崩溃日志到本地文件（失败返回 null） */
    private fun saveCrashLog(throwable: Throwable): File? {
        return try {
            val logDir = logDir(context)
            if (!logDir.exists()) logDir.mkdirs()

            val timestamp =
                SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.getDefault())
                    .format(Date())
            val logFile = File(logDir, "crash_$timestamp.txt")

            FileWriter(logFile).use { writer ->
                writer.append("=============================================\n")
                writer.append("           应用崩溃日志\n")
                writer.append("=============================================\n\n")

                writer.append("【时间】$timestamp\n")
                writer.append("【应用版本】Unknown (由错误日志页展示实际版本)\n")
                writer.append("【设备型号】${Build.MANUFACTURER} ${Build.MODEL}\n")
                writer.append("【系统版本】Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})\n")
                writer.append("【CPU架构】${Build.SUPPORTED_ABIS.joinToString(", ")}\n\n")

                writer.append("【异常类型】${throwable.javaClass.name}\n")
                writer.append("【异常消息】${throwable.message ?: "无"}\n\n")

                writer.append("【堆栈跟踪】\n")
                throwable.printStackTrace(PrintWriter(writer))

                writer.append("\n\n=============================================\n")
                writer.append("提示：如需反馈问题，请将此文件发送给开发者\n")
                writer.append("文件位置：${logFile.absolutePath}\n")
                writer.append("=============================================\n")
            }

            Log.e(TAG, "崩溃日志已保存: ${logFile.absolutePath}")
            trimLogs()
            logFile
        } catch (e: Exception) {
            Log.e(TAG, "保存崩溃日志失败", e)
            null
        }
    }

    /**
     * 自动裁剪（risk_audit #8）：日志数量 ≤ 50 且总大小 ≤ 10MB，
     * 超过上限删除最旧的（按修改时间），防止日志无限累积。
     * 与 Dart 侧 appendDartLog 后的裁剪共用同一上限语义。
     */
    private fun trimLogs() {
        try {
            val dir = logDir(context)
            if (!dir.exists() || !dir.isDirectory) return
            val files = dir.listFiles()
                ?.filter { it.isFile && (it.name.endsWith(".txt") || it.name.endsWith(".log")) }
                ?.sortedBy { it.lastModified() } // 最旧在前
                ?: return
            val maxCount = 50
            val maxBytes = 10L * 1024 * 1024 // 10 MB
            var total = files.sumOf { it.length() }
            var i = 0
            while (i < files.size && (files.size - i > maxCount || total > maxBytes)) {
                val f = files[i]
                val len = f.length()
                if (f.delete()) total -= len
                i++
            }
        } catch (e: Exception) {
            Log.e(TAG, "裁剪崩溃日志失败", e)
        }
    }

    private fun showCrashToast() {
        try {
            Handler(Looper.getMainLooper()).post {
                Toast.makeText(
                    context,
                    "应用遇到错误已停止运行\n日志已保存，可在「关于 → 错误日志」查看",
                    Toast.LENGTH_LONG,
                ).show()
            }
        } catch (e: Exception) {
            Log.e(TAG, "显示崩溃提示失败", e)
        }
    }
}
