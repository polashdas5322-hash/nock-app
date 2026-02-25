import 'package:flutter/material.dart';

/// A drawing stroke with color and width
/// Used by the camera's drawing overlay system
///
/// IMPORTANT: [points] must be stored as normalized coordinates (0.0 to 1.0)
/// relative to the capture area width and height.
class DrawingStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  const DrawingStroke({
    required this.points,
    required this.color,
    this.strokeWidth = 5.0,
  });

  /// Create a copy with new points added
  DrawingStroke copyWithPoint(Offset point) {
    return DrawingStroke(
      points: [...points, point],
      color: color,
      strokeWidth: strokeWidth,
    );
  }
}
