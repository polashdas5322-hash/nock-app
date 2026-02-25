import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Location & Distance Service
///
/// Competitor Analysis: 73 requests for distance features (especially from LDR couples).
/// This enables the "Distance Badge" on widgets showing how far apart friends are.
///
/// Privacy-First Design:
/// - Location is OPTIONAL (off by default)
/// - Only shares with accepted friends
/// - City-level precision (not exact coordinates)
/// - Can disable at any time
class DistanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _locationEnabledKey = 'location_sharing_enabled';
  static const String _lastLatKey = 'last_latitude';
  static const String _lastLngKey = 'last_longitude';
  static const String _lastCityKey = 'last_city';

  /// Check if user has enabled location sharing
  Future<bool> isLocationSharingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_locationEnabledKey) ?? false;
  }

  /// Enable/disable location sharing
  Future<void> setLocationSharing(bool enabled, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_locationEnabledKey, enabled);

    if (enabled) {
      // Update location immediately
      await updateLocation(userId);
    } else {
      // Clear location from Firestore
      await _firestore.collection('users').doc(userId).update({
        'location': FieldValue.delete(),
        'locationUpdatedAt': FieldValue.delete(),
      });
    }
  }

  /// Check if location permissions are granted
  Future<bool> checkPermissions() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('DistanceService: Error checking permissions: $e');
      return false;
    }
  }

  /// Get current position
  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await checkPermissions();
      if (!hasPermission) return null;

      // Use low accuracy for privacy (city-level)
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, // City-level precision
          distanceFilter: 1000, // Only update if moved 1km+
        ),
      );
    } catch (e) {
      debugPrint('DistanceService: Error getting position: $e');
      return null;
    }
  }

  /// Update user's location in Firestore (with privacy rounding)
  Future<bool> updateLocation(String userId) async {
    try {
      final isEnabled = await isLocationSharingEnabled();
      if (!isEnabled) return false;

      final position = await getCurrentPosition();
      if (position == null) return false;

      // Round to 2 decimal places for privacy (~1km accuracy)
      final roundedLat = (position.latitude * 100).round() / 100;
      final roundedLng = (position.longitude * 100).round() / 100;

      // Save locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_lastLatKey, roundedLat);
      await prefs.setDouble(_lastLngKey, roundedLng);

      // Update Firestore
      await _firestore.collection('users').doc(userId).update({
        'location': GeoPoint(roundedLat, roundedLng),
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint(
        'DistanceService: Location updated ($roundedLat, $roundedLng)',
      );
      return true;
    } catch (e) {
      debugPrint('DistanceService: Error updating location: $e');
      return false;
    }
  }

  /// Calculate distance between two users
  Future<DistanceInfo?> getDistanceBetweenUsers(
    String userId1,
    String userId2,
  ) async {
    try {
      final doc1 = await _firestore.collection('users').doc(userId1).get();
      final doc2 = await _firestore.collection('users').doc(userId2).get();

      final data1 = doc1.data();
      final data2 = doc2.data();

      if (data1 == null || data2 == null) return null;

      final location1 = data1['location'] as GeoPoint?;
      final location2 = data2['location'] as GeoPoint?;

      if (location1 == null || location2 == null) return null;

      final distanceMeters = Geolocator.distanceBetween(
        location1.latitude,
        location1.longitude,
        location2.latitude,
        location2.longitude,
      );

      return DistanceInfo(
        distanceMeters: distanceMeters,
        user1HasLocation: true,
        user2HasLocation: true,
      );
    } catch (e) {
      debugPrint('DistanceService: Error calculating distance: $e');
      return null;
    }
  }

  /// Get distance from current user to a friend
  Future<DistanceInfo?> getDistanceToFriend(
    String currentUserId,
    String friendId,
  ) async {
    return getDistanceBetweenUsers(currentUserId, friendId);
  }

  /// Get formatted distance string for widget display
  Future<String?> getDistanceLabel(
    String currentUserId,
    String friendId,
  ) async {
    final distance = await getDistanceToFriend(currentUserId, friendId);
    if (distance == null) return null;
    return distance.formattedDistance;
  }
}

/// Distance information model
class DistanceInfo {
  final double distanceMeters;
  final bool user1HasLocation;
  final bool user2HasLocation;

  DistanceInfo({
    required this.distanceMeters,
    required this.user1HasLocation,
    required this.user2HasLocation,
  });

  /// Distance in kilometers
  double get distanceKm => distanceMeters / 1000;

  /// Distance in miles
  double get distanceMiles => distanceMeters / 1609.34;

  /// Formatted distance string (auto-selects unit)
  String get formattedDistance {
    if (distanceMeters < 1000) {
      // Less than 1km - show "nearby"
      return '📍 Nearby';
    } else if (distanceKm < 10) {
      // Less than 10km
      return '📍 ${distanceKm.toStringAsFixed(1)}km';
    } else if (distanceKm < 100) {
      // Less than 100km
      return '📍 ${distanceKm.round()}km';
    } else if (distanceMiles < 100) {
      // Use miles for larger distances (US users)
      return '📍 ${distanceMiles.round()}mi';
    } else {
      // Very far - just show rounded miles
      return '📍 ${(distanceMiles / 100).round() * 100}mi';
    }
  }

  /// Short format for widget display
  String get shortFormat {
    if (distanceMeters < 1000) {
      return 'Nearby';
    } else if (distanceKm < 100) {
      return '${distanceKm.round()}km';
    } else {
      return '${distanceMiles.round()}mi';
    }
  }

  /// Check if users are "close" (within 50km)
  bool get isClose => distanceKm < 50;

  /// Check if users are in same city (within 10km)
  bool get isSameCity => distanceKm < 10;

  /// Check if it's a long-distance relationship (>500km)
  bool get isLongDistance => distanceKm > 500;
}

/// Provider for DistanceService
final distanceServiceProvider = Provider<DistanceService>((ref) {
  return DistanceService();
});

/// Provider for location sharing enabled state
final locationSharingEnabledProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(distanceServiceProvider);
  return service.isLocationSharingEnabled();
});

