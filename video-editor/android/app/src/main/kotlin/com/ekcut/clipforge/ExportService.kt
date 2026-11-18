package com.ekcut.clipforge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps ClipForge running while a video exports (a 40-minute video takes
 * a quarter of an hour or more on a phone): a foreground service with an
 * "Exporting" notification, so that Android does not stop the app when the
 * screen goes off or another app is opened, and a partial wake lock, so
 * that the processor keeps working with the screen off. FFmpeg itself runs
 * in the app's own process (ffmpeg_kit); this service only keeps that
 * process alive. Started and stopped from Dart (MainActivity's channel).
 */
class ExportService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Exporting video"
        val text = intent?.getStringExtra(EXTRA_TEXT)
            ?: "Keep ClipForge open while it exports."
        val notification = buildNotification(title, text)
        when {
            Build.VERSION.SDK_INT >= 35 -> startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING)
            Build.VERSION.SDK_INT >= 29 -> startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            else -> startForeground(NOTIFICATION_ID, notification)
        }
        if (wakeLock == null) {
            val power = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK, "ClipForge:export"
            ).apply {
                setReferenceCounted(false)
                // Released when the export ends; the limit is a safety net.
                acquire(4 * 60 * 60 * 1000L)
            }
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(title: String, text: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 &&
            manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID, "Exports", NotificationManager.IMPORTANCE_LOW
                ).apply { description = "Shown while a video is exported" }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
    }

    // Android 15+ stops data-sync / media-processing services after their
    // daily time budget (6 hours); far beyond any export.
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    companion object {
        const val CHANNEL_ID = "exports"
        const val NOTIFICATION_ID = 4107
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
    }
}
