import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:nock/core/theme/app_icons.dart';
import 'package:nock/shared/widgets/app_icon.dart';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';

/// 2025 Permission Guard - Contextual Progressive Disclosure
///
/// Instead of blocking users with full-screen permission gates,
/// this widget wraps interactive elements and requests permissions
/// only when the user attempts to use the feature.
///
/// Usage:
/// ```dart
/// PermissionGuard(
///   permission: Permission.camera,
///   featureName: 'Camera',
///   featureDescription: 'Take photos to share with voice notes',
///   onGranted: () => _startCamera(),
///   child: CaptureButton(),
/// )
/// ```
class PermissionGuard extends StatelessWidget {
  final Permission permission;
  final String featureName;
  final String featureDescription;
  final VoidCallback onGranted;
  final Widget child;

  /// Optional: Called when permanently denied (after showing settings dialog)
  final VoidCallback? onPermanentlyDenied;

  const PermissionGuard({
    super.key,
    required this.permission,
    required this.featureName,
    required this.featureDescription,
    required this.onGranted,
    required this.child,
    this.onPermanentlyDenied,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTap: () => _handleTap(context), child: child);
  }

  Future<void> _handleTap(BuildContext context) async {
    // Check if already granted
    final status = await permission.status;

    if (status.isGranted) {
      onGranted();
      return;
    }

    if (status.isPermanentlyDenied) {
      _showSettingsDialog(context);
      return;
    }

    // Show contextual permission request
    final shouldRequest = await _showPermissionExplanation(context);

    if (shouldRequest) {
      final newStatus = await permission.request();

      if (newStatus.isGranted) {
        onGranted();
      } else if (newStatus.isPermanentlyDenied) {
        _showSettingsDialog(context);
      }
    }
  }

  Future<bool> _showPermissionExplanation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                AppIcon(
                  _getIconForPermission(),
                  color: AppColors.primaryAction,
                ),
                const SizedBox(width: 12),
                Text(featureName, style: AppTypography.headlineMedium),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  featureDescription,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryAction.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        AppIcons.privacy,
                        color: AppColors.primaryAction,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your privacy is important. We only use this when you\'re actively using the feature.',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.primaryAction,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Not Now',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAction,
                ),
                child: Text(
                  'Enable $featureName',
                  style: AppTypography.buttonText.copyWith(
                    color: AppColors.textInverse,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '$featureName Access Required',
          style: AppTypography.headlineMedium,
        ),
        content: Text(
          'You\'ve previously denied $featureName access. Please enable it in Settings to use this feature.',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onPermanentlyDenied?.call();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryAction,
            ),
            child: Text(
              'Open Settings',
              style: AppTypography.buttonText.copyWith(
                color: AppColors.textInverse,
              ),
            ),
          ),
        ],
      ),
    );
  }

  PhosphorIconData _getIconForPermission() {
    if (permission == Permission.camera) return AppIcons.camera;
    if (permission == Permission.microphone) return AppIcons.mic;
    if (permission == Permission.notification) return AppIcons.notification;
    if (permission == Permission.contacts) return AppIcons.contacts;
    if (permission == Permission.photos) return AppIcons.gallery;
    return AppIcons.verified;
  }
}

/// Helper function to check and request camera + mic together
Future<bool> requestCameraAndMicPermissions(BuildContext context) async {
  final cameraStatus = await Permission.camera.status;
  final micStatus = await Permission.microphone.status;

  if (cameraStatus.isGranted && micStatus.isGranted) {
    return true;
  }

  // Request both together
  final statuses = await [Permission.camera, Permission.microphone].request();

  final allGranted = statuses.values.every((status) => status.isGranted);

  if (!allGranted) {
    final hasPermanentlyDenied = statuses.values.any(
      (s) => s.isPermanentlyDenied,
    );

    if (hasPermanentlyDenied && context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Permissions Required',
            style: AppTypography.headlineMedium,
          ),
          content: Text(
            'Camera and Microphone access are needed to create vibes. Please enable them in Settings.',
            style: AppTypography.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAction,
              ),
              child: Text(
                'Open Settings',
                style: AppTypography.buttonText.copyWith(
                  color: AppColors.textInverse,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  return allGranted;
}

/// Helper function to check and request notification permission
/// Call this after user sends their first vibe
Future<bool> requestNotificationPermission(BuildContext context) async {
  final status = await Permission.notification.status;

  if (status.isGranted) return true;

  final shouldRequest =
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              AppIcon(AppIcons.notification, color: AppColors.secondaryAction),
              const SizedBox(width: 12),
              Text('Stay Connected', style: AppTypography.headlineMedium),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Get notified when your friends send you vibes!',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.secondaryAction.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.like,
                      color: AppColors.secondaryAction,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You just sent your first vibe! 🎉',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.secondaryAction,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Maybe Later',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondaryAction,
              ),
              child: Text(
                'Enable Notifications',
                style: AppTypography.buttonText.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ) ??
      false;

  if (shouldRequest) {
    final newStatus = await Permission.notification.request();
    return newStatus.isGranted;
  }

  return false;
}
