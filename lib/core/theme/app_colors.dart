import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

/// Bioluminescent Noir Design System
/// 
/// A palette designed for high-intimacy social interactions among Gen Z.
/// Replaces the harsh Cyberpunk neons with organic, calming glows.
class AppColors {
  AppColors._();

  // --- Core Palette ---
  
  /// Bio-Lime: The primary action color. Organic, generative, and optimistic.
  static const Color bioLime = Color(0xFFD4F49C);
  
  /// Digital Lavender: Represents mental health, stability, and platonic love.
  static const Color digitalLavender = Color(0xFFE5D1FA);
  
  /// Void Navy: The restful, private background that reduces alert fatigue.
  /// UPDATED: Switched to Material Dark (#121212) per OLED optimization guidelines.
  static const Color voidNavy = Color(0xFF121212);
  
  /// Starlight: Softer alternative to pure white for text.
  static const Color starlight = Color(0xFFF0F2F5);

  // --- Backgrounds ---
  static const Color background = voidNavy;
  // Neutral dark variance for secondary backgrounds
  static const Color backgroundAlt = Color(0xFF1E1E1E); 
  // Slight elevation for cards (Material surface color)
  static const Color surface = Color(0xFF1E1E1E); 
  // Lighter surface for high elevation (Dialogs, Snackbars)
  static const Color surfaceLight = Color(0xFF2C2C2C);

  // --- Semantic Accents ---
  static const Color primaryAction = bioLime;
  static const Color secondaryAction = digitalLavender;
  static const Color success = bioLime;
  static const Color error = Color(0xFFFF6B6B); // Thermal Orange
  static const Color warning = Color(0xFFFFAA00);
  
  // --- Passive Layer ---
  static const Color textPrimary = starlight;
  static const Color textSecondary = Color(0xFFB0B0C5);
  static const Color textTertiary = Color(0xFF8489A1); // Lightened for WCAG AA (4.5:1)

  // --- Gradients ---
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bioLime, digitalLavender],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [surface, background],
  );

  // --- Luminous Borders (Spatial Glass Architecture) ---
  
  /// Luminous border - top edge (light catch effect)
  /// Used to simulate overhead light source hitting glass edge
  static const Color luminousBorderTop = Color(0x99FFFFFF); // 60% white
  
  /// Luminous border - bottom edge (fade to transparent)
  /// Creates the rim light effect by fading out at bottom
  static const Color luminousBorderBottom = Color(0x1AFFFFFF); // 10% white
  
  /// Gradient for luminous borders (top-to-bottom light fade)
  /// Apply this to border strokes for the Spatial Glass effect
  static const LinearGradient luminousBorderGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [luminousBorderTop, luminousBorderBottom],
  );
  
  /// Inner glow - light (for glass bevel effect)
  /// Simulates light bouncing inside the glass surface
  static const Color innerGlowLight = Color(0x4DFFFFFF); // 30% white
  
  /// Inner glow - dark (for depth and shadow)
  /// Adds subtle depth to create 3D glass appearance
  static const Color innerGlowDark = Color(0x1A000000); // 10% black

  // --- Theme Data ---
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: bioLime,
      colorScheme: const ColorScheme.dark(
        primary: bioLime,
        secondary: digitalLavender,
        surface: surface,
        onSurface: starlight,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: starlight, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: starlight),
        bodyMedium: TextStyle(color: starlight),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }

  // --- Legacy / Compatibility Members ---
  static const Color glassBackground = Color(0x1A121212); // #121212 with 10% alpha
  static const Color glassBackgroundDark = Color(0x33121212); // #121212 with 20% alpha
  static const Color glassBorder = Color(0x4DD4F49C); // bioLime with ~30% alpha
  static const Color urgency = error;
  static const Color telemetry = digitalLavender;
  static const Color vibePrimary = bioLime;
  static const Color vibeSecondary = digitalLavender;
  static const Color vibeBackground = voidNavy;
  static const Color vibeAccent = digitalLavender;
  static const Color statusLive = bioLime;
  static const Color statusRecording = error;
  static const Color statusOffline = textTertiary;
  static const Color retroTagText = textSecondary;
  static const Color surfaceCard = surface;

  // Aura legacy colors
  static const Color auraHappy = bioLime;
  static const Color auraWarm = Color(0xFFFED766);
  static const Color auraCool = digitalLavender;
  static const Color auraSad = Color(0xFF637081);
  static const Color auraNeutral = starlight;

  static const LinearGradient auraGradient = primaryGradient;

  /// Syncs the current theme colors to native widgets.
  static Future<void> syncThemeWithWidgets() async {
    final List<Future<void>> futures = [
      HomeWidget.saveWidgetData<String>('theme_primary', 'D4F49C'),
      HomeWidget.saveWidgetData<String>('theme_secondary', 'E5D1FA'),
      HomeWidget.saveWidgetData<String>('theme_background', '121212'),
      HomeWidget.saveWidgetData<String>('theme_starlight', 'F0F2F5'),
    ];
    await Future.wait(futures);
  }
}
