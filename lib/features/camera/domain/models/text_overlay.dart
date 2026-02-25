import 'package:flutter/material.dart';
import '../../../../core/theme/app_typography.dart';

/// Font styles for NoteIt-style text editing
enum TextFontStyle {
  classic, // Clean sans-serif
  handwritten, // Playful handwritten
  bold, // Heavy impact
  retro, // Monospace/retro
  neon, // Glowing effect
}

extension TextFontStyleExtension on TextFontStyle {
  String get displayName {
    switch (this) {
      case TextFontStyle.classic:
        return 'Classic';
      case TextFontStyle.handwritten:
        return 'Script';
      case TextFontStyle.bold:
        return 'Bold';
      case TextFontStyle.retro:
        return 'Retro';
      case TextFontStyle.neon:
        return 'Neon';
    }
  }

  TextStyle getStyle(double fontSize, Color color) {
    switch (this) {
      case TextFontStyle.classic:
        return AppTypography.bodyMedium.copyWith(
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.w500,
        );
      case TextFontStyle.handwritten:
        return AppTypography.handwritten.copyWith(
          fontSize: fontSize,
          color: color,
        );
      case TextFontStyle.bold:
        return AppTypography.bodyMedium.copyWith(
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.w900,
        );
      case TextFontStyle.retro:
        return AppTypography.displayMedium.copyWith(
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.w600,
        );
      case TextFontStyle.neon:
        return AppTypography.bodyMedium.copyWith(
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: color.withAlpha(179), blurRadius: 10),
            Shadow(color: color.withAlpha(128), blurRadius: 20),
          ],
        );
    }
  }
}

/// A text overlay item with font style support
///
/// IMPORTANT: [position] must be stored as normalized coordinates (0.0 to 1.0)
/// relative to the capture area width and height.
class TextOverlay {
  String text;
  Offset position;
  Color color;
  double fontSize;
  TextFontStyle fontStyle;
  double scale;
  double rotation;

  TextOverlay({
    required this.text,
    required this.position,
    this.color = Colors.white,
    this.fontSize = 32,
    this.fontStyle = TextFontStyle.classic,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  /// Create a copy with updated properties
  TextOverlay copyWith({
    String? text,
    Offset? position,
    Color? color,
    double? fontSize,
    TextFontStyle? fontStyle,
    double? scale,
    double? rotation,
  }) {
    return TextOverlay(
      text: text ?? this.text,
      position: position ?? this.position,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      fontStyle: fontStyle ?? this.fontStyle,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }
}
