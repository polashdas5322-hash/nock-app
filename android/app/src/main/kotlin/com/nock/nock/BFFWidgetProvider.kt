package com.nock.nock

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.app.PendingIntent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import java.net.URL
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * BFF Widget Provider - 1-tap access to record for a specific friend
 * 
 * Features:
 * - Configurable friend selection (via BFFConfigActivity)
 * - Deep link to recording screen for that friend
 * - Shows friend avatar and streak
 * - Supports Lock Screen placement (Android 15+)
 */
class BFFWidgetProvider : AppWidgetProvider() {
    
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || 
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            Log.d(TAG, "Boot/Update received, refreshing BFF widget")
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, BFFWidgetProvider::class.java)
            )
            for (appWidgetId in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        }
    }
    
    companion object {
        private const val TAG = "BFFWidget"
        private const val PREFS_NAME = "HomeWidgetPrefs" // Standardized for HomeWidget plugin
        
        /**
         * Update a specific widget with friend data
         */
        fun updateWidget(context: Context, appWidgetId: Int) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
        
        /**
         * Update all BFF widgets
         */
        fun updateAll(context: Context) {
            val intent = Intent(context, BFFWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            }
            context.sendBroadcast(intent)
        }
        
        private fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            try {
                Log.d(TAG, "updateAppWidget: Starting for widget $appWidgetId")
                
                // 🚀 2026 STANDARD: Use HomeWidgetPlugin to ensure correct SharedPrefs bucket
                val widgetData = es.antonborri.home_widget.HomeWidgetPlugin.getData(context)
                
                // HomeWidget plugin does NOT use the "flutter." prefix by default
                val friendId = widgetData.getString("widget_${appWidgetId}_friendId", null)
                val friendName = widgetData.getString("widget_${appWidgetId}_name", "BFF") ?: "BFF"
                val friendAvatarUrl = widgetData.getString("widget_${appWidgetId}_avatar", null)
                
                Log.d(TAG, "updateAppWidget: friendId=$friendId, friendName=$friendName")
            
                val views = RemoteViews(context.packageName, R.layout.bff_widget_layout)

            // Set friend name with safety truncation for layout stability
            // 🧠 Zero State: Guide user if no friend selected
            val displayNameRaw = if (friendId.isNullOrEmpty()) "Tap to Setup" else friendName
            views.setTextViewText(R.id.friend_name, if (displayNameRaw.length > 15) displayNameRaw.take(12) + "..." else displayNameRaw)
            
            // Load avatar from local path (Flutter-Push Architecture)
            // Priority: 1. Global path (avatar_$friendId) 2. Instance path (friendAvatarUrl)
            val globalAvatarPath = if (friendId != null) widgetData.getString("avatar_$friendId", null) else null
            val avatarPath = globalAvatarPath ?: friendAvatarUrl

            if (!avatarPath.isNullOrEmpty()) {
                // CRITICAL FIX: Use setSafeImage (Downsampling + URI method)
                // Avatars are small, so 256px is plenty.
                WidgetUtils.setSafeImage(context, views, R.id.friend_avatar, avatarPath, friendId, 256)
            } else {
                // âœ¨ Zero State Fix: Show bioluminescent ring even if no friend selected
                // This signals "Potential" rather than an empty/broken feature.
                views.setImageViewResource(R.id.friend_avatar, R.drawable.circle_gradient)
                views.setInt(R.id.friend_avatar, "setAlpha", 180) // Slightly dimmer for background feel
            }
            
            // Deep link intent to recording screen - NOW LAUNCHES MAIN ACTIVITY (API 34 COMPLIANT)
            if (!friendId.isNullOrEmpty()) {
                val recordIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = Uri.parse("nock:///record/$friendId")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    recordIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            } else {
                // No friend configured - open config activity (MainActivity)
                val configIntent = Intent(context, MainActivity::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_CONFIGURE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    configIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }
            
            appWidgetManager.updateAppWidget(appWidgetId, views)
            Log.d(TAG, "updateAppWidget: Widget updated successfully")
            } catch (e: Exception) {
                Log.e(TAG, "updateAppWidget: ERROR - ${e.message}", e)
            }
        }
    }
    
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
    
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        // Clean up preferences when widgets are removed
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        
        for (appWidgetId in appWidgetIds) {
            editor.remove("widget_${appWidgetId}_friendId")
            editor.remove("widget_${appWidgetId}_name")
            editor.remove("widget_${appWidgetId}_avatar")
        }
        
        editor.apply()
        Log.d(TAG, "Cleaned up prefs for deleted widgets")
    }
    
    override fun onEnabled(context: Context) {
        Log.d(TAG, "First BFF widget enabled")
    }
    
    override fun onDisabled(context: Context) {
        Log.d(TAG, "Last BFF widget disabled")
    }
}
