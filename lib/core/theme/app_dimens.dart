
/// **AppDimens**
///
/// Single source of truth for layout dimensions, padding, margins, and border radii.
/// Replaces hardcoded pixel values to ensure consistency and responsiveness.
class AppDimens {
  // Padding & Margins (Based on 4pt/2pt grid)
  static const double p2 = 2.0;
  static const double p4 = 4.0;
  static const double p8 = 8.0;
  static const double p12 = 12.0;
  static const double p16 = 16.0;
  static const double p20 = 20.0;
  static const double p24 = 24.0;
  static const double p32 = 32.0;
  static const double p40 = 40.0;
  static const double p48 = 48.0;
  static const double p64 = 64.0;

  // Border Radii
  static const double r4 = 4.0;
  static const double r8 = 8.0;
  static const double r12 = 12.0;
  static const double r16 = 16.0; // Standard Card
  static const double r20 = 20.0;
  static const double r24 = 24.0; // Large Card
  static const double r32 = 32.0; // Pill
  static const double rFull = 999.0; // Circle

  // Icon Sizes
  static const double iconXS = 16.0; // Small indicators
  static const double iconS = 20.0; // Inline icons
  static const double iconM = 24.0; // Standard actions
  static const double iconL = 32.0; // Large actions
  static const double iconXL = 48.0; // Hero icons

  // Layout Constants
  static const double bottomNavBarHeight = 60.0;
  static const double buttonHeight = 56.0;
  static const double touchTarget = 48.0; // Accessibility minimum

  // Widget Specific
  static const double glassBorderWidth = 1.0;
  static const double activeBorderWidth = 2.0;
}
