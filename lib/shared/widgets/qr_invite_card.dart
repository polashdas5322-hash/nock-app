import 'package:nock/core/theme/app_icons.dart';
import 'package:nock/shared/widgets/app_icon.dart';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';

/// QR Code Invite Card Widget
/// Displays a clean QR code card that users can share to invite friends.
/// Similar to AirBuds.fm design - white card with username, tagline, and scannable QR.
class QRInviteCard extends StatelessWidget {
  final String username;
  final String? userId;
  final String? displayName;

  const QRInviteCard({
    super.key,
    required this.username,
    this.userId,
    this.displayName,
  });

  /// Generate the deep link URL for this user
  String get inviteUrl {
    if (userId != null) {
      return 'https://nock.app/invite/$userId';
    }
    return 'https://nock.app/invite/$username';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.textPrimary.withOpacity(0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16, // Tighter blur
            spreadRadius: 0, // No spread
            offset: const Offset(0, 4), // Natural drop direction
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Username handle
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '@$username',
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Tagline
            Text(
              'INVITE TO NOCK',
              style: AppTypography.labelLarge.copyWith(letterSpacing: 2),
            ),

            const SizedBox(height: 4),

            // App URL
            Text(
              'nock.app',
              style: AppTypography.labelMedium.copyWith(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 20),

            // QR Code
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.textPrimary.withOpacity(0.05),
                  width: 1,
                ),
              ),
              child: QrImageView(
                data: inviteUrl,
                version: QrVersions.auto,
                size: 180,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppColors.textPrimary,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.textPrimary,
                ),
                embeddedImage: null,
                embeddedImageStyle: null,
              ),
            ),

            const SizedBox(height: 16),

            // Scan instruction
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(AppIcons.scan, size: 16, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Text(
                  'Scan to add me on Nock',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
