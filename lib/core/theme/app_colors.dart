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

  // Glass Surfaces (Standardized Opacities)
  static final Color surfaceGlassLow = Colors.white.withOpacity(0.05);
  static final Color surfaceGlassMedium = Colors.white.withOpacity(0.1);
  static final Color surfaceGlassDim = Colors.white.withOpacity(
    0.1,
  ); // Alias for 10% white
  static final Color surfaceGlassHigh = Colors.white.withOpacity(0.2);

  static final Color surfaceSubtle = Colors.white.withOpacity(0.03);
  static final Color borderSubtle = Colors.white.withOpacity(0.05);

  // --- Semantic Accents ---
  static const Color primaryAction = bioLime;
  static const Color secondaryAction = Color(0xFF00FFFF); // Cyan
  static const Color urgency = Color(0xFFFF3366); // Cyber-Red
  static const Color error = urgency;
  static const Color warning = Color(0xFFFFAA00);
  static const Color success = Color(
    0xFF2E7D32,
  ); // Green success (Material green.shade800)
  static const Color telemetry = Color(0xFFB388FF); // Lavender

  // --- NEW MASTER FIX TOKENS (100% Compliance) ---

  // 1. Semantic Text Colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Colors.white54;
  static const Color textPlaceholder = Color(0xFF424242);
  static const Color textTertiary = Color(0xFF8489A1);
  static const Color textInverse = Colors.black;
  static const Color textDetail = Color(0xFF8489A1); // Alias for Tertiary

  // 6. Semantic Surfaces
  static const Color surfaceWarm = Color(
    0xFF252525,
  ); // Warmer background for calmer areas

  // 2. Bento Card Gradients
  static const Color surfaceDark = Color(0xFF111111);
  static const Color surfaceDarker = Color(0xFF0D0D0D);
  static const Color cardBorder = Color(0xFF0F0F0F);

  // 3. Specific Accents
  static const Color electricBlue = Color(0xFF0055FF); // Clusters
  static const Color bioCyan = Colors.cyan; // Orb gradients

  // Edit Mode Accents
  static const Color accentCoral = Color(0xFFFF6B6B); // Draw mode
  static const Color accentTeal = Color(0xFF4ECDC4); // Sticker mode
  static const Color accentPurple = Color(0xFF667EEA); // Text mode
  static const Color accentCyan = Color(0xFF00F0FF); // Audio / Electric Cyan

  // 4. Utilities
  static const Color shadow = Colors.black26;
  static const Color transparent = Colors.transparent;
  static const Color surfaceDialog = Color(0xFF222222);
  static const Color instagramBrand = Color(0xFFDD2A7B);
  static const Color glassBorderLight = Colors.white24;

  // 5. Palettes
  static const List<Color> drawingPalette = [
    Color(0xFFF0F0F0), // Ghost White
    Color(0xFF39FF14), // Acid Green
    Color(0xFF00F0FF), // Electric Cyan
    Color(0xFFFF2A6D), // Glitch Red
    Color(0xFF00FF9F), // Spring Green
    Color(0xFF586069), // Gunmetal Grey
    Colors.black,
  ];

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

  // --- Legacy / Compatibility Members (Restored) ---
  static const Color glassBackground = Color(
    0x1A121212,
  ); // #121212 with 10% alpha
  static const Color glassBackgroundDark = Color(
    0x33121212,
  ); // #121212 with 20% alpha
  static const Color glassBorder = Color(0x4DD4F49C); // bioLime with ~30% alpha
  static const Color vibePrimary = bioLime;
  static const Color vibeSecondary = digitalLavender;
  static const Color vibeBackground = voidNavy;
  static const Color vibeAccent = digitalLavender;
  static const Color statusLive = bioLime;
  static const Color statusRecording = error;
  static const Color statusOffline = textTertiary;
  static const Color retroTagText = textSecondary;
  static const Color surfaceCard = surface;

  // Aura visualization colors
  static const Color auraHappy = bioLime;
  static const Color auraWarm = Color(0xFFFED766);
  static const Color auraCool = digitalLavender;
  static const Color auraSad = Color(0xFF637081);
  static const Color auraNeutral = starlight;
  static const LinearGradient auraGradient = primaryGradient;

  // Luminous Borders
  static const Color luminousBorderTop = Color(0x99FFFFFF);
  static const Color luminousBorderBottom = Color(0x1AFFFFFF);
  static const LinearGradient luminousBorderGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [luminousBorderTop, luminousBorderBottom],
  );
  static const Color innerGlowLight = Color(0x4DFFFFFF);
  static const Color innerGlowDark = Color(0x1A000000);

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
