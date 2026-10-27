package com.example.flutter_govar_foreground_service

import android.Manifest
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.example.flutter_govar_foreground_service.NotificationUtils.Companion.FOREGROUND_SERVICE_NOTIFICATION_ID
import com.example.flutter_govar_foreground_service.NotificationUtils.Companion.FOREGROUND_SERVICE_TEXT
import com.example.flutter_govar_foreground_service.NotificationUtils.Companion.FOREGROUND_SERVICE_TITLE

class MediaForegroundService : Service() {

    override fun onCreate() {
        super.onCreate()

        val audioManager = getSystemService(AUDIO_SERVICE) as? AudioManager
        audioManager?.apply {
            mode = AudioManager.MODE_IN_COMMUNICATION

            val isHeadsetConnected = isWiredHeadsetOn || isBluetoothA2dpOn
            if (isHeadsetConnected) {
                isSpeakerphoneOn = false
            } else {
                isSpeakerphoneOn = true
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        var title: String? = null
        var text: String? = null
        intent?.apply {
            title = getStringExtra(FOREGROUND_SERVICE_TITLE)
            text = getStringExtra(FOREGROUND_SERVICE_TEXT)
        }
        val saved = getSharedPreferences("govar_call_notification", Context.MODE_PRIVATE)
        // START_STICKY may restart with a null intent. Keep the selected UI text.
        startForegroundService(title ?: saved.getString(FOREGROUND_SERVICE_TITLE, null),
            text ?: saved.getString(FOREGROUND_SERVICE_TEXT, null))
        return START_STICKY
    }

    private fun startForegroundService(title: String?, text: String?) {
        val notification = NotificationUtils(this).getForegroundServiceNotification(title, text)

        val hasCameraPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED

        val hasRecordAudioPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED


        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            var type = FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (hasCameraPermission) {
                    type = type or FOREGROUND_SERVICE_TYPE_CAMERA
                }

                if (hasRecordAudioPermission) {
                    type = type or FOREGROUND_SERVICE_TYPE_MICROPHONE
                }

            }
            startForeground(FOREGROUND_SERVICE_NOTIFICATION_ID, notification, type)
        } else {
            startForeground(FOREGROUND_SERVICE_NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    companion object {
        fun startService(context: Context, title: String? = null, text: String? = null) {
            // Persist before requesting the service so a process restart cannot lose locale.
            val saved = context.getSharedPreferences("govar_call_notification", Context.MODE_PRIVATE)
            saved.edit().apply {
                if (!title.isNullOrBlank()) putString(FOREGROUND_SERVICE_TITLE, title)
                if (!text.isNullOrBlank()) putString(FOREGROUND_SERVICE_TEXT, text)
            }.commit()
            val intent = Intent(context, MediaForegroundService::class.java).apply {
                putExtra(FOREGROUND_SERVICE_TITLE, title)
                putExtra(FOREGROUND_SERVICE_TEXT, text)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            context.stopService(Intent(context, MediaForegroundService::class.java))
        }
    }
}