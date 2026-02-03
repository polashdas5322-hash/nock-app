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
      systemNavigationBarColor: Color(0xFF121212),
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
  runApp(
    const ProviderScope(
      child: NockApp(),
    ),
  );
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
  // Track initialization state
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Start initialization immediately (not in addPostFrameCallback)
    _initApp();
  }
  
  Future<void> _initApp() async {
    try {
      final router = ref.read(routerProvider);
      
      // Initialize deep link handling
      final deepLinkService = ref.read(deepLinkServiceProvider);
      await deepLinkService.initialize(router);
      
      // Initialize FCM with router
      final fcmService = ref.read(fcmTokenServiceProvider);
      await fcmService.initialize(router: router);

      // Initialize Cache & Subscription services
      final cacheService = ref.read(cacheCleanupServiceProvider);
      await cacheService.initialize();
      
      final subscriptionService = ref.read(subscriptionServiceProvider);
      await subscriptionService.initialize();

      // 🧹 STORAGE HYGIENE: Clean up orphaned ghost recordings (Fire & Forget)
      // We don't await this to keep app startup instant. It runs in background.
      StorageHygieneService.cleanOrphanedRecordings();

      // Audio Focus & Session (Best Practice)
      await AudioService.initSession();

      // Sync theme colors to native widgets
      await AppColors.syncThemeWithWidgets();

    } catch (e) {
      debugPrint('Service initialization error: $e');
    } finally {
      // Mark as initialized regardless of success/failure to unblock app
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. BLOCK the app until services are ready
    if (!_isInitialized) {
      // Return a simple loading screen
      // This prevents the Router from even existing yet
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: AppColors.background,
        ),
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(
              color: AppColors.primaryAction,
              strokeWidth: 3,
            ),
          ),
        ),
      );
    }

    // 2. Services are ready: Render the real app with Router
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Nock',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
      builder: (context, child) {
        // ACCESSIBILITY FIX: Allow text scaling but cap it to prevent layout breaks
        final textScaler = MediaQuery.textScalerOf(context);
        return AudioLifecycleManager(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: textScaler.clamp(maxScaleFactor: 1.3),
            ),
            child: child ?? const SizedBox(),
          ),
        );
      },
    );
  }
}

