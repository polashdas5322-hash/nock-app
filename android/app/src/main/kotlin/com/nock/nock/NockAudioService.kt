package com.nock.nock

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.os.Environment
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import android.support.v4.media.session.MediaSessionCompat
import androidx.media.app.NotificationCompat.MediaStyle
import android.media.AudioManager
import android.media.AudioFocusRequest
import androidx.core.app.NotificationCompat

/**
 * NockAudioService - Background Foreground Service for Widget Audio Playback
 * 
 * This service enables the "Invisible App" experience where tapping the widget
 * plays audio instantly on the home screen without opening the app.
 * 
 * Key Features:
 * - Plays audio in the background via MediaPlayer
 * - Shows a MediaStyle notification (required by Android for foreground services)
 * - Auto-kills itself when audio finishes to save battery
 * - Handles errors gracefully
 */
class NockAudioService : Service() {

    private var mediaPlayer: MediaPlayer? = null
    private var mediaSession: MediaSessionCompat? = null
    
    private lateinit var audioManager: AudioManager
    private var focusRequest: AudioFocusRequest? = null
    
    // Track current foreground service type to allow atomic transitions (API 34)
    private var currentServiceType: Int = 0
    
    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                mediaPlayer?.setVolume(1.0f, 1.0f)
                if (mediaPlayer?.isPlaying == false) mediaPlayer?.start()
            }
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                // The Camera (or another app) is taking the mic/speaker.
                // 1. Release hardware locks and pause
                stopPlayback()

                
                // 2. Downgrade/Stop service to release OS-level hardware handles
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(NOTIFICATION_ID, createNotification("Nock", "Ready", null), 
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> mediaPlayer?.setVolume(0.2f, 0.2f)
        }
    }

    companion object {
        const val ACTION_PLAY = "com.nock.nock.ACTION_PLAY"
        const val ACTION_STOP = "com.nock.nock.ACTION_STOP"
        const val EXTRA_AUDIO_URL = "audio_url"
        const val EXTRA_SENDER_NAME = "sender_name"
        const val EXTRA_NOCK_ID = "nock_id"
        const val EXTRA_RECEIVER_ID = "receiver_id"
        const val CHANNEL_ID = "nock_playback_channel"
        const val NOTIFICATION_ID = 101
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        mediaSession = MediaSessionCompat(this, "NockAudioService").apply {
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val resultReceiver = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra("completer", android.os.ResultReceiver::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra("completer")
        }

        try {
            when (intent?.action) {
                ACTION_PLAY -> {
                    val audioUrl = intent.getStringExtra(EXTRA_AUDIO_URL)
                    val senderName = intent.getStringExtra(EXTRA_SENDER_NAME) ?: "Friend"
                    val nockId = intent.getStringExtra(EXTRA_NOCK_ID)

                    // 🛡️ 2026 STABILITY FIX: Always call startForeground high up
                    // Android OS kills the process if startForeground() isn't called within ~5s
                    // even if we intended to stop immediately.
                    val notification = createNotification(
                        if (audioUrl.isNullOrEmpty()) "Nock Idle" else "Playing Nock",
                        if (audioUrl.isNullOrEmpty()) "Ready" else "From $senderName",
                        nockId
                    )
                    
                    if (Build.VERSION.SDK_INT >= 34) {
                        startForeground(NOTIFICATION_ID, notification, 
                            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
                    } else {
                        startForeground(NOTIFICATION_ID, notification)
                    }

                    if (audioUrl != null && audioUrl.isNotEmpty()) {
                        playAudio(audioUrl)
                    } else {
                        android.util.Log.d("NockAudioService", "Empty audio URL, stopping immediately.")
                        stopSelf()
                    }
                }
                ACTION_STOP -> {
                    stopPlayback()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }

            }
            
            // Signal trampoline activity that the service reached foreground state
            resultReceiver?.send(Activity.RESULT_OK, null)

        } catch (e: Exception) {
            android.util.Log.e("NockAudioService", "Error in onStartCommand: ${e.message}")
            // Even on error, release the trampoline activity
            resultReceiver?.send(Activity.RESULT_CANCELED, null)
            
            // Stop service if we failed to reach foreground state effectively
            if (intent?.action != ACTION_STOP) {
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun playAudio(url: String) {
        // Stop previous playback if any
        stopPlayback()

        // Request Audio Focus
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val playbackAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(playbackAttributes)
                .setAcceptsDelayedFocusGain(true)
                .setOnAudioFocusChangeListener(focusChangeListener)
                .build()
            audioManager.requestAudioFocus(focusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            )
        }

        if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            stopSelf()
            return
        }

        try {
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .build()
                )
                setDataSource(url)
                prepareAsync()
                
                setOnPreparedListener {
                    it.start()
                }
                
                setOnCompletionListener {
                    stopPlayback()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
                
                setOnErrorListener { _, what, extra ->
                    android.util.Log.e("NockAudioService", "MediaPlayer error: $what")
                    stopPlayback()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    true
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("NockAudioService", "Error playing audio", e)
            stopPlayback()
            stopSelf()
        }
    }

    private fun stopPlayback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusChangeListener)
        }

        mediaPlayer?.let {
            if (it.isPlaying) {
                it.stop()
            }
            it.release()
        }
        mediaPlayer = null
    }

    private fun createNotification(title: String, text: String, nockId: String?): Notification {
        // Create intent to open app when notification is tapped
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (nockId != null) {
                putExtra("nockId", nockId)
                putExtra("route", "/player")
            }
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
 
        // Create stop action
        val stopIntent = Intent(this, NockAudioService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_pause,
                    "Stop",
                    stopPendingIntent
                )
            )
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        // âœ¨ BIOLUMINESCENT HUD: Tint notification based on state
        // Bio-Lime for Playback, Digital Lavender for Idle
        val intentAction = (if (mediaPlayer != null) ACTION_PLAY else "IDLE")
        val tintColor = when (intentAction) {
            ACTION_PLAY -> 0xFFD4F49C.toInt()   // bioLime
            else -> 0xFFE5D1FA.toInt()          // digitalLavender
        }
        builder.setColor(tintColor)
        // Ensure the icon/background follows the brand color
        builder.setSubText("Nocking")

        // Apply MediaStyle
        mediaSession?.let {
            builder.setStyle(
                MediaStyle()
                    .setMediaSession(it.sessionToken)
                    .setShowActionsInCompactView(0)
            )
        }

        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Nock Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when a Nock is playing"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        try {
            stopPlayback()

        } catch (e: Exception) {
            android.util.Log.e("NockAudioService", "Error in onDestroy cleanup: ${e.message}")
        }
        super.onDestroy()
    }
}
