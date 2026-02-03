package com.nock.nock

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import java.io.File

class MainActivity : FlutterActivity() {
    private val DEEPLINK_CHANNEL = "com.nock.nock/deeplink"
    private val SHARE_CHANNEL = "com.nock.nock/share"
    private val WIDGET_CHANNEL = "com.nock.nock/widget"
    private val AUDIO_CHANNEL = "com.nock.nock/audio_control"
    
    private var pendingWidgetId: Int = android.appwidget.AppWidgetManager.INVALID_APPWIDGET_ID
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Handle initial deep link if app was launched via deep link
        handleDeepLink(intent)

        // Setup audio control channel to stop background service
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "stopNockAudioService") {
                val stopIntent = Intent(this, NockAudioService::class.java)
                stopService(stopIntent)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
        
        // Setup share channel for social media sharing
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // Instagram share
                "shareToInstagram" -> {
                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath != null) {
                        val success = shareToApp(imagePath, "com.instagram.android")
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "imagePath is required", null)
                    }
                }
                "isInstagramInstalled" -> {
                    result.success(isAppInstalled("com.instagram.android"))
                }
                
                // TikTok share
                "shareToTikTok" -> {
                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath != null) {
                        val success = shareToApp(imagePath, "com.zhiliaoapp.musically")
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "imagePath is required", null)
                    }
                }
                "isTikTokInstalled" -> {
                    result.success(isAppInstalled("com.zhiliaoapp.musically"))
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Setup widget channel for configuration finish
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "finishConfig") {
                val widgetId = call.argument<Int>("appWidgetId") ?: android.appwidget.AppWidgetManager.INVALID_APPWIDGET_ID
                if (widgetId != android.appwidget.AppWidgetManager.INVALID_APPWIDGET_ID) {
                    val resultValue = Intent().apply {
                        putExtra(android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                    }
                    setResult(RESULT_OK, resultValue)
                    finish()
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // ==================== BACKGROUND UPLOAD CHANNEL ====================
        val BACKGROUND_UPLOAD_CHANNEL = "com.nock.nock/background_upload"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_UPLOAD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundTask" -> {
                    val title = call.argument<String>("title") ?: "Uploading"
                    val subtitle = call.argument<String>("subtitle") ?: "Please wait..."
                    
                    val workRequest = androidx.work.OneTimeWorkRequestBuilder<VibeUploadWorker>()
                        .setExpedited(androidx.work.OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                        .setInputData(androidx.work.workDataOf(
                            "title" to title,
                            "subtitle" to subtitle
                        ))
                        .build()
                    
                    androidx.work.WorkManager.getInstance(this).enqueue(workRequest)
                    result.success(workRequest.id.toString())
                }
                "updateTaskProgress" -> {
                    val taskId = call.argument<String>("taskId")
                    val fraction = call.argument<Double>("fraction") ?: 0.0
                    if (taskId != null) {
                        // 🛡️ 2026 GOLD STANDARD: Reactive progress updates to native worker
                        val progressInt = (fraction * 100).toInt()
                        (this as? androidx.lifecycle.LifecycleOwner)?.lifecycleScope?.launch {
                            VibeUploadWorker.progressFlow.emit(taskId to progressInt)
                        }
                    }
                    result.success(true)
                }
                "stopBackgroundTask" -> {
                    val taskId = call.argument<String>("taskId")
                    if (taskId != null) {
                        VibeUploadWorker.stopTask(taskId)
                        androidx.work.WorkManager.getInstance(this).cancelWorkById(java.util.UUID.fromString(taskId))
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    /**
     * Share image directly to a specific app using explicit intent
     * This bypasses the system share sheet and opens the target app directly
     * Works for Instagram, TikTok, WhatsApp, etc.
     */
    private fun shareToApp(imagePath: String, packageName: String): Boolean {
        return try {
            val file = File(imagePath)
            if (!file.exists()) {
                android.util.Log.e("MainActivity", "Image file does not exist: $imagePath")
                return false
            }
            
            // Check if target app is installed
            if (!isAppInstalled(packageName)) {
                android.util.Log.e("MainActivity", "App not installed: $packageName")
                return false
            }
            
            // Get content URI using FileProvider
            val contentUri: Uri = FileProvider.getUriForFile(
                this,
                "com.nock.nock.provider",
                file
            )
            
            // Create explicit intent for the target app
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "image/*"
                putExtra(Intent.EXTRA_STREAM, contentUri)
                // CRITICAL: Set package to bypass system share sheet and open app directly
                setPackage(packageName)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            
            // Start the target app directly
            startActivity(intent)
            true
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to share to $packageName: ${e.message}")
            false
        }
    }
    
    /**
     * Check if an app is installed on the device
     */
    private fun isAppInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, PackageManager.GET_ACTIVITIES)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // Handle deep link when app is already running
        handleDeepLink(intent)
    }
    
    private fun handleDeepLink(intent: Intent?) {
        val action = intent?.action
        val data = intent?.data
        
        // Handle Widget Configuration
        if (action == android.appwidget.AppWidgetManager.ACTION_APPWIDGET_CONFIGURE) {
            pendingWidgetId = intent.getIntExtra(
                android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_ID,
                android.appwidget.AppWidgetManager.INVALID_APPWIDGET_ID
            )
            
            if (pendingWidgetId != android.appwidget.AppWidgetManager.INVALID_APPWIDGET_ID) {
                android.util.Log.d("MainActivity", "Configuring widget: $pendingWidgetId")
                // We'll let Flutter handle the routing via the initial route or deep link
                // The intent data might need to be set so GoRouter picks it up
                intent.data = Uri.parse("nock://widget-config/$pendingWidgetId")
            }
        }

        if (action == Intent.ACTION_VIEW || action == "com.nock.nock.OPEN_NOCK") {
            if (data != null) {
                android.util.Log.d("MainActivity", "Deep link/Action received: $action, data: $data")
            }
        }
    }
}
