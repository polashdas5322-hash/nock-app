import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

/// FCM Token Service
///
/// Manages FCM (Firebase Cloud Messaging) tokens for push notifications.
/// Tokens are saved to Firestore so Cloud Functions can send targeted pushes.
class FCMTokenService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  GoRouter? _router;

  /// Initialize FCM and save token
  /// Pass router for navigation when user taps notification
  Future<void> initialize({GoRouter? router}) async {
    _router = router;

    // Listen for token refresh
    _messaging.onTokenRefresh.listen(_saveTokenToFirestore);

    // Get current token and save
    final token = await getToken();
    if (token != null) {
      await _saveTokenToFirestore(token);
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // FIX #1: Handle notification clicks when app is in background/terminated
    // This enables Deep Link from Notification → Player Screen
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationClick);

    // FIX #1b: Handle cold start from notification (app was terminated)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint(
        'FCMTokenService: App opened from terminated state via notification',
      );
      _handleNotificationClick(initialMessage);
    }
  }

  /// Handle notification click - Navigate to appropriate screen
  void _handleNotificationClick(RemoteMessage message) {
    debugPrint('FCMTokenService: Notification clicked');
    debugPrint('  Data: ${message.data}');

    if (_router == null) {
      debugPrint('FCMTokenService: Router not available, cannot navigate');
      return;
    }

    final messageType = message.data['type'];
    final vibeId = message.data['vibeId'];

    switch (messageType) {
      case 'NEW_VIBE':
      case 'WIDGET_UPDATE':
        // Navigate directly to player screen with fromNotification=true
        if (vibeId != null && vibeId.isNotEmpty) {
          debugPrint('FCMTokenService: Navigating to /player/$vibeId');
          _router!.go('/player/$vibeId?fromNotification=true');
        }
        break;

      default:
        debugPrint('FCMTokenService: Unknown type, going home');
        _router!.go('/home');
    }
  }

  /// Save FCM token to user's Firestore document
  /// 2025 BEST PRACTICE: Check-then-Sync to avoid redundant writes
  Future<void> _saveTokenToFirestore(String? token) async {
    if (token == null || token.isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('FCMTokenService: No user signed in, cannot save token');
      return;
    }

    try {
      // 1. Fetch current document to check if sync is actually needed
      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data();
        final currentToken = data?['fcmToken'] as String?;
        final lastUpdated = data?['fcmTokenUpdatedAt'] as Timestamp?;

        // 2. Only update if token changed OR sync is older than 30 days
        bool needsSync = currentToken != token;

        if (!needsSync && lastUpdated != null) {
          final thirtyDaysAgo = DateTime.now().subtract(
            const Duration(days: 30),
          );
          if (lastUpdated.toDate().isBefore(thirtyDaysAgo)) {
            needsSync = true;
          }
        }

        if (!needsSync) {
          debugPrint(
            'FCMTokenService: Token already synced and fresh, skipping write',
          );
          return;
        }

        await _firestore.collection('users').doc(user.uid).update({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Document doesn't exist, create it
        await _firestore.collection('users').doc(user.uid).set({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      debugPrint(
        'FCMTokenService: Token successfully synced for user ${user.uid}',
      );
    } catch (e) {
      debugPrint('FCMTokenService: Error syncing token: $e');
    }
  }

  /// Get current FCM token
  /// 2025 BEST PRACTICE: Graceful handling of registration limits + Retry Logic
  Future<String?> getToken() async {
    const int maxRetries = 3;
    const Duration initialDelay = Duration(seconds: 1);

    for (int i = 0; i < maxRetries; i++) {
      try {
        return await _messaging.getToken();
      } catch (e) {
        final errorStr = e.toString().toUpperCase();

        if (errorStr.contains('TOO_MANY_REGISTRATIONS')) {
          debugPrint(
            '══════════════════════════════════════════════════════════════',
          );
          debugPrint(
            'CRITICAL: FCM Registration Limit Reached (TOO_MANY_REGISTRATIONS)',
          );
          debugPrint('This usually happens on Emulators with stale data.');
          debugPrint(
            'FIX: Wipe Data on your Android Emulator (AVD Manager -> Wipe Data)',
          );
          debugPrint(
            '══════════════════════════════════════════════════════════════',
          );
          return null; // Don't retry this specific error
        }

        debugPrint(
          'FCMTokenService: getToken error (Attempt ${i + 1}/$maxRetries): $e',
        );

        if (i < maxRetries - 1) {
          // Exponential backoff: 1s, 2s, 4s...
          final delay = initialDelay * (1 << i);
          debugPrint(
            'FCMTokenService: Retrying in ${delay.inSeconds} seconds...',
          );
          await Future.delayed(delay);
        }
      }
    }

    debugPrint(
      'FCMTokenService: Failed to get token after $maxRetries attempts.',
    );
    return null;
  }

  /// Handle foreground messages (app is open)
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCMTokenService: Foreground message received');
    debugPrint('  Data: ${message.data}');

    final messageType = message.data['type'];

    switch (messageType) {
      case 'WIDGET_UPDATE':
        // Update widget even when app is open
        debugPrint('FCMTokenService: Widget update received in foreground');
        // Widget is already synced via Firestore listener when app is open
        break;

      default:
        debugPrint('FCMTokenService: Unknown message type: $messageType');
    }
  }

  /// Delete token on logout
  Future<void> deleteToken() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _firestore.collection('users').doc(user.uid).update({
          'fcmToken': FieldValue.delete(),
        });
      } catch (e) {
        debugPrint('FCMTokenService: Error deleting token: $e');
      }
    }

    // Also delete from FCM
    await _messaging.deleteToken();
  }

  /// Check notification permission status
  Future<AuthorizationStatus> getPermissionStatus() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus;
  }

  /// Request notification permissions
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      criticalAlert: false,
      announcement: false,
      carPlay: false,
    );

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }
}

/// FCM Token Service Provider
final fcmTokenServiceProvider = Provider<FCMTokenService>((ref) {
  return FCMTokenService();
});
