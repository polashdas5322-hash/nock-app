import 'dart:math' as math;
import 'package:nock/shared/widgets/app_icon.dart';
import 'package:flutter/material.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';

/// EXPANDED: The V2 "Transmodal Orb"
/// Features:
/// 1. Pulsating Ripple Background (CustomPainter) - "The Living Breath"
/// 2. Progress Ring (CustomPainter) - "The Timer"
/// 3. Glassmorphic Core - "The Object"
class BioluminescentOrb extends StatefulWidget {
  final bool isRecording;
  final int durationSeconds;

  final double? progress; // Override internal timer (0.0 to 1.0)
  final Widget? centerOverride; // Override default Mic/Timer
  final bool showProgressRing; // Control visibility of progress ring

  final double amplitude; // 0.0 to 1.0
  final VoidCallback onTap;

  const BioluminescentOrb({
    super.key,
    required this.isRecording,
    required this.durationSeconds,
    this.amplitude = 0.0,
    required this.onTap,
    this.progress,
    this.centerOverride,
    this.showProgressRing = true, // Default to true (show ring)
  });

  @override
  State<BioluminescentOrb> createState() => _BioluminescentOrbState();
}

class _BioluminescentOrbState extends State<BioluminescentOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _rippleController;

  // Base size of the core orb
  static const double _coreSize = 140.0;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // Slow, deep breath
    );

    if (widget.isRecording) {
      _rippleController.repeat();
    }
  }

  @override
  void didUpdateWidget(BioluminescentOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording != oldWidget.isRecording) {
      if (widget.isRecording) {
        _rippleController.repeat();
      } else {
        _rippleController.stop();
        _rippleController.reset();
      }
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reactive Pulse: Scale core based on voice amplitude
    final pulseScale = 1.0 + (widget.amplitude * 0.15);

    // ACCESSIBILITY FIX: Added Semantics for screen readers
    return Semantics(
      button: true,
      label: widget.isRecording ? 'Stop Recording' : 'Start Recording',
      value: widget.isRecording
          ? 'Recording in progress. ${_formatDuration(widget.durationSeconds)} elapsed.'
          : 'Ready to record',
      onTap: widget.onTap,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. PULSATING RIPPLES (Background)
            // Only active when recording to reduce visual clutter in idle state
            if (widget.isRecording)
              AnimatedBuilder(
                animation: _rippleController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: PulsatingCirclesPainter(
                      animation: _rippleController,
                      // FIX: Changed from AppColors.telemetry (Lavender) to primaryAction (Green)
                      color: AppColors.primaryAction,
                    ),
                    size: const Size(300, 300), // Canvas size for ripples
                  );
                },
              ),

            // 2. PROGRESS RING (Mid-layer)
            // Wraps strictly around the orb
            if (widget.showProgressRing &&
                (widget.isRecording || widget.progress != null))
              SizedBox(
                width: _coreSize + 24, // Slight padding
                height: _coreSize + 24,
                child: CustomPaint(
                  painter: ProgressRingPainter(
                    // Map seconds to 0..1 (60s loop) OR use override
                    progress:
                        widget.progress ??
                        ((widget.durationSeconds % 60) / 60.0),
                    color: AppColors.textPrimary.withOpacity(0.3),
                    activeColor: AppColors.textPrimary,
                  ),
                ),
              ),

            // 3. GLASSMORPHIC CORE (Foreground)
            Transform.scale(
              scale: pulseScale,
              child: Container(
                width: _coreSize,
                height: _coreSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // FIX: UNIFIED GRADIENT (Always Green/Bio-Lime)
                  // We keep the "Radioactive" look consistent across states
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryAction.withOpacity(0.9), // Bio-Lime
                      AppColors.bioCyan.withOpacity(
                        0.6,
                      ), // Electric Cyan accent
                    ],
                  ),
                  boxShadow: [
                    // Core Glow
                    BoxShadow(
                      // FIX: Always use primaryAction (Green)
                      color: AppColors.primaryAction.withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                    // Rim Reflection
                    BoxShadow(
                      color: AppColors.textPrimary.withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: -2,
                      offset: const Offset(-4, -4),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.textPrimary.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child:
                      widget.centerOverride ??
                      (widget.isRecording
                          ? Text(
                              _formatDuration(widget.durationSeconds),
                              style: AppTypography.displayMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                shadows: [
                                  BoxShadow(
                                    color: AppColors.shadow,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            )
                          : AppIcon(
                              PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                              size: 56,
                              color: AppColors.textPrimary,
                            )),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}

// --- PAINTERS ---

class PulsatingCirclesPainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;

  PulsatingCirclesPainter({required this.animation, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Base radius matches the core orb roughly
    final baseRadius = 70.0;
    final maxRadius = size.width * 0.45; // Expand to ~135

    // Draw 3 distinct ripples that travel outwards
    for (int i = 0; i < 3; i++) {
      // Offset the phase for each ripple so they don't overlap perfectly
      // (animation.value + offset) % 1.0
      final double phase = (animation.value + (i * 0.33)) % 1.0;

      // Radius expands with phase
      final double radius = baseRadius + (maxRadius - baseRadius) * phase;

      // Opacity fades out as it expands (Bell curve or linear fade)
      // Starts at 0.5, ends at 0.0
      final double opacity = (1.0 - phase) * 0.4;

      final paint = Paint()
        ..color = color.withOpacity(opacity.clamp(0.0, 1.0))
        ..style = PaintingStyle
            .stroke // FIXED: Ring ripple instead of muddy fill
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PulsatingCirclesPainter oldDelegate) => true;
}

class ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color activeColor;

  ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 4;
    const strokeWidth = 3.0;

    // 1. Background Track
    final backgroundPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, backgroundPaint);

    // 2. Active Arc
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Start from top (-90 degrees)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
