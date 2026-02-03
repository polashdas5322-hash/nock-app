import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:nock/core/theme/app_colors.dart';

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
          color: Colors.white.withOpacity(0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3), // Dark shadow, not colored
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Tagline
            const Text(
              'INVITE TO NOCK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            
            const SizedBox(height: 4),
            
            // App URL
            Text(
              'nock.app',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            
            const SizedBox(height: 20),
            
            // QR Code
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.05),
                  width: 1,
                ),
              ),
              child: QrImageView(
                data: inviteUrl,
                version: QrVersions.auto,
                size: 180,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.white,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.white,
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
                const Icon(
                  Icons.qr_code_scanner,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Scan to add me on Nock',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
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
