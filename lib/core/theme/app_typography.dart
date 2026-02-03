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

  // ============ DISPLAY STYLES (SpaceMono - Brand Identity) ============
  
  static TextStyle get displayLarge => GoogleFonts.spaceMono(
    fontSize: 48,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: -1,
  );

  static TextStyle get displayMedium => GoogleFonts.spaceMono(
    fontSize: 36,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static TextStyle get displaySmall => GoogleFonts.spaceMono(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );

  // ============ HEADLINE STYLES (SpaceMono - Section Headers) ============
  
  static TextStyle get headlineLarge => GoogleFonts.spaceMono(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get headlineMedium => GoogleFonts.spaceMono(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get headlineSmall => GoogleFonts.spaceMono(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // ============ BODY STYLES (Inter - Readable Content) ============
  
  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // ============ LABEL STYLES (Inter - UI Elements) ============
  
  static TextStyle get labelLarge => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0.3,
  );

  static TextStyle get labelMedium => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0.3,
  );

  static TextStyle get labelSmall => GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: AppColors.textTertiary,
    letterSpacing: 0.3,
  );

  // ============ BUTTON STYLES (Inter - Call to Actions) ============
  
  static TextStyle get buttonText => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.background,
    letterSpacing: 0.5,
  );

  static TextStyle get buttonTextSmall => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.background,
    letterSpacing: 0.3,
  );

  // ============ SPECIAL STYLES (SpaceMono - Data/Retro) ============
  
  static TextStyle get accentText => GoogleFonts.spaceMono(
    fontSize: 14,
    fontWeight: FontWeight.bold,
    color: AppColors.primaryAction,
    letterSpacing: 0.5,
  );

  static TextStyle get retroTag => GoogleFonts.spaceMono(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: AppColors.retroTagText,
    letterSpacing: 1.5,
  );

  static TextStyle get statusText => GoogleFonts.spaceMono(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.statusLive,
  );

  static TextStyle get timestampText => GoogleFonts.spaceMono(
    fontSize: 10,
    fontWeight: FontWeight.normal,
    color: AppColors.textTertiary,
    letterSpacing: 0.5,
  );

  static TextStyle get dataText => GoogleFonts.spaceMono(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0.5,
  );

  // ============ CAPTION STYLES (Inter - Descriptions) ============
  
  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.textTertiary,
    height: 1.3,
  );

  static TextStyle get captionAccent => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.primaryAction,
    height: 1.3,
  );

  // ============ HANDWRITTEN STYLES (Permanent Marker - Notes) ============
  
  static TextStyle get handwritten => GoogleFonts.permanentMarker(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    letterSpacing: 0.5,
  );
}
