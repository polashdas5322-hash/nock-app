import 'package:nock/core/theme/app_icons.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nock/core/theme/app_colors.dart';

/// Aura Visualization Widget
/// Creates a glowing, pulsing color blob that responds to audio
/// Maps volume to size and pitch/sentiment to color
class AuraVisualization extends StatefulWidget {
  final List<double> waveformData;
  final bool isRecording;
  final bool isPlaying;
  final double size;
  final AuraMood mood;

  const AuraVisualization({
    super.key,
    this.waveformData = const [],
    this.isRecording = false,
    this.isPlaying = false,
    this.size = 200,
    this.mood = AuraMood.neutral,
  });

  @override
  State<AuraVisualization> createState() => _AuraVisualizationState();
}

class _AuraVisualizationState extends State<AuraVisualization>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _rotationController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Check initial state
    if (widget.isRecording || widget.isPlaying) {
      _pulseController.repeat(reverse: true);
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(AuraVisualization oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isActive = widget.isRecording || widget.isPlaying;
    final wasActive = oldWidget.isRecording || oldWidget.isPlaying;

    if (isActive != wasActive) {
      if (isActive) {
        _pulseController.repeat(reverse: true);
        _rotationController.repeat();
      } else {
        _pulseController.stop();
        _pulseController.reset();
        _rotationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  Color get _primaryColor {
    switch (widget.mood) {
      case AuraMood.happy:
        return AppColors.auraHappy;
      case AuraMood.excited:
        return AppColors.auraWarm;
      case AuraMood.calm:
        return AppColors.auraCool;
      case AuraMood.sad:
        return AppColors.auraSad;
      case AuraMood.neutral:
      default:
        return AppColors.auraNeutral;
    }
  }

  Color get _secondaryColor {
    switch (widget.mood) {
      case AuraMood.happy:
        return AppColors.auraWarm;
      case AuraMood.excited:
        return AppColors.secondaryAction;
      case AuraMood.calm:
        return AppColors.auraSad;
      case AuraMood.sad:
        return AppColors.auraCool;
      case AuraMood.neutral:
      default:
        return AppColors.primaryAction;
    }
  }

  double get _currentAmplitude {
    if (widget.waveformData.isEmpty) return 0.5;
    return widget.waveformData.last.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isRecording || widget.isPlaying;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _rotationController]),
      builder: (context, child) {
        final baseScale = isActive
            ? 0.8 + (_currentAmplitude * 0.4)
            : 0.9; // Static rest state (no pulsing)

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow
              Transform.scale(
                scale: baseScale * 1.2,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _primaryColor.withOpacity(0.3),
                        _primaryColor.withOpacity(0.1),
                        AppColors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Middle layer - rotating gradient
              Transform.rotate(
                angle: _rotationController.value * 2 * math.pi,
                child: Transform.scale(
                  scale: baseScale,
                  child: Container(
                    width: widget.size * 0.8,
                    height: widget.size * 0.8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: [
                          _primaryColor,
                          _secondaryColor,
                          _primaryColor.withOpacity(0.5),
                          _secondaryColor.withOpacity(0.5),
                          _primaryColor,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Core blob with blur
              Transform.scale(
                scale: baseScale * 0.9,
                child: Container(
                  width: widget.size * 0.6,
                  height: widget.size * 0.6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.textPrimary.withOpacity(0.9),
                        _primaryColor.withOpacity(0.8),
                        _secondaryColor.withOpacity(0.6),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryColor.withOpacity(0.5),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),

              // Waveform overlay when active
              if (isActive && widget.waveformData.isNotEmpty)
                RepaintBoundary(
                  child: CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: WaveformPainter(
                      waveformData: List.from(
                        widget.waveformData,
                      ), // Pass a snapshot
                      color: AppColors.textPrimary.withOpacity(0.5),
                    ),
                  ),
                ),

              // Center icon
              Icon(
                widget.isRecording
                    ? AppIcons.mic
                    : widget.isPlaying
                    ? AppIcons.volumeUp
                    : AppIcons.touch,
                color: AppColors.background,
                size: widget.size * 0.2,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Waveform painter for the aura center
class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final Color color;

  WaveformPainter({required this.waveformData, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    final centerY = size.height / 2;
    final width = size.width;
    final barWidth = width / waveformData.length;

    for (int i = 0; i < waveformData.length; i++) {
      final x = i * barWidth;
      final amplitude = waveformData[i] * size.height * 0.3;

      if (i == 0) {
        path.moveTo(x, centerY - amplitude);
      } else {
        path.lineTo(x, centerY - amplitude);
      }
    }

    // Mirror the waveform
    for (int i = waveformData.length - 1; i >= 0; i--) {
      final x = i * barWidth;
      final amplitude = waveformData[i] * size.height * 0.3;
      path.lineTo(x, centerY + amplitude);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    // Robust comparison: length check first (fast), then reference check
    if (oldDelegate.waveformData.length != waveformData.length) return true;
    return oldDelegate.waveformData != waveformData ||
        oldDelegate.color != color;
  }
}

/// Mood types for Aura visualization
enum AuraMood {
  happy, // Yellow/Gold
  excited, // Orange/Pink
  calm, // Blue
  sad, // Purple
  neutral, // Cyan
}

/// Simple waveform bar visualization
class WaveformBars extends StatelessWidget {
  final List<double> waveformData;
  final double height;
  final Color color;
  final int barCount;

  const WaveformBars({
    super.key,
    required this.waveformData,
    this.height = 40,
    this.color = AppColors.primaryAction,
    this.barCount = 30,
  });

  @override
  Widget build(BuildContext context) {
    final displayData = _normalizeData();

    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(barCount, (index) {
          final value = displayData.length > index ? displayData[index] : 0.1;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 3,
            height: height * value.clamp(0.1, 1.0),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }),
      ),
    );
  }

  List<double> _normalizeData() {
    if (waveformData.isEmpty) {
      return List.generate(barCount, (_) => 0.1);
    }

    // Sample the waveform data to match bar count
    final step = waveformData.length / barCount;
    return List.generate(barCount, (i) {
      final index = (i * step).floor().clamp(0, waveformData.length - 1);
      return waveformData[index];
    });
  }
}
