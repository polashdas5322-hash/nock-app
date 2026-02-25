import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/features/onboarding/presentation/permission_screens.dart';
import 'package:nock/features/onboarding/presentation/identity_screen.dart';
import 'package:nock/features/onboarding/presentation/widget_setup_screen.dart';
import 'package:nock/features/onboarding/presentation/splash_screen.dart';
import 'package:nock/features/auth/presentation/welcome_screen.dart';
import 'package:nock/features/home/presentation/home_screen.dart';
import 'package:nock/features/camera/presentation/camera_screen_new.dart';
import 'package:nock/features/invite/presentation/invite_acceptance_screen.dart';
import 'package:nock/features/player/presentation/player_screen.dart';
import 'package:nock/features/squad/presentation/add_friends_screen.dart';
import 'package:nock/features/squad/presentation/squad_screen.dart';
import 'package:nock/features/subscription/presentation/subscription_screen.dart';
import 'package:nock/core/models/vibe_model.dart';
import 'package:nock/core/providers/onboarding_provider.dart';
import 'package:nock/core/providers/deep_link_provider.dart';
import 'package:nock/core/providers/widget_launch_provider.dart';
import 'package:nock/features/auth/presentation/not_found_screen.dart';

/// Provider for tracking if widget launch has been handled
final _widgetLaunchHandledProvider = StateProvider<bool>((ref) => false);

