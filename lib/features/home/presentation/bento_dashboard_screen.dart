import 'dart:async';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
// For CombineLatestStream
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_dimens.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:nock/core/constants/app_constants.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/services/transcription_service.dart';
import 'package:nock/core/services/vibe_service.dart'; // For paginatedVibesProvider
import 'package:nock/core/models/user_model.dart';
import 'package:nock/core/models/vibe_model.dart';
import 'package:nock/shared/widgets/glass_container.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/theme/app_icons.dart';
import 'package:nock/shared/widgets/app_icon.dart';

import 'package:nock/core/services/widget_update_service.dart';

// ============================================================================
// PROVIDERS - Using existing data structures from your codebase
// ============================================================================

/// Latest vibes received or sent by current user (for Hero Tile)
final _heroVibesProvider = StreamProvider.family<List<VibeModel>, bool>((
  ref,
  isSent,
) {
  // 🧠 OPTIMIZATION: Only watch the ID.
  // This prevents re-fetching when 'lastActive' updates in the background.
  final userId = ref.watch(
    currentUserProvider.select((user) => user.valueOrNull?.id),
  );

  if (userId == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection(AppConstants.vibesCollection)
      .where(isSent ? 'senderId' : 'receiverId', isEqualTo: userId)
      .orderBy('createdAt', descending: true)
      .limit(5)
      .snapshots()
      .map((snapshot) {
        final docs = snapshot.docs
            .map((doc) => VibeModel.fromFirestore(doc))
            .toList();

        // 🧠 SMART SORT ALGORITHM (Client-Side)
        // 1. Priority: Unread items (isPlayed == false) -> Hero Slot
        // 2. Recency: If priority is equal, sort by time
        docs.sort((a, b) {
          if (a.isPlayed != b.isPlayed) {
            // If one is unread (false) and other is read (true)
            // We want false < true, so false comes first?
            // Wait, sort ascending?
            // boolean compare: false < true.
            // If a.isPlayed (false) and b.isPlayed (true), we want a first.
            // return -1.
            return a.isPlayed ? 1 : -1;
          }
          // If priority is equal, sort by time descending
          return b.createdAt.compareTo(a.createdAt);
        });

        // Return top 5 for the Bento Grid
        return docs.take(5).toList();
      });
});

/// Friends list provider (for avatar display)
/// FIX: Batch query to handle Firestore whereIn limit of 10
final _friendsProvider = StreamProvider<List<UserModel>>((ref) {
  // FIX: Optimization - Only watch friendIds list to prevent total rebuild on timestamp updates
  // This saves massive Firestore read costs
  final friendIds = ref.watch(
    currentUserProvider.select(
      (user) => user.valueOrNull?.friendIds ?? const <String>[],
    ),
  );

  if (friendIds.isEmpty) {
    return Stream.value([]);
  }

  // COST OPTIMIZATION: Removed chunked real-time streams (Read Explosion risk).
  // Instead, we just fetch the first 20 friends (limit for simple whereIn).
  // Ideally, this should be paginated or fetched via a dedicated backend endpoint.

  // We take max 20 friends to keep it within one Firestore query limit (normally 10 or 30 depending on filter)
  // 'whereIn' supports up to 10 limits usually, or 30 with recent updates.
  // To be safe and cheap, we stick to the top 10 most recent friends.

  final topFriends = friendIds.take(10).toList();

  if (topFriends.isEmpty) {
    return Stream.value([]);
  }

  // Single performant stream
  return FirebaseFirestore.instance
      .collection(AppConstants.usersCollection)
      .where(FieldPath.documentId, whereIn: topFriends)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList(),
      );
});

// ============================================================================
// LAYOUT STATE ENUM - For the "Breathing Grid" adaptive layout
// ============================================================================

/// Layout states for the priority-based "Breathing Grid"
/// The grid adapts its structure based on the most important content
enum _BentoLayoutState {
  /// Data is loading - Show skeleton
  loading,

  /// Video vibe received - Full-width cinematic hero
  videoHero,

  /// Photo/voice vibe received - Standard bento layout
  standard,

  /// No friends yet - Onboarding focused empty state
  emptyNoFriends,

  /// Has friends but no content - Waiting for vibes
  emptyWithFriends,
}

// ============================================================================
// MEMORY CLUSTER MODEL - For Narrative Grouping
// ============================================================================

enum MemoryClusterType {
  flashback, // "On This Day" / Time Travel
  today, // Today's vibes
  yesterday, // Yesterday's vibes
  thisWeek, // Recent cluster
  month, // Monthly archive
}

class MemoryCluster {
  final String title;
  final String? subtitle;
  final DateTime startDate;
  final DateTime endDate;
  final List<VibeModel> vibes;
  final MemoryClusterType type;

  MemoryCluster({
    required this.title,
    this.subtitle,
    required this.startDate,
    required this.endDate,
    required this.vibes,
    required this.type,
  });

  VibeModel? get heroVibe => vibes.isNotEmpty ? vibes.first : null;
}

// ============================================================================
// BENTO DASHBOARD SCREEN
// ============================================================================

