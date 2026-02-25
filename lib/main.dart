import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'core/router/app_router.dart';
import 'core/services/widget_update_service.dart';
import 'core/services/cache_cleanup_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/fcm_token_service.dart';
import 'core/services/audio_service.dart';
import 'core/services/subscription_service.dart';
import 'core/services/storage_hygiene_service.dart'; // CRITICAL: Storage cleanup

/// Main entry point for the Nock app
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style for immersive experience
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.voidNavy,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Firebase
  await Firebase.initializeApp();

  // 📶 OFFLINE CONTINUITY: Ensure dashboard is "Instant-On" even without network.
  // We explicitly enable persistence but use default cache size (40MB) for security.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  // Register FCM background message handler for widget updates
  // This MUST be done before runApp() and handler MUST be top-level
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // STARTUP FIX: Don't request notification permissions here!
  // It blocks app launch and users deny without context.
  // Instead, ask AFTER first vibe is sent (contextual permission priming)
  // See: preview_screen.dart _askForNotificationsContextually()

  // REMOVED: _syncPendingReadReceipts() - Race Condition Fix
  // The sync is now handled reactively in HomeScreen via ref.listen on currentUserProvider.
  // This fixes the race condition where authStateChanges().first could timeout on slow devices.
  // See: lib/features/home/presentation/home_screen.dart - build() method

  // Run the app
  runApp(const ProviderScope(child: NockApp()));
}

// REMOVED: _syncPendingReadReceipts() function
// The blocking auth check with timeout was causing silent failures on slow devices.
// This logic is now in HomeScreen.build() using ref.listen for reactive sync.
// Benefits:
// 1. Zero-Blocking Launch: App starts instantly
// 2. Guaranteed Auth: Sync only happens when user is confirmed authenticated
// 3. Self-Healing: Re-syncs on re-login or account switch

// REMOVED: _requestNotificationPermissions
// This is now handled contextually in preview_screen.dart

/// Root application widget
class NockApp extends ConsumerStatefulWidget {
  const NockApp({super.key});

  @override
  ConsumerState<NockApp> createState() => _NockAppState();
}

class _NockAppState extends ConsumerState<NockApp> {
  // 🚀 OPTIMIZATION: Removed _isInitialized state.
  // The app should render the UI immediately. Services load in background.

  @override
  void initState() {
    super.initState();
    // Fire-and-forget background initialization
    _initBackgroundServices();
  }

  /// Initialize non-critical services in the background without blocking UI
  Future<void> _initBackgroundServices() async {
    // Small delay to let the UI frame render first
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final router = ref.read(routerProvider);

      // Initialize deep link handling
      final deepLinkService = ref.read(deepLinkServiceProvider);
      await deepLinkService.initialize(router);

      // Initialize FCM with router
      final fcmService = ref.read(fcmTokenServiceProvider);
      await fcmService.initialize(router: router);

      // Initialize Cache & Subscription services (Background)
      final cacheService = ref.read(cacheCleanupServiceProvider);
      cacheService.initialize(); // Fire & Forget

      final subscriptionService = ref.read(subscriptionServiceProvider);
      subscriptionService.initialize(); // Fire & Forget

      // 🧹 STORAGE HYGIENE: Clean up orphaned ghost recordings (Fire & Forget)
      StorageHygieneService.cleanOrphanedRecordings();

      // Audio Focus & Session (Best Practice)
      await AudioService.initSession();

      // Sync theme colors to native widgets
      await AppColors.syncThemeWithWidgets();

      debugPrint('🚀 App: Background initialization complete');
    } catch (e) {
      debugPrint('⚠️ App: Service initialization error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🎨 UX OPTIMIZATION: IsInitialized check REMOVED.
    // The router provider is watched immediately. The Router itself handles
    // redirecting to splash/loading states if Auth/Onboarding are loading.
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Nock',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
      builder: (context, child) {
        // ACCESSIBILITY FIX: Full Dynamic Type support enabled
        return AudioLifecycleManager(child: child ?? const SizedBox());
      },
    );
  }
}
