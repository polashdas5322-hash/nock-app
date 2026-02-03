import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nock/core/services/audio_service.dart';
import 'package:nock/core/theme/app_colors.dart';

/// Isolated leaf widget for high-frequency waveform updates.
/// 
/// This prevents "Waveform Rebuild Storms" by containing the ref.watch 
/// and isolating repaints via RepaintBoundary.
class WaveformVisualizer extends ConsumerWidget {
  final int barCount;
  final double height;
  final double width;
  final Color? color;
  final bool isPlaying;

  const WaveformVisualizer({
    super.key,
    this.barCount = 10,
    this.height = 24,
    this.width = double.infinity,
    this.color,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. ISOLATED WATCH: Only this widget rebuilds every 100ms
    final waveformData = ref.watch(waveformDataProvider);

    // 2. REPAINT BOUNDARY: Firewalls the GPU from redrawing heavy layers (Camera Texture)
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (index) {
            double value = 0.3; // Default resting height
            
            if (waveformData.isNotEmpty) {
              final step = (waveformData.length / barCount).ceil();
              final dataIndex = (index * step).clamp(0, waveformData.length - 1);
              value = waveformData[dataIndex];
            }
            
            final barHeight = (value * height).clamp(height * 0.2, height);
            
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 3,
              height: barHeight,
              decoration: BoxDecoration(
                color: color ?? (isPlaying ? AppColors.primaryAction : Colors.white.withOpacity(0.7)),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ),
    );
  }
}
