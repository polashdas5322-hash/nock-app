package com.nock.nock

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import android.app.PendingIntent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Log
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File
import java.net.URL
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Nock Widget Provider
 * 
 * Displays the latest received nock (photo + voice) on the home screen.
 * Tapping the widget opens the app to the player screen.
 */
class NockWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        // Handle custom actions
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                android.util.Log.d("NockWidget", "Boot/Update received, refreshing widget")
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val componentName = android.content.ComponentName(context, NockWidgetProvider::class.java)
                val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
                for (appWidgetId in appWidgetIds) {
                    updateAppWidget(context, appWidgetManager, appWidgetId)
                }
            }
            ACTION_PLAY_AUDIO -> {
                // REMOVED: Receiver-based start is deprecated due to BAL restrictions in Android 14.
                // We now launch TrampolineActivity directly via PendingIntent.getActivity()
            }
            
            // Heart button tap - Send nudge (102 requests for quick interactions)
            ACTION_SEND_NUDGE -> {
                // REMOVED: Receiver-based start is deprecated. 
                // PendingIntent.getActivity() now launches MainActivity directly.
            }
        }
    }

    companion object {
        const val ACTION_PLAY_AUDIO = "com.nock.nock.ACTION_PLAY_AUDIO"
        const val ACTION_SEND_NUDGE = "com.nock.nock.ACTION_SEND_NUDGE"
        const val EXTRA_AUDIO_URL = "audio_url"
        const val EXTRA_NOCK_ID = "nock_id"
        const val EXTRA_RECEIVER_ID = "receiver_id"
        
        private const val PREFS_NAME = "HomeWidgetPrefs"

        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            try {
                android.util.Log.d("NockWidget", "updateAppWidget: Starting for widget $appWidgetId")
                val views = RemoteViews(context.packageName, R.layout.nock_widget_layout)
                
                // ⚡ OPTIMISTIC RENDERING: Get existing data IMMEDIATELY to avoid "Loading..." flash
                val widgetData = HomeWidgetPlugin.getData(context)
                
                // 🔍 DIAGNOSTIC LOG: List all keys to see if they have prefixes or wrong names
                val allKeys = widgetData.all.keys
                android.util.Log.d("NockWidget", "DEBUG: All SharedPrefs keys: ${allKeys.joinToString(", ")}")
                
                var senderName = widgetData.getString("senderName", null)
                var senderId = widgetData.getString("senderId", null)
                var nockId = widgetData.getString("vibeId", null) ?: widgetData.getString("nockId", null)
                var imageUrl = widgetData.getString("imageUrl", null)
                var isPlayed = widgetData.getBoolean("isPlayed", true)
                var timestamp = widgetData.getLong("timestamp", 0L)
                var transcription = widgetData.getString("transcription", null) ?: widgetData.getString("transcriptionPreview", null)

                // 🔄 RESILIENCY FALLBACK: If individual keys are missing, try to extract from Squad JSON
                // This ensures Nock/Hero widget stays in sync with the Squad grid source of truth.
                if (senderName == null || nockId == null) {
                    try {
                        val vibesJson = widgetData.getString("recent_vibes", null)
                        if (!vibesJson.isNullOrEmpty()) {
                            val array = org.json.JSONArray(vibesJson)
                            if (array.length() > 0) {
                                val hero = array.getJSONObject(0)
                                senderName = hero.optString("senderName", null)
                                nockId = hero.optString("vibeId", null)
                                senderId = hero.optString("senderId", null)
                                imageUrl = hero.optString("imageUrl", null)
                                isPlayed = hero.optBoolean("isPlayed", false)
                                timestamp = hero.optLong("timestamp", 0L)
                                transcription = hero.optString("transcription", null)
                                android.util.Log.d("NockWidget", "Fallback Success: Extracted hero $nockId from JSON")
                            }
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("NockWidget", "Fallback failed: ${e.message}")
                    }
                }

                android.util.Log.d("NockWidget", "updateAppWidget: Final Data - senderName=$senderName, vibeId=$nockId")

                if (senderName != null && nockId != null) {
                    // Populate view
                    val displayName = if (senderName.length > 15) senderName.take(12) + "..." else senderName
                    views.setTextViewText(R.id.sender_name, displayName)
                    
                    val infoText = if (timestamp > 0) {
                        formatTimeAgo(timestamp)
                    } else if (!transcription.isNullOrEmpty()) {
                        "\"$transcription\""
                    } else {
                        ""
                    }
                    // views.setTextViewText(R.id.time_text, infoText) // If you have a time text field
                    
                    views.setViewVisibility(R.id.status_indicator, if (!isPlayed) android.view.View.VISIBLE else android.view.View.GONE)
                    views.setViewVisibility(R.id.play_button, android.view.View.VISIBLE)
                    
                    // Set up click intent - Opens app player
                    val openIntent = Intent(context, MainActivity::class.java).apply {
                        action = Intent.ACTION_VIEW
                        data = Uri.parse("nock:///player/$nockId")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    }
                    val openPi = PendingIntent.getActivity(context, appWidgetId, openIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    views.setOnClickPendingIntent(R.id.widget_image, openPi)

                    // Play button
                    val playIntent = Intent(context, TrampolineActivity::class.java).apply {
                        action = "com.nock.nock.ACTION_PLAY"
                        putExtra("audio_url", widgetData.getString("audioUrl", ""))
                        putExtra("sender_name", senderName)
                        putExtra("nock_id", nockId)
                    }
                    val playPi = PendingIntent.getActivity(context, appWidgetId + 200, playIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    views.setOnClickPendingIntent(R.id.play_button, playPi)

                    // Load image
                    if (!imageUrl.isNullOrEmpty()) {
                        loadImageAsync(context, imageUrl, views, appWidgetManager, appWidgetId, nockId)
                    }
                } else {
                    // Fallback for new widgets
                    views.setTextViewText(R.id.sender_name, "Nock")
                    views.setViewVisibility(R.id.play_button, android.view.View.GONE)
                    views.setViewVisibility(R.id.status_indicator, android.view.View.GONE)
                    
                    val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    val openPi = PendingIntent.getActivity(context, appWidgetId, openIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    views.setOnClickPendingIntent(R.id.widget_image, openPi)
                }
                
                appWidgetManager.updateAppWidget(appWidgetId, views)
                android.util.Log.d("NockWidget", "updateAppWidget: Widget updated successfully")
            } catch (e: Exception) {
                android.util.Log.e("NockWidget", "updateAppWidget: ERROR - ${e.message}", e)
            }
        }
        
        private fun loadImageAsync(
            context: Context,
            imageUrl: String,
            views: RemoteViews,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            nockId: String? = null
        ) {
            // 🧠 ANTI-FLICKER OPTIMIZATION: Move heavy I/O and decoding to background.
            // This prevents "hitch" during home screen page swipes.
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    // 1. Perform decoding and URI generation in background
                    WidgetUtils.setSafeImage(context, views, R.id.widget_image, imageUrl, nockId)
                    
                    // 2. Update widget once decoding is done
                    withContext(Dispatchers.Main) {
                        appWidgetManager.updateAppWidget(appWidgetId, views)
                        android.util.Log.d("NockWidget", "Async image update complete for $appWidgetId")
                    }
                } catch (e: Exception) {
                    android.util.Log.e("NockWidget", "Background image load failed: ${e.message}")
                }
            }
        }

        /**
         * Format timestamp to human-readable relative time (e.g., "2m ago", "1h ago", "3d ago")
         * Follows Dual Coding Theory - adds unique value instead of redundant content type info
         */
        private fun formatTimeAgo(timestampMs: Long): String {
            val now = System.currentTimeMillis()
            val diffMs = now - timestampMs
            
            val seconds = diffMs / 1000
            val minutes = seconds / 60
            val hours = minutes / 60
            val days = hours / 24
            val weeks = days / 7
            
            return when {
                seconds < 60 -> "now"
                minutes < 60 -> "${minutes}m ago"
                hours < 24 -> "${hours}h ago"
                days < 7 -> "${days}d ago"
                else -> "${weeks}w ago"
            }
        }
    }
}
