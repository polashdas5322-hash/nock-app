import 'package:flutter/material.dart';
import 'package:nock/features/camera/domain/models/drawing_stroke.dart';

/// Custom painter for drawing strokes on camera preview
/// Paints both completed strokes and the current in-progress stroke
class DrawingPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final List<Offset> currentStroke;
  final Color currentColor;
  final double currentStrokeWidth;

  DrawingPainter({
    required this.strokes,
    required this.currentStroke,
    required this.currentColor,
    required this.currentStrokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Base width for scaling stroke width (matches PlayerScreen strategy)
    final strokeScale = size.width / 360;

    // Draw completed strokes
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth * strokeScale
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      
      if (stroke.points.length > 1) {
        final path = Path();
        path.moveTo(stroke.points.first.dx * size.width, stroke.points.first.dy * size.height);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx * size.width, stroke.points[i].dy * size.height);
        }
        canvas.drawPath(path, paint);
      }
    }
    
    // Draw current stroke
    if (currentStroke.length > 1) {
      final paint = Paint()
        ..color = currentColor
        ..strokeWidth = currentStrokeWidth * strokeScale
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      
      final path = Path();
      path.moveTo(currentStroke.first.dx * size.width, currentStroke.first.dy * size.height);
      for (int i = 1; i < currentStroke.length; i++) {
        path.lineTo(currentStroke[i].dx * size.width, currentStroke[i].dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.currentStroke != currentStroke ||
        oldDelegate.currentColor != currentColor ||
        oldDelegate.currentStrokeWidth != currentStrokeWidth;
  }
}
