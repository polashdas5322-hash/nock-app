import 'package:nock/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/providers/onboarding_provider.dart';
import 'package:nock/shared/widgets/glass_container.dart';

/// THE MAGIC SCREEN (Step 3 of 4)
///
/// "Make your home screen alive."
///
/// This screen guides the user to add the widget.
/// We use an "Honest Button" ("I've added it") because programmatic detection is unreliable.
class WidgetSetupScreen extends ConsumerStatefulWidget {
  const WidgetSetupScreen({super.key});

  @override
  ConsumerState<WidgetSetupScreen> createState() => _WidgetSetupScreenState();
}

class _WidgetSetupScreenState extends ConsumerState<WidgetSetupScreen> {
  bool _isChecking = false;

  Future<void> _finishOnboarding() async {
    setState(() => _isChecking = true);

    // 1. Mark onboarding as complete
    // The AppRouter is watching this provider and will automatically
    // redirect to Home when this completes.
    // REMOVED: context.go(AppRoutes.home) to avoid Double Navigation Race Condition.
    await ref.read(onboardingStateProvider.notifier).completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.vibeSecondary.withOpacity(0.15),
                    AppColors.background,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                children: [
                  const Spacer(flex: 1),

                  // Visual Preview (Phone Mockup or Illustration)
                  _buildWidgetPreview(),

                  const SizedBox(height: 40),

                  // Copy
                  Text('The Magic', style: AppTypography.displaySmall),
                  const SizedBox(height: 12),
                  Text(
                    'Add the Nock widget to your home screen to see live moments from your squad.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Instructions (Platform Specific)
                  _buildInstructions(),

                  const SizedBox(height: 32),

                  // Action: "I've added it"
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isChecking ? null : _finishOnboarding,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.vibePrimary,
                        foregroundColor: AppColors.textInverse,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isChecking
                          ? const CircularProgressIndicator(
                              color: AppColors.textInverse,
                            )
                          : Text(
                              "I've Added It",
                              style: AppTypography.labelLarge.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Skip (Small)
                  TextButton(
                    onPressed: _finishOnboarding,
                    child: Text(
                      'Do it later',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetPreview() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.glassBorder, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.vibePrimary.withOpacity(0.3),
            blurRadius: 40,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      // Mockup Content
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Placeholder Image
            Container(color: AppColors.surface),

            // "Camera" Icon in center
            Center(
              child: Icon(
                AppIcons.camera,
                size: 48,
                color: AppColors.textSecondary.withOpacity(0.5),
              ),
            ),

            // Overlay Text
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: GlassContainer(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: AppColors.vibePrimary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Sarah',
                      style: AppTypography.labelSmall.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    final isIOS = Platform.isIOS;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorderLight),
      ),
      child: Row(
        children: [
          Icon(AppIcons.touch, color: AppColors.vibePrimary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              isIOS
                  ? 'Long press home screen → Tap + → Select Nock'
                  : 'Long press home screen → Widgets → Nock',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
