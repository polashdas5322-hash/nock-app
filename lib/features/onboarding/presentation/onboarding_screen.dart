import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/providers/onboarding_provider.dart';
import 'package:nock/shared/widgets/glass_container.dart';
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

/// Onboarding Screen - Introduction to Vibe (2025 Progressive Disclosure)
/// 
/// Key Changes for 2025:
/// - No permission gates during onboarding
/// - Permissions requested contextually when features are used
/// - Skip button goes directly to auth/home
/// - "Get Started" completes onboarding without forcing permissions
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingData> _pages = [
    OnboardingData(
      title: 'Voice + Photo',
      subtitle: 'Share moments with your voice',
      description: 'Capture a photo, add a 10-second voice note, and send it instantly to your squad.',
      mood: AuraMood.happy,
      icon: Icons.photo_camera,
    ),
    OnboardingData(
      title: 'Widget Magic',
      subtitle: 'Your home screen comes alive',
      description: 'See and hear your friends without opening the app. Tap to play, hold to reply.',
      mood: AuraMood.excited,
      icon: Icons.widgets,
    ),
    OnboardingData(
      title: 'Time Travel',
      subtitle: 'Share memories, not just moments',
      description: 'Upload photos from your gallery with a retro date stamp. Every picture tells a story.',
      mood: AuraMood.calm,
      icon: Icons.history,
    ),
    OnboardingData(
      title: 'Memory Vault',
      subtitle: 'Never lose a vibe',
      description: 'Keep all your voice memories safe. Relive every moment on a beautiful calendar.',
      mood: AuraMood.neutral,
      icon: Icons.lock,
    ),
  ];

  /// 2025 FIX: Complete onboarding and go to auth/home
  /// No permission gates - they'll be requested contextually
  Future<void> _completeOnboarding() async {
    // CRITICAL FIX: Check mounted and capture state BEFORE any await
    // This prevents "Cannot use ref after widget was disposed" error
    if (!mounted) return;
    
    // Capture auth state BEFORE the await to avoid ref access after disposal
    final authState = ref.read(authStateProvider);
    final isLoggedIn = authState.valueOrNull != null;
    final onboardingNotifier = ref.read(onboardingStateProvider.notifier);
    
    // Mark onboarding as complete
    // This prevents the infinite redirect loop between /welcome and /onboarding
    await onboardingNotifier.completeOnboarding();
    
    // Re-check mounted after await since widget may have been disposed
    if (!mounted) return;
    
    if (isLoggedIn) {
      // User is already logged in -> go directly to home
      context.go('/home');
    } else {
      // User not logged in -> go to welcome/auth screen
      context.go('/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button - 2025: Goes directly to auth, no permissions
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(
                    'Skip',
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),

            // Page view
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index]);
                },
              ),
            ),

            // Page indicators
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (index) => _buildIndicator(index),
                ),
              ),
            ),

            // Next/Get Started button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_currentPage < _pages.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    } else {
                      // 2025 FIX: Go directly to auth, no permission gates
                      _completeOnboarding();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryAction,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _currentPage < _pages.length - 1 ? 'Next' : 'Get Started',
                    style: AppTypography.buttonText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Aura with icon
          Stack(
            alignment: Alignment.center,
            children: [
              AuraVisualization(
                size: 180,
                mood: data.mood,
              ),
              Icon(
                data.icon,
                size: 48,
                color: AppColors.background,
              ),
            ],
          ),
          const SizedBox(height: 48),

          // Title
          ShaderMask(
            shaderCallback: (bounds) =>
                AppColors.primaryGradient.createShader(bounds),
            child: Text(
              data.title,
              style: AppTypography.displaySmall.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),

          // Subtitle
          Text(
            data.subtitle,
            style: AppTypography.headlineSmall.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Description in glass container
          GlassContainer(
            padding: const EdgeInsets.all(20),
            child: Text(
              data.description,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator(int index) {
    final isActive = index == _currentPage;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: isActive ? AppColors.primaryAction : AppColors.surfaceLight,
      ),
    );
  }
}

class OnboardingData {
  final String title;
  final String subtitle;
  final String description;
  final AuraMood mood;
  final IconData icon;

  OnboardingData({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.mood,
    required this.icon,
  });
}
