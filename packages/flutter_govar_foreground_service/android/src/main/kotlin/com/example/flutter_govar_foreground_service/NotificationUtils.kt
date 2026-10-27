package com.example.flutter_govar_foreground_service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

class NotificationUtils(private val context: Context) {

    companion object {
        const val FOREGROUND_SERVICE_TITLE = "foreground_service_title"
        const val FOREGROUND_SERVICE_TEXT = "foreground_service_text"
        const val FOREGROUND_SERVICE_NOTIFICATION_ID = 1
        const val CHANNEL_ID = "foreground_service_channel"
    }

    fun getForegroundServiceNotification(title: String?, text: String?): Notification {
        createNotificationChannel()

        val notificationIntent = Intent(context, MediaForegroundService::class.java)
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE
        )

        val appIcon = getAppIcon(context, context.packageName)

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title ?: "Govar")
            .setContentText(text ?: "Govar")
            .setSmallIcon(appIcon)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun getAppIcon(context: Context, packageName: String): Int {
        return try {
            val applicationInfo = context.packageManager.getApplicationInfo(packageName, 0)
            applicationInfo.icon
        } catch (e: Exception) {
            e.printStackTrace()
            android.R.drawable.sym_def_app_icon
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Govar",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }
}