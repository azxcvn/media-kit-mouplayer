package com.azxcvn.moumou

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "moumou/video_info"

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
                            result.success(getVideoInfo(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getVideoInfo(path: String): Map<String, Any?> {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L

            val bitmap = retriever.getFrameAtTime(
                0,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            )
            val thumbPath = if (bitmap != null) {
                val dir = File(cacheDir, "thumbs")
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, "${path.hashCode()}.jpg")
                if (!file.exists()) {
                    FileOutputStream(file).use { out ->
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
                    }
                }
                bitmap.recycle()
                file.absolutePath
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
}
