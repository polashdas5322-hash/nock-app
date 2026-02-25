import 'dart:io';
import 'dart:math' as math;
import 'package:nock/shared/widgets/app_icon.dart';
import 'package:flutter/material.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_dimens.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/features/camera/domain/models/camera_models.dart';
import 'package:nock/core/services/media_service.dart'; // For CameraState
import 'package:nock/features/camera/presentation/widgets/bioluminescent_orb.dart'; // V2 Orb
import 'package:nock/core/models/vibe_model.dart'; // For replyTo

/// The "Portal View" widget that handles the camera preview,
/// captured content (image/video), and audio-only mode background.
class CameraPortalView extends StatelessWidget {
  final CameraState cameraState;
  final bool showCurtain;
  final File? capturedImage;
  final File? capturedVideo;
  final bool isRecordingVideo;
  final bool isAudioOnlyMode;
  final bool isMicPermissionGranted;
  final bool isVideoPreviewReady;
  final VideoPlayerController? videoPreviewController;
  final bool wasFrontCamera;
  final VibeModel? replyTo;
  final EditMode currentEditMode;

  final bool isRecordingAudio;
  final int audioDuration;
  final double audioAmplitude;
  final VoidCallback? onToggleAudioRecording;

  // Callbacks (Restored)
  final ValueChanged<Offset>? onTapToPlaceText;
  final VoidCallback onRetryCameraInit;
  final VoidCallback onRequestCameraPermission;
  final VoidCallback onRequestMicPermission;
  final Function(String path, int generation) onInitializeVideoPreview;
  final int initGeneration;
  final VoidCallback onToggleVideoPlayback;

  const CameraPortalView({
    super.key,
    required this.cameraState,
    required this.showCurtain,
    this.capturedImage,
    this.capturedVideo,
    required this.isRecordingVideo,
    required this.isAudioOnlyMode,
    required this.isMicPermissionGranted,
    required this.isVideoPreviewReady,
    this.videoPreviewController,
    required this.wasFrontCamera,
    this.replyTo,
    required this.currentEditMode,
    this.onTapToPlaceText,
    required this.onRetryCameraInit,
    required this.onRequestCameraPermission,
    required this.onRequestMicPermission,
    required this.onInitializeVideoPreview,
    required this.initGeneration,
    required this.onToggleVideoPlayback,
    required this.isRecordingAudio,
    required this.audioDuration,
    this.audioAmplitude = 0.0,
    this.onToggleAudioRecording,
  });

  @override
  Widget build(BuildContext context) {
    if (showCurtain) {
      return _buildPortalLoadingState('Starting camera...');
    }

    // PERMISSION PLACEHOLDER: Show if permission required
    // This allows users to enable camera access JIT from the portal
    // FIX: Only show if NOT in audio-only mode (Compliance with Guideline 5.1.1)
    if (!isAudioOnlyMode &&
        (cameraState.error == 'Camera permission required' ||
            cameraState.error == 'Camera permission denied')) {
      return _buildPermissionPlaceholder(context);
    }

    // PORTAL CONTENT

    // CASE 1: Captured Image (Review Mode)
    if (capturedImage != null) {
      Widget imageWidget = Image.file(capturedImage!, fit: BoxFit.cover);

      // SELFIE MIRROR FIX: Flip preview horizontally for front camera
      if (wasFrontCamera) {
        imageWidget = Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationY(math.pi),
          child: imageWidget,
        );
      }

      return RepaintBoundary(child: imageWidget);
    }

    // CASE 2: Captured Video (Review Mode)
    if (capturedVideo != null) {
      if (isVideoPreviewReady && videoPreviewController != null) {
        Widget videoWidget = FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: videoPreviewController!.value.size.width,
            height: videoPreviewController!.value.size.height,
            child: VideoPlayer(videoPreviewController!),
          ),
        );

