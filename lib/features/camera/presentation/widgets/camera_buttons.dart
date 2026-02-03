import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/shared/widgets/glass_container.dart';

/// Reusable camera screen button widgets
/// These are commonly used button patterns in the camera UI

/// A translucent circular "glass" button
/// Used for top-left/top-right action buttons (settings, close, undo)
class GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final double size;

  const GlassButton({
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
            color: color?.withAlpha(51) ?? AppColors.glassBackground,
          ),
          child: PhosphorIcon(
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
  final IconData icon;
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
            PhosphorIcon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
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
  final IconData icon;
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
                  ? accentColor.withAlpha(38) // 15% accent tint when active
                  : AppColors.glassBackground,
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
            child: PhosphorIcon(
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
  final IconData icon;
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
            child: PhosphorIcon(icon, color: Colors.white, size: 24),
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
  final IconData icon;
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
              child: PhosphorIcon(icon, color: Colors.white, size: 24),
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
  final IconData icon;
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
        child: PhosphorIcon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}
