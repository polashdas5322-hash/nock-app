package com.nock.nock

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import androidx.core.content.ContextCompat

class TrampolineActivity : Activity() {
    
    companion object {
        private const val TAG = "TrampolineActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        Log.d(TAG, "TrampolineActivity created. Intent: ${intent?.action}")

        // --- START FIX: IMMEDIATE HAPTIC FEEDBACK ---
        try {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (vibrator.hasVibrator()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    vibrator.vibrate(50)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Vibration failed: ${e.message}")
        }
        
        // --- HANDSHAKE MECHANISM FOR ANDROID 14 ---
        // We must NOT finish the activity until the Service has successfully called
        // startForeground(). If we finish early, the system might transition the app
        // to "Background" state and throw a SecurityException for microphone usage.
        
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        
        // Safety timeout: If service never calls back, don't leave this activity orphaned forever
        val timeoutRunnable = Runnable {
            Log.w(TAG, "Handshake timeout! Finishing trampoline to avoid orphaning.")
            finish()
        }

        val finisher = object : android.os.ResultReceiver(handler) {
            override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
                Log.d(TAG, "Service handshake received (result: $resultCode). Finishing trampoline.")
                handler.removeCallbacks(timeoutRunnable)
                finish()
            }
        }

        // Forward the intent to NockAudioService
        intent?.let { originalIntent ->
            // --- START FIX: ANDROID 13+ "ZOMBIE" AUDIO MITIGATION ---
            // If we don't have notification permissions on Android 13+, 
            // the foreground service notification will be SUPPRESSED.
            // This leaves the user with "Zombie Audio": playing but un-stoppable.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val permission = android.Manifest.permission.POST_NOTIFICATIONS
                if (androidx.core.content.ContextCompat.checkSelfPermission(this, permission) != 
                    android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    
                    Log.w(TAG, "Notification permission missing! Redirecting to MainActivity to avoid Zombie Audio.")
                    
                    // Fallback: Open the main app so the user has the full player UI and controls.
                    val mainIntent = Intent(this, MainActivity::class.java).apply {
                        action = originalIntent.action
                        originalIntent.extras?.let { putExtras(it) }
                        data = originalIntent.data
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    }
                    startActivity(mainIntent)
                    finish()
                    return
                }
            }
            // --- END ZOMBIE AUDIO FIX ---

            val serviceIntent = Intent(this, NockAudioService::class.java).apply {
                action = originalIntent.action
                originalIntent.extras?.let { putExtras(it) }
                data = originalIntent.data
                putExtra("completer", finisher)
            }
            
            try {
                ContextCompat.startForegroundService(this, serviceIntent)
                Log.d(TAG, "Service started, waiting for handshake...")
                
                // Start the safety timer (10 seconds is a safe watchdog for slow cold starts)
                // This only fires if the Handshake fails or the service crashes.
                handler.postDelayed(timeoutRunnable, 10000)
                
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start service: ${e.message}")
                finish()
            }
        } ?: run {
            finish()
        }
        
        moveTaskToBack(true)
    }
}
