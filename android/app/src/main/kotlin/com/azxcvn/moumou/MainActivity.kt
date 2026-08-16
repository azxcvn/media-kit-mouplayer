package com.azxcvn.moumou

import android.database.Cursor
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.provider.MediaStore
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
                            // 耗时解码放到后台线程，避免阻塞 UI 线程
                            Thread {
                                val info = getVideoInfo(path)
                                runOnUiThread { result.success(info) }
                            }.start()
                        }
                    }
                    "getVideos" -> result.success(getVideos())
                    else -> result.notImplemented()
                }
            }
    }

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

            val bitmap = retriever.getFrameAtTime(
                0,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
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
