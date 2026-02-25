import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deep Link Context Provider
///
/// Preserves deep link data (like invite codes) across the auth flow.
/// When a user clicks an invite link but isn't logged in, the inviterId
/// is stored here and retrieved after authentication completes.

const String _pendingInviteKey = 'pending_invite_id';

/// Provider to track pending invite from deep link
final pendingInviteProvider =
    StateNotifierProvider<PendingInviteNotifier, String?>((ref) {
      return PendingInviteNotifier();
    });

const String _pendingRedirectKey = 'pending_redirect_location';

/// Provider to track ANY pending redirect (invites, player, record, etc.)
final pendingRedirectProvider =
    StateNotifierProvider<PendingRedirectNotifier, String?>((ref) {
      return PendingRedirectNotifier();
    });

/// Optimized for Router: Returns null if invite is dismissed for this session
final activeInviteProvider = Provider<String?>((ref) {
  return ref.watch(pendingInviteProvider.notifier).pendingInviteId;
});

class PendingInviteNotifier extends StateNotifier<String?> {
  String? _dismissedId;

  PendingInviteNotifier() : super(null) {
    _loadPendingInvite();
  }

  /// Load any pending invite from persistent storage
  Future<void> _loadPendingInvite() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final inviterId = prefs.getString(_pendingInviteKey);
      if (inviterId != null && inviterId.isNotEmpty) {
        state = inviterId;
      }
    } catch (e) {
      // Ignore errors loading pending invite
    }
  }

  /// Store an invite ID to be processed after authentication
  Future<void> setPendingInvite(String inviterId) async {
    // If it's a new ID, reset dismissal
    if (inviterId != _dismissedId) {
      _dismissedId = null;
    }
    state = inviterId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingInviteKey, inviterId);
    } catch (e) {
      // Store failed, but we have it in memory
    }
  }

  /// Dismiss the current invite from showing automatically in this session.
  /// This prevents the "Magnetic Redirect" in the router while preserving
  /// the invite ID in storage for later retrieval (if needed).
  void dismiss() {
    _dismissedId = state;
    // We trigger a state update to force router re-evaluation
    final current = state;
    state = null; // Set to null so router stops redirecting
    state = current; // Set back so listeners still see it if they need to
  }

  /// Clear the pending invite after it's been processed
  Future<void> clearPendingInvite() async {
    state = null;
    _dismissedId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingInviteKey);
    } catch (e) {
      // Ignore
    }
  }

  /// Get the pending invite ID (if any and not dismissed)

  String? get pendingInviteId {
    if (state == _dismissedId) return null;
    return state;
  }
}

class PendingRedirectNotifier extends StateNotifier<String?> {
  PendingRedirectNotifier() : super(null) {
    _loadPendingRedirect();
  }

  Future<void> _loadPendingRedirect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_pendingRedirectKey);
      if (path != null && path.isNotEmpty) {
        state = path;
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> setPendingRedirect(String path) async {
    state = path;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingRedirectKey, path);
    } catch (e) {
      // Ignore
    }
  }

  Future<void> clearPendingRedirect() async {
    state = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingRedirectKey);
    } catch (e) {
      // Ignore
    }
  }
}
