package com.azxcvn.moumou

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * 听视频后台播放服务（工作.md 阶段1 第 2 点，参考小喵 player BackgroundPlaybackService）：
 *
 * 极简前台服务，**仅用于维持进程不被系统杀死**，不带任何媒体控制功能。
 * 实际音频仍由 libmpv（media_kit Player）播放——退到后台后只要进程存活、
 * 音频焦点未被抢占，mpv 就会继续出声。启动本服务（前台 + mediaPlayback 类型）
 * 后，系统不会在退后台时暂停/回收进程，从而实现「像音乐播放器一样后台播放」。
 *
 * 进入听视频界面时启动，退出时停止。
 */
class BackgroundPlaybackService : Service() {

    companion object {
        private const val TAG = "BgPlaybackService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "moumou_background_playback"

        fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "听视频后台播放",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "在后台继续播放视频音频"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }
            (context.getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        var title = intent?.getStringExtra("media_title")
        if (title.isNullOrBlank()) title = "听视频"
        try {
            // 点击通知回到本 Activity（singleTop，不新建实例）
            val openIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val pendingIntent = PendingIntent.getActivity(
                this, 0, openIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

            val notification = Notification.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText("正在后台播放")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                @Suppress("DEPRECATION")
                startForeground(NOTIFICATION_ID, notification)
            }
            Log.d(TAG, "Foreground service started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground", e)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}
