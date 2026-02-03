package com.nock.nock

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import androidx.work.WorkManager
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.collectLatest
import java.util.concurrent.ConcurrentHashMap

/**
 * Vibe Upload Worker
 * 
 * A "Short-lived" expedited worker that ensures the app process survives
 * while Dart performs a critical media upload.
 */
class VibeUploadWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    companion object {
        const val CHANNEL_ID = "vibe_uploads"
        private const val NOTIFICATION_ID = 1001
        
        // Static flow to send progress updates to the active worker
        internal val progressFlow = MutableSharedFlow<Pair<String, Int>>(extraBufferCapacity = 10)
        
        // Static map to track active tasks and signal completion
        internal val activeTasks = ConcurrentHashMap<String, CompletableDeferred<Unit>>()
        
        fun stopTask(taskId: String) {
            activeTasks[taskId]?.complete(Unit)
        }
    }

    override suspend fun doWork(): Result {
        val taskId = id.toString()
        val title = inputData.getString("title") ?: "Uploading Vibe"
        val subtitle = inputData.getString("subtitle") ?: "Please wait..."
        
        android.util.Log.d("VibeUploadWorker", "🛡️ Starting background upload survival task: $taskId")
        
        val completionSignal = CompletableDeferred<Unit>()
        activeTasks[taskId] = completionSignal
        
        try {
            // Initial notification
            setForeground(createForegroundInfo(title, subtitle, 0))
            
            // Listen for progress updates and completion in parallel
            coroutineScope {
                val progressJob = launch {
                    progressFlow.collectLatest { (updateId, progress) ->
                        if (updateId == taskId) {
                            setForeground(createForegroundInfo(title, subtitle, progress))
                        }
                    }
                }
                
                completionSignal.await()
                progressJob.cancel()
            }
            
            return Result.success()
        } catch (e: Exception) {
            return Result.failure()
        } finally {
            activeTasks.remove(taskId)
        }
    }

    private suspend fun createForegroundInfo(title: String, subtitle: String, progress: Int): ForegroundInfo {
        val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Vibe Uploads",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows progress of vibes being sent"
            }
            notificationManager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setProgress(100, progress, progress == 0) 
            // 🛡️ 2026 GOLD STANDARD: Use ProgressStyle for system-level prioritization
            .setStyle(NotificationCompat.BigTextStyle().bigText(subtitle))
            .build()

        // 2026 Standard: Specify foreground service type
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    /**
     * CRITICAL FIX: Required for setExpedited() on Android 11 and lower.
     * WorkManager calls this method *before* doWork() starts to promote the
     * worker to a Foreground Service on legacy systems.
     *
     * This prevents the "IllegalStateException: Not implemented" crash.
     */
    override suspend fun getForegroundInfo(): ForegroundInfo {
        // Retrieve the same input data passed to the worker request
        val title = inputData.getString("title") ?: "Uploading Vibe"
        val subtitle = inputData.getString("subtitle") ?: "Please wait..."

        // Reuse the existing createForegroundInfo method.
        // We pass 0 as the initial progress value.
        // This ensures the notification is ready immediately for the OS.
        return createForegroundInfo(title, subtitle, 0)
    }

    /**
     * Public method to update progress from MainActivity
     */
    suspend fun updateProgress(title: String, subtitle: String, progress: Int) {
        setForeground(createForegroundInfo(title, subtitle, progress))
    }
}
