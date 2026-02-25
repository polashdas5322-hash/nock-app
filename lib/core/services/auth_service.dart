import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; // 🍎 For Apple token revocation
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:io';
import '../models/user_model.dart';
import '../constants/app_constants.dart';
import 'cloudinary_service.dart';
import 'cache_cleanup_service.dart';

/// Auth Service Provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref);
});

/// Current User Stream Provider
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Current User Model Provider
final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .snapshots()
          .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

/// Authentication Service
///
/// Supports authentication methods:
/// 1. Google Sign-In (fastest, most common)
/// 2. Apple Sign-In (required for iOS, privacy-focused)
class AuthService {
  final Ref? _ref; // Horizontal access for forensic cleanup
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  AuthService([this._ref]);

  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUser?.uid;

  // ==================== GOOGLE SIGN-IN ====================

  /// Sign in with Google
  /// Returns UserCredential on success, throws on failure
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Trigger the Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the credential
      final userCredential = await _auth.signInWithCredential(credential);

      // Save user ID for cold start sync
      await _saveUserId(userCredential.user?.uid);

      // Create/update user document
      if (userCredential.user != null) {
        await createOrUpdateUserDocument(
          userId: userCredential.user!.uid,
          email: googleUser.email,
          displayName: googleUser.displayName ?? 'Nock User',
          avatarUrl: googleUser.photoUrl,
          authProvider: 'google',
        );
      }

