import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/models/vibe_model.dart';
import 'package:nock/features/onboarding/presentation/onboarding_screen.dart';
import 'package:nock/features/onboarding/presentation/permission_screens.dart';
import 'package:nock/features/onboarding/presentation/widget_setup_screen.dart';
import 'package:nock/features/auth/presentation/welcome_screen.dart';
import 'package:nock/features/home/presentation/home_screen.dart';
import 'package:nock/features/home/presentation/home_screen.dart';
import 'package:nock/features/camera/presentation/camera_screen_new.dart';
import 'package:nock/features/camera/presentation/preview_screen.dart';
import 'package:nock/features/subscription/presentation/subscription_screen.dart';
import 'package:nock/features/invite/presentation/invite_acceptance_screen.dart';
import 'package:nock/features/squad/presentation/squad_screen.dart';
import 'package:nock/features/squad/presentation/add_friends_screen.dart';
import 'package:nock/features/player/presentation/player_screen.dart';
import 'package:nock/core/providers/onboarding_provider.dart';
import 'package:nock/core/providers/deep_link_provider.dart';
import 'package:nock/core/providers/widget_launch_provider.dart';
import 'package:nock/features/widget/presentation/bff_config_screen.dart';
import 'package:nock/features/auth/presentation/not_found_screen.dart';
// SplashScreen is exported by onboarding_screen.dart

/// Provider for tracking if widget launch has been handled
final _widgetLaunchHandledProvider = StateProvider<bool>((ref) => false);

