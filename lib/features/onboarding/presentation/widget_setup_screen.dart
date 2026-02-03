import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/shared/widgets/glass_container.dart';
import 'package:nock/core/providers/onboarding_provider.dart';

/// Widget Setup Screen - Forces user to install the widget before entering the app
/// This is the "Widget Lockout" from the design specification
class WidgetSetupScreen extends ConsumerStatefulWidget {
  const WidgetSetupScreen({super.key});

  @override
  ConsumerState<WidgetSetupScreen> createState() => _WidgetSetupScreenState();
}

class _WidgetSetupScreenState extends ConsumerState<WidgetSetupScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _bounceController;
  bool _widgetInstalled = false;
  Timer? _checkTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    // Removed: _startWidgetCheck() - replaced with honest "I've Added It" button
    // iOS/Android cannot reliably detect if a widget is installed
    // Showing "Waiting for widget..." when it will never detect is misleading UX
  }

  /// Mark widget as installed (user confirmation)
  /// This replaces the fake auto-detection that never worked
  void _confirmWidgetAdded() {
    setState(() => _widgetInstalled = true);
    // Haptic feedback for confirmation
    HapticFeedback.mediumImpact();
  }

  Future<void> _finishOnboarding() async {
    debugPrint('🏁 WidgetSetup: Finishing onboarding...');
    await ref.read(onboardingStateProvider.notifier).completeOnboarding();
    debugPrint('🏁 WidgetSetup: Onboarding marked complete, navigating to home...');
    
    // CRITICAL: Must explicitly navigate after completing onboarding
    // The router redirect only fires when navigating TO a route, not on state changes
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bounceController.dispose();
    _checkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              // Skip for demo (remove in production)
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => context.go(AppRoutes.welcome),
                  child: Text(
                    'Skip (Demo)',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Title
              Text(
                'Add the Widget',
                style: AppTypography.displaySmall,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              Text(
                'The magic happens on your home screen',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 40),

              // Widget preview
              Center(child: _buildWidgetPreview()),

              const SizedBox(height: 32),

              // Instructions
              GlassContainer(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildStep(1, 'Long press on your home screen'),
                    const SizedBox(height: 16),
                    _buildStep(2, 'Tap the "+" button or "Widgets"'),
                    const SizedBox(height: 16),
                    _buildStep(3, 'Find and add the Vibe widget'),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // HONEST UX: "I've Added It" confirmation button
              if (!_widgetInstalled) ...[
                // Confirmation button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _confirmWidgetAdded,
                    icon: const Icon(Icons.check, color: AppColors.primaryAction),
                    label: Text(
                      "I've Added the Widget",
                      style: AppTypography.buttonText.copyWith(
                        color: AppColors.primaryAction,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primaryAction, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                // Success state
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.success),
                    const SizedBox(width: 8),
                    Text(
                      'Great! Widget confirmed ✓',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Continue button - ALWAYS enabled (App Store compliance)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _finishOnboarding(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _widgetInstalled 
                        ? AppColors.primaryAction 
                        : AppColors.surface,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: Text(
                    _widgetInstalled ? 'Continue' : 'Skip for Now',
                    style: AppTypography.buttonText.copyWith(
                      color: _widgetInstalled 
                          ? AppColors.background 
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Manual continue option
              Center(
                child: TextButton(
                  onPressed: () => _finishOnboarding(),
                  child: Text(
                    "I'll add it later",
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWidgetPreview() {
    return GlassContainer(
      width: 200,
      height: 200,
      borderRadius: 32,
      showGlow: true,
      glowColor: AppColors.primaryAction,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Fake profile picture
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.auraGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryAction.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Icon(
              Icons.person,
              size: 50,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Tap to play',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'New Vibe',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryAction.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primaryAction),
          ),
          child: Center(
            child: Text(
              '$number',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.primaryAction,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
