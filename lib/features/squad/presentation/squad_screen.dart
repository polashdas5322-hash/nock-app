import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/theme/app_icons.dart';
import 'package:nock/shared/widgets/app_icon.dart';

import 'package:nock/core/constants/app_constants.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/services/vibe_service.dart';
import 'package:nock/core/models/user_model.dart';
import 'package:nock/shared/widgets/glass_container.dart';
import 'package:nock/core/utils/app_modal.dart';
import 'package:rxdart/rxdart.dart'; // <--- ADD THIS LINE

/// Friends provider (basic - just user models)
/// FIX: Batch query to handle Firestore whereIn limit of 10
final friendsProvider = StreamProvider<List<UserModel>>((ref) {
  final currentUser = ref.watch(currentUserProvider);

  return currentUser.when(
    data: (user) {
      if (user == null || user.friendIds.isEmpty) {
        return Stream.value([]);
      }

      // FIX: Batch queries for friends beyond the whereIn limit of 10
      final friendIds = user.friendIds.toList();

      // Split into chunks of 10
      final chunks = <List<String>>[];
      for (var i = 0; i < friendIds.length; i += 10) {
        chunks.add(
          friendIds.sublist(
            i,
            i + 10 > friendIds.length ? friendIds.length : i + 10,
          ),
        );
      }

      // Create a stream for each chunk
      final streams = chunks.map((chunk) {
        return FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .snapshots()
            .map(
              (snapshot) => snapshot.docs
                  .map((doc) => UserModel.fromFirestore(doc))
                  .toList(),
            );
      }).toList();

      // Merge all streams
      if (streams.isEmpty) return Stream.value([]);
      if (streams.length == 1) return streams.first;

      // INDUSTRY BEST PRACTICE: Use CombineLatestStream for clean state management
      // This prevents duplicate accumulation and ensures UI shows exact DB state
      if (streams.length == 1) return streams.first;

      // CombineLatest emits whenever ANY chunk updates, with fresh complete list
      return CombineLatestStream.list(streams).map((listOfLists) {
        // Flatten List<List<UserModel>> into single List<UserModel>
        return listOfLists.expand((batch) => batch).toList();
      });
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// Squad member with health info combined
class SquadMember {
  final UserModel user;
  final DateTime? lastVibeAt;

  SquadMember({required this.user, this.lastVibeAt});
}

/// Compute vibe level based on history
/// POSITIVE FRAMING: Connections are "Bloom", "Steady", or "Chill"

/// Enhanced friends provider with health status (Tamagotchi effect)
/// FIX: Batch query to handle Firestore whereIn limit of 30
final squadWithHealthProvider = StreamProvider<List<SquadMember>>((ref) {
  final currentUser = ref.watch(currentUserProvider);

  return currentUser.when(
    data: (user) {
      if (user == null || user.friendIds.isEmpty) {
        return Stream.value([]);
      }

      // FIX: Batch queries for friends beyond the whereIn limit of 30
      final friendIds = user.friendIds.toList();

      // Split into chunks of 10 (conservative, Firestore limit is 30)
      final chunks = <List<String>>[];
      for (var i = 0; i < friendIds.length; i += 10) {
        chunks.add(
          friendIds.sublist(
            i,
            i + 10 > friendIds.length ? friendIds.length : i + 10,
          ),
        );
      }

      // Create a stream for each chunk
      final streams = chunks.map((chunk) {
        return FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .snapshots()
            .map((snapshot) {
              return snapshot.docs.map((doc) {
                final userModel = UserModel.fromFirestore(doc);
                return SquadMember(
                  user: userModel,
                  lastVibeAt: userModel.lastActive,
                );
              }).toList();
            });
      }).toList();

      // Merge all streams using CombineLatestStream (same pattern as friendsProvider)
      if (streams.isEmpty) return Stream.value([]);
      if (streams.length == 1) return streams.first;

      // CombineLatest emits whenever ANY chunk updates, with fresh complete list
      return CombineLatestStream.list(streams).map((listOfLists) {
        // Flatten List<List<SquadMember>> into single List<SquadMember>
        return listOfLists.expand((batch) => batch).toList();
      });
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// Squad Screen - 2025 Modern UI/UX
///
/// Key Changes:
/// - FAB moved to bottom thumb zone for reachability
/// - Health-based visual hierarchy (glowing cards)
/// - Fluid animations and haptic feedback
class SquadScreen extends ConsumerStatefulWidget {
  const SquadScreen({super.key});

  @override
  ConsumerState<SquadScreen> createState() => _SquadScreenState();
}

class _SquadScreenState extends ConsumerState<SquadScreen> {
  @override
  Widget build(BuildContext context) {
    final squadMembers = ref.watch(squadWithHealthProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      // 2025 FIX: FAB at bottom for thumb reachability
      floatingActionButton: _buildAddFriendFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: Column(
          children: [
            // Header - Simplified, no action buttons in hard-to-reach zone
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your Squad', style: AppTypography.headlineLarge),
                        const SizedBox(height: 4),
                        currentUser.when(
                          data: (user) => Text(
                            '${user?.friendIds.length ?? 0}/${AppConstants.maxFriendsCount} friends',
                            style: AppTypography.bodySmall,
                          ),
                          loading: () => const SizedBox(),
                          error: (_, __) => const SizedBox(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Squad list with health indicators
            Expanded(
              child: squadMembers.when(
                data: (members) {
                  if (members.isEmpty) {
                    return _buildEmptyState();
                  }

                  // 2025: Sort by recency, not "decay"
                  final sortedMembers = List<SquadMember>.from(members)
                    ..sort((a, b) {
                      final timeA = a.lastVibeAt ?? DateTime(0);
                      final timeB = b.lastVibeAt ?? DateTime(0);
                      return timeB.compareTo(timeA);
                    });

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
                    itemCount: sortedMembers.length,
                    itemBuilder: (context, index) {
                      return _buildSquadMemberCard(sortedMembers[index]);
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryAction,
                  ),
                ),
                error: (_, __) => Center(
                  child: Text(
                    'Unable to load squad',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 2025 FIX: Full-width FAB at bottom for thumb reachability
  Widget _buildAddFriendFAB() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FloatingActionButton.extended(
          onPressed: () {
            HapticFeedback.mediumImpact();
            context.push(AppRoutes.addFriends);
          },
          backgroundColor: AppColors.primaryAction,
          icon: AppIcon(AppIcons.addFriend, color: Colors.black),
          label: Text(
            'Add Friends',
            style: AppTypography.buttonText.copyWith(color: Colors.black),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(AppIcons.friends, size: 80, color: AppColors.textTertiary),
            const SizedBox(height: 32),
            Text('Your squad is empty', style: AppTypography.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Add friends to start sharing vibes',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // Explicit CTA at thumb level
            Text(
              '👇 Tap below to add friends',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.primaryAction,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 2025 Card with history-based styling
  Widget _buildSquadMemberCard(SquadMember member) {
    final friend = member.user;

    return GestureDetector(
      onLongPress: () => _showFriendOptions(context, member),
      onTap: () {
        // FIXED: Make text/avatar tappable (Dead Zone Fix)
        HapticFeedback.mediumImpact();
        context.push(AppRoutes.camera);
      },
      child: GlassContainer(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        // LUMINOUS ARCHITECTURE: Use gradient borders instead of colored borders
        useLuminousBorder: true,
        // Move semantic color to subtle background tint
        backgroundColor: _getStatusColor(friend.status).withOpacity(0.05),
        showGlow:
            friend.status == UserStatus.online ||
            friend.status == UserStatus.recording,
        useSmallGlow: true,
        glowColor: _getStatusColor(friend.status),
        child: Opacity(
          // No opacity decay for now, keep it visible
          opacity: 1.0,
          child: Row(
            children: [
              // Avatar with vibe ring
              _buildVibeAvatar(friend),

              const SizedBox(width: 16),

              // Friend info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.displayName,
                      style: AppTypography.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (friend.status == UserStatus.recording)
                          _buildRecordingIndicator()
                        else
                          Text(
                            _getStatusText(friend),
                            style: AppTypography.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Quick Send
              // Options Menu (3 dots)
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _showFriendOptions(context, member);
                },
                icon: AppIcon(
                  AppIcons.moreVertical,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(), // Compact touch target
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVibeAvatar(UserModel friend) {
    // Default to status color
    final baseColor = _getStatusColor(friend.status);

    return Stack(
      children: [
        // Vibe ring glow with luminous border
        CustomPaint(
          painter: CircularLuminousBorderPainter(
            strokeWidth: 3,
            baseColor: baseColor,
          ),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Subtle glow for active users
              boxShadow:
                  (friend.status == UserStatus.online ||
                      friend.status == UserStatus.recording)
                  ? [
                      BoxShadow(
                        color: baseColor.withOpacity(0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.auraGradient,
              ),
              child: friend.avatarUrl != null
                  ? ClipOval(
                      child: Image.network(
                        friend.avatarUrl!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : AppIcon(
                      AppIcons.profile,
                      size: 24,
                      color: AppColors.textPrimary,
                    ),
            ),
          ),
        ),
        // Status dot - ONLY show for ACTIVE states (recording/listening)
        // Online/offline is shown via text ("5m ago"), not binary dots
        if (friend.status == UserStatus.recording ||
            friend.status == UserStatus.listening)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _getStatusColor(friend.status),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.background, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecordingIndicator() {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.statusRecording,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Recording...',
          style: AppTypography.statusText.copyWith(
            color: AppColors.statusRecording,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(UserStatus status) {
    switch (status) {
      case UserStatus.online:
        return AppColors.statusLive;
      case UserStatus.recording:
        return AppColors.statusRecording;
      case UserStatus.listening:
        return AppColors.primaryAction;
      case UserStatus.offline:
        return AppColors.statusOffline;
    }
  }

  String _getStatusText(UserModel friend) {
    final now = DateTime.now();
    final lastActive = friend.lastActive;
    final difference = now.difference(lastActive);

    if (friend.status == UserStatus.online) {
      return 'Online now';
    } else if (difference.inMinutes < 5) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  Future<void> _showFriendOptions(
    BuildContext context,
    SquadMember member,
  ) async {
    await AppModal.show(
      context: context,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Friend info header
            ListTile(
              leading: CircleAvatar(
                backgroundImage: member.user.avatarUrl != null
                    ? NetworkImage(member.user.avatarUrl!)
                    : null,
                child: member.user.avatarUrl == null
                    ? AppIcon(AppIcons.profile)
                    : null,
              ),
              title: Text(
                member.user.displayName,
                style: AppTypography.headlineSmall,
              ),
            ),
            Divider(color: AppColors.surfaceGlassDim),

            // Remove Friend (soft exit)
            ListTile(
              leading: AppIcon(
                AppIcons.removeFriend,
                color: AppColors.textSecondary,
              ),
              title: Text(
                'Remove Friend',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: Text(
                'They won\'t be notified',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmRemoveFriend(context, member);
              },
            ),

            // Block (aggressive)
            ListTile(
              leading: AppIcon(AppIcons.block, color: AppColors.urgency),
              title: Text(
                'Block',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.urgency,
                ),
              ),
              subtitle: Text(
                'Hides all content from this person',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmBlock(context, member);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Confirm remove friend
  Future<void> _confirmRemoveFriend(
    BuildContext context,
    SquadMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Remove Friend?',
          style: AppTypography.headlineSmall.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Remove ${member.user.displayName} from your friend list? They won\'t be notified.',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _removeFriend(member.user.id);
    }
  }

  /// Confirm block user
  Future<void> _confirmBlock(BuildContext context, SquadMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Block User?',
          style: AppTypography.headlineSmall.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Block ${member.user.displayName}? You won\'t see their vibes anymore.',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.urgency),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _blockUser(member.user.id);
    }
  }

  /// Remove friend (silent)
  Future<void> _removeFriend(String friendId) async {
    try {
      await ref.read(authServiceProvider).removeFriend(friendId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend removed'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove friend: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Block user
  Future<void> _blockUser(String userId) async {
    try {
      await ref.read(vibeServiceProvider).blockUser(userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User blocked'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to block user: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