      return userCredential;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    }
  }

  // ==================== APPLE SIGN-IN ====================

  /// Sign in with Apple
  /// Returns UserCredential on success, throws on failure
  Future<UserCredential?> signInWithApple() async {
    try {
      // Generate nonce for security
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      // Request credential for Apple Sign-In
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      // Create an OAuthCredential from the Apple credential
      final oauthCredential = OAuthProvider(
        'apple.com',
      ).credential(idToken: appleCredential.identityToken, rawNonce: rawNonce);

      // Sign in to Firebase with the credential
      final userCredential = await _auth.signInWithCredential(oauthCredential);

      // Save user ID for cold start sync
      await _saveUserId(userCredential.user?.uid);

      // Create/update user document
      // Note: Apple may only provide name on first sign-in
      if (userCredential.user != null) {
        String displayName = 'Nock User';
        if (appleCredential.givenName != null) {
          displayName =
              '${appleCredential.givenName} ${appleCredential.familyName ?? ''}'
                  .trim();
        } else if (userCredential.user!.displayName != null) {
          displayName = userCredential.user!.displayName!;
        }

        await createOrUpdateUserDocument(
          userId: userCredential.user!.uid,
          email: appleCredential.email ?? userCredential.user!.email,
          displayName: displayName,
          avatarUrl: userCredential.user!.photoURL,
          authProvider: 'apple',
        );
      }

      return userCredential;
    } catch (e) {
      debugPrint('Apple Sign-In Error: $e');
      rethrow;
    }
  }

  /// Generate a random nonce for Apple Sign-In security
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// SHA256 hash of a string
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ==================== USER DOCUMENT MANAGEMENT ====================

  /// Create or update user document (works for all auth providers)
  Future<void> createOrUpdateUserDocument({
    required String userId,
    String? phoneNumber,
    String? email,
    required String displayName,
    String? avatarUrl,
    String authProvider = 'google',
    bool isGuest = false,
    bool isProfileUpdate =
        false, // FIX: Track if this is an explicit profile update
  }) async {
    final userDoc = _firestore
        .collection(AppConstants.usersCollection)
        .doc(userId);
    final docSnapshot = await userDoc.get();

    if (!docSnapshot.exists) {
      // Create new user (ALWAYS use provided name on first sign-in)
      final user = UserModel(
        id: userId,
        phoneNumber: phoneNumber ?? '',
        email: email,
        displayName: displayName,
        avatarUrl: avatarUrl,
        createdAt: DateTime.now(),
        lastActive: DateTime.now(),
        authProvider: authProvider,
        isGuest: isGuest,
      );
      await userDoc.set(user.toFirestore());
    } else {
      // Update existing user - PROTECT custom profile data
      final updateData = <String, dynamic>{'lastActive': Timestamp.now()};

      final existingData = docSnapshot.data();

      // Only update fields if they have values
      if (email != null) updateData['email'] = email;

      // Protect avatar: Only update if current is null/empty or this is a profile update
      final existingAvatar = existingData?['avatarUrl'] as String?;
      if (avatarUrl != null) {
        if (existingAvatar == null ||
            existingAvatar.isEmpty ||
            isProfileUpdate) {
          updateData['avatarUrl'] = avatarUrl;
        }
      }

      if (!isGuest) updateData['isGuest'] = false;

      // CRITICAL FIX: Update displayName if it's an explicit profile update
      // OR if the current name is a default/empty value.
      // This solves the "Name Amnesia" bug where Apple/Google Sign-In would
      // otherwise ignore the name on subsequent logins.
      final existingName = existingData?['displayName'] as String?;
      final isDefaultName =
          existingName == null ||
          existingName.isEmpty ||
          existingName == 'Nock User';

      if (isProfileUpdate || isDefaultName) {
        updateData['displayName'] = displayName;
        updateData['searchName'] = displayName.toLowerCase();
      }

      if (updateData.length > 1) {
        // More than just lastActive
        await userDoc.update(updateData);
      }
    }
  }

  // ==================== UTILITIES ====================

  /// Save user ID to SharedPreferences for cold start sync
  Future<void> _saveUserId(String? userId) async {
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_user_id', userId);
  }

  /// Update FCM token
  Future<void> updateFcmToken(String token) async {
    if (currentUserId == null) return;
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(currentUserId)
        .update({'fcmToken': token});
  }

  /// Update user status
  Future<void> updateUserStatus(UserStatus status) async {
    if (currentUserId == null) return;

    try {
      // Use set with merge to handle case where document doesn't exist
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(currentUserId)
          .set({
            'status': status.name,
            'lastActive': Timestamp.now(),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to update user status: $e');
    }
  }

  /// Sign out
  /// CRITICAL: Delete FCM token FIRST to prevent notifications going to wrong user
  Future<void> signOut() async {
    try {
      await updateUserStatus(UserStatus.offline);
    } catch (e) {
      // Ignore if user document doesn't exist (guest)
    }

    // 🚿 PRIVACY HARDENING: Clear local Firestore cache (Ghost Data)
    // Ensures "Instant-On" data from previous user isn't visible.
    // We must terminate() the instance before clearPersistence() can succeed.
    try {
      await FirebaseFirestore.instance.terminate();
      await FirebaseFirestore.instance.clearPersistence();
      debugPrint('AuthService: Local persistence scrubbed successfully');
    } catch (e) {
      debugPrint('AuthService: Failed to scrub persistence: $e');
    }

    // Delete FCM token
    await _deleteFcmToken();

    // Sign out from Google if signed in
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      // Ignore Google sign out errors
    }

    // Clear saved user ID
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user_id');

    await _auth.signOut();
  }

  /// Delete account permanently
  /// Guideline 5.1.1(v) Requirement - "Forensic Scrubbing"
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userId = user.uid;

    try {
      debugPrint('AuthService: Starting forensic scrub for $userId...');

      // 🍎 APPLE TOKEN REVOCATION (App Store Guideline 5.1.1(v))
      // CRITICAL: We MUST revoke the Apple OAuth token before deleting the account.
      // Failure to do this will result in App Store rejection.
      //
      // Note: This is a best-effort call. If it fails, we continue with deletion
      // since the user has explicitly requested account deletion.
      await _revokeAppleTokenIfNeeded();

      // 1. Scrub Vibes (Sent & Received) - Recursive batching for Android 14/Large Data safety
      await _deleteQueryBatch(
        _firestore
            .collection(AppConstants.vibesCollection)
            .where('senderId', isEqualTo: userId),
      );
      await _deleteQueryBatch(
        _firestore
            .collection(AppConstants.vibesCollection)
            .where('receiverId', isEqualTo: userId),
      );
      debugPrint('AuthService: Vibes scrubbed');

      // 2. Scrub Friendships (Both directions) - Recursive batching
      await _deleteQueryBatch(
        _firestore
            .collection(AppConstants.friendshipsCollection)
            .where('userId', isEqualTo: userId),
      );
      await _deleteQueryBatch(
        _firestore
            .collection(AppConstants.friendshipsCollection)
            .where('friendId', isEqualTo: userId),
      );
      debugPrint('AuthService: Friendships scrubbed');

      // 3. Scrub Private Sub-collections (Widget Data)
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('private')
          .doc('widget_data')
          .delete();

      // 4. Scrub Device Cache (Immediate Wipe)
      if (_ref != null) {
        try {
          await _ref.read(cacheCleanupServiceProvider).forceWipe();
          debugPrint('AuthService: Local device cache wiped');
        } catch (e) {
          debugPrint('AuthService: Cache wipe failed during deletion: $e');
        }
      }

      // 5. Delete User Document
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .delete();

      // 6. Clear saved user ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_user_id');

      // 🚿 PRIVACY HARDENING: Final Forensic Scrub of local database
      // Must terminate() before clearPersistence()
      try {
        await FirebaseFirestore.instance.terminate();
        await FirebaseFirestore.instance.clearPersistence();
        debugPrint(
          'AuthService: Local persistence scrubbed after account deletion',
        );
      } catch (e) {
        debugPrint('AuthService: Post-deletion scrub failed: $e');
      }

      // 7. Delete the Firebase Auth user
      // Note: This requires a recent login. UI handles re-auth prompt via catch block.
      await user.delete();

      debugPrint('AuthService: Forensic scrub COMPLETE for $userId');
    } catch (e) {
      debugPrint('AuthService: Error deleting account: $e');
      rethrow;
    }
  }

  /// Helper to delete documents in batches of 450 (safely under 500 limit)
  /// Uses recursion to handle large datasets (e.g., >1000 vibes).
  Future<void> _deleteQueryBatch(Query query) async {
    // Limit each fetch to stay safely under 500 batches
    final limitedQuery = query.limit(450);

    final snapshots = await limitedQuery.get();
    if (snapshots.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshots.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
    debugPrint('AuthService: Committed batch of ${snapshots.size} deletes');

    // Recursively call for the next batch if we hit the limit
    if (snapshots.size >= 450) {
      await _deleteQueryBatch(query);
    }
  }

  /// Update user profile photo
  /// This propagates the change to:
  /// 1. User document
  /// 2. All vibes sent by the user (denormalized senderAvatar)
  /// 3. Friends' widget_data if the current vibe is from this user
  Future<void> updateAvatar(File imageFile) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      debugPrint('AuthService: Updating avatar for $uid...');

      // 1. Upload to Cloudinary
      final avatarUrl = await cloudinaryService.uploadImage(imageFile);
      if (avatarUrl == null) {
        throw Exception('Failed to upload image to Cloudinary');
      }

      // 2. Update User Document
      await _firestore.collection(AppConstants.usersCollection).doc(uid).update(
        {'avatarUrl': avatarUrl},
      );
      debugPrint('AuthService: User document updated with new avatar');

      // 3. Propagate to Vibes (Batched)
      // Firestore batches are limited to 500 ops. We use multiple batches if needed.
      final vibesQuery = await _firestore
          .collection(AppConstants.vibesCollection)
          .where('senderId', isEqualTo: uid)
          .get();

      if (vibesQuery.docs.isNotEmpty) {
        WriteBatch batch = _firestore.batch();
        int count = 0;
        for (var doc in vibesQuery.docs) {
          batch.update(doc.reference, {'senderAvatar': avatarUrl});
          count++;
          if (count >= 500) {
            await batch.commit();
            batch = _firestore.batch();
            count = 0;
          }
        }
        if (count > 0) await batch.commit();
        debugPrint(
          'AuthService: Propagated avatar to ${vibesQuery.size} vibes',
        );
      }

      // 4. Update Friends' Widget Data
      // We check friends who have current user's vibe as their latest
      final currentUserDoc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .get();
      final List<String> friendIds = List<String>.from(
        currentUserDoc.data()?['friendIds'] ?? [],
      );

      for (final friendId in friendIds) {
        final widgetDataRef = _firestore
            .collection(AppConstants.usersCollection)
            .doc(friendId)
            .collection('private')
            .doc('widget_data');

        final widgetDoc = await widgetDataRef.get();
        if (widgetDoc.exists) {
          final data = widgetDoc.data();
          final stateMap = data?['widgetState'] as Map<String, dynamic>?;
          if (stateMap != null) {
            final latestVibeId = stateMap['latestVibeId'];
            // If the latest vibe for this friend is from the current user
            // we should find if that vibeId is in our vibes list
            final isOwnVibe = vibesQuery.docs.any((d) => d.id == latestVibeId);

            if (isOwnVibe) {
              await widgetDataRef.update({
                'widgetState.senderAvatar': avatarUrl,
                // If it's audio-only, the imageUrl also needs update
                if (stateMap['isAudioOnly'] == true)
                  'widgetState.latestImageUrl': avatarUrl,
              });
              debugPrint(
                'AuthService: Updated widget_data for friend $friendId',
              );
            }
          }
        }
      }

      // 5. Update local cache if possible
      // (BFF widgets and main widget will eventually refresh via Push or next app open)

      debugPrint('AuthService: Avatar update COMPLETE for $uid');
    } catch (e) {
      debugPrint('AuthService: Error updating avatar: $e');
      rethrow;
    }
  }

  /// Remove friend (silent unfriend - no notification)
  /// Provides "soft exit" from friendship without blocking
  Future<void> removeFriend(String friendId) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      debugPrint('AuthService: Removing friend $friendId');

      // Remove from both users' friendIds arrays
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .update({
            'friendIds': FieldValue.arrayRemove([friendId]),
          });

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(friendId)
          .update({
            'friendIds': FieldValue.arrayRemove([userId]),
          });

      // Mark friendship as removed
      final friendshipQuery = await _firestore
          .collection(AppConstants.friendshipsCollection)
          .where('userId', isEqualTo: userId)
          .where('friendId', isEqualTo: friendId)
          .limit(1)
          .get();

      if (friendshipQuery.docs.isNotEmpty) {
        await friendshipQuery.docs.first.reference.update({
          'status': 'removed',
          'removedAt': FieldValue.serverTimestamp(),
          'removedBy': userId,
        });
      }

      // Check reverse friendship
      final reverseFriendshipQuery = await _firestore
          .collection(AppConstants.friendshipsCollection)
          .where('userId', isEqualTo: friendId)
          .where('friendId', isEqualTo: userId)
          .limit(1)
          .get();

      if (reverseFriendshipQuery.docs.isNotEmpty) {
        await reverseFriendshipQuery.docs.first.reference.update({
          'status': 'removed',
          'removedAt': FieldValue.serverTimestamp(),
          'removedBy': userId,
        });
      }

      debugPrint('AuthService: Friend removed successfully');
    } catch (e) {
      debugPrint('AuthService: Error removing friend: $e');
      rethrow;
    }
  }

  /// Delete FCM token on logout
  Future<void> _deleteFcmToken() async {
    if (currentUserId == null) return;

    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(currentUserId)
          .update({'fcmToken': FieldValue.delete()});

      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      // Don't block signout on token deletion failure
    }
  }

  /// 🍎 Revoke Apple OAuth token if the user signed in with Apple
  ///
  /// CRITICAL: App Store Guideline 5.1.1(v) requires revoking Apple tokens
  /// when a user deletes their account.
  ///
  /// This method:
  /// 1. Checks if user signed in with Apple (via providerData)
  /// 2. Attempts to get a fresh authorizationCode for revocation
  /// 3. Calls the revokeAppleToken Cloud Function
  Future<void> _revokeAppleTokenIfNeeded() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Check if user signed in with Apple
    final isAppleUser = user.providerData.any(
      (info) => info.providerId == 'apple.com',
    );

    if (!isAppleUser) {
      debugPrint('AuthService: User is not an Apple user, skipping revocation');
      return;
    }

    debugPrint('AuthService: Revoking Apple OAuth token...');

    try {
      // Option 1: Try to get a fresh authorization code
      // Apple Sign-In will silently return a new authorizationCode if the user
      // is still signed in (no UI prompt if already authorized)
      String? authorizationCode;

      try {
        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: [], // No scopes needed for revocation
        );
        authorizationCode = credential.authorizationCode;
      } catch (e) {
        debugPrint('AuthService: Could not get fresh Apple auth code: $e');
        // Continue - we'll try with any stored refresh token
      }

      // Call the Cloud Function to revoke the token
      final callable = FirebaseFunctions.instance.httpsCallable(
        'revokeAppleToken',
      );
      final result = await callable.call({
        'authorizationCode': authorizationCode,
        // Note: In a more complete implementation, you would store and pass
        // the refresh_token obtained during initial sign-in
      });

      final success = result.data['success'] as bool? ?? false;
      if (success) {
        debugPrint('AuthService: Apple token revoked successfully');
      } else {
        final error = result.data['error'] as String? ?? 'Unknown error';
        debugPrint('AuthService: Apple revocation returned: $error');
        // Don't throw - allow deletion to proceed
      }
    } catch (e) {
      debugPrint('AuthService: Apple token revocation error: $e');
      // Don't throw - allow account deletion to proceed even if revocation fails
      // The user has explicitly requested deletion
    }
  }
}
