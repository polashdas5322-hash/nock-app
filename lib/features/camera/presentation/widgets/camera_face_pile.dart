import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/theme/app_icons.dart';
import 'package:nock/core/models/user_model.dart';
import 'package:nock/features/squad/presentation/squad_screen.dart';
import 'package:nock/features/camera/presentation/widgets/camera_buttons.dart';

/// Displays overlapping friend avatars in the camera screen's top-right corner.
///
/// Two display modes:
/// - **Default**: Shows top 3 friends with a "+N" badge for remaining.
/// - **Pre-selection**: Shows selected friends with a "+N" badge for hidden selections.
///
/// Tapping opens the pre-selection sheet for choosing recipients before capture.
class CameraFacePile extends ConsumerWidget {
  final Set<String> preSelectedRecipientIds;
  final VoidCallback onTap;

  const CameraFacePile({
    super.key,
    required this.preSelectedRecipientIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendsProvider);

    return friendsAsync.when(
      data: (friends) {
        // No Friends? Show "Add Friend" button
        if (friends.isEmpty) {
          return CameraGlassButton(
            icon: AppIcons.addFriend,
            onPressed: () {
              HapticFeedback.mediumImpact();
              context.push('/add-friends');
            },
          );
        }

        // Determine what to show based on selection state
        final bool hasPreSelection = preSelectedRecipientIds.isNotEmpty;
        List<UserModel> displayFriends;
        int badgeCount = 0;

        if (!hasPreSelection) {
          // STATE 1: No Selection -> Show top 3 friends + remaining count
          displayFriends = friends.take(3).toList();
          badgeCount = (friends.length > 3) ? (friends.length - 3) : 0;
        } else {
          // STATE 2: Selection Active -> Show selected friends + remaining SELECTED count
          final selectedFriendsList = friends
              .where((f) => preSelectedRecipientIds.contains(f.id))
              .toList();
          displayFriends = selectedFriendsList.take(3).toList();
          badgeCount = (preSelectedRecipientIds.length > 3)
              ? (preSelectedRecipientIds.length - 3)
              : 0;
        }

        // Dynamic width calculation
        const double overlap = 22.0;
        const double avatarSize = 32.0;
        final double badgeWidth = (badgeCount > 0) ? 28.0 : 0.0;

        final int visibleCount = displayFriends.length;
        final double containerWidth = visibleCount == 0
            ? 48.0
            : ((visibleCount - 1) * overlap) + avatarSize + badgeWidth;

        return GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          child: SizedBox(
            height: 48,
            width: containerWidth + 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatars
                if (visibleCount > 0)
                  Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      SizedBox(
                        width: ((visibleCount - 1) * overlap) + avatarSize,
                        height: avatarSize,
                      ),
                      ...List.generate(visibleCount, (index) {
                        final friend = displayFriends[index];
                        return Positioned(
                          left: index * overlap,
                          child: Container(
                            width: avatarSize,
                            height: avatarSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              color: AppColors.surfaceLight,
                              image: friend.avatarUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(friend.avatarUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: friend.avatarUrl == null
                                ? Center(
                                    child: Text(
                                      friend.displayName.isNotEmpty
                                          ? friend.displayName[0].toUpperCase()
                                          : '?',
                                      style: AppTypography.labelSmall.copyWith(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        );
                      }),
                    ],
                  ),

                // Badge (Context-aware: "more friends" or "more selected")
                if (badgeCount > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 24,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '+$badgeCount',
                        style: AppTypography.labelSmall.copyWith(
                          color: hasPreSelection
                              ? AppColors.primaryAction
                              : Colors.white.withOpacity(0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      // Loading/Error states: show nothing to avoid layout shift
      loading: () => const SizedBox.shrink(),
      error: (_, __) => CameraGlassButton(
        icon: AppIcons.friends,
        onPressed: () => context.push('/add-friends'),
      ),
    );
  }
}
