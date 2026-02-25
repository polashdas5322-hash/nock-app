import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/theme/app_icons.dart';
import 'package:nock/shared/widgets/app_icon.dart';

import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/services/fcm_token_service.dart';
import 'package:nock/core/services/widget_update_service.dart';
import 'package:nock/core/models/user_model.dart';
import 'package:nock/shared/widgets/glass_container.dart';
import 'package:nock/shared/widgets/vibe_bottom_sheet.dart';
import 'package:nock/core/utils/app_modal.dart';
import 'package:nock/features/camera/presentation/camera_screen_new.dart';
import 'package:nock/features/home/presentation/bento_dashboard_screen.dart';
import 'package:collection/collection.dart';
import 'package:nock/core/providers/vibe_upload_provider.dart';
import 'package:nock/core/providers/deep_link_provider.dart';


/// Home Screen - 2025 Modern UI/UX
/// 
/// Navigation Model:
/// - Swipe UP: History/Dashboard (social hub)
/// - Default: Camera (camera-first)
/// - Settings: Modal overlay (not a full page)
/// 
/// Vertical swipe navigation with "History" indicator at bottom.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  
  // 0: Camera (default), 1: Dashboard (swipe up)
  final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;
  bool _isUpdatingAvatar = false;

  
  // FIX: Edge Guard + Drawing Mode Lock for Gesture Conflict
  ScrollPhysics _pagePhysics = const BouncingScrollPhysics(parent: PageScrollPhysics());
  bool _isDrawingMode = false; // Locks page swipe when camera is in drawing mode
  bool _isCameraActive = false; // Hides history indicator when camera is recording/captured
  Timer? _statusHeartbeat; // Heartbeat to keep user online
  StreamSubscription? _widgetClickedSubscription; // FIX: Memory Leak - Store for cancellation
  
  // REACTIVE SYNC FIX: Static guard to prevent multiple syncs per session
  // This replaces the race-prone main.dart sync that used authStateChanges().first
  static String? _lastSyncedUserId;

  @override
  void initState() {
    super.initState();
    
    // Immersive status bar
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.voidNavy,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // Immersive status bar removed listener as _pageOffset is no longer needed

    // FIX: Add lifecycle observer to track app state (online/offline)
    WidgetsBinding.instance.addObserver(this);

    // Initialize services
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authServiceProvider).updateUserStatus(UserStatus.online);
      ref.read(fcmTokenServiceProvider).initialize();
      _handleWidgetLaunch();
      
      // FIX 2024-12-25: REMOVED ref.listen from here!
      // ref.listen CANNOT be used in addPostFrameCallback/initState
      // It MUST be in build() - moved to build() method below line 204
      
      // FIX 1: Heartbeat - Keep user online while app is active
      // Prevents "False Offline" bug where user disappears after 5 min
      _statusHeartbeat = Timer.periodic(const Duration(minutes: 2), (timer) {
        if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          ref.read(authServiceProvider).updateUserStatus(UserStatus.online);
          debugPrint('HomeScreen: Heartbeat - updated status to online');
        }
      });
    });

  }

  /// FIX: Handle app lifecycle changes to update user online status
  /// This fixes the "Ghost User" bug where users appear online indefinitely
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground - set online
        ref.read(authServiceProvider).updateUserStatus(UserStatus.online);
        debugPrint('HomeScreen: App resumed - set status to online');
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App went to background or closed - set offline
        ref.read(authServiceProvider).updateUserStatus(UserStatus.offline);
        debugPrint('HomeScreen: App paused/detached - set status to offline');
        break;
    }
  }


  /// Edge Guard: Lock PageView when camera is in drawing mode OR active state
  /// This prevents vertical drawings/swipes from triggering page navigation during recording/capture

  Future<void> _handleWidgetLaunch() async {
    try {
      final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initialUri != null) {
        _handleWidgetUri(initialUri);
      }
      
      _widgetClickedSubscription = HomeWidget.widgetClicked.listen((uri) {
        if (uri != null) {
          _handleWidgetUri(uri);
        }
      });
    } catch (e) {
      debugPrint('HomeScreen: Error handling widget launch: $e');
    }
  }

  void _handleWidgetUri(Uri uri) {
    debugPrint('HomeScreen: Widget clicked with URI: $uri');
    final vibeId = uri.queryParameters['vibeId'];
    if (vibeId != null && vibeId.isNotEmpty && mounted) {
      // FIX Issue 8: Use pushReplacement to prevent back-stack accumulation
      // When users repeatedly click widgets, this ensures Back always goes to Home
      context.pushReplacement('${AppRoutes.player}/$vibeId');
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Note: Don't use ref.read() in dispose - widget may already be unmounted
    // The status will be set to offline automatically when user logs out
    // or when the app is backgrounded (handled in didChangeAppLifecycleState)
    
    _statusHeartbeat?.cancel();
    _widgetClickedSubscription?.cancel(); // FIX: Memory Leak - Cancel subscription
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // REACTIVE SYNC FIX: Listen to auth changes and sync read receipts
    // This fixes the race condition in main.dart where authStateChanges().first
    // could timeout on slow devices, causing read receipts to never sync.
    //
    // Why this works:
    // 1. Zero-Blocking: App launches instantly, sync happens in background
    // 2. Guaranteed Auth: Only syncs when user is confirmed authenticated
    // 3. Self-Healing: Re-syncs on re-login or account switch
    ref.listen<AsyncValue<UserModel?>>(currentUserProvider, (previous, next) {
      next.whenData((user) {
        // Only sync if we have a user AND haven't synced for this user yet
        if (user != null && _lastSyncedUserId != user.id) {
          _lastSyncedUserId = user.id;
          debugPrint('🔄 Auth detected: Syncing read receipts for ${user.id}...');
          WidgetUpdateService.syncPendingReadReceipts(user.id);
        }
      });
    });
    
    // FIX 2024-12-25: Handle pending invites (moved from initState)
    // Use activeInviteProvider to respect session-level dismissals
    ref.listen<String?>(activeInviteProvider, (previous, next) {
      if (next != null && mounted) {
        final target = '/home/invite/$next';
        
        if (GoRouterState.of(context).matchedLocation == target) {
          debugPrint('HomeScreen: Already at invite target, skipping context.go');
          return;
        }

        debugPrint('HomeScreen: Active invite detected: $next');
        context.go(target);
        
        // Use dismiss() instead of clearPendingInvite() to avoid losing 
        // the invite from storage if the user just wants to browse.
        ref.read(pendingInviteProvider.notifier).dismiss();
      }
    });

    // 📤 VIBE UPLOAD FEEDBACK LISTENER (Global success/error)
    ref.listen<List<VibeUploadTask>>(vibeUploadProvider, (previous, next) {
      // Check for tasks that transitioned to success or error in the 'next' state
      for (final task in next) {
        final prevTask = previous?.firstWhereOrNull((t) => t.id == task.id);
        
        // Transition to SUCCESS
        if (task.status == VibeUploadStatus.success && prevTask?.status != VibeUploadStatus.success) {
          if (task.isSilent) continue; // 🔇 Local UI handle feedback
           debugPrint('🏁 [HomeScreen] Vibe upload completed: ${task.id}');
           // 2026 UX: Debounced Toast Logic
           // We suppress individual toasts here because SmartSendSheet handles the immediate "Sent!" feedback.
           // However, if the user leaves the app or navigates away quickly, we still want a confirmation.
           // But showing 10 toasts for 10 friends is spam.
           
           // Logic: Only show toast if NO other toast is currently visible (simple debounce)
           // Or better: Just show "Vibe sent!" generically. 
           
           // We'll rely on the existing SnackBar behavior which queues them, 
           // BUT we explicitly remove current one to avoid queue buildup?
           ScaffoldMessenger.of(context).removeCurrentSnackBar(); 
           
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                   AppIcon(AppIcons.checkCircle, color: AppColors.primaryAction, size: 20),
                   const SizedBox(width: 12),
                   // Generic message covers both single and multi-send scenarios nicely
                   Text('Vibe sent!', style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              backgroundColor: const Color(0xFF1E1E1E),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2), // Short duration
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        
        // Transition to ERROR
        if (task.status == VibeUploadStatus.error && prevTask?.status != VibeUploadStatus.error) {
          if (task.isSilent) continue; // 🔇 Local UI handles feedback
          debugPrint('❌ [HomeScreen] Vibe upload error feedback: ${task.error}');
          HapticFeedback.vibrate();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                   AppIcon(AppIcons.error, color: AppColors.error, size: 20),
                   const SizedBox(width: 12),
                   Expanded(child: Text('Failed to send: ${task.error ?? "Unknown error"}')),
                ],
              ),
              backgroundColor: const Color(0xFF1E1E1E),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              action: SnackBarAction(
                label: 'Retry',
                textColor: AppColors.primaryAction,
                onPressed: () {
                   // VibeUploadNotifier handles auto-retry logic or we can trigger it
                },
              ),
            ),
          );
        }
      }
    });
    
    return Scaffold(
      backgroundColor: AppColors.voidNavy,
      body: Stack(
        children: [
          // Main VERTICAL navigation (swipe up for dashboard)
            PageView(
                controller: _pageController,
                scrollDirection: Axis.vertical, // Vertical swipe!
                physics: _pagePhysics,
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                  HapticFeedback.selectionClick();
                },
                children: [
                  // Page 0: Camera (Default - top)
                  CameraScreenNew(
                    key: const ValueKey('camera_screen_main'),
                    onOpenVault: _openVaultSheet,
                    onOpenSettings: _openSettingsSheet,
                    isVisible: _currentPage == 0,
                    onDrawingModeChanged: (isDrawing) {
                      // Lock/unlock PageView based on drawing mode
                      setState(() {
                        _isDrawingMode = isDrawing;
                        _pagePhysics = (isDrawing || _isCameraActive)
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(parent: PageScrollPhysics());
                      });
                    },
                    onCaptureStateChanged: (isActive) {
                      // Hide/show history indicator based on camera state
                      setState(() {
                        _isCameraActive = isActive;
                        _pagePhysics = (_isDrawingMode || isActive)
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(parent: PageScrollPhysics());
                      });
                    },
                  ),
                  
                  // Page 1: Bento Dashboard (Swipe UP to see)
                  BentoDashboardScreen(
                    onNavigateBack: () {
                      // Navigate back to camera (page 0)
                      _pageController.animateToPage(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    },
                  ),
                ],
              ),

          // History indicator (only on camera page AND when camera is idle)
          if (_currentPage == 0 && !_isCameraActive)
            _buildHistoryIndicator(),
        ],
      ),
    );
  }

  /// History indicator at bottom of camera - tap or swipe up to see history
  Widget _buildHistoryIndicator() {
    // FIX: Respect iOS home indicator area on iPhone X+
    final bottomSafeArea = MediaQuery.of(context).viewPadding.bottom;
    
    return Positioned(
      bottom: 24 + bottomSafeArea, // Position safely above home indicator (avoid gesture conflict)
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () {
          // Animate to dashboard page
          _pageController.animateToPage(
            1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        },
        onVerticalDragEnd: (details) {
          // Swipe up gesture
          if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
            _pageController.animateToPage(
              1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'History',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white.withAlpha(180),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            AppIcon(
              AppIcons.caretUp,
              color: Colors.white.withAlpha(120),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  void _openVaultSheet() {
    HapticFeedback.mediumImpact();
    AppModal.show(
      context: context,
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('Memories', style: AppTypography.headlineMedium),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: AppIcon(AppIcons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            // Vault content placeholder
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIcons.gallery,
                      size: 64,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your memories will appear here',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
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

  void _openSettingsSheet() {
    HapticFeedback.mediumImpact();
    AppModal.show(
      context: context,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => _SettingsContent(scrollController: controller),
      ),
    );
  }
}

/// Settings Content - Extracted for modal use
class _SettingsContent extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  
  const _SettingsContent({super.key, this.scrollController});

  @override
  ConsumerState<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<_SettingsContent> {
  bool _isUpdatingAvatar = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle - REMOVED (VibeBottomSheet provides this)
          
          // Header
          Row(
            children: [
              Text('Settings', style: AppTypography.headlineLarge),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: AppIcon(AppIcons.close, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Profile section
          currentUser.when(
            data: (user) => user != null
                ? _buildProfileCard(context, user)
                : const SizedBox(),
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primaryAction),
            ),
            error: (_, __) => const SizedBox(),
          ),

          const SizedBox(height: 24),

          // Settings options
          _buildSettingsItem(
            icon: AppIcons.notification,
            title: 'Notifications',
            onTap: () {},
          ),
          _buildSettingsItem(
            icon: AppIcons.unlock,
            title: 'Privacy',
            onTap: () {},
          ),
          _buildSettingsItem(
            icon: AppIcons.widget,
            title: 'Widget Setup',
            onTap: () => context.push(AppRoutes.widgetSetup),
          ),
          _buildSettingsItem(
            icon: AppIcons.help,
            title: 'Help & Support',
            onTap: () {},
          ),
          _buildSettingsItem(
            icon: AppIcons.info,
            title: 'About',
            onTap: () {},
          ),

          // 🔧 DEBUG: Widget Testing Section (only in debug mode)
          if (kDebugMode) ...[
            const SizedBox(height: 32),
            Text('DEBUG: Test Widgets', style: AppTypography.labelLarge.copyWith(color: Colors.orange)),
            const SizedBox(height: 16),
            
            // Test Video Vibe
            GlassContainer(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              showGlow: true,
              glowColor: Colors.red,
              onTap: () async {
                await WidgetUpdateService.updateWidgetFromPush({
                  'senderName': 'Test User',
                  'senderId': 'test-user-123',
                  'senderAvatar': 'https://picsum.photos/200',
                  'vibeId': 'test-video-${DateTime.now().millisecondsSinceEpoch}',
                  'audioUrl': 'https://example.com/test.mp3',
                  'imageUrl': 'https://picsum.photos/400/600', // Thumbnail
                  'videoUrl': 'https://example.com/test.mp4',
                  'audioDuration': '15',
                  'isVideo': 'true',
                  'isAudioOnly': 'false',
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('📹 Video vibe sent to widget!')),
                  );
                }
              },
              child: Row(
                children: [
                  PhosphorIcon(PhosphorIcons.videoCamera(PhosphorIconsStyle.regular), color: Colors.red),
                  const SizedBox(width: 12),
                  Text('Test VIDEO Vibe', style: AppTypography.bodyMedium),
                  const Spacer(),
                  PhosphorIcon(PhosphorIcons.play(PhosphorIconsStyle.fill), color: Colors.white54),
                ],
              ),
            ),
            
            // Test Audio-Only Vibe
            GlassContainer(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              showGlow: true,
              glowColor: Colors.green,
              onTap: () async {
                await WidgetUpdateService.updateWidgetFromPush({
                  'senderName': 'Voice Test',
                  'senderId': 'test-user-456',
                  'senderAvatar': 'https://picsum.photos/200/200',
                  'vibeId': 'test-audio-${DateTime.now().millisecondsSinceEpoch}',
                  'audioUrl': 'https://example.com/voice.mp3',
                  'imageUrl': 'https://picsum.photos/200/200', // Avatar for blur
                  'audioDuration': '8',
                  'isVideo': 'false',
                  'isAudioOnly': 'true',
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('🎤 Audio-only vibe sent to widget!')),
                  );
                }
              },
              child: Row(
                children: [
                  PhosphorIcon(PhosphorIcons.microphone(PhosphorIconsStyle.regular), color: Colors.green),
                  const SizedBox(width: 12),
                  Text('Test AUDIO-ONLY Vibe', style: AppTypography.bodyMedium),
                  const Spacer(),
                  PhosphorIcon(PhosphorIcons.play(PhosphorIconsStyle.fill), color: Colors.white54),
                ],
              ),
            ),
            
            // Test Photo+Audio Vibe
            GlassContainer(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              showGlow: true,
              glowColor: Colors.purple,
              onTap: () async {
                await WidgetUpdateService.updateWidgetFromPush({
                  'senderName': 'Photo Test',
                  'senderId': 'test-user-789',
                  'senderAvatar': 'https://picsum.photos/201/201',
                  'vibeId': 'test-photo-${DateTime.now().millisecondsSinceEpoch}',
                  'audioUrl': 'https://example.com/audio.mp3',
                  'imageUrl': 'https://picsum.photos/400/600',
                  'audioDuration': '5',
                  'isVideo': 'false',
                  'isAudioOnly': 'false',
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('📷 Photo+Audio vibe sent to widget!')),
                  );
                }
              },
              child: Row(
                children: [
                  PhosphorIcon(PhosphorIcons.camera(), color: Colors.purple),
                  const SizedBox(width: 12),
                  Text('Test PHOTO+AUDIO Vibe', style: AppTypography.bodyMedium),
                  const Spacer(),
                  PhosphorIcon(PhosphorIcons.play(), color: Colors.white54),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Vibe+ subscription
          _buildSubscriptionCard(context),

          const SizedBox(height: 32),

          // Sign out
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () async {
                    await ref.read(authServiceProvider).signOut();
                    if (context.mounted) {
                      Navigator.pop(context);
                      context.go(AppRoutes.splash);
                    }
                  },
                  child: Text(
                    'Sign Out',
                    style: AppTypography.labelLarge.copyWith(color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 24),
                TextButton(
                  onPressed: () => _confirmDeleteAccount(context),
                  child: Text(
                    'Delete Account',
                    style: AppTypography.labelLarge.copyWith(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Version
          Center(
            child: Text(
              'Nock v1.0.0',
              style: AppTypography.caption,
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, UserModel user) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      useLuminousBorder: true, // 🌟 PHASE 2: Luminous profile card
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.auraGradient,
            ),
            child: user.avatarUrl != null
                ? ClipOval(
                    child: Image.network(user.avatarUrl!, fit: BoxFit.cover),
                  )
                : PhosphorIcon(PhosphorIcons.user(PhosphorIconsStyle.regular), size: 28, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName, style: AppTypography.headlineSmall),
                const SizedBox(height: 4),
                Text(user.phoneNumber, style: AppTypography.bodySmall),
              ],
            ),
          ),
          IconButton(
            onPressed: _isUpdatingAvatar ? null : () => _pickAndUploadAvatar(context),
            icon: _isUpdatingAvatar 
                ? const SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary)
                  )
                : Icon(AppIcons.edit, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadAvatar(BuildContext context) async {
    debugPrint('🔘 Profile Edit Button Pressed!');
    final picker = ImagePicker();
    try {
      debugPrint('📸 Launching Image Picker...');
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      debugPrint('📸 Image Picker Result: ${image?.path ?? "Cancelled"}');

      if (image != null) {
        setState(() => _isUpdatingAvatar = true);
        HapticFeedback.mediumImpact();
        
        await ref.read(authServiceProvider).updateAvatar(File(image.path));
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile picture updated everywhere!'),
              backgroundColor: AppColors.vibePrimary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update avatar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAvatar = false);
      }
    }
  }



  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      useLuminousBorder: true, // 🌟 PHASE 2: Luminous settings
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary),
          const SizedBox(width: 16),
          Text(title, style: AppTypography.bodyLarge),
          const Spacer(),
          Icon(AppIcons.chevronRight, color: AppColors.textTertiary),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      showGlow: true,
      useLuminousBorder: true, // 🌟 PHASE 2: Luminous premium card
      glowColor: AppColors.secondaryAction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppColors.primaryGradient.createShader(bounds),
                child: Text(
                  'VIBE+',
                  style: AppTypography.headlineMedium.copyWith(color: Colors.white),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.secondaryAction,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '\$4.99/mo',
                  style: AppTypography.labelMedium.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Unlock unlimited memories in the Vault',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push(AppRoutes.subscription),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondaryAction,
              ),
              child: Text('Upgrade', style: AppTypography.buttonText),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Account?', style: AppTypography.headlineSmall.copyWith(color: Colors.white)),
        content: Text(
          'This will permanently delete your profile, vibes, and subscription data. This action cannot be undone.',
          style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppTypography.buttonText.copyWith(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete Permanently', style: AppTypography.buttonText.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // 2025: Robust deletion flow with re-authentication support
      try {
        await ref.read(authServiceProvider).deleteAccount();
        if (context.mounted) _handleDeletionSuccess(context);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          debugPrint('🔐 Deletion requires re-authentication. Prompting user...');
          if (context.mounted) {
            await _handleReauthenticationFlow(context);
          }
        } else {
            if (context.mounted) _handleDeletionError(context, e.message ?? e.code);
        }
      } catch (e) {
        if (context.mounted) _handleDeletionError(context, e.toString());
      }
    }
  }

  Future<void> _handleReauthenticationFlow(BuildContext context) async {
    // 1. Explain why
    final shouldReauth = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Security Check', style: AppTypography.headlineSmall.copyWith(color: Colors.white)),
        content: Text(
          'For your security, please sign in again to confirm you want to delete this account.',
          style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
             onPressed: () => Navigator.pop(context, false),
             child: Text('Cancel', style: AppTypography.buttonText.copyWith(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryAction),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Verify Identity', style: AppTypography.buttonText.copyWith(color: Colors.black)),
          ),
        ],
      ),
    );

    if (shouldReauth != true) return;

    // 2. Determine provider and re-authenticate
    try {
        final originalUser = ref.read(currentUserProvider).value;
        final originalUid = FirebaseAuth.instance.currentUser?.uid; // Capture physical UID
        final provider = originalUser?.authProvider ?? 'google';
        
        if (originalUid == null) throw Exception('No authenticated user found');

        debugPrint('🔐 Re-authenticating via $provider (Original UID: $originalUid)...');
        
        if (provider == 'google') {
            await ref.read(authServiceProvider).signInWithGoogle();
        } else if (provider == 'apple') {
            await ref.read(authServiceProvider).signInWithApple();
        } else {
             throw Exception('Unsupported auth provider for legacy re-auth');
        }

        // --- SECURITY FIX: IDENTITY VERIFICATION ---
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid != originalUid) {
            debugPrint('🚨 SECURITY ALERT: Identity mismatch during re-auth! (New: $currentUid, Original: $originalUid)');
            
            // Immediately sign out to clear the "wrong" account
            await ref.read(authServiceProvider).signOut();
            
            if (context.mounted) {
                showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                        backgroundColor: AppColors.surface,
                        title: Text('Identity Mismatch', style: AppTypography.headlineSmall.copyWith(color: Colors.white)),
                        content: Text(
                            'The account you just signed into does not match the one you are trying to delete. Please sign in with the correct account.',
                            style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
                        ),
                        actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('OK', style: AppTypography.buttonText.copyWith(color: AppColors.primaryAction)),
                            ),
                        ],
                    ),
                );
            }
            return;
        }
        // --- END SECURITY FIX ---
        
        // 3. Retry Deletion immediately
        await ref.read(authServiceProvider).deleteAccount();
        if (context.mounted) _handleDeletionSuccess(context);

    } catch (e) {
        if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Verification failed: $e')),
            );
        }
    }
  }

  void _handleDeletionSuccess(BuildContext context) {
      Navigator.pop(context); // Close settings sheet
      context.go(AppRoutes.splash);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account successfully deleted.')),
      );
  }

  void _handleDeletionError(BuildContext context, String error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
  }
}
