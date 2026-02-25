import 'package:flutter/material.dart';
import 'package:nock/core/theme/app_colors.dart';

/// A unified bottom sheet widget that implements the "Two-Tier" design system.
///
/// Tier 1 (isFloat = true):
/// - Detached "Floating Island" look
/// - 32px rounded corners
/// - 16px margins
/// - High blur
/// - Used for: Quick actions, Context menus (e.g. Audio Picker, Player Options)
///
/// Tier 2 (isFloat = false):
/// - Attached "Drawer" look
/// - 24px rounded top corners
/// - 0px margins (full width)
/// - Medium blur
/// - Used for: Heavy tasks (e.g. Add Friends, Settings, Legal)
class VibeBottomSheet extends StatelessWidget {
  final Widget child;
  final double? heightFactor;

  const VibeBottomSheet({super.key, required this.child, this.heightFactor});

  @override
  Widget build(BuildContext context) {
    const double borderRadius = 24.0;
    const Color baseColor = AppColors.surface;

    return Container(
      width: double.infinity,
      height: heightFactor != null
          ? MediaQuery.of(context).size.height * heightFactor!
          : null,
      decoration: const BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
        border: Border(
          top: BorderSide(color: AppColors.glassBorderLight, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Standardized "Glow Handle"
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Content
          Flexible(child: child),
        ],
      ),
    );
  }
}