/// App Router Provider
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final onboardingState = ref.watch(onboardingStateProvider);
  // CRITICAL FIX: Watch the ACTIVE invite (respects session dismissal)
  final activeInviteId = ref.watch(activeInviteProvider);
  final pendingInviteNotifier = ref.read(pendingInviteProvider.notifier);
  final widgetLaunch = ref.watch(widgetLaunchProvider);
  
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    redirect: (context, state) async {
      debugPrint('🔀 Router: redirect called for ${state.matchedLocation}');
      

      
      final isLoading = authState.isLoading || onboardingState.isLoading;
      debugPrint('🔀 Router: isLoading=$isLoading (auth=${authState.isLoading}, onboarding=${onboardingState.isLoading})');
      
      if (isLoading) {
        debugPrint('🔀 Router: Still loading, staying on current route');
        return null; // Stay on current route (usually splash)
      }

      final isLoggedIn = authState.valueOrNull != null;
      final onboardingCompleted = onboardingState.valueOrNull ?? false;
      
      debugPrint('🔀 Router: isLoggedIn=$isLoggedIn, onboardingCompleted=$onboardingCompleted');
      
      final isSplash = state.matchedLocation == AppRoutes.splash;
      final isWelcome = state.matchedLocation == '/welcome';
      final isAuthRoute = isWelcome;
      final isOnboardingRoute = state.matchedLocation == AppRoutes.onboarding ||
          // 2025 FIX: Permission routes removed from safe list.
          // Force users to finish intro before accessing permissions.
          // state.matchedLocation.startsWith('/permission') ||
          state.matchedLocation == AppRoutes.widgetSetup;
      
      final isInviteRoute = state.matchedLocation.startsWith('/home/invite/') || 
          state.matchedLocation.startsWith('/home/i/') ||
          state.matchedLocation.startsWith('/invite/') ||
          state.matchedLocation.startsWith('/i/');
      
      // DEEP LINK FIX: Android parses nock://invite/userid as path=/invite/userid
      // But sometimes it might come as just /userid - handle both cases
      // If the path looks like an unknown route (not matching any known routes),
      // and it could be an invite ID, redirect to proper invite route
      final matchedPath = state.matchedLocation;
      final isKnownRoute = matchedPath == '/' ||
          matchedPath == '/home' ||
          matchedPath == '/welcome' ||
          matchedPath == '/onboarding' ||
          matchedPath.startsWith('/permission') ||
          matchedPath == '/widget-setup' ||

          matchedPath == '/camera' ||
          matchedPath == '/preview' ||
          matchedPath == '/vault' ||
          matchedPath == '/squad' ||
          matchedPath == '/add-friends' ||
          matchedPath.startsWith('/home/player/') ||
          matchedPath.startsWith('/invite/') ||
          matchedPath.startsWith('/record/') ||
          matchedPath == AppRoutes.splash;
      
      
      // Unknown route check REMOVED
      // We no longer "guess" IDs from unknown paths to prevent hijacking
      // valid feature routes (like /settings_page).
      // Short-links should now use the explicit /i/ prefix.

      if (!isLoggedIn) {
        debugPrint('🔀 Router: User NOT logged in');
        
        // SAVE PROTECTED DEEP LINK (The "Lost Link" Fix)
        // If unauth user tries to access a feature, save location before kicking to welcome.
        // We only save safe, meaningful routes (player, record).
        if (state.matchedLocation.startsWith('/home/player/') || 
            state.matchedLocation.startsWith('/home/record/') ||
            state.matchedLocation.startsWith('/player/') ||
            state.matchedLocation.startsWith('/record/') ||
            state.matchedLocation.startsWith('/p/') ||
            state.matchedLocation.startsWith('/r/')) {
             
             final targetUri = state.uri.toString();
             debugPrint('🔀 Router: Unauth user accessing $targetUri -> Saving to pendingRedirect');
             ref.read(pendingRedirectProvider.notifier).setPendingRedirect(targetUri);
        }

        // Handle Deep Link Invite for unauth user - SAVE IT for later
        if (isInviteRoute) {
          final uri = state.uri;
          if (uri.pathSegments.length > 1) {
            // Check if it's /invite/ID or /i/ID
            if (uri.pathSegments[0] == 'invite' || uri.pathSegments[0] == 'i') {
              final inviteId = uri.pathSegments[1];
              await pendingInviteNotifier.setPendingInvite(inviteId);
            }
          }
          debugPrint('🔀 Router: Invite route -> /welcome');
          return '/welcome';
        }

        // Allow auth/welcome routes
        if (isAuthRoute) {
          debugPrint('🔀 Router: Already on auth route, staying');
          return null;
        }
        
        // If onboarding not done, go to onboarding
        if (!onboardingCompleted) {
          if (isOnboardingRoute) { // FIX: Don't stay on Splash, allow redirect to Onboarding
            debugPrint('🔀 Router: On onboarding route, staying');
            return null;  // Allow staying on onboarding screens
          }
          debugPrint('🔀 Router: Onboarding not complete -> /onboarding');
          return AppRoutes.onboarding;
        }
        
        // Onboarding done but not logged in -> go to welcome/auth
        debugPrint('🔀 Router: Onboarding done, not authed -> /welcome');
        return '/welcome';
      }
      // 2. User is logged in - handle onboarding and auth routes
      // NOTE: We get here only if isLoggedIn=true (passed the !isLoggedIn block above)
      
      debugPrint('🔀 Router: User IS logged in');
      
      // If logged in and onboarding not done, let them finish onboarding
      if (!onboardingCompleted) {
        debugPrint('🔀 Router: Logged in but onboarding not complete');
        
        // If they're on an auth route (welcome, phone), redirect to onboarding or home
        if (isAuthRoute) {
          debugPrint('🔀 Router: On auth route while logged in -> /onboarding');
          return AppRoutes.onboarding;  // Continue onboarding
        }
        
        // Allow onboarding routes
        if (isOnboardingRoute) {
          debugPrint('🔀 Router: On onboarding route, staying');
          return null;
        }
        
        // Trying to go to home or other protected route before onboarding complete
        debugPrint('🔀 Router: Logged in, onboarding not complete -> /onboarding');
        return AppRoutes.onboarding;
      }
      
      // 3. User is logged in AND onboarding complete - redirect away from auth/onboarding routes
      
      // RESTORE PENDING REDIRECT (Deep Link Persistence)
      // Check if we need to restore a deep link that was clicked while logged out
      final pendingRedirect = ref.read(pendingRedirectProvider);
      if (pendingRedirect != null) {
        debugPrint('🔀 Router: Restoring pending redirect -> $pendingRedirect');
        // Clear it so we don't loop
        ref.read(pendingRedirectProvider.notifier).clearPendingRedirect();
        return pendingRedirect;
      }

      if (isAuthRoute || isOnboardingRoute || isSplash) {
        debugPrint('🔀 Router: Logged in + onboarded, on auth/onboarding route -> /home');
        return AppRoutes.home;
      }

      // 4. TRANSFORMATION: Redirect top-level Deep Link aliases to nested routes
      // This ensures we maintain the correct navigation stack [Home -> Feature]
      if (state.matchedLocation.startsWith('/invite/')) {
        final userId = state.pathParameters['userId'];
        return '/home/invite/$userId';
      }
      if (state.matchedLocation.startsWith('/i/')) {
        final userId = state.pathParameters['userId'];
        return '/home/i/$userId';
      }
      if (state.matchedLocation.startsWith('/player/')) {
        final vibeId = state.pathParameters['vibeId'];
        return '/home/player/$vibeId';
      }
      if (state.matchedLocation.startsWith('/p/')) {
        final vibeId = state.pathParameters['vibeId'];
        return '/home/player/$vibeId';
      }
      if (state.matchedLocation.startsWith('/record/')) {
        final friendId = state.pathParameters['friendId'];
        return '/home/record/$friendId';
      }
      if (state.matchedLocation.startsWith('/r/')) {
        final friendId = state.pathParameters['friendId'];
        return '/home/record/$friendId';
      }

      // 4. CRITICAL FIX: Check for Pending Invite BEFORE going home
      // This completes the viral loop - users who clicked invite links
      // will now be redirected to accept the invite after logging in
      // 2025 FIX: Check if we are already on the invite route to prevent loop
      final activeInviteId = ref.read(activeInviteProvider);
      if (activeInviteId != null && !isInviteRoute) {
        final target = '/home/invite/$activeInviteId';
        
        // CRITICAL GUARD: If we are already within the invite sub-tree, do NOT redirect.
        if (state.matchedLocation.startsWith('/home/invite/')) {
          debugPrint('🔀 Router: Already in invite flow, stopping redirect');
          return null;
        }
        
        debugPrint('🔀 Router: Redirecting to invite acceptance for $activeInviteId');
        return target;
      }

      // 5. Handle Widget Cold Start
      final rHandler = ref.read(_widgetLaunchHandledProvider.notifier);
      final isHandled = ref.read(_widgetLaunchHandledProvider);
      final launchUri = widgetLaunch.valueOrNull;
      
      if (!isHandled && launchUri != null) {
        rHandler.state = true;
        // Extract vibe ID from widget launch URI if present
        final vibeId = launchUri.queryParameters['vibeId'];
        if (vibeId != null && vibeId.isNotEmpty) {
          // INSTANT REPLY: Mark as from notification for reply focus
          debugPrint('🔀 Router: Widget launch -> player/$vibeId (fromNotification)');
          return '/home/player/$vibeId?fromNotification=true';
        }
      }
      
      // 5.5 CRITICAL FIX: Handle "naked" IDs from old nock://player/ID or nock://invite/ID links
      // When scheme host is present but not handled by Uri components, GoRouter sees just /ID
      if (!isKnownRoute && state.uri.pathSegments.length == 1) {
        final possibleId = state.uri.pathSegments.first;
        // UUID Pattern check (36 chars with hyphens)
        final uuidRegex = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);
        
        if (uuidRegex.hasMatch(possibleId)) {
           debugPrint('🔀 Router: Naked UUID detected ($possibleId), attempting player redirect');
           // Default to player if naked ID found
           return '/home/player/$possibleId';
        }
      }
      
      
      // 6. Default: Redirect from auth/splash routes to Home
      if (isAuthRoute || isSplash || isOnboardingRoute) {
        debugPrint('🔀 Router: Redirecting from $state.matchedLocation to ${AppRoutes.home}');
        return AppRoutes.home;
      }

      debugPrint('🔀 Router: No redirect needed, staying at ${state.matchedLocation}');
      return null;
    },
    routes: [
      // Splash
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),

      // Onboarding
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      
      // Welcome screen (multi-auth: Google, Apple, Phone, Guest)
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),

      // Permission screens
      GoRoute(
        path: AppRoutes.permissionMic,
        builder: (context, state) => const MicrophonePermissionScreen(),
      ),
      GoRoute(
        path: AppRoutes.permissionNotification,
        builder: (context, state) => const NotificationPermissionScreen(),
      ),
      GoRoute(
        path: AppRoutes.permissionCamera,
        builder: (context, state) => const CameraPermissionScreen(),
      ),
      GoRoute(
        path: AppRoutes.permissionContacts,
        builder: (context, state) => const ContactsPermissionScreen(),
      ),
      GoRoute(
        path: AppRoutes.widgetSetup,
        builder: (context, state) => const WidgetSetupScreen(),
      ),

      // Main screens
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
        routes: [
          // NESTED ROUTES: Synthesize stack [Home -> Feature]
          // This ensures the back button works for deep links!
          
          // Player - nested under /home
          GoRoute(
            path: 'player/:vibeId',
            builder: (context, state) {
              final extra = state.extra;
              VibeModel? vibe;
              List<VibeModel>? vibesList;
              int? startIndex;
              
              if (extra is VibeModel) {
                vibe = extra;
              } else if (extra is Map<String, dynamic>) {
                vibe = extra['vibe'] as VibeModel?;
                vibesList = extra['vibesList'] as List<VibeModel>?;
                startIndex = extra['startIndex'] as int?;
              }
              
              final fromNotification = state.uri.queryParameters['fromNotification'] == 'true';
              
              return PlayerScreen(
                vibe: vibe,
                vibeId: state.pathParameters['vibeId'],
                fromNotification: fromNotification,
                vibesList: vibesList,
                startIndex: startIndex,
              );
            },
          ),

          // Invite Acceptance - nested under /home
          GoRoute(
            path: 'invite/:userId',
            builder: (context, state) {
              final userId = state.pathParameters['userId'];
              return InviteAcceptanceScreen(inviterId: userId ?? '');
            },
          ),
          
          // Short Invite Alias
          GoRoute(
            path: 'i/:userId',
            builder: (context, state) {
              final userId = state.pathParameters['userId'];
              return InviteAcceptanceScreen(inviterId: userId ?? '');
            },
          ),

          GoRoute(
            path: 'squad',
            builder: (context, state) => const SquadScreen(),
          ),
          GoRoute(
            path: 'add-friends',
            builder: (context, state) => const AddFriendsScreen(),
          ),
          GoRoute(
            path: 'subscription',
            builder: (context, state) => const SubscriptionScreen(),
          ),
          
          // Record - nested under /home
          GoRoute(
            path: 'record/:friendId',
            builder: (context, state) {
              final friendId = state.pathParameters['friendId'];
              return CameraScreenNew(
                isAudioOnly: true,
                recipientId: friendId,
              );
            },
          ),
        ],
      ),
      
      // TOP-LEVEL ALIASES for Deep Links (API 34/Android 14 compatibility)
      // These routes prevent the "Janky" errorBuilder fallback.
      // The top-level redirect: logic will transform these into /home/... nested routes
      // to ensure a correct navigation stack remains.
      GoRoute(
        path: '/invite/:userId',
        builder: (context, state) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: '/i/:userId',
        builder: (context, state) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: '/player/:vibeId',
        builder: (context, state) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: '/p/:vibeId', // Short alias for player
        builder: (context, state) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),

      // Preview screen for sending vibes
      GoRoute(
        path: '/preview',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return PreviewScreen(
            imagePath: extra?['imagePath'] ?? '',
            audioPath: extra?['audioPath'] ?? '',
            videoPath: extra?['videoPath'],
            isVideo: extra?['isVideo'] ?? false,
            isAudioOnly: extra?['isAudioOnly'] ?? false,  // Audio-only mode
            senderAvatarUrl: extra?['senderAvatarUrl'],   // For blurred background
            isFromGallery: extra?['isFromGallery'] ?? false,
            originalPhotoDate: extra?['originalPhotoDate'],
            audioDuration: extra?['audioDuration'] as int?,
          );
        },
      ),

      // Camera - keeps separate for full screen immersion
      GoRoute(
        path: AppRoutes.camera,
        builder: (context, state) => CameraScreenNew(replyTo: state.extra as VibeModel?),
      ),

      // TOP-LEVEL ALIASES for Deep Links (API 34/Android 14 compatibility)
      GoRoute(
        path: '/record/:friendId',
        builder: (context, state) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: '/r/:friendId', // Short alias
        builder: (context, state) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),

      // Widget Configuration - Modern BFF Selector
      GoRoute(
        path: '/widget-config/:appWidgetId',
        builder: (context, state) {
          final appWidgetId = int.tryParse(state.pathParameters['appWidgetId'] ?? '0') ?? 0;
          return BFFConfigScreen(appWidgetId: appWidgetId);
        },
      ),
    ],
    // Custom error handler for genuine 404s
    errorBuilder: (context, state) {
      debugPrint('🔀 Router Error: URI=${state.uri}, path=${state.uri.path}');
      return NotFoundScreen(uri: state.uri);
    },
  );
});
