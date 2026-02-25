import 'package:nock/core/theme/app_icons.dart';
import 'package:nock/shared/widgets/app_icon.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/constants/app_routes.dart';

/// 404 / Error Screen
///
/// Replaces the dead-end error page with a branded recovery screen.
/// Provides a clear "Go Home" button to prevent user strand.
class NotFoundScreen extends StatelessWidget {
  final Uri uri;

  const NotFoundScreen({super.key, required this.uri});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        decoration: const BoxDecoration(gradient: AppColors.darkGradient),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Branded Logo or Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primaryAction.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryAction.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: AppIcon(
                  AppIcons.exploreOff,
                  size: 40,
                  color: AppColors.primaryAction,
                ),
              ),
              const SizedBox(height: 32),

              // Error Message
              Text(
                '404',
                style: AppTypography.displayLarge.copyWith(
                  color: AppColors.primaryAction,
                  fontSize: 64,
                ),
              ),
              const SizedBox(height: 8),
              Text('Page Not Found', style: AppTypography.headlineLarge),
              const SizedBox(height: 16),
              Text(
                'The link you followed might be broken or the page has been moved.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                uri.toString(),
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 48),

              // Recovery Action
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => context.go(AppRoutes.home),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryAction,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text('Go Back Home', style: AppTypography.buttonText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
