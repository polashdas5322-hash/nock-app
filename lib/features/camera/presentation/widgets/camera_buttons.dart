import 'package:nock/shared/widgets/app_icon.dart';
import 'package:flutter/material.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/theme/app_dimens.dart';
import 'package:nock/shared/widgets/glass_container.dart';

/// Reusable camera screen button widgets
/// These are commonly used button patterns in the camera UI

/// A translucent circular "glass" button
/// Used for top-left/top-right action buttons (settings, close, undo)
class CameraGlassButton extends StatelessWidget {
  final PhosphorIconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final double size;

  const CameraGlassButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: CustomPaint(
        painter: CircularLuminousBorderPainter(
          strokeWidth: 1.5,
          baseColor: AppColors.glassBorder,
        ),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color?.withAlpha(38) ?? AppColors.glassBackground.withOpacity(0.05),
          ),
          child: AppIcon(
            icon, 
            color: color ?? Colors.white, 
            size: size * 0.5,
          ),
        ),
      ),
    );
  }
}

/// A pill-shaped button with icon and label
/// Used for Flash/Flip camera controls
class MiniPillButton extends StatelessWidget {
  final PhosphorIconData icon;
  final String label;
  final VoidCallback onTap;

  const MiniPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        useLuminousBorder: true,
        borderRadius: 24,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        backgroundColor: AppColors.glassBackground,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, color: Colors.white, size: 18),
            const SizedBox(width: AppDimens.p8),
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A glass edit mode button with icon and label
/// 2025 REFACTOR: Replaced noisy gradients with GlassContainer (Bioluminescent Noir)
/// - Default: Glass background with luminous border (minimal, non-distracting)
/// - Active: Colored glow accent indicates selection
/// This matches Locket/NoteIt/Snapchat's "invisible UI" pattern
class EditModeButton extends StatelessWidget {
  final PhosphorIconData icon;
  final String label;
  final Color accentColor; // Replaced Gradient with single accent Color
  final VoidCallback onTap;
  final bool isActive;

  const EditModeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Glass button with optional glow on active
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              // Glass background (subtle, non-distracting)
              color: isActive 
                  ? accentColor.withAlpha(26) // Reduced from 15% to 10%
                  : AppColors.glassBackground.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive 
                    ? accentColor.withAlpha(153) // Visible border when active
                    : AppColors.glassBorder, // Subtle border when inactive
                width: isActive ? 2 : 1,
              ),
              // Glow shadow ONLY when active (Bioluminescent accent)
              boxShadow: isActive ? [
                BoxShadow(
                  color: accentColor.withAlpha(77), // 30% opacity glow
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ] : null,
            ),
            child: AppIcon(
              icon, 
              color: isActive ? accentColor : Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: isActive 
                  ? accentColor 
                  : Colors.white.withAlpha(204),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// A bottom navigation button with icon and label
/// Used for Memories/Vibes buttons at the bottom
class BottomNavButton extends StatelessWidget {
  final PhosphorIconData icon;
  final String label;
  final VoidCallback onTap;

  const BottomNavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassContainer(
            width: 52,
            height: 52,
            borderRadius: 16,
            useLuminousBorder: true,
            backgroundColor: AppColors.glassBackground,
            child: AppIcon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white.withAlpha(204),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// A circular action button with icon and label
/// Used for Retake/Save action buttons when captured
class CircleActionButton extends StatelessWidget {
  final PhosphorIconData icon;
  final String label;
  final VoidCallback onTap;

  const CircleActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            painter: CircularLuminousBorderPainter(
              strokeWidth: 1,
              baseColor: AppColors.glassBorder.withOpacity(0.4),
            ),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.glassBackground,
              ),
              child: AppIcon(icon, color: Colors.white, size: 24),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white.withAlpha(204),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple toolbar icon button
/// Used in edit mode toolbars (stroke size, etc.)
class ToolbarIconButton extends StatelessWidget {
  final PhosphorIconData icon;
  final VoidCallback onTap;
  final double iconSize;

  const ToolbarIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AppIcon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}

/// A mic button that pulses when recording (Voiceover Mode)
/// Adds subtle life to the UI without blocking the image
class PulsingMicButton extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onTap;
  
  const PulsingMicButton({
    super.key,
    required this.isRecording,
    required this.onTap,
  });

  @override
  State<PulsingMicButton> createState() => _PulsingMicButtonState();
}

class _PulsingMicButtonState extends State<PulsingMicButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // Slow breathing
    );
    
    // Subtle scale pulse (1.0 -> 1.1)
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isRecording) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PulsingMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording != oldWidget.isRecording) {
      if (widget.isRecording) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // Only pulse when recording
          final scale = widget.isRecording ? _scaleAnimation.value : 1.0;
          
          return Transform.scale(
            scale: scale,
            child: Container(
              width: widget.isRecording ? 88 : 80, // Slightly larger when active
              height: widget.isRecording ? 88 : 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Red when recording, Surface/White when idle
                color: widget.isRecording ? AppColors.error : AppColors.surfaceLight,
                border: Border.all(
                  color: widget.isRecording ? AppColors.error : AppColors.textSecondary,
                  width: 3,
                ),
                // Dynamic glow only when recording
                boxShadow: widget.isRecording 
                    ? [
                        BoxShadow(
                          color: AppColors.error.withOpacity(0.5),
                          blurRadius: 15 * (scale - 0.5), // Breathing glow
                          spreadRadius: 2,
                        )
                      ] 
                    : null,
              ),
              child: PhosphorIcon(
                widget.isRecording 
                    ? PhosphorIcons.stop(PhosphorIconsStyle.fill) 
                    : PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                color: AppColors.textPrimary,
                size: 32,
              ),
            ),
          );
        },
      ),
    );
  }
}
