package com.nock.nock

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.app.PendingIntent
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import android.view.View
import org.json.JSONArray
import java.net.URL
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Squad Widget Provider - Shows latest 3 vibes in a horizontal grid
 * 
 * Features:
 * - Displays 3 most recent vibes
 * - Shows sender avatar/image, name, and time
 * - Unread indicators
 * - Deep links to PlayerScreen for each vibe
 * - Auto-refreshes every 30 minutes
 */
class SquadWidgetProvider : AppWidgetProvider() {
    
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || 
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            Log.d(TAG, "Boot/Update received, refreshing Squad widget")
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, SquadWidgetProvider::class.java)
            )
            for (appWidgetId in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        }
    }
    
    companion object {
        private const val TAG = "SquadWidget"
        
        /**
         * Update all Squad widgets
         */
        fun updateAll(context: Context) {
            val intent = Intent(context, SquadWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            }
            context.sendBroadcast(intent)
        }
        
        private fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            // 🧠 ANTI-FLICKER OPTIMIZATION: Squad widget decodes 3 images.
            // Move entire update cycle to background to prevent UI lag.
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    Log.d(TAG, "updateAppWidget: Starting background update for $appWidgetId")
                    val views = RemoteViews(context.packageName, R.layout.squad_widget_layout)
                    
                    val vibes = loadVibes(context)
                    Log.d(TAG, "updateAppWidget: Loaded ${vibes.size} vibes")
                    
                    // These lookups and decodings now happen in the background!
                    updateVibeSlot(context, views, vibes.getOrNull(0), 1, appWidgetId)
                    updateVibeSlot(context, views, vibes.getOrNull(1), 2, appWidgetId)
                    updateVibeSlot(context, views, vibes.getOrNull(2), 3, appWidgetId)

                    // ZERO STATE HANDLING
                    if (vibes.isEmpty()) {
                        views.setViewVisibility(R.id.content_container, View.GONE)
                        views.setViewVisibility(R.id.empty_state_container, View.VISIBLE)
                        
                        val openIntent = Intent(context, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        }
                        val pendingIntent = PendingIntent.getActivity(
                            context, appWidgetId, openIntent, 
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        views.setOnClickPendingIntent(R.id.empty_state_container, pendingIntent)
                    } else {
                        views.setViewVisibility(R.id.content_container, View.VISIBLE)
                        views.setViewVisibility(R.id.empty_state_container, View.GONE)
                    }
                    
                    // 🚀 Final render on the Main thread
                    withContext(Dispatchers.Main) {
                        appWidgetManager.updateAppWidget(appWidgetId, views)
                        Log.d(TAG, "updateAppWidget: Widget updated successfully on MAIN thread")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "updateAppWidget: Async update failed: ${e.message}", e)
                }
            }
        }
        
        private fun loadVibes(context: Context): List<VibeData> {
            try {
                // 🚀 2026 STANDARD: Use HomeWidgetPlugin to ensure correct SharedPrefs bucket
                val widgetData = es.antonborri.home_widget.HomeWidgetPlugin.getData(context)
                val vibesJson = widgetData.getString("recent_vibes", null)
                
                Log.d(TAG, "loadVibes: Data string found: ${vibesJson?.take(100)}...")
                
                if (vibesJson.isNullOrEmpty()) {
                    Log.w(TAG, "loadVibes: recent_vibes key is NULL or empty")
                    return emptyList()
                }
                
                val array = JSONArray(vibesJson)
                Log.d(TAG, "loadVibes: Found ${array.length()} vibes in JSON")
                
                return (0 until minOf(array.length(), 3)).map { i ->
                    val obj = array.getJSONObject(i)
                    VibeData(
                        vibeId = obj.getString("vibeId"),
                        senderName = obj.getString("senderName"),
                        imageUrl = obj.optString("imageUrl", null),
                        isPlayed = obj.optBoolean("isPlayed", false),
                        timestamp = obj.optLong("timestamp", System.currentTimeMillis()),
                        transcription = obj.optString("transcription", "")
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "loadVibes: CRITICAL FAILURE: ${e.message}")
                e.printStackTrace()
                return emptyList()
            }
        }
        
        private fun updateVibeSlot(
            context: Context,
            views: RemoteViews,
            vibe: VibeData?,
            slotNumber: Int,
            appWidgetId: Int
        ) {
            val containerId = when (slotNumber) {
                1 -> R.id.vibe_1_container
                2 -> R.id.vibe_2_container
                3 -> R.id.vibe_3_container
                else -> return
            }
            
            val imageId = when (slotNumber) {
                1 -> R.id.vibe_1_image
                2 -> R.id.vibe_2_image
                3 -> R.id.vibe_3_image
                else -> return
            }
            
            val nameId = when (slotNumber) {
                1 -> R.id.vibe_1_name
                2 -> R.id.vibe_2_name
                3 -> R.id.vibe_3_name
                else -> return
            }
            
            val timeId = when (slotNumber) {
                1 -> R.id.vibe_1_time
                else -> 0
            }
            
            // TRANSCRIPTION: Only valid for Hero Slot (1)
            val transcriptionId = when (slotNumber) {
                1 -> R.id.vibe_transcription
                else -> 0
            }
            
            val unreadId = when (slotNumber) {
                1 -> R.id.vibe_1_unread
                2 -> R.id.vibe_2_unread
                3 -> R.id.vibe_3_unread
                else -> return
            }
            
            if (vibe == null) {
                views.setViewVisibility(containerId, View.GONE)
                return
            }
            
            views.setViewVisibility(containerId, View.VISIBLE)
            val displayName = if (vibe.senderName.length > 15) vibe.senderName.take(12) + "..." else vibe.senderName
            views.setTextViewText(nameId, displayName)
            if (timeId != 0) {
                views.setTextViewText(timeId, formatTimeAgo(vibe.timestamp))
            }
            
            // BIND TRANSCRIPTION (If exists and is slot 1)
            if (transcriptionId != 0) {
                if (!vibe.transcription.isNullOrEmpty()) {
                    views.setTextViewText(transcriptionId, "\"" + vibe.transcription + "\"")
                    views.setViewVisibility(transcriptionId, View.VISIBLE)
                } else {
                    views.setViewVisibility(transcriptionId, View.GONE)
                }
            }
            
            // Unread indicator
            views.setViewVisibility(unreadId, if (vibe.isPlayed) View.GONE else View.VISIBLE)
            
            // Load image from local path (Flutter-Push Architecture)
            if (!vibe.imageUrl.isNullOrEmpty()) {
                // CRITICAL FIX: Use setSafeImage (Downsampling + URI method)
                // We have 3 slots, so URI method is mandatory to stay under 1MB Binder limit.
                WidgetUtils.setSafeImage(context, views, imageId, vibe.imageUrl, vibe.vibeId, 300)
            }
            
            // Deep link to player
            val playerIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("nock:///player/${vibe.vibeId}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId * 10 + slotNumber,
                playerIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            views.setOnClickPendingIntent(containerId, pendingIntent)
        }
        
        private fun formatTimeAgo(timestamp: Long): String {
            val now = System.currentTimeMillis()
            val diff = now - timestamp
            
            return when {
                diff < TimeUnit.MINUTES.toMillis(1) -> "now"
                diff < TimeUnit.HOURS.toMillis(1) -> "${TimeUnit.MILLISECONDS.toMinutes(diff)}m"
                diff < TimeUnit.DAYS.toMillis(1) -> "${TimeUnit.MILLISECONDS.toHours(diff)}h"
                else -> "${TimeUnit.MILLISECONDS.toDays(diff)}d"
            }
        }
    }
    
    data class VibeData(
        val vibeId: String,
        val senderName: String,
        val imageUrl: String?,
        val isPlayed: Boolean,
        val timestamp: Long,
        val transcription: String?
    )
    
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        Log.d(TAG, "onUpdate called for ${appWidgetIds.size} widgets")
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }
    
    override fun onEnabled(context: Context) {
        Log.d(TAG, "First Squad widget enabled")
    }
    
    override fun onDisabled(context: Context) {
        Log.d(TAG, "Last Squad widget disabled")
    }
}
