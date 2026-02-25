import 'package:flutter/material.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/shared/widgets/aura_visualization.dart';

/// Splash Screen - Static logo for seamless native transition
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Aura visualization (Static)
            const AuraVisualization(
              size: 200,
              isRecording: false,
              mood: AuraMood.neutral,
            ),
            const SizedBox(height: 40),
            // App name
            ShaderMask(
              shaderCallback: (bounds) =>
                  AppColors.primaryGradient.createShader(bounds),
              child: Text(
                'VIBE',
                style: AppTypography.displayLarge.copyWith(
                  color: Colors.white,
                  letterSpacing: 8,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Feel the connection',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
