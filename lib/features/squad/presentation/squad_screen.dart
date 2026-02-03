import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/constants/app_constants.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/services/vibe_service.dart';
import 'package:nock/core/models/user_model.dart';
import 'package:nock/core/models/squad_model.dart';
import 'package:nock/shared/widgets/glass_container.dart';
import 'package:nock/shared/widgets/aura_visualization.dart';
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
        chunks.add(friendIds.sublist(
          i, 
          i + 10 > friendIds.length ? friendIds.length : i + 10,
        ));
      }
      
      // Create a stream for each chunk
      final streams = chunks.map((chunk) {
        return FirebaseFirestore.instance
            .collection(AppConstants.usersCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .snapshots()
            .map((snapshot) =>
                snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList());
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
  final VibeLevel vibeLevel;
  final DateTime? lastVibeAt;
  
  SquadMember({
    required this.user,
    required this.vibeLevel,
    this.lastVibeAt,
  });
}

/// Compute vibe level based on history
/// POSITIVE FRAMING: Connections are "Bloom", "Steady", or "Chill"
VibeLevel _computeVibeLevel(DateTime? lastActive) {
  // Null means no vibes yet - ready for first chill bloom!
  if (lastActive == null) return VibeLevel.chill;
  
  final now = DateTime.now();
  final daysSinceActive = now.difference(lastActive).inDays;
  
  if (daysSinceActive <= 1) {
    return VibeLevel.bloom;   // 🌸 Active connection
  } else if (daysSinceActive <= 3) {
    return VibeLevel.steady;  // ⚡ Building history
  } else {
    return VibeLevel.chill;   // 🌫️ Low-key / resting
  }
}

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
        chunks.add(friendIds.sublist(
          i, 
          i + 10 > friendIds.length ? friendIds.length : i + 10,
        ));
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
                final vibeLevel = _computeVibeLevel(userModel.lastActive);
                return SquadMember(
                  user: userModel,
                  vibeLevel: vibeLevel,
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
                        Text(
                          'Your Squad',
                          style: AppTypography.headlineLarge,
                        ),
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
          icon: const Icon(Icons.person_add_rounded, color: Colors.black),
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
            const AuraVisualization(
              size: 150,
              mood: AuraMood.calm,
            ),
            const SizedBox(height: 32),
            Text(
              'Your squad is empty',
              style: AppTypography.headlineMedium,
            ),
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
    final level = member.vibeLevel;
    
    return GestureDetector(
      onLongPress: () => _showFriendOptions(context, member),
      onTap: () { // FIXED: Make text/avatar tappable (Dead Zone Fix)
        HapticFeedback.mediumImpact();
        context.push(AppRoutes.camera); 
      },
      child: GlassContainer(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        // LUMINOUS ARCHITECTURE: Use gradient borders instead of colored borders
        useLuminousBorder: true,
        // Move semantic color to subtle background tint
        backgroundColor: _getLevelColor(level).withOpacity(0.05),
        showGlow: level == VibeLevel.bloom || 
                  friend.status == UserStatus.online ||
                  friend.status == UserStatus.recording,
        useSmallGlow: true,
        glowColor: level == VibeLevel.bloom 
            ? AppColors.statusLive 
            : _getStatusColor(friend.status),
        child: Opacity(
          opacity: _getLevelOpacity(level),
          child: Row(
            children: [
              // Avatar with vibe ring
              _buildVibeAvatar(friend, level),
              
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
                        else if (level == VibeLevel.chill)
                          _buildChillNudge()  // 🌫️ Low-key nudge
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
                icon: const Icon(
                  Icons.more_vert_rounded,
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

  Widget _buildVibeAvatar(UserModel friend, VibeLevel level) {
    final levelColor = _getLevelColor(level);
    
    return Stack(
      children: [
        // Vibe ring glow with luminous border
        CustomPaint(
          painter: CircularLuminousBorderPainter(
            strokeWidth: 3,
            baseColor: levelColor,
          ),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: level == VibeLevel.bloom
                  ? [
                      BoxShadow(
                        color: AppColors.statusLive.withAlpha(76),
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
                  : const Icon(
                      Icons.person,
                      size: 24,
                      color: Colors.white,
                    ),
            ),
          ),
        ),
        // Status dot
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: _getStatusColor(friend.status),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.background,
                width: 2,
              ),
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

  /// 🌫️ Chill nudge - Positive framing
  Widget _buildChillNudge() {
    return Row(
      children: [
        Icon(
          Icons.water_drop_rounded, // 💧 Water Drop (Needs care)
          size: 14,
          color: AppColors.primaryAction.withOpacity(0.7), // Blue/Cyan tint
        ),
        const SizedBox(width: 4),
        Text(
          'Water the garden 🌱', // Nurturing CTA
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }


  // Vibe level helpers (positive framing)
  Color _getLevelColor(VibeLevel level) {
    switch (level) {
      case VibeLevel.bloom:  // 🌸 Active
        return AppColors.statusLive;
      case VibeLevel.steady: // ⚡ Steady
        return AppColors.primaryAction;
      case VibeLevel.chill:  // 🌫️ Chill
        return Colors.grey;
    }
  }

  Color _getLevelBorderColor(VibeLevel level) {
    switch (level) {
      case VibeLevel.bloom:
        return AppColors.statusLive.withAlpha(76);
      case VibeLevel.steady:
        return AppColors.primaryAction.withAlpha(76);
      case VibeLevel.chill:
        return Colors.grey.withAlpha(76);
    }
  }

  double _getLevelOpacity(VibeLevel level) {
    switch (level) {
      case VibeLevel.bloom:
        return 1.0;
      case VibeLevel.steady:
        return 0.95;
      case VibeLevel.chill:
        return 0.85;
    }
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

  /// Show friend management options
  Future<void> _showFriendOptions(BuildContext context, SquadMember member) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
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
                    ? const Icon(Icons.person) 
                    : null,
              ),
              title: Text(
                member.user.displayName,
                style: AppTypography.headlineSmall,
              ),
            ),
            const Divider(color: Colors.white10),
            
            // Remove Friend (soft exit)
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: AppColors.textSecondary),
              title: const Text('Remove Friend', style: TextStyle(color: Colors.white)),
              subtitle: const Text('They won\'t be notified', style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _confirmRemoveFriend(context, member);
              },
            ),
            
            // Block (aggressive)
            ListTile(
              leading: const Icon(Icons.block, color: AppColors.urgency),
              title: const Text('Block', style: TextStyle(color: AppColors.urgency)),
              subtitle: const Text('Hides all content from this person', style: TextStyle(color: Colors.white24, fontSize: 12)),
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
  Future<void> _confirmRemoveFriend(BuildContext context, SquadMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Remove Friend?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove ${member.user.displayName} from your friend list? They won\'t be notified.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
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
        title: const Text('Block User?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Block ${member.user.displayName}? You won\'t see their vibes anymore.',
          style: const TextStyle(color: Colors.white70),
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
