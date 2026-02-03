package com.nock.nock

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

object WidgetUtils {
    private const val WIDGET_CACHE_DIR = "widget_images"
    private const val PROVIDER_AUTHORITY = "com.nock.nock.provider"

    /**
     * Saves a bitmap to the cache directory and returns a content URI.
     * Uses JPEG to keep the file size minimal for the widget host.
     */
    fun saveBitmapAndGetUri(context: Context, bitmap: Bitmap, fileName: String): Uri? {
        val cacheDir = File(context.cacheDir, WIDGET_CACHE_DIR)
        if (!cacheDir.exists() && !cacheDir.mkdirs()) {
            return null
        }

        // Clean up old files with same prefix to avoid cache bloat
        // e.g. if fileName is "view_1_..." delete all "view_1_*"
        val prefix = fileName.substringBeforeLast("_") + "_"
        deleteFilesWithPrefix(context, prefix)

        val file = File(cacheDir, fileName)
        return try {
            FileOutputStream(file).use { out ->
                // Use JPEG for widgets - much smaller than PNG
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
            }
            FileProvider.getUriForFile(context, PROVIDER_AUTHORITY, file)
        } catch (e: IOException) {
            e.printStackTrace()
            null
        }
    }

    /**
     * Helper to set image on RemoteViews safely (downsampled + URI method).
     * This is the "Gold Standard" fix for TransactionTooLargeException.
     * 
     * @param vibeId Optional ID to look up local cached version if path is a URL
     */
    fun setSafeImage(context: Context, views: android.widget.RemoteViews, viewId: Int, path: String, vibeId: String? = null, targetSize: Int = 300) {
        try {
            var actualPath = path
            
            // 1. Resolve local cached path if needed
            if (path.startsWith("http") && vibeId != null) {
                val flutterFilesDir = File(context.filesDir, "widget_images")
                val files = listOf("vibe_image_$vibeId.png", "nock_image_$vibeId.png", "avatar_$vibeId.png")
                for (fileName in files) {
                    val file = File(flutterFilesDir, fileName)
                    if (file.exists()) {
                        actualPath = file.absolutePath
                        break
                    }
                }
            }

            val file = File(actualPath)
            if (!file.exists()) return

            // 2. Load downsampled bitmap (Binder Safe)
            // 300px @ RGB_565 is ~180KB. 3 of these = ~540KB. Well under 1MB limit.
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(actualPath, options)
            
            options.inSampleSize = calculateInSampleSize(options, targetSize, targetSize)
            options.inJustDecodeBounds = false
            options.inPreferredConfig = Bitmap.Config.RGB_565 
            
            val bitmap = BitmapFactory.decodeFile(actualPath, options)
            
            if (bitmap != null) {
                // 3. Directly set bitmap (Much more robust than URI for widgets)
                views.setImageViewBitmap(viewId, bitmap)
                android.util.Log.d("WidgetUtils", "Set bitmap for view $viewId from $actualPath")
            }
        } catch (e: Exception) {
            android.util.Log.e("WidgetUtils", "Error setting safe image: ${e.message}")
        }
    }

    fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val height: Int = options.outHeight
        val width: Int = options.outWidth
        var inSampleSize = 1
        if (height > reqHeight || width > reqWidth) {
            val halfHeight = height / 2
            val halfWidth = width / 2
            while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    /**
     * Cleans up old widget images from the cache.
     */
    fun clearCache(context: Context) {
        val cacheDir = File(context.cacheDir, WIDGET_CACHE_DIR)
        if (cacheDir.exists()) {
            cacheDir.listFiles()?.forEach { it.delete() }
        }
    }

    /**
     * Deletes files starting with the given prefix.
     * Used to clean up old timestamped images for a specific widget.
     */
    fun deleteFilesWithPrefix(context: Context, prefix: String) {
        val cacheDir = File(context.cacheDir, WIDGET_CACHE_DIR)
        if (cacheDir.exists()) {
            cacheDir.listFiles()?.forEach { file ->
                if (file.name.startsWith(prefix)) {
                    file.delete()
                }
            }
        }
    }

    /**
     * Checks if a file exists in the cache and returns its URI.
     * Used to avoid redundant network calls.
     */
    fun getCachedUri(context: Context, fileName: String): Uri? {
        val cacheDir = File(context.cacheDir, WIDGET_CACHE_DIR)
        val file = File(cacheDir, fileName)
        
        return if (file.exists()) {
            FileProvider.getUriForFile(context, PROVIDER_AUTHORITY, file)
        } else {
            null
        }
    }
}
