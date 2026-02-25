import 'package:flutter/material.dart';

/// Custom painter for corner progress indicator during video recording
/// Draws an animated rounded rectangle border that fills based on progress
class CornerProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final double cornerRadius;

  CornerProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.cornerRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));

    final fullPath = Path()..addRRect(rrect);
    final pathMetrics = fullPath.computeMetrics().first;
    final extractPath = pathMetrics.extractPath(
      0,
      pathMetrics.length * progress,
    );

    // Glow effect
    final glowPaint = Paint()
      ..color = color.withAlpha(102)
      ..strokeWidth = strokeWidth + 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawPath(extractPath, glowPaint);
    canvas.drawPath(extractPath, paint);
  }

  @override
  bool shouldRepaint(CornerProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
