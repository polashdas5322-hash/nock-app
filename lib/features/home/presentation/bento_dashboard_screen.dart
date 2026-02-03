import 'dart:async';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rxdart/rxdart.dart'; // For CombineLatestStream
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/constants/app_constants.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/services/transcription_service.dart';
import 'package:nock/core/services/vibe_service.dart'; // For paginatedVibesProvider
import 'package:nock/core/models/user_model.dart';
import 'package:nock/core/models/vibe_model.dart';
import 'package:nock/core/models/squad_model.dart';
import 'package:nock/shared/widgets/glass_container.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/services/widget_update_service.dart';

// ============================================================================
// PROVIDERS - Using existing data structures from your codebase
// ============================================================================

/// Latest vibes received or sent by current user (for Hero Tile)
final _heroVibesProvider = StreamProvider.family<List<VibeModel>, bool>((ref, isSent) {
  // 🧠 OPTIMIZATION: Only watch the ID. 
  // This prevents re-fetching when 'lastActive' updates in the background.
  final userId = ref.watch(currentUserProvider.select(
    (user) => user.valueOrNull?.id
  ));
  
  if (userId == null) return const Stream.empty();
  
  return FirebaseFirestore.instance
      .collection(AppConstants.vibesCollection)
      .where(isSent ? 'senderId' : 'receiverId', isEqualTo: userId)
      .orderBy('createdAt', descending: true)
      .limit(5)
      .snapshots()
      .map((snapshot) {
        final docs = snapshot.docs.map((doc) => VibeModel.fromFirestore(doc)).toList();
            
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
  final friendIds = ref.watch(currentUserProvider.select(
    (user) => user.valueOrNull?.friendIds ?? const <String>[]
  ));
  
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
      .map((snapshot) =>
          snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList());
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
  flashback,    // "On This Day" / Time Travel
  today,        // Today's vibes
  yesterday,    // Yesterday's vibes  
  thisWeek,     // Recent cluster
  month,        // Monthly archive
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
  ConsumerState<BentoDashboardScreen> createState() => _BentoDashboardScreenState();
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
    final currentUserDisplayName = ref.watch(currentUserProvider.select((u) => u.valueOrNull?.displayName));
    final currentUserAvatar = ref.watch(currentUserProvider.select((u) => u.valueOrNull?.avatarUrl));
    final currentUserIsPremium = ref.watch(currentUserProvider.select((u) => u.valueOrNull?.isPremium));
    final currentUserHasTrial = ref.watch(currentUserProvider.select((u) => u.valueOrNull?.hasPremiumAccess));
    final currentUserId = ref.watch(currentUserProvider.select((u) => u.valueOrNull?.id));

    final latestVibesAsync = ref.watch(_heroVibesProvider(_isSentView));
    final friendsAsync = ref.watch(_friendsProvider);
    
    // OPTIMIZATION: Computer active friends here from the main friends list
    // This removes the need for a separate Firestore stream (saves battery/reads)
    final fiveMinutesAgo = DateTime.now().subtract(const Duration(minutes: 5));
    final activeFriends = (friendsAsync.valueOrNull ?? []).where((friend) => 
        friend.status == UserStatus.online ||
        friend.lastActive.isAfter(fiveMinutesAgo)
    ).toList();
    
    // HYBRID DASHBOARD: Watch paginated vibes for infinite memories grid
    // Family provider allows us to switch and keep both lists in memory cached
    final paginatedState = ref.watch(paginatedVibesProvider(_isSentView));
    
    // FIX: Listen to vibes changes to trigger transcriptions
    // This replaces the side-effect inside _buildHeroTile
    ref.listen<AsyncValue<List<VibeModel>>>(_heroVibesProvider(_isSentView), (previous, next) {
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
          debugPrint('🔄 [BentoDashboard] Syncing friends_list for native BFF selection');
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
        final isAtTop = !_scrollController.hasClients || _scrollController.offset <= 0;
        
        debugPrint('👇 Pointer up: isAtTop=$isAtTop, dragDistance=${dragDistance.toStringAsFixed(0)}');
        
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
            if (error.contains('FAILED_PRECONDITION') || error.contains('index')) {
              debugPrint('🔥 [BentoDashboard] DATABASE INDEX MISSING: $error');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Unable to load full history at this time.'),
                    backgroundColor: Colors.black87,
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
        // Swipe Down Hint - Fix for vertical navigation discoverability
        SliverSafeArea(
          bottom: false,
          sliver: SliverToBoxAdapter(
            child: _buildSwipeDownHint(),
          ),
        ),
        
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
          child: _buildFlashbackSection(_getFlashbacks(paginatedState.vibes)),
        ),

        // Memories Section Header
        SliverToBoxAdapter(
          child: _buildMemoriesHeader(),
        ),

        // Clustered Memories List
        if (paginatedState.vibes.isEmpty && paginatedState.isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primaryAction),
              ),
            ),
          )
        else if (paginatedState.vibes.isEmpty)
          SliverToBoxAdapter(
            child: _buildEmptyMemoriesState(),
          )
        else
          ..._buildMemoryClusters(paginatedState.vibes).map((cluster) {
            return [
              // Cluster Date Header
              SliverToBoxAdapter(
                child: Padding(
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
                        style: TextStyle(
                          color: cluster.type == MemoryClusterType.month 
                            ? Colors.white.withOpacity(0.4)
                            : Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        cluster.subtitle ?? '',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.2),
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
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.75,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final vibe = cluster.vibes[index];
                      // Infinite scroll trigger: only on the very last vibe of all clusters
                      if (vibe.id == paginatedState.vibes.last.id && 
                          !paginatedState.isLoading && 
                          paginatedState.hasMore) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          ref.read(paginatedVibesProvider(_isSentView).notifier).loadMore();
                        });
                      }
                      return _buildMemoryTile(vibe);
                    },
                    childCount: cluster.vibes.length,
                  ),
                ),
              ),
            ];
          }).expand((e) => e),
        
        // Loading indicator at bottom when fetching more
        if (paginatedState.isLoading && paginatedState.vibes.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
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
        const SliverToBoxAdapter(
          child: SizedBox(height: 120),
        ),
      ],
          );
        },
      ),
    );
  }

  Widget _buildSwipeDownHint() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 6, // UX FIX: Increased from 4px for accessibility
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryAction.withOpacity(0.1),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
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
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                    color: Colors.white.withOpacity(0.1),
                    width: 1.5,
                  ),
                  image: avatarUrl != null
                      ? DecorationImage(
                          image: NetworkImage(avatarUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                  gradient: avatarUrl == null
                      ? AppColors.auraGradient
                      : null,
                ),
                child: avatarUrl == null
                  ? Center(
                      child: Text(
                        displayName?.isNotEmpty == true
                            ? displayName![0].toUpperCase()
                            : 'V',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
              ),
              // Online indicator (subtle, no glow)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.primaryAction,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.background,
                      width: 2,
                    ),
                  ),
                ),
              ),
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
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.5),
                    letterSpacing: 1,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      displayName ?? 'Nock User',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (isPremium == true) ...[
                      const SizedBox(width: 8),
                      _buildBadge('PRO', AppColors.primaryAction),
                    ] 
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
        border: Border.all(
          color: color.withOpacity(0.5),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
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
      child: const Icon(Icons.people_outline, color: Colors.white, size: 22),
    );
  }



  /// Determines the current layout state based on content priority
  /// This enables the "Breathing Grid" - layout adapts to content type
  _BentoLayoutState _getLayoutState({
    required List<VibeModel> vibes,
    required List<UserModel> allFriends,
    required bool isFriendsLoading,  // FIX: Add loading state param
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
    required bool isFriendsLoading,  // FIX: Add loading parameter
  }) {
    final heroVibe = vibes.isNotEmpty ? vibes.first : null;
    final layoutState = _getLayoutState(
      vibes: vibes,
      allFriends: allFriends,
      isFriendsLoading: isFriendsLoading,  // FIX: Pass loading state
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
            // Full-width video hero (optimized 4:5 ratio for vertical social vibes)
          AspectRatio(
            aspectRatio: 4 / 5,  // Social-optimized vertical ratio (replaces 16:9 crop)
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
            aspectRatio: 1.3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 65,
                  child: _buildHeroTile(heroVibe, isActive: true),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 35,
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
        return Column(
          key: key,
          children: [
            _buildEmptyStateNoFriends(),
          ],
        );
        
      // ═══════════════════════════════════════════════════════════════════
      // STATE 5: EMPTY (Has Friends, No Content) - Waiting for vibes
      // ═══════════════════════════════════════════════════════════════════
      case _BentoLayoutState.emptyWithFriends:
        return Column(
          key: key,
          children: [
            AspectRatio(
              aspectRatio: 1.3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 65,
                    child: _buildEmptyHeroPlaceholder(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 35,
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
              child: Icon(
                Icons.waving_hand,
                size: 32,
                color: AppColors.primaryAction,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Welcome to Vibe!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add friends to start sharing voice notes and photos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
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
                    backgroundColor: Colors.white.withOpacity(0.03), // Subtle background
                    useLuminousBorder: false, // NO GLOW for skeletons
                    borderColor: Colors.white.withOpacity(0.05),
                    child: Center(
                       child: CircularProgressIndicator(color: Colors.white.withOpacity(0.2)),
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
                        backgroundColor: Colors.white.withOpacity(0.03),
                        useLuminousBorder: false,
                        borderColor: Colors.white.withOpacity(0.05),
                        child: const SizedBox(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: GlassContainer(
                        backgroundColor: Colors.white.withOpacity(0.03),
                        useLuminousBorder: false,
                        borderColor: Colors.white.withOpacity(0.05),
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
             backgroundColor: Colors.white.withOpacity(0.03),
             useLuminousBorder: false,
             borderColor: Colors.white.withOpacity(0.05),
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
          colors: [
            const Color(0xFF111111),
            const Color(0xFF0D0D0D),
          ],
        ),
        border: Border.all(
          color: AppColors.primaryAction.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_camera_outlined,
            color: Colors.white.withOpacity(0.2),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Waiting for vibes...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Swipe down to send one!',
            style: TextStyle(
              color: AppColors.primaryAction.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Hero Tile - Latest vibe from a friend with live photo support
  /// [isFullWidth] - When true, optimized for full-width video display
  /// [isActive] - When true, shows the glowing Acid Green to Electric Cyan border
  Widget _buildHeroTile(VibeModel? vibe, {bool isFullWidth = false, bool isActive = false}) {
    return GestureDetector(
      onTap: () {
        if (vibe != null) {
          HapticFeedback.lightImpact();
          // SWIPE NAVIGATION: Pass vibes list for horizontal swipe through recent vibes
          final vibesList = ref.read(_heroVibesProvider(_isSentView)).valueOrNull ?? [];
          final startIndex = vibesList.indexWhere((v) => v.id == vibe.id);
          
          if (startIndex >= 0 && vibesList.length > 1) {
            context.push('/home/player/${vibe.id}', extra: {
              'vibe': vibe,
              'vibesList': vibesList,
              'startIndex': startIndex,
            });
          } else {
            // Fallback: single vibe (backwards compatible)
            context.push('/home/player/${vibe.id}', extra: vibe);
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: const Color(0xFF111111),
          border: isActive ? Border.all(color: Colors.transparent, width: 2) : null,
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
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primaryAction,
                        AppColors.telemetry,
                      ],
                    ),
                  ),
                ),
              ),
            
            // Inner content container (clipping for border)
            Positioned.fill(
              child: Container(
                margin: EdgeInsets.all(isActive ? 2 : 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: const Color(0xFF111111),
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
                            child: Icon(
                              Icons.image_outlined,
                              color: Colors.white.withOpacity(0.2),
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
                                ? [AppColors.primaryAction.withOpacity(0.4), AppColors.secondaryAction.withOpacity(0.4)]
                                : [AppColors.primaryAction.withOpacity(0.2), AppColors.secondaryAction.withOpacity(0.2)],
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
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              /* Pulsing Dot Removed per User Request */
                              /* Spacer Removed */
                              Text(
                                _formatTimeAgo(vibe.createdAt),
                                style: const TextStyle(
                                  color: Colors.white,
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
                                  color: Colors.white.withOpacity(0.2),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.videocam, color: Colors.white, size: 10),
                              ],
                              if (vibe.replyVibeId != null) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.reply, color: AppColors.primaryAction, size: 10),
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.black26,
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
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mic,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'AUDIO VIBE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          if (vibe != null) ...[
            const SizedBox(height: 4),
            Text(
              '${vibe.audioDuration}s recorded',
              style: TextStyle(
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
          Icon(
            Icons.photo_camera_outlined,
            color: Colors.white.withOpacity(0.3),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'No vibes yet',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => context.push(AppRoutes.addFriends),
            child: Text(
              'Add friends to see their vibes',
              style: TextStyle(
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
  Widget _buildStatusTile(List<UserModel> activeFriends, List<UserModel> allFriends, {bool isCompact = false}) {
    final isAnybodyOnline = activeFriends.isNotEmpty;
    final displayFriend = activeFriends.isNotEmpty 
        ? activeFriends.first 
        : (allFriends.isNotEmpty ? allFriends.first : null);
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF111111),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background gradient REMOVED for clean look
          
          // Content
          Padding(
            padding: EdgeInsets.all(isCompact ? 10 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Friend avatar or icon
                    Container(
                      width: isCompact ? 28 : 32,
                      height: isCompact ? 28 : 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: displayFriend?.avatarUrl == null 
                            ? AppColors.primaryAction 
                            : null,
                        image: displayFriend?.avatarUrl != null
                            ? DecorationImage(
                                image: NetworkImage(displayFriend!.avatarUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3), // Dark shadow for depth
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: displayFriend?.avatarUrl == null
                          ? Center(
                              child: Icon(
                                isAnybodyOnline ? Icons.person : Icons.person_outline,
                                color: Colors.white,
                                size: isCompact ? 14 : 16,
                              ),
                            )
                          : null,
                    ),
                    // Status indicator (Ambient Glowing Border on Avatar handles this now)
                    if (isAnybodyOnline)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryAction,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryAction,
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      )
                    else
                      Icon(
                        Icons.circle_outlined,
                        color: Colors.white.withOpacity(0.3),
                        size: isCompact ? 14 : 16,
                      ),
                  ],
                ),
                // Compact display friend info
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isCompact)
                            Text(
                              displayFriend?.displayName ?? 'No friends yet',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryAction, AppColors.secondaryAction],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.black, size: 16),
              ),
              const SizedBox(width: 10),
              const Text(
                'ON THIS DAY',
                style: TextStyle(
                  color: Colors.white,
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
            itemBuilder: (context, index) => _buildFlashbackCard(flashbacks[index]),
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
          color: Colors.white.withOpacity(0.05),
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
                decoration: BoxDecoration(
                  gradient: AppColors.auraGradient,
                ),
                child: const Center(child: Icon(Icons.mic, color: Colors.white24, size: 40)),
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
                  style: const TextStyle(
                    color: Colors.black,
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
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      vibe.senderName,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateFormat('MMM d, yyyy').format(vibe.createdAt),
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9),
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
  List<MemoryCluster> _buildMemoryClusters(List<VibeModel> vibes) {
    if (vibes.isEmpty) return [];
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));
    
    final grouped = <String, List<VibeModel>>{};
    
    for (final vibe in vibes) {
      final createdDate = DateTime(vibe.createdAt.year, vibe.createdAt.month, vibe.createdAt.day);
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
      final type = entry.key == 'Today' ? MemoryClusterType.today :
                   entry.key == 'Yesterday' ? MemoryClusterType.yesterday :
                   entry.key == 'This Week' ? MemoryClusterType.thisWeek :
                   MemoryClusterType.month;
                   
      return MemoryCluster(
        title: entry.key,
        subtitle: '${entry.value.length} memories',
        startDate: entry.value.last.createdAt,
        endDate: entry.value.first.createdAt,
        vibes: entry.value,
        type: type,
      );
    }).toList();
  }

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
          colors: [AppColors.telemetry, Color(0xFF0055FF)],
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
          colors: [const Color(0xFF111111), const Color(0xFF111111)],
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
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.grid_view_rounded,
              color: Colors.white.withOpacity(0.7),
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
        color: Colors.white.withOpacity(0.05),
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
          boxShadow: isActive ? [
            BoxShadow(
              color: Colors.white.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
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
    const DEBUG_FORCE_LOCKED = false;
    
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isPremium = user?.hasPremiumAccess ?? false;
    final isLocked = DEBUG_FORCE_LOCKED || (!isPremium && 
                     !_isSentView && // Sent vibes are always accessible
                     DateTime.now().difference(vibe.createdAt).inHours > AppConstants.freeHistoryHours);
    
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
          border: isLocked ? null : Border.all(color: Colors.white.withOpacity(0.05)),
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
                        AppColors.primaryAction.withOpacity(0.08), // Subtle brand tint
                        Colors.black.withOpacity(0.6), // Gradient to dark for text
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow, color: Colors.white, size: 12),
                      const SizedBox(width: 2),
                      Text(
                        _formatDuration(vibe.audioDuration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          // No border - Gen Z prefers borderless frosted elements
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_open_rounded,
                              color: AppColors.primaryAction,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'UNLOCK',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
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
                decoration: isLocked ? null : BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
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
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: isLocked ? FontWeight.w500 : FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Timestamp + Reactions (unlocked only)
                    if (!isLocked) ...[
                      Text(
                        _formatTimeAgo(vibe.createdAt),
                        style: TextStyle(
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
                              style: const TextStyle(fontSize: 10),
                            ),
                            if (vibe.reactions.length > 1) ...[
                              const SizedBox(width: 2),
                              Text(
                                '+${vibe.reactions.length - 1}',
                                style: TextStyle(
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
              Positioned(
                top: 8,
                left: 8,
                child: const SizedBox(),
              ),
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
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isExpired ? Icons.lock_outline : Icons.photo_library_outlined,
              size: 36,
              color: isExpired ? AppColors.secondaryAction.withOpacity(0.5) : Colors.white.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isExpired ? 'Unlock Your Vault' : 'No memories yet',
            style: TextStyle(
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
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 13,
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          color: Colors.white.withOpacity(0.05),
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryAction,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.white.withOpacity(0.05),
          child: const Icon(Icons.broken_image, color: Colors.white24),
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
          child: Icon(
            Icons.mic,
            size: 32,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      );
    } else {
      return Container(
        color: Colors.white.withOpacity(0.05),
        child: Center(
          child: Text(
            vibe.senderName.isNotEmpty ? vibe.senderName[0].toUpperCase() : '?',
            style: TextStyle(
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
