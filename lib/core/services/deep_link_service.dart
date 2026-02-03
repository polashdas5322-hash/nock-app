import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

/// Deep Link Service
/// 
/// Handles incoming deep links from:
/// - nock://invite/userid (custom scheme)
/// - nock://player/vibeId (player deep link)
/// - https://nock.app/invite/userid (universal links)
/// 
/// Uses app_links package for reliable deep link handling on both platforms.
class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  GoRouter? _router;
  
  /// Initialize the deep link listener
  Future<void> initialize(GoRouter router) async {
    _router = router;
    
    // Handle initial link (if app was launched via deep link)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('🔗 DeepLink: Initial link received: $initialUri');
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('🔗 DeepLink: Error getting initial link: $e');
    }
    
    // Listen for subsequent links (when app is already running)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('🔗 DeepLink: Stream link received: $uri');
        _handleDeepLink(uri);
      },
      onError: (error) {
        debugPrint('🔗 DeepLink: Stream error: $error');
      },
    );

    // CRITICAL: Handle Deferred Deep Linking (Clipboard Bridge)
    // If a user clicks our HTTPS link but doesn't have the app installed,
    // they are sent to the store. We can't easily track that without Branch/FDL.
    // WORKAROUND: We copy the link to their clipboard, and read it here on first launch.
    _checkClipboardForDeferredInvite();
  }

  /// Check clipboard for a Nock invite link (Deferred Deep Link Bridge)
  Future<void> _checkClipboardForDeferredInvite() async {
    try {
      // Small delay to ensure engine is ready
      await Future.delayed(const Duration(seconds: 1));
      
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      
      if (text != null && text.contains('getnock.app/i/')) {
        debugPrint('🔗 DeepLink: Deferred link found in clipboard: $text');
        final uri = Uri.parse(text);
        
        // Safety: Only process if it matches our pattern
        if (uri.pathSegments.isNotEmpty && (uri.host == 'getnock.app' || uri.host == 'nock.app')) {
          _handleDeepLink(uri);
          
          // Optional: Clear clipboard to avoid double-processing
          // await Clipboard.setData(const ClipboardData(text: ''));
        }
      }
    } catch (e) {
      debugPrint('🔗 DeepLink: Error checking clipboard: $e');
    }
  }
  
  /// Process an incoming deep link
  void _handleDeepLink(Uri uri) {
    debugPrint('🔗 DeepLink: Processing: scheme=${uri.scheme}, host=${uri.host}, path=${uri.path}');
    
    // Handle nock://player/vibeId or nock:///player/vibeId
    // FIX #2: Add player deep link handler BEFORE invite logic
    if (uri.scheme == 'nock') {
      // Check for player path first
      if (uri.host == 'player' && uri.pathSegments.isNotEmpty) {
        final vibeId = uri.pathSegments.first;
        debugPrint('🔗 DeepLink: Player detected (host=player): vibeId=$vibeId');
        _navigateToPlayer(vibeId);
        return;
      } else if (uri.path.startsWith('/player/')) {
        final segments = uri.pathSegments;
        if (segments.length >= 2 && segments[0] == 'player') {
          final vibeId = segments[1];
          debugPrint('🔗 DeepLink: Player detected (path): vibeId=$vibeId');
          _navigateToPlayer(vibeId);
          return;
        }
      } else if (uri.path.startsWith('/record/')) {
        final segments = uri.pathSegments;
        if (segments.length >= 2 && segments[0] == 'record') {
          final friendId = segments[1];
          debugPrint('🔗 DeepLink: Record detected (path): friendId=$friendId');
          _navigateToRecord(friendId);
          return;
        }
      }
            // Then handle invite paths
        if (uri.host == 'record' && uri.queryParameters.containsKey('to')) {
          final friendId = uri.queryParameters['to']!;
          debugPrint('🔗 DeepLink: Record detected (host=record): friendId=$friendId');
          _navigateToRecord(friendId);
          return;
        } else if (uri.host == 'invite' && uri.pathSegments.isNotEmpty) {
        // nock://invite/userid -> path is /userid, host is invite
        final userId = uri.pathSegments.first;
        debugPrint('🔗 DeepLink: Invite detected (host=invite): userId=$userId');
        _navigateToInvite(userId);
      } else if (uri.path.startsWith('/invite/')) {
        // nock:///invite/userid -> path is /invite/userid  
        final segments = uri.pathSegments;
        if (segments.length >= 2 && segments[0] == 'invite') {
          final userId = segments[1];
          debugPrint('🔗 DeepLink: Invite detected (path): userId=$userId');
          _navigateToInvite(userId);
        }
      } else if (uri.pathSegments.isNotEmpty) {
        // nock://userid (direct user ID) - catch-all for invites
        final userId = uri.pathSegments.first;
        debugPrint('🔗 DeepLink: Possible direct userId: $userId');
        _navigateToInvite(userId);
      }
    }
    // Handle https://nock.app/invite/userid or https://nock.app/player/vibeId
    else if (uri.scheme == 'https' && 
             (uri.host == 'nock.app' || uri.host == 'getnock.app')) {
      if (uri.pathSegments.length >= 2 && (uri.pathSegments[0] == 'invite' || uri.pathSegments[0] == 'i')) {
        final userId = uri.pathSegments[1];
        debugPrint('🔗 DeepLink: HTTPS invite (path=${uri.pathSegments[0]}): userId=$userId');
        _navigateToInvite(userId);
      } else if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'player') {
        final vibeId = uri.pathSegments[1];
        debugPrint('🔗 DeepLink: HTTPS player: vibeId=$vibeId');
        _navigateToPlayer(vibeId);
      } else if (uri.pathSegments.length >= 2 && (uri.pathSegments[0] == 'record' || uri.pathSegments[0] == 'r')) {
        final friendId = uri.pathSegments[1];
        debugPrint('🔗 DeepLink: HTTPS record: friendId=$friendId');
        _navigateToRecord(friendId);
      }
    }
  }
  
  /// Navigate to the player screen
  void _navigateToPlayer(String vibeId) {
    if (_router != null && vibeId.isNotEmpty) {
      debugPrint('🔗 DeepLink: Navigating to /home/player/$vibeId');
      _router!.go('/home/player/$vibeId?fromNotification=true');
    }
  }
  
  /// Navigate to the invite acceptance screen
  void _navigateToInvite(String userId) {
    if (_router != null && userId.isNotEmpty) {
      debugPrint('🔗 DeepLink: Navigating to /home/invite/$userId');
      _router!.go('/home/invite/$userId');
    }
  }

  /// Navigate to the recording screen (Walkie-Talkie mode)
  void _navigateToRecord(String friendId) {
    if (_router != null && friendId.isNotEmpty) {
      debugPrint('🔗 DeepLink: Navigating to /home/record/$friendId');
      _router!.go('/home/record/$friendId');
    }
  }
  
  /// Dispose of the listener
  void dispose() {
    _linkSubscription?.cancel();
  }
}

/// Provider for the deep link service
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService();
});