/// State notifier for managing location settings
class LocationSettingsNotifier extends StateNotifier<LocationSettingsState> {
  final DistanceService _service;
  final String _userId;

  LocationSettingsNotifier(this._service, this._userId)
    : super(const LocationSettingsState()) {
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final isEnabled = await _service.isLocationSharingEnabled();
    final hasPermission = await _service.checkPermissions();

    state = state.copyWith(
      isEnabled: isEnabled,
      hasPermission: hasPermission,
      isLoading: false,
    );
  }

  Future<void> toggleLocationSharing() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true);

    // If enabling, check permissions first
    if (!state.isEnabled && !state.hasPermission) {
      final hasPermission = await _service.checkPermissions();
      if (!hasPermission) {
        state = state.copyWith(
          isLoading: false,
          error: 'Location permission denied',
        );
        return;
      }
      state = state.copyWith(hasPermission: true);
    }

    // Toggle the setting
    final newEnabled = !state.isEnabled;
    await _service.setLocationSharing(newEnabled, _userId);

    state = state.copyWith(
      isEnabled: newEnabled,
      isLoading: false,
      error: null,
    );
  }

  Future<void> updateLocation() async {
    if (!state.isEnabled) return;

    state = state.copyWith(isUpdating: true);
    await _service.updateLocation(_userId);
    state = state.copyWith(isUpdating: false);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// State for location settings
class LocationSettingsState {
  final bool isEnabled;
  final bool hasPermission;
  final bool isLoading;
  final bool isUpdating;
  final String? error;

  const LocationSettingsState({
    this.isEnabled = false,
    this.hasPermission = false,
    this.isLoading = true,
    this.isUpdating = false,
    this.error,
  });

  LocationSettingsState copyWith({
    bool? isEnabled,
    bool? hasPermission,
    bool? isLoading,
    bool? isUpdating,
    String? error,
  }) {
    return LocationSettingsState(
      isEnabled: isEnabled ?? this.isEnabled,
      hasPermission: hasPermission ?? this.hasPermission,
      isLoading: isLoading ?? this.isLoading,
      isUpdating: isUpdating ?? this.isUpdating,
      error: error,
    );
  }
}

/// Family provider for location settings
final locationSettingsProvider =
    StateNotifierProvider.family<
      LocationSettingsNotifier,
      LocationSettingsState,
      String
    >((ref, userId) {
      final service = ref.watch(distanceServiceProvider);
      return LocationSettingsNotifier(service, userId);
    });

/// Provider for distance to a specific friend
final distanceToFriendProvider =
    FutureProvider.family<DistanceInfo?, ({String userId, String friendId})>((
      ref,
      params,
    ) async {
      final service = ref.watch(distanceServiceProvider);
      return service.getDistanceToFriend(params.userId, params.friendId);
    });