/// App Router Provider
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final onboardingState = ref.watch(onboardingStateProvider);
  // CRITICAL FIX: Watch the ACTIVE invite (respects session dismissal)
  final activeInviteId = ref.watch(activeInviteProvider);
  final pendingInviteNotifier = ref.read(
    pendingInviteProvider.notifier,
  ); // Keep for legacy
  final widgetLaunch = ref.watch(widgetLaunchProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    redirect: (context, state) async {
      debugPrint('🔀 Router: redirect called for ${state.matchedLocation}');

      final isLoading = authState.isLoading || onboardingState.isLoading;
      debugPrint(
        '🔀 Router: isLoading=$isLoading (auth=${authState.isLoading}, onboarding=${onboardingState.isLoading})',
      );

      if (isLoading) {
        debugPrint('🔀 Router: Still loading, staying on current route');
        return null; // Stay on current route (usually splash)
      }

      final isLoggedIn = authState.valueOrNull != null;
      final onboardingCompleted = onboardingState.valueOrNull ?? false;

      debugPrint(
        '🔀 Router: isLoggedIn=$isLoggedIn, onboardingCompleted=$onboardingCompleted',
      );

      final isSplash = state.matchedLocation == AppRoutes.splash;
      final isWelcome = state.matchedLocation == AppRoutes.welcome;
      final isAuthRoute = isWelcome;

      // Onboarding Route Check (Updated for 5-Stage Flow with Identity)
      final isOnboardingRoute =
          state.matchedLocation == AppRoutes.identity ||
          state.matchedLocation == AppRoutes.permissionContacts ||
          state.matchedLocation == AppRoutes.widgetSetup;

      // 1. Splash Handling
      if (isSplash) {
        if (isLoggedIn) {
          if (onboardingCompleted) {
            return AppRoutes.home;
          } else {
            return AppRoutes.identity; // Start at Identity (Stage 2)
          }
        } else {
          return AppRoutes.welcome;
        }
      }

      // 2. Unauthenticated User Logic
      if (!isLoggedIn) {
        // Allow Invite Routes to pass through to "Welcome" (handled by UI state if needed, or redirect)
        // Actually, for invite/deep links, we usually want them to land on Welcome
        // but store the pending invite.
        // For now, if not logged in, force Welcome unless already there.
        if (isAuthRoute) return null;

        // Allow Deep Links to pass through? No, must auth first.
        // We rely on DeepLinkService to store the pending link and redirect after auth.
        // So here we enforce Welcome.
        return AppRoutes.welcome;
      }

      // 3. Authenticated User Logic
      if (isLoggedIn) {
        // If user is on Welcome, move them forward
        if (isAuthRoute) {
          if (onboardingCompleted) {
            return AppRoutes.home;
          } else {
            return AppRoutes.identity;
          }
        }

        // 3a. Viral Loop: Force Redirect to Invite if Pending
        // This handles "Deep Link Jump Scare" safely:
        // - WelcomeScreen waits for invite check -> Sets Store
        // - Auth Completes -> Router sees activeInviteId -> Redirects here
        // - InviteScreen mounts -> Dismisses ID -> User can leave
        if (activeInviteId != null) {
          final invitePath = '/home/invite/$activeInviteId';
          if (state.matchedLocation != invitePath) {
            debugPrint(
              '🔀 Router: Force redirect to pending invite: $invitePath',
            );
            return invitePath;
          }
        }

        // 4. Onboarding Enforcement
        // If Onboarding NOT complete, strict flow:
        // Welcome -> Squad (Contacts) -> Magic (Widget) -> Home
        if (!onboardingCompleted) {
          // Allow Invite Acceptance to bypass onboarding?
          // "Viral Loop Optimization": If user has an active invite, maybe go straight to InviteAcceptance?
          // Code below handles specific routes.

          // Allow them to be on onboarding routes
          if (isOnboardingRoute) return null;

          // If they are trying to go Home, force Identity
          if (state.matchedLocation == AppRoutes.home) {
            return AppRoutes.identity;
          }

          // Allow other routes if necessary? Generally lock them in.
          // Ensure they are in the flow.
          // If they are lost, send to Identity.
          return AppRoutes.identity;
        }

        // 5. Onboarding Complete -> Block Onboarding Routes
        if (isOnboardingRoute) {
          return AppRoutes.home;
        }
      }

      return null; // No redirect needed
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      // NEW ONBOARDING ROUTES
      GoRoute(
        path: AppRoutes.identity,
        builder: (context, state) => const IdentityScreen(),
      ),
      GoRoute(
        path: AppRoutes.permissionContacts,
        builder: (context, state) => const ContactsPermissionScreen(),
      ),
      GoRoute(
        path: AppRoutes.widgetSetup,
        builder: (context, state) => const WidgetSetupScreen(),
      ),

      // MAIN APP
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) {
          // Handle deep links passed as query params or extra if needed?
          // Usually state.pathParameters
          return const HomeScreen();
        },
        routes: [
          // Sub-routes if any
          GoRoute(
            path: 'camera',
            builder: (context, state) => CameraScreenNew(
              isVisible: true,
              // Pass params if any
            ),
          ),
          GoRoute(
            path: 'profile',
            builder: (context, state) => const Scaffold(
              body: Center(child: Text("Profile Stub")),
            ), // Placeholder
          ),
          // Player screen for viewing vibes
          GoRoute(
            path: 'player/:vibeId',
            builder: (context, state) {
              final vibeId = state.pathParameters['vibeId'];
              final vibe = state.extra is VibeModel ? state.extra as VibeModel : null;
              return PlayerScreen(
                vibeId: vibeId,
                vibe: vibe,
              );
            },
          ),
          // Add Friends screen
          GoRoute(
            path: 'add-friends',
            builder: (context, state) => const AddFriendsScreen(),
          ),
          // Subscription / Paywall screen
          GoRoute(
            path: 'subscription',
            builder: (context, state) => const SubscriptionScreen(),
          ),
          // Squad Manager screen
          GoRoute(
            path: 'squad',
            builder: (context, state) => const SquadScreen(),
          ),
        ],
      ),

      // OTHER ROUTES ...
      GoRoute(
        path: '/invite/:userId',
        builder: (context, state) {
          final userId = state.pathParameters['userId'];
          return InviteAcceptanceScreen(inviterId: userId ?? '');
        },
      ),
    ],
    errorBuilder: (context, state) => NotFoundScreen(uri: state.uri),
  );
});