/// Bento Dashboard Screen - Gen Z "Chaos meets Cyber-Minimalism"
///
/// Replaces the old SquadScreen with a dynamic, widget-style dashboard
/// that aggregates friend activity into a visually rich control center.
///
/// Layout:
/// ┌─────────┬─────────┐
/// │  Hero   │  Note   │
/// │ (2x2)   │  (1x1)  │
/// │         ├─────────┤
/// │         │ Status  │
/// │         │  (1x1)  │
/// ├─────────┴─────────┤
/// │   Action (2x1)    │
/// └───────────────────┘
/// │ Squad Active Bar  │
/// └───────────────────┘
class BentoDashboardScreen extends ConsumerStatefulWidget {
  const BentoDashboardScreen({super.key, this.onNavigateBack});

  /// Called when user swipes down at the top to navigate back to camera
  final VoidCallback? onNavigateBack;

  @override
  ConsumerState<BentoDashboardScreen> createState() =>
      _BentoDashboardScreenState();
}

class _BentoDashboardScreenState extends ConsumerState<BentoDashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  // For swipe-back navigation detection
  final ScrollController _scrollController = ScrollController();
  double _dragStartY = 0;

  // FIX: Debounce timer for widget updates to prevent native bridge flooding
  Timer? _widgetUpdateTimer;

  // FIX: Optimization - Periodic timer to refresh "Active" status UI without a separate stream
  Timer? _statusRefreshTimer;

  // 🧭 PERSISTENCE FIX: Track if we are viewing Sent or Received history
  bool _isSentView = false;

  @override
  void initState() {
    super.initState();
    // UX FIX: Removed perpetual pulse animation.
    // Research shows constant 2-second loops cause "alert fatigue."
    // The bright bioLime color is sufficient to indicate "live" status.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    ); // Static - no repeat. Could animate once on new data if needed.

    // FIX: Optimized periodic refresh for "Online" status
    _statusRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    _widgetUpdateTimer?.cancel();
    _statusRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🧠 OPTIMIZATION: Only watch specific parts of currentUser to prevent redundant rebuilds
    // on background timestamp updates (lastActive).
    final currentUserDisplayName = ref.watch(
      currentUserProvider.select((u) => u.valueOrNull?.displayName),
    );
    final currentUserAvatar = ref.watch(
      currentUserProvider.select((u) => u.valueOrNull?.avatarUrl),
    );
    final currentUserIsPremium = ref.watch(
      currentUserProvider.select((u) => u.valueOrNull?.isPremium),
    );
    final currentUserHasTrial = ref.watch(
      currentUserProvider.select((u) => u.valueOrNull?.hasPremiumAccess),
    );
    final currentUserId = ref.watch(
      currentUserProvider.select((u) => u.valueOrNull?.id),
    );

    final latestVibesAsync = ref.watch(_heroVibesProvider(_isSentView));
    final friendsAsync = ref.watch(_friendsProvider);

    // OPTIMIZATION: Computer active friends here from the main friends list
    // This removes the need for a separate Firestore stream (saves battery/reads)
    final fiveMinutesAgo = DateTime.now().subtract(const Duration(minutes: 5));
    final activeFriends = (friendsAsync.valueOrNull ?? [])
        .where(
          (friend) =>
              friend.status == UserStatus.online ||
              friend.lastActive.isAfter(fiveMinutesAgo),
        )
        .toList();

    // HYBRID DASHBOARD: Watch paginated vibes for infinite memories grid
    // Family provider allows us to switch and keep both lists in memory cached
    final paginatedState = ref.watch(paginatedVibesProvider(_isSentView));

    // FIX: Listen to vibes changes to trigger transcriptions
    // This replaces the side-effect inside _buildHeroTile
    ref.listen<AsyncValue<List<VibeModel>>>(_heroVibesProvider(_isSentView), (
      previous,
      next,
    ) {
      next.whenData((vibes) {
        for (final vibe in vibes) {
          if (vibe.audioUrl.isNotEmpty) {
            // Check if we need to load transcription
            final notifier = ref.read(transcriptionStateProvider.notifier);
            if (notifier.getTranscription(vibe.id) == null) {
              notifier.loadTranscription(vibe.id, vibe.audioUrl);
            }
          }
        }

        // SQUAD & NOCK WIDGET SYNC: Update all widgets with recent vibes
        // FIX: Debounce to prevent flooding native bridge during Firestore sync
        if (vibes.isNotEmpty) {
          _widgetUpdateTimer?.cancel();
          _widgetUpdateTimer = Timer(const Duration(seconds: 1), () {
            if (!mounted) return;
            debugPrint('🔄 [BentoDashboard] Syncing all widgets (debounced)');
            WidgetUpdateService.refreshAllWidgets(vibes);
          });
        }
      });
    });

    // BFF CONFIG SYNC: Ensure friends list is available for native configuration activities
    // This fixes the "Data Desert" where BFF widgets had no friends to select from.
    ref.listen<AsyncValue<List<UserModel>>>(_friendsProvider, (previous, next) {
      next.whenData((friends) {
        if (friends.isNotEmpty) {
          debugPrint(
            '🔄 [BentoDashboard] Syncing friends_list for native BFF selection',
          );
          WidgetUpdateService.syncFriendsList(friends);
        }
      });
    });

    // Use Listener for raw pointer events - these fire BEFORE gesture recognizers
    // This allows us to detect swipe-down at top before CustomScrollView claims the gesture
    return Listener(
      onPointerDown: (event) {
        _dragStartY = event.position.dy;
        debugPrint('👆 Pointer down at y=${_dragStartY.toStringAsFixed(0)}');
      },
      onPointerUp: (event) {
        final dragEndY = event.position.dy;
        final dragDistance = dragEndY - _dragStartY;
        final isAtTop =
            !_scrollController.hasClients || _scrollController.offset <= 0;

        debugPrint(
          '👇 Pointer up: isAtTop=$isAtTop, dragDistance=${dragDistance.toStringAsFixed(0)}',
        );

        // Swipe down = positive dragDistance (finger moved down)
        // Threshold: 80px drag at the top of scroll
        if (isAtTop && dragDistance > 80) {
          debugPrint('🔙 Swipe-down navigation triggered!');
          widget.onNavigateBack?.call();
        }
      },
      child: Builder(
        builder: (context) {
          // 🔍 INDEX ERROR SURFACING: Show errors if Firestore query fails (missing index)
          if (paginatedState.error != null) {
            final error = paginatedState.error!;
            if (error.contains('FAILED_PRECONDITION') ||
                error.contains('index')) {
              debugPrint('🔥 [BentoDashboard] DATABASE INDEX MISSING: $error');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Unable to load full history at this time.',
                    ),
                    backgroundColor: AppColors.surfaceDialog,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 3),
                    action: SnackBarAction(
                      label: 'Dismiss',
                      textColor: AppColors.primaryAction,
                      onPressed: () {},
                    ),
                  ),
                );
              });
            }
          }

          return CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: _buildHeader(
                  displayName: currentUserDisplayName,
                  avatarUrl: currentUserAvatar,
                  isPremium: currentUserIsPremium ?? false,
                  hasPremiumAccess: currentUserHasTrial ?? false,
                ),
              ),

              // Bento Grid
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimens.p16),
                sliver: SliverToBoxAdapter(
                  child: latestVibesAsync.when(
                    data: (vibes) => _buildBentoGrid(
                      vibes: vibes,
                      currentUserId: currentUserId,
                      activeFriends: activeFriends,
                      allFriends: friendsAsync.valueOrNull ?? [],
                      isFriendsLoading: friendsAsync.isLoading,
                    ),
                    loading: () => _buildBentoSkeleton(),
                    error: (_, __) => const SizedBox(height: 300),
                  ),
                ),
              ),

              // ═══════════════════════════════════════════════════════════════════
              // NARRATIVE ENGINE: Flashbacks & Clusters
              // ═══════════════════════════════════════════════════════════════════

              // "On This Day" Section
              SliverToBoxAdapter(
                child: _buildFlashbackSection(
                  _getFlashbacks(paginatedState.vibes),
                ),
              ),

              // Memories Section Header
              SliverToBoxAdapter(child: _buildMemoriesHeader()),

              // Clustered Memories List
              if (paginatedState.vibes.isEmpty && paginatedState.isLoading)
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryAction,
                      ),
                    ),
                  ),
                )
              else if (paginatedState.vibes.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyMemoriesState())
              else
                ..._buildMemoryClusters(paginatedState.vibes)
                    .map((cluster) {
                      return [
                        // Cluster Date Header
                        SliverToBoxAdapter(
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    gradient: _getClusterGradient(cluster.type),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  cluster.title.toUpperCase(),
                                  style: AppTypography.labelSmall.copyWith(
                                    color:
                                        cluster.type == MemoryClusterType.month
                                        ? AppColors.textSecondary
                                        : AppColors.textPrimary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  cluster.subtitle ?? '',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.textTertiary,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Cluster Grid
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 0.75,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final vibe = cluster.vibes[index];
                              // Infinite scroll trigger: only on the very last vibe of all clusters
                              if (vibe.id == paginatedState.vibes.last.id &&
                                  !paginatedState.isLoading &&
                                  paginatedState.hasMore) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  ref
                                      .read(
                                        paginatedVibesProvider(
                                          _isSentView,
                                        ).notifier,
                                      )
                                      .loadMore();
                                });
                              }
                              return _buildMemoryTile(vibe);
                            }, childCount: cluster.vibes.length),
                          ),
                        ),
                      ];
                    })
                    .expand((e) => e),

              // Loading indicator at bottom when fetching more
              if (paginatedState.isLoading && paginatedState.vibes.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryAction,
                        ),
                      ),
                    ),
                  ),
                ),

              // Bottom padding for FAB / safe area
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader({
    String? displayName,
    String? avatarUrl,
    required bool isPremium,
    required bool hasPremiumAccess,
  }) {
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 12) {
      greeting = 'Good Morning';
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
    } else {
      greeting = 'Good Evening';
    }

    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16 + statusBarHeight, 20, 16),
      child: Row(
        children: [
          // Profile avatar with online indicator (no glow - Status Tile is focal point)
          Stack(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.surfaceGlassMedium,
                    width: 1.5,
                  ),
                  image: avatarUrl != null
                      ? DecorationImage(
                          image: NetworkImage(avatarUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                  gradient: avatarUrl == null ? AppColors.auraGradient : null,
                ),
                child: avatarUrl == null
                    ? Center(
                        child: Text(
                          displayName?.isNotEmpty == true
                              ? displayName![0].toUpperCase()
                              : 'V',
                          style: AppTypography.headlineSmall.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
              ),
              // REMOVED: Self-status dot - user knows their own status
              // Online indicators only show for friends now
            ],
          ),
          const SizedBox(width: 12),
          // Greeting
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 1,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      displayName ?? 'Nock User',
                      style: AppTypography.headlineSmall.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (isPremium == true) ...[
                      const SizedBox(width: 8),
                      _buildBadge('PRO', AppColors.primaryAction),
                    ],
                    // REMOVED: Trial badge (User request to clean UI)
                    // else if (hasPremiumAccess == true) ...[
                    //   const SizedBox(width: 8),
                    //   _buildBadge('TRIAL', AppColors.secondaryAction),
                    // ],
                  ],
                ),
              ],
            ),
          ),
          // Notifications button with unread count
          _buildNotificationButton(),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildNotificationButton() {
    // Navigate to Squad Manager
    // PHASE 1 DEMO: Luminous border enabled to showcase Spatial Glass effect
    return GlassContainer(
      width: 44,
      height: 44,
      borderRadius: 22,
      padding: EdgeInsets.zero,
      useLuminousBorder: true, // 🌟 LUMINOUS ARCHITECTURE (Phase 1)
      onTap: () {
        HapticFeedback.lightImpact();
        context.push(AppRoutes.squadManager);
      },
      child: AppIcon(AppIcons.friends, color: AppColors.textPrimary, size: 22),
    );
  }

  /// Determines the current layout state based on content priority
  /// This enables the "Breathing Grid" - layout adapts to content type
  _BentoLayoutState _getLayoutState({
    required List<VibeModel> vibes,
    required List<UserModel> allFriends,
    required bool isFriendsLoading, // FIX: Add loading state param
  }) {
    final heroVibe = vibes.isNotEmpty ? vibes.first : null;

    // Priority 1: Video gets cinematic full-width treatment
    if (heroVibe?.isVideo == true) {
      return _BentoLayoutState.videoHero;
    }

    // Priority 2: Photo/Voice vibe - standard layout
    if (heroVibe != null) {
      return _BentoLayoutState.standard;
    }

    // FIX: Priority 3 - Check loading state BEFORE empty state
    // This prevents FOUC (Flash of Unstyled Content)
    if (isFriendsLoading) {
      // Show loading skeleton while friends are loading
      return _BentoLayoutState.loading;
    }

    // Priority 4: No content at all - empty state (only after loading completes)
    if (allFriends.isEmpty) {
      return _BentoLayoutState.emptyNoFriends;
    }

    return _BentoLayoutState.emptyWithFriends;
  }

  Widget _buildBentoGrid({
    required List<VibeModel> vibes,
    required String? currentUserId,
    required List<UserModel> activeFriends,
    required List<UserModel> allFriends,
    required bool isFriendsLoading, // FIX: Add loading parameter
  }) {
    final heroVibe = vibes.isNotEmpty ? vibes.first : null;
    final layoutState = _getLayoutState(
      vibes: vibes,
      allFriends: allFriends,
      isFriendsLoading: isFriendsLoading, // FIX: Pass loading state
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _buildLayoutForState(
        key: ValueKey(layoutState),
        state: layoutState,
        heroVibe: heroVibe,
        activeFriends: activeFriends,
        allFriends: allFriends,
        currentUserId: currentUserId,
      ),
    );
  }

  Widget _buildLayoutForState({
    required Key key,
    required _BentoLayoutState state,
    required VibeModel? heroVibe,
    required List<UserModel> activeFriends,
    required List<UserModel> allFriends,
    required String? currentUserId,
  }) {
    switch (state) {
      // ═══════════════════════════════════════════════════════════════════
      // STATE 0: LOADING - Show Skeleton
      // ═══════════════════════════════════════════════════════════════════
      case _BentoLayoutState.loading:
        return _buildBentoSkeleton();

      // ═══════════════════════════════════════════════════════════════════
      // STATE 1: VIDEO HERO - Full-width cinematic mode
      // ═══════════════════════════════════════════════════════════════════
      case _BentoLayoutState.videoHero:
        return Column(
          key: key,
          children: [
            // Full-width video hero (optimized 3:4 ratio for better vertical immersion)
            AspectRatio(
              aspectRatio: 3 / 4,
              child: _buildHeroTile(heroVibe, isFullWidth: true),
            ),
            const SizedBox(height: 8),
            // Status bar below video
            _buildStatusTile(activeFriends, allFriends, isCompact: true),
          ],
        );

      // ═══════════════════════════════════════════════════════════════════
      // STATE 2: STANDARD - Classic bento grid (photo/voice)
      // ═══════════════════════════════════════════════════════════════════
      case _BentoLayoutState.standard:
        return Column(
          key: key,
          children: [
            AspectRatio(
              aspectRatio:
                  1.1, // Taller ratio (was 1.3) to allow list to breathe
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex:
                        60, // Adjusted split (was 65/35) to give status more width
                    child: _buildHeroTile(heroVibe, isActive: true),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 40,
                    child: _buildStatusTile(activeFriends, allFriends),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        );

      // ═══════════════════════════════════════════════════════════════════
      // STATE 4: EMPTY (No Friends) - Onboarding focused
      // ═══════════════════════════════════════════════════════════════════
      case _BentoLayoutState.emptyNoFriends:
        return Column(key: key, children: [_buildEmptyStateNoFriends()]);

      // ═══════════════════════════════════════════════════════════════════
      // STATE 5: EMPTY (Has Friends, No Content) - Waiting for vibes
      // ═══════════════════════════════════════════════════════════════════
      case _BentoLayoutState.emptyWithFriends:
        return Column(
          key: key,
          children: [
            AspectRatio(
              aspectRatio: 1.1,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 60, child: _buildEmptyHeroPlaceholder()),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 40,
                    child: _buildStatusTile(activeFriends, allFriends),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
    }
  }

  Widget _buildEmptyStateNoFriends() {
    return AspectRatio(
      aspectRatio: 1.2,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        useLuminousBorder: true, // 🌟 PHASE 2: Luminous empty state
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryAction.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                AppIcons.touch,
                size: 32,
                color: AppColors.primaryAction,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome to Vibe!',
              style: AppTypography.headlineMedium.copyWith(
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add friends to start sharing voice notes and photos.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Skeleton loader to prevent FOUC (Flash of Unstyled Content)
  Widget _buildBentoSkeleton() {
    return Column(
      children: [
        // Hero Skeleton
        AspectRatio(
          aspectRatio: 1.2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Large Tile
              Expanded(
                flex: 6,
                child: GlassContainer(
                  backgroundColor: AppColors.surfaceSubtle, // Subtle background
                  useLuminousBorder: false, // NO GLOW for skeletons
                  borderColor: AppColors.borderSubtle,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Side Column
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    Expanded(
                      child: GlassContainer(
                        backgroundColor: AppColors.surfaceSubtle,
                        useLuminousBorder: false,
                        borderColor: AppColors.borderSubtle,
                        child: const SizedBox(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: GlassContainer(
                        backgroundColor: AppColors.surfaceSubtle,
                        useLuminousBorder: false,
                        borderColor: AppColors.borderSubtle,
                        child: const SizedBox(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Action Tile Skeleton
        SizedBox(
          height: 80,
          child: GlassContainer(
            backgroundColor: AppColors.surfaceSubtle,
            useLuminousBorder: false,
            borderColor: AppColors.borderSubtle,
            child: const SizedBox(),
          ),
        ),
      ],
    );
  }

  /// Empty hero placeholder when waiting for vibes
  Widget _buildEmptyHeroPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceDark, AppColors.surfaceDarker],
        ),
        border: Border.all(
          color: AppColors.primaryAction.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(
            PhosphorIcons.camera(),
            color: AppColors.surfaceGlassHigh,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Waiting for vibes...',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Swipe down to send one!',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryAction.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// Hero Tile - Latest vibe from a friend with live photo support
  /// [isFullWidth] - When true, optimized for full-width video display
  /// [isActive] - When true, shows the glowing Acid Green to Electric Cyan border
  Widget _buildHeroTile(
    VibeModel? vibe, {
    bool isFullWidth = false,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: () {
        if (vibe != null) {
          HapticFeedback.lightImpact();
          // SWIPE NAVIGATION: Pass vibes list for horizontal swipe through recent vibes
          final vibesList =
              ref.read(_heroVibesProvider(_isSentView)).valueOrNull ?? [];
          final startIndex = vibesList.indexWhere((v) => v.id == vibe.id);

          if (startIndex >= 0 && vibesList.length > 1) {
            context.push(
              '/home/player/${vibe.id}',
              extra: {
                'vibe': vibe,
                'vibesList': vibesList,
                'startIndex': startIndex,
              },
            );
          } else {
            // Fallback: single vibe (backwards compatible)
            context.push('/home/player/${vibe.id}', extra: vibe);
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimens.r24),
          color: AppColors.surfaceDark,
          border: isActive
              ? Border.all(color: AppColors.transparent, width: 2)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Gradient Border Background (Hero always pops)
            if (isActive)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppDimens.r24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primaryAction, AppColors.telemetry],
                    ),
                  ),
                ),
              ),

            // Inner content container (clipping for border)
            Positioned.fill(
              child: Container(
                margin: EdgeInsets.all(isActive ? 2 : 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppDimens.r24 - 2),
                  color: AppColors.surfaceDark,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background image
                    if (vibe?.imageUrl != null)
                      CachedNetworkImage(
                        imageUrl: vibe!.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: AppColors.background,
                          child: Center(
                            child: AppIcon(
                              AppIcons.gallery,
                              color: AppColors.textPrimary.withOpacity(0.2),
                              size: 48,
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.background,
                          child: _buildEmptyHeroContent(),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: vibe?.isAudioOnly == true
                                ? [
                                    AppColors.primaryAction.withOpacity(0.4),
                                    AppColors.secondaryAction.withOpacity(0.4),
                                  ]
                                : [
                                    AppColors.primaryAction.withOpacity(0.2),
                                    AppColors.secondaryAction.withOpacity(0.2),
                                  ],
                          ),
                        ),
                        child: vibe?.isAudioOnly == true
                            ? _buildAudioOnlyHeroContent(vibe)
                            : _buildEmptyHeroContent(),
                      ),

                    // Gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.transparent,
                            AppColors.transparent,
                            AppColors.background.withOpacity(0.7),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),

                    // Timestamp pill
                    if (vibe != null)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceGlassLow,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.surfaceGlassMedium,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              /* Pulsing Dot Removed per User Request */
                              /* Spacer Removed */
                              Text(
                                _formatTimeAgo(vibe.createdAt),
                                style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.textPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              if (vibe.isVideo) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 1,
                                  height: 10,
                                  color: AppColors.textPrimary.withOpacity(0.2),
                                ),
                                const SizedBox(width: 6),
                                const SizedBox(width: 6),
                                AppIcon(
                                  AppIcons.video,
                                  color: Colors.white,
                                  size: 10,
                                ),
                              ],
                              if (vibe.replyVibeId != null) ...[
                                const SizedBox(width: 6),
                                AppIcon(
                                  AppIcons.reply,
                                  color: AppColors.primaryAction,
                                  size: 10,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                    // Metadata Overlay (Gen Z Inspired: Consolidate to Bottom-Left)
                    if (vibe != null)
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              vibe.senderName,
                              style: AppTypography.headlineSmall.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                shadows: [
                                  Shadow(
                                    color: AppColors.shadow,
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioOnlyHeroContent(VibeModel? vibe) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceGlassMedium,
              shape: BoxShape.circle,
            ),
            child: AppIcon(AppIcons.mic, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 12),
          Text('AUDIO VIBE', style: AppTypography.labelMedium),
          if (vibe != null) ...[
            const SizedBox(height: 4),
            Text(
              '${vibe.audioDuration}s recorded',
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white.withOpacity(0.6),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyHeroContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            PhosphorIcons.camera(),
            color: Colors.white.withOpacity(0.3),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'No vibes yet',
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => context.push(AppRoutes.addFriends),
            child: Text(
              'Add friends to see their vibes',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.primaryAction.withOpacity(0.8),
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Status Tile - Shows active friends
  /// [isCompact] - Smaller version for video hero layout
  Widget _buildStatusTile(
    List<UserModel> activeFriends,
    List<UserModel> allFriends, {
    bool isCompact = false,
  }) {
    // Show up to 3 friends if available
    final displayFriends = activeFriends.isNotEmpty
        ? activeFriends.take(3).toList()
        : allFriends.take(3).toList();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.r24),
        color: AppColors.surfaceDark,
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                activeFriends.isNotEmpty ? 'ONLINE' : 'FRIENDS',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceGlassMedium,
                  borderRadius: BorderRadius.circular(AppDimens.r12),
                ),
                child: Text(
                  '${allFriends.length}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (displayFriends.isEmpty)
            Center(
              child: AppIcon(
                AppIcons.friends,
                color: AppColors.textSecondary.withOpacity(0.3),
                size: 24,
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final avatarSize = isCompact ? 32.0 : 40.0;
                  final spacing = 8.0;
                  final maxAvatars =
                      ((constraints.maxWidth + spacing) /
                              (avatarSize + spacing))
                          .floor()
                          .clamp(1, 3);
                  final limitedFriends = displayFriends
                      .take(maxAvatars)
                      .toList();

                  return Row(
                    children: limitedFriends.asMap().entries.map((entry) {
                      final index = entry.key;
                      final friend = entry.value;
                      final isLast = index == limitedFriends.length - 1;
                      return Padding(
                        padding: EdgeInsets.only(right: isLast ? 0 : 8),
                        child: Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: AppColors.surfaceLight,
                            border: Border.all(
                              color: AppColors.surfaceLight,
                              width: 1,
                            ),
                            image: friend.avatarUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(friend.avatarUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: friend.avatarUrl == null
                              ? Center(
                                  child: Text(
                                    friend.displayName[0].toUpperCase(),
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NARRATIVE ENGINE: Flashbacks & Clusters (Merged from Vault)
  // ═══════════════════════════════════════════════════════════════════════════

  /// "On This Day" - Memories from this date in previous years
  List<VibeModel> _getFlashbacks(List<VibeModel> vibes) {
    final now = DateTime.now();
    return vibes.where((vibe) {
      final created = vibe.createdAt;
      return created.month == now.month &&
          created.day == now.day &&
          created.year != now.year;
    }).toList();
  }

  /// Flashback section - "On This Day" memories (Horizontal Reel)
  Widget _buildFlashbackSection(List<VibeModel> flashbacks) {
    if (flashbacks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.primaryAction,
                      AppColors.secondaryAction,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AppIcon(
                  AppIcons.sparkle,
                  color: AppColors.textInverse,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'ON THIS DAY',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: flashbacks.length,
            itemBuilder: (context, index) =>
                _buildFlashbackCard(flashbacks[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildFlashbackCard(VibeModel vibe) {
    final yearsAgo = DateTime.now().year - vibe.createdAt.year;

    return GestureDetector(
      onTap: () => context.push('${AppRoutes.player}/${vibe.id}', extra: vibe),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: AppColors.textPrimary.withOpacity(0.05),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (vibe.imageUrl != null)
              CachedNetworkImage(
                imageUrl: vibe.imageUrl!,
                fit: BoxFit.cover,
                memCacheWidth: 300,
              )
            else
              Container(
                decoration: BoxDecoration(gradient: AppColors.auraGradient),
                child: Center(
                  child: AppIcon(
                    AppIcons.mic,
                    color: AppColors.glassBorderLight,
                    size: 40,
                  ),
                ),
              ),

            // Years ago badge
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryAction,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$yearsAgo ${yearsAgo == 1 ? 'Year' : 'Years'} Ago',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textInverse,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Info bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.transparent,
                      AppColors.background.withOpacity(0.8),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      vibe.senderName,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateFormat('MMM d, yyyy').format(vibe.createdAt),
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textPrimary.withOpacity(0.6),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Group vibes into narrative clusters (Merged from Vault)
  ///
  /// 🔗 BATCH GROUPING: When viewing "By Me" (sent vibes), vibes with the same
  /// batchId are grouped together to show a single entry instead of N duplicates.
  List<MemoryCluster> _buildMemoryClusters(List<VibeModel> vibes) {
    if (vibes.isEmpty) return [];

    // 🔗 STEP 1: Deduplicate batch-sent vibes for "By Me" view
    List<VibeModel> displayVibes = vibes;
    Map<String, int> batchRecipientCounts = {}; // batchId -> recipient count

    if (_isSentView) {
      final Map<String, VibeModel> uniqueVibesByBatch = {};
      final Map<String, int> batchCounts = {};

      for (final vibe in vibes) {
        if (vibe.batchId != null) {
          // Count recipients for this batch
          batchCounts[vibe.batchId!] = (batchCounts[vibe.batchId!] ?? 0) + 1;

          // Keep only the first vibe of each batch (as representative)
          if (!uniqueVibesByBatch.containsKey(vibe.batchId)) {
            uniqueVibesByBatch[vibe.batchId!] = vibe;
          }
        } else {
          // No batchId = single send, use vibe ID as key
          uniqueVibesByBatch[vibe.id] = vibe;
          batchCounts[vibe.id] = 1;
        }
      }

      displayVibes = uniqueVibesByBatch.values.toList();
      // Sort by createdAt descending (most recent first)
      displayVibes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      batchRecipientCounts = batchCounts;
    }

    // Store counts for use in memory tiles
    _batchRecipientCounts = batchRecipientCounts;

    // STEP 2: Group into date-based clusters (existing logic)
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final grouped = <String, List<VibeModel>>{};

    for (final vibe in displayVibes) {
      final createdDate = DateTime(
        vibe.createdAt.year,
        vibe.createdAt.month,
        vibe.createdAt.day,
      );
      String key;

      if (createdDate == today) {
        key = 'Today';
      } else if (createdDate == yesterday) {
        key = 'Yesterday';
      } else if (createdDate.isAfter(weekAgo)) {
        key = 'This Week';
      } else {
        key = DateFormat('MMMM yyyy').format(vibe.createdAt);
      }

      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(vibe);
    }

    return grouped.entries.map((entry) {
      final type = entry.key == 'Today'
          ? MemoryClusterType.today
          : entry.key == 'Yesterday'
          ? MemoryClusterType.yesterday
          : entry.key == 'This Week'
          ? MemoryClusterType.thisWeek
          : MemoryClusterType.month;

      return MemoryCluster(
        title: entry.key,
        subtitle: '${entry.value.length} ${_isSentView ? "vibes" : "memories"}',
        startDate: entry.value.last.createdAt,
        endDate: entry.value.first.createdAt,
        vibes: entry.value,
        type: type,
      );
    }).toList();
  }

  // 🔗 Cache for batch recipient counts (populated by _buildMemoryClusters)
  Map<String, int> _batchRecipientCounts = {};

  LinearGradient _getClusterGradient(MemoryClusterType type) {
    switch (type) {
      case MemoryClusterType.flashback:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.telemetry, AppColors.primaryAction],
        );
      case MemoryClusterType.today:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryAction, AppColors.secondaryAction],
        );
      case MemoryClusterType.yesterday:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.telemetry, AppColors.electricBlue],
        );
      case MemoryClusterType.thisWeek:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.urgency, AppColors.urgency.withOpacity(0.5)],
        );
      case MemoryClusterType.month:
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceDark, AppColors.surfaceDark],
        );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HYBRID DASHBOARD: Memories Section Header
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMemoriesHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: AppIcon(
              AppIcons.widget,
              color: AppColors.textPrimary.withOpacity(0.7),
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _isSentView ? 'MY SENT VIBES' : 'YOUR MEMORIES',
            style: AppTypography.retroTag.copyWith(
              color: AppColors.textPrimary.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
          const Spacer(),
          // 🔘 Cyber-Minimalist Segmented Control
          _buildSegmentedControl(),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      height: 40, // TOUCH TARGET FIX: Increased from 32 to 40
      padding: const EdgeInsets.all(3), // Slightly more padding
      decoration: BoxDecoration(
        color: AppColors.surfaceGlassLow,
        borderRadius: BorderRadius.circular(20), // More rounded (Capsule)
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegmentItem(
            label: 'For Me',
            isActive: !_isSentView,
            onTap: () => setState(() => _isSentView = false),
          ),
          _buildSegmentItem(
            label: 'By Me',
            isActive: _isSentView,
            onTap: () => setState(() => _isSentView = true),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentItem({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque, // Ensure clicks are caught
      onTap: () {
        if (!isActive) {
          HapticFeedback.lightImpact();
          onTap();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        // Fill the available vertical space (40 - 6 = 34px)
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.surfaceGlassLow,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HYBRID DASHBOARD: Memory Tile Builder
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMemoryTile(VibeModel vibe) {
    // ⚠️ DEBUG: Set to TRUE to preview locked tile design. Set to FALSE for production!
    const debugForceLocked = false;

    final user = ref.watch(currentUserProvider).valueOrNull;
    final isPremium = user?.hasPremiumAccess ?? false;
    final isLocked =
        debugForceLocked ||
        (!isPremium &&
            !_isSentView && // Sent vibes are always accessible
            DateTime.now().difference(vibe.createdAt).inHours >
                AppConstants.freeHistoryHours);

    final isVideo = vibe.isVideo;
    final hasAudio = vibe.audioUrl.isNotEmpty && vibe.imageUrl == null;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (isLocked) {
          context.push(AppRoutes.subscription);
        } else {
          context.push('${AppRoutes.player}/${vibe.id}');
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surface,
          // UX FIX: No border on locked/blurred vibes to avoid framing the blur
          border: isLocked
              ? null
              : Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ═══════════════════════════════════════════════════════════════
            // LAYER 1: MEDIA CONTENT
            // Locked: Light blur (sigma 4) - "Teaser" state per Curiosity Gap Theory
            // Unlocked: Full clarity
            // ═══════════════════════════════════════════════════════════════
            if (isLocked)
              ImageFiltered(
                // UX FIX: Sigma 4 instead of 10. Allows recognition of shapes/faces
                // to trigger FOMO without revealing details.
                imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: _buildMediaContent(vibe, hasAudio),
              )
            else
              _buildMediaContent(vibe, hasAudio),

            // ═══════════════════════════════════════════════════════════════
            // LAYER 2: BRAND GRADIENT OVERLAY (Locked only)
            // Replaces heavy ColorFilter.darken - lighter, more premium feel
            // ═══════════════════════════════════════════════════════════════
            if (isLocked)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.primaryAction.withOpacity(
                          0.08,
                        ), // Subtle brand tint
                        AppColors.background.withOpacity(
                          0.6,
                        ), // Gradient to dark for text
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),

            // Video indicator (unlocked only)
            if (isVideo && !isLocked)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIcons.play,
                        color: AppColors.textPrimary,
                        size: 12,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _formatDuration(vibe.audioDuration),
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 🔗 BATCH RECIPIENT COUNT BADGE (Sent view only)
            // Shows "Sent to N friends" for batch-sent vibes
            if (_isSentView && !isLocked) ...[
              () {
                final batchKey = vibe.batchId ?? vibe.id;
                final recipientCount = _batchRecipientCounts[batchKey] ?? 1;
                if (recipientCount > 1) {
                  return Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryAction.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            AppIcons.friends,
                            color: Colors.white,
                            size: 10,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$recipientCount',
                            style: AppTypography.labelSmall.copyWith(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }(),
            ],

            // ═══════════════════════════════════════════════════════════════
            // LAYER 3: CTA PILL (Locked only)
            // 2026 Standard: Frosted glass pill with action text, no border
            // Psychology: "UNLOCK" is an invitation, not a block
            // ═══════════════════════════════════════════════════════════════
            if (isLocked)
              Positioned.fill(
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          // No border - Gen Z prefers borderless frosted elements
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(
                              AppIcons.unlock,
                              color: AppColors.primaryAction,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'UNLOCK',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ═══════════════════════════════════════════════════════════════
            // LAYER 4: BOTTOM INFO
            // Locked: Sender name ONLY (FOMO hook) - no timestamp
            // Unlocked: Full metadata with time and reactions
            // ═══════════════════════════════════════════════════════════════
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: isLocked
                    ? null
                    : BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.transparent,
                            AppColors.background.withOpacity(0.7),
                          ],
                        ),
                      ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sender name (always visible - FOMO hook)
                    Text(
                      isLocked ? 'From ${vibe.senderName}' : vibe.senderName,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: isLocked
                            ? FontWeight.w500
                            : FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Timestamp + Reactions (unlocked only)
                    if (!isLocked) ...[
                      Text(
                        _formatTimeAgo(vibe.createdAt),
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 10,
                        ),
                      ),
                      if (vibe.reactions.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              vibe.reactions.first.emoji,
                              style: AppTypography.bodyMedium.copyWith(
                                fontSize: 10,
                              ),
                            ),
                            if (vibe.reactions.length > 1) ...[
                              const SizedBox(width: 2),
                              Text(
                                '+${vibe.reactions.length - 1}',
                                style: AppTypography.labelSmall.copyWith(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            // Unplayed indicator REMOVED per user request
            if (false) // Disabled
              Positioned(top: 8, left: 8, child: const SizedBox()),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildEmptyMemoriesState() {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isExpired = user != null && !user.hasPremiumAccess;

    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surfaceGlassLow,
              shape: BoxShape.circle,
            ),
            child: AppIcon(
              isExpired ? AppIcons.lock : AppIcons.gallery,
              size: 36,
              color: isExpired
                  ? AppColors.secondaryAction.withOpacity(0.5)
                  : Colors.white.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isExpired ? 'Unlock Your Vault' : 'No memories yet',
            style: AppTypography.headlineSmall.copyWith(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isExpired
                ? 'Your 7-day trial has ended. Subscribe to VIBE+ to see your full history and unlock the Vault.'
                : 'Vibes from your friends will appear here',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          if (isExpired) ...[
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.push(AppRoutes.subscription),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondaryAction,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Upgrade to VIBE+'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMediaContent(VibeModel vibe, bool hasAudio) {
    if (vibe.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: vibe.imageUrl!,
        fit: BoxFit.cover,
        memCacheWidth: 400,
        placeholder: (_, __) => Container(
          color: AppColors.surfaceGlassLow,
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryAction,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: AppColors.surfaceGlassLow,
          child: AppIcon(AppIcons.error, color: Colors.white24),
        ),
      );
    } else if (hasAudio) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryAction.withOpacity(0.3),
              AppColors.secondaryAction.withOpacity(0.3),
            ],
          ),
        ),
        child: Center(
          child: AppIcon(
            AppIcons.mic,
            size: 32,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      );
    } else {
      return Container(
        color: AppColors.surfaceGlassLow,
        child: Center(
          child: Text(
            vibe.senderName.isNotEmpty ? vibe.senderName[0].toUpperCase() : '?',
            style: AppTypography.displayMedium.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
        ),
      );
    }
  }
}
