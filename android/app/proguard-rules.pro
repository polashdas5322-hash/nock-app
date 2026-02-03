# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Home Widget
-keep class es.antonborri.home_widget.** { *; }

# Vibe Widget Provider
-keep class com.vibe.vibe.VibeWidgetProvider { *; }

# Keep Kotlin coroutines
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}

# Keep callback methods for home_widget
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Prevent obfuscation of types which use ButterKnife annotations
-keep class butterknife.** { *; }
-dontwarn butterknife.internal.**
-keep class **$$ViewBinder { *; }

# Serializers
-keepattributes *Annotation*
-keep class * implements java.io.Serializable { *; }

# CRITICAL: Ignore missing Play Core classes (not used but referenced by Flutter engine)
# These are only needed for deferred components which we don't use
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.common.**

# FFmpeg Kit
-keep class com.arthenica.ffmpegkit.** { *; }
-dontwarn com.arthenica.ffmpegkit.**

# Audioplayers
-dontwarn xyz.luan.audioplayers.**

# Record
-dontwarn com.llfbandit.record.**
