import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Vibe App Typography System - 2025 Standards
///
/// Typography Pairing:
/// - HEADERS: SpaceMono (cyberpunk/tech aesthetic for branding)
/// - BODY: Inter (modern geometric sans-serif for readability)
/// - RETRO: SpaceMono (timestamps, tags, data displays)
class AppTypography {
  AppTypography._();

  // ============ DISPLAY STYLES (Space Grotesk - Organic Tech) ============

  static TextStyle get displayLarge => TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 48,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: -1.5, // Tighter tracking looks more premium
    height: 1.1,
  );

  static TextStyle get displayMedium => TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 36,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: -1.0,
    height: 1.1,
  );

  static TextStyle get displaySmall => TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  // ============ HEADLINE STYLES (Space Grotesk - Section Headers) ============

  static TextStyle get headlineLarge => TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static TextStyle get headlineMedium => TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get headlineSmall => TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // ============ BODY STYLES (Inter - Readable Content) ============

  static TextStyle get bodyLarge => TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle get bodyMedium => TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get bodySmall => TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // ============ LABEL STYLES (Inter - UI Elements) ============

  static TextStyle get labelLarge => TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0.3,
  );

  static TextStyle get labelMedium => TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0.3,
  );

  // Replace all 'fontSize: 11' usages with this
  static TextStyle get labelSmall => TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
    letterSpacing: 0.3,
  );

  // Replace all 'fontSize: 9' usages with this
  static TextStyle get labelExtraSmall => TextStyle(
    fontFamily: 'Inter',
    fontSize: 9,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
    letterSpacing: 0.3,
  );

  // ============ BUTTON STYLES (Inter - Call to Actions) ============

  static TextStyle get buttonText => TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.background,
    letterSpacing: 0.5,
  );

  static TextStyle get buttonTextSmall => TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.background,
    letterSpacing: 0.3,
  );

  // ============ SPECIAL STYLES (Mix of Grotesk & Mono) ============

  // Use Grotesk for UI accents
  static TextStyle get accentText => TextStyle(
    fontFamily: 'SpaceGrotesk',
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: AppColors.primaryAction,
    letterSpacing: 0.5,
  );

  // Strictly for decorative headers, tags, and HUD elements
  static TextStyle get retroTag => TextStyle(
    fontFamily: 'SpaceMono',
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AppColors.retroTagText,
    letterSpacing: 1.5,
  );

  static TextStyle get statusText => TextStyle(
    fontFamily: 'SpaceMono',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.statusLive,
  );

  // ============ CAPTION STYLES (Inter - Descriptions) ============

  static TextStyle get caption => TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.textTertiary,
    height: 1.3,
  );

  static TextStyle get captionAccent => TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.primaryAction,
    height: 1.3,
  );

  // ============ HANDWRITTEN STYLES (Permanent Marker - Notes) ============

  static TextStyle get handwritten => GoogleFonts.permanentMarker(
    fontSize: 24, // Slightly larger for readability
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    letterSpacing: 0.5,
  );
}
