import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_constants.dart';

/// User model for Vibe app
/// Contains user profile, squad membership, and widget state
class UserModel {
  final String id;
  final String phoneNumber;
  final String? email;  // For Google/Apple auth
  final String displayName;
  final String searchName;  // Lowercase displayName for case-insensitive search
  final String? username;  // Unique handle for invite links (e.g., @john_doe)
  final String? avatarUrl;
  final List<String> squadIds;
  final List<String> friendIds;
  final String? fcmToken;
  final DateTime createdAt;
  final DateTime lastActive;
  final bool isPremium;
  final WidgetState? widgetState;
  final UserStatus status;
  final String authProvider;  // 'phone', 'google', 'apple', 'guest'
  final bool isGuest;  // True if using guest mode (limited features)
  final List<String> blockedUserIds; // Safety: Blocked users will be filtered from feed

  UserModel({
    required this.id,
    required this.phoneNumber,
    this.email,
    required this.displayName,
    String? searchName,
    this.username,
    this.avatarUrl,
    this.squadIds = const [],
    this.friendIds = const [],
    this.fcmToken,
    required this.createdAt,
    required this.lastActive,
    this.isPremium = false,
    this.widgetState,
    this.status = UserStatus.offline,
    this.authProvider = 'phone',
    this.isGuest = false,
    this.blockedUserIds = const [],
  }) : searchName = searchName ?? displayName.toLowerCase();

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      phoneNumber: data['phoneNumber'] ?? '',
      email: data['email'],
      displayName: data['displayName'] ?? '',
      searchName: data['searchName'] ?? (data['displayName'] ?? '').toString().toLowerCase(),
      username: data['username'],  // Unique invite handle
      avatarUrl: data['avatarUrl'],
      squadIds: List<String>.from(data['squadIds'] ?? []),
      friendIds: List<String>.from(data['friendIds'] ?? []),
      fcmToken: data['fcmToken'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastActive: (data['lastActive'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isPremium: data['isPremium'] ?? false,
      widgetState: data['widgetState'] != null
          ? WidgetState.fromMap(data['widgetState'])
          : null,
      status: UserStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => UserStatus.offline,
      ),
      authProvider: data['authProvider'] ?? 'phone',
      isGuest: data['isGuest'] ?? false,
      blockedUserIds: List<String>.from(data['blockedUserIds'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'phoneNumber': phoneNumber,
      'email': email,
      'displayName': displayName,
      'searchName': searchName,
      'username': username,
      'avatarUrl': avatarUrl,
      'squadIds': squadIds,
      'friendIds': friendIds,
      'fcmToken': fcmToken,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastActive': Timestamp.fromDate(lastActive),
      'isPremium': isPremium,
      'widgetState': widgetState?.toMap(),
      'status': status.name,
      'authProvider': authProvider,
      'isGuest': isGuest,
      'blockedUserIds': blockedUserIds,
    };
  }

  /// Check if user has premium access (either paid or within trial period)
  bool get hasPremiumAccess {
    if (isPremium) return true;
    
    // Reverse Trial: Grant premium to new users for trial period
    // uses createdAt timestamp from user registration
    final trialExpiry = createdAt.add(Duration(days: AppConstants.reverseTrialDays));
    return DateTime.now().isBefore(trialExpiry);
  }

  UserModel copyWith({
    String? id,
    String? phoneNumber,
    String? email,
    String? displayName,
    String? searchName,
    String? username,
    String? avatarUrl,
    List<String>? squadIds,
    List<String>? friendIds,
    String? fcmToken,
    DateTime? createdAt,
    DateTime? lastActive,
    bool? isPremium,
    WidgetState? widgetState,
    UserStatus? status,
    String? authProvider,
    bool? isGuest,
    List<String>? blockedUserIds,
  }) {
    return UserModel(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      searchName: searchName ?? this.searchName,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      squadIds: squadIds ?? this.squadIds,
      friendIds: friendIds ?? this.friendIds,
      fcmToken: fcmToken ?? this.fcmToken,
      createdAt: createdAt ?? this.createdAt,
      lastActive: lastActive ?? this.lastActive,
      isPremium: isPremium ?? this.isPremium,
      widgetState: widgetState ?? this.widgetState,
      status: status ?? this.status,
      authProvider: authProvider ?? this.authProvider,
      isGuest: isGuest ?? this.isGuest,
      blockedUserIds: blockedUserIds ?? this.blockedUserIds,
    );
  }
}

/// User status states
enum UserStatus {
  online,
  offline,
  recording,
  listening,
}

/// Widget state for the home screen widget
/// Denormalized data for efficient widget reads
class WidgetState {
  final String? latestVibeId;
  final String? latestAudioUrl;
  final String? latestImageUrl;
  final String? senderName;
  final String? senderAvatar;
  final int? audioDuration;
  final List<double>? waveformData;
  final DateTime? timestamp;
  final bool isPlayed;
  
  /// 📝 Transcription-First: First 50 chars of voice message
  /// Enables "glanceability" - users can read in meetings/class
  final String? transcriptionPreview;
  
  /// 🎬 4-State Widget Protocol: Content type flags
  /// Enables widgets to show different UI for video/audio-only/photo+audio
  final bool isVideo;       // True = Video vibe (show play overlay)
  final bool isAudioOnly;   // True = Voice note only (show mic icon)
  final String? videoUrl;   // For video deep linking

  WidgetState({
    this.latestVibeId,
    this.latestAudioUrl,
    this.latestImageUrl,
    this.senderName,
    this.senderAvatar,
    this.audioDuration,
    this.waveformData,
    this.timestamp,
    this.isPlayed = false,
    this.transcriptionPreview,
    this.isVideo = false,
    this.isAudioOnly = false,
    this.videoUrl,
  });

  factory WidgetState.fromMap(Map<String, dynamic> map) {
    return WidgetState(
      latestVibeId: map['latestVibeId'],
      latestAudioUrl: map['latestAudioUrl'],
      latestImageUrl: map['latestImageUrl'],
      senderName: map['senderName'],
      senderAvatar: map['senderAvatar'],
      audioDuration: map['audioDuration'],
      waveformData: map['waveformData'] != null
          ? List<double>.from(map['waveformData'])
          : null,
      timestamp: map['timestamp'] != null
          ? (map['timestamp'] as Timestamp).toDate()
          : null,
      isPlayed: map['isPlayed'] ?? false,
      transcriptionPreview: map['transcriptionPreview'],
      // 🎬 4-State Widget Protocol
      isVideo: map['isVideo'] ?? false,
      isAudioOnly: map['isAudioOnly'] ?? false,
      videoUrl: map['videoUrl'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latestVibeId': latestVibeId,
      'latestAudioUrl': latestAudioUrl,
      'latestImageUrl': latestImageUrl,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'audioDuration': audioDuration,
      'waveformData': waveformData,
      'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : null,
      'isPlayed': isPlayed,
      'transcriptionPreview': transcriptionPreview,
      // 🎬 4-State Widget Protocol
      'isVideo': isVideo,
      'isAudioOnly': isAudioOnly,
      'videoUrl': videoUrl,
    };
  }

  WidgetState copyWith({
    String? latestVibeId,
    String? latestAudioUrl,
    String? latestImageUrl,
    String? senderName,
    String? senderAvatar,
    int? audioDuration,
    List<double>? waveformData,
    DateTime? timestamp,
    bool? isPlayed,
    String? transcriptionPreview,
    bool? isVideo,
    bool? isAudioOnly,
    String? videoUrl,
  }) {
    return WidgetState(
      latestVibeId: latestVibeId ?? this.latestVibeId,
      latestAudioUrl: latestAudioUrl ?? this.latestAudioUrl,
      latestImageUrl: latestImageUrl ?? this.latestImageUrl,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      audioDuration: audioDuration ?? this.audioDuration,
      waveformData: waveformData ?? this.waveformData,
      timestamp: timestamp ?? this.timestamp,
      isPlayed: isPlayed ?? this.isPlayed,
      transcriptionPreview: transcriptionPreview ?? this.transcriptionPreview,
      isVideo: isVideo ?? this.isVideo,
      isAudioOnly: isAudioOnly ?? this.isAudioOnly,
      videoUrl: videoUrl ?? this.videoUrl,
    );
  }
}