        if (wasFrontCamera) {
          videoWidget = Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(math.pi),
            child: videoWidget,
          );
        }

        return GestureDetector(
          onTap: onToggleVideoPlayback,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(child: videoWidget),
              if (!videoPreviewController!.value.isPlaying)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: AppColors.shadow,
                      shape: BoxShape.circle,
                    ),
                    child: AppIcon(
                      PhosphorIcons.play(PhosphorIconsStyle.fill),
                      color: AppColors.textPrimary,
                      size: 48,
                    ),
                  ),
                ),
            ],
          ),
        );
      } else if (!isVideoPreviewReady) {
        return Container(
          color: AppColors.surface,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: AppColors.primaryAction),
                const SizedBox(height: 16),
                Text(
                  'Preparing video...',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // Fallback for failed video preview init
        return GestureDetector(
          onTap: () {
            if (capturedVideo != null) {
              onInitializeVideoPreview(capturedVideo!.path, initGeneration + 1);
            }
          },
          child: Container(
            color: AppColors.surface,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: AppColors.glassBorderLight,
                          shape: BoxShape.circle,
                        ),
                        child: AppIcon(
                          PhosphorIcons.videoCamera(PhosphorIconsStyle.fill),
                          color: AppColors.textPrimary,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Tap to retry preview',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    // CASE 3: Audio-Only (Hardware Agnostic)
    // This mode does NOT require camera initialization (Compliance Fix)
    // CASE 3: Audio-Only (Hardware Agnostic)
    if (isAudioOnlyMode) {
      if (!isMicPermissionGranted) {
        return _buildMicPermissionPlaceholder(context);
      }
      return Stack(
        alignment: Alignment.center,
        children: [
          // 1. Dark Background Base
          Container(color: AppColors.voidNavy),

          // 2. The Living Orb (High Frequency Repaint)
          RepaintBoundary(
            child: BioluminescentOrb(
              isRecording: isRecordingAudio,
              durationSeconds: audioDuration,
              amplitude: audioAmplitude,
              showProgressRing: false, // Timer text inside orb is sufficient
              onTap: onToggleAudioRecording ?? () {},
            ),
          ),
        ],
      );
    }

    // CASE 4: Live Camera Preview
    if (cameraState.isInitialized && cameraState.controller != null) {
      // SAFETY: previewSize may be null before first frame renders on some Android devices
      // (Samsung S22/S23, Pixels). This prevents crash while waiting for sensor to report size.
      final previewSize = cameraState.controller!.value.previewSize;
      if (previewSize == null) {
        return _buildPortalLoadingState('Preparing preview...');
      }
      final size = previewSize;

      // Default: Live Camera Preview
      return Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.height, // Swapped for portrait
                height: size.width,
                child: CameraPreview(cameraState.controller!),
              ),
            ),
          ),

          // Reply Context Overlay
          if (replyTo != null)
            Positioned(
              top: 80,
              right: 24, // Moved down to avoid Status Bar collision
              child: Hero(
                tag: 'vibe_avatar_${replyTo!.id}',
                child: Container(
                  width: 56,
                  height: 56, // Reduced from 72x72
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppDimens.r12),
                    border: Border.all(
                      color: AppColors.glassBorderLight,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                    image: DecorationImage(
                      image: CachedNetworkImageProvider(
                        replyTo!.imageUrl ?? replyTo!.senderAvatar ?? '',
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),

          // Tap-to-Place Area for Text Mode
          if (currentEditMode == EditMode.text && onTapToPlaceText != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) => onTapToPlaceText!(details.localPosition),
              ),
            ),
        ],
      );
    }

    // CASE 5: Errors (Permissions, initialization failure)
    // FIX: Only show if NOT in audio-only mode
    if (!isAudioOnlyMode && cameraState.error != null) {
      return Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(32),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: PhosphorIcon(
                    cameraState.error!.contains('permission')
                        ? PhosphorIcons.camera(PhosphorIconsStyle.light)
                        : PhosphorIcons.warningCircle(PhosphorIconsStyle.light),
                    color: AppColors.error,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  cameraState.error!.contains('permission')
                      ? 'Camera Access Required'
                      : 'Camera Error',
                  style: AppTypography.headlineSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  cameraState.error!.contains('permission')
                      ? 'Nock needs camera access to capture photos and videos. Please enable it in Settings.'
                      : cameraState.error!,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onRetryCameraInit,
                      icon: PhosphorIcon(
                        PhosphorIcons.arrowsClockwise(
                          PhosphorIconsStyle.regular,
                        ),
                        size: 20,
                      ),
                      label: const Text('Retry'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.textSecondary),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await openAppSettings();
                      },
                      icon: PhosphorIcon(
                        PhosphorIcons.gearSix(PhosphorIconsStyle.fill),
                        size: 20,
                      ),
                      label: const Text('Open Settings'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryAction,
                        foregroundColor: AppColors.textInverse,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Default loading
    return _buildPortalLoadingState('Starting camera...');
  }

  Widget _buildPortalLoadingState(String message) {
    return Container(
      color: AppColors.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: AppColors.primaryAction,
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionPlaceholder(BuildContext context) {
    return Container(
      color: AppColors.surface,
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PhosphorIcon(
            PhosphorIcons.videoCameraSlash(PhosphorIconsStyle.light),
            color: AppColors.textSecondary,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'Enable Camera to Vibe',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.textPrimary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We need access to capture moments.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onRequestCameraPermission,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                'Allow Access',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textInverse,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicPermissionPlaceholder(BuildContext context) {
    return Container(
      color: AppColors.surface,
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PhosphorIcon(
            PhosphorIcons.microphoneSlash(PhosphorIconsStyle.light),
            color: AppColors.textSecondary,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'Enable Microphone to Vibe',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.textPrimary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We need access to record your voice.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onRequestMicPermission,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                'Allow Access',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textInverse,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // _buildAudioModeGradient removed as part of Portal V2 upgrade
}
