import 'package:flutter/material.dart';

/// A sticker overlay item
/// Represents an emoji sticker placed on the camera capture
/// 
/// IMPORTANT: [position] must be stored as normalized coordinates (0.0 to 1.0)
/// relative to the capture area width and height.
class StickerOverlay {
  String emoji;
  Offset position;
  double scale;
  double rotation;

  StickerOverlay({
    required this.emoji,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
  });
  
  /// Create a copy with updated position
  StickerOverlay copyWith({
    String? emoji,
    Offset? position,
    double? scale,
    double? rotation,
  }) {
    return StickerOverlay(
      emoji: emoji ?? this.emoji,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }
}
