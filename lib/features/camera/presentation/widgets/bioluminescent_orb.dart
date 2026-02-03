import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:nock/core/theme/app_colors.dart';

/// EXPANDED: The V2 "Transmodal Orb"
/// Features:
/// 1. Pulsating Ripple Background (CustomPainter) - "The Living Breath"
/// 2. Progress Ring (CustomPainter) - "The Timer"
/// 3. Glassmorphic Core - "The Object"
class BioluminescentOrb extends StatefulWidget {
  final bool isRecording;
  final int durationSeconds;
  final double amplitude; // 0.0 to 1.0
  final VoidCallback onTap;

  const BioluminescentOrb({
    super.key,
    required this.isRecording,
    required this.durationSeconds,
    this.amplitude = 0.0,
    required this.onTap,
  });

  @override
  State<BioluminescentOrb> createState() => _BioluminescentOrbState();
}

class _BioluminescentOrbState extends State<BioluminescentOrb> with SingleTickerProviderStateMixin {
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

    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. PULSATING RIPPLES (Background)
          // Only active when recording
          if (widget.isRecording)
            AnimatedBuilder(
              animation: _rippleController,
              builder: (context, child) {
                return CustomPaint(
                  painter: PulsatingCirclesPainter(
                    animation: _rippleController,
                    color: AppColors.telemetry, // Lavender
                  ),
                  size: const Size(300, 300), // Canvas size for ripples
                );
              },
            ),

          // 2. PROGRESS RING (Mid-layer)
          // Wraps strictly around the orb
          if (widget.isRecording)
            SizedBox(
              width: _coreSize + 24, // Slight padding
              height: _coreSize + 24,
              child: CustomPaint(
                painter: ProgressRingPainter(
                  // Map seconds to 0..1 (60s loop)
                  progress: (widget.durationSeconds % 60) / 60.0,
                  color: Colors.white.withOpacity(0.3),
                  activeColor: Colors.white,
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.isRecording
                      ? [
                          const Color(0xFFE5D1FA).withOpacity(0.9), // Solid Lavender
                          const Color(0xFFD8B4FE).withOpacity(0.7),
                        ]
                      : [
                          AppColors.primaryAction.withOpacity(0.8), // Bio-Lime
                          Colors.cyan.withOpacity(0.6),
                        ],
                ),
                boxShadow: [
                  // Core Glow
                  BoxShadow(
                    color: (widget.isRecording ? AppColors.telemetry : AppColors.primaryAction)
                        .withOpacity(0.5),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                  // Rim Reflection
                  BoxShadow(
                    color: Colors.white.withOpacity(0.4),
                    blurRadius: 10,
                    spreadRadius: -2,
                    offset: const Offset(-4, -4),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: widget.isRecording
                    ? Text(
                        _formatDuration(widget.durationSeconds),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      )
                    : PhosphorIcon(
                        PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                        size: 56,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
        ],
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
        ..style = PaintingStyle.stroke // FIXED: Ring ripple instead of muddy fill
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
