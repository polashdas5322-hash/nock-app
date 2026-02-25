import 'package:cloud_firestore/cloud_firestore.dart';

/// Vibe model - represents a voice+photo message
/// The core unit of communication in the app
class VibeModel {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String receiverId;
  final String audioUrl;
  final String? imageUrl;
  final String? videoUrl; // For video vibes
  final bool isVideo; // True if this is a video vibe
  final bool
  isAudioOnly; // True if audio-only (uses blurred profile as background)
  final int audioDuration; // in seconds
  final List<double> waveformData;
  final DateTime createdAt;
  final bool isFromGallery;
  final DateTime? originalPhotoDate; // For "Time Travel" feature
  final bool isPlayed;
  final DateTime? playedAt;
  final String? replyVibeId; // If this is a reply to another vibe
  final List<VibeReaction> reactions;
  final String? transcription; // AI generated transcription for "Read-First"
  final String? widgetHook; // 🪝 AI-generated 3-word hook for widget engagement
  final List<TextReply> textReplies; // "Visual Whispers" text messages

  // Batch Support: Links vibes sent to multiple friends in one action
  final String?
  batchId; // Shared ID for batch-sent vibes (null for single sends or legacy vibes)

  // GDPR Compliance: Deletion metadata
  final bool isDeleted; // True if sender deleted this vibe
  final DateTime? deletedAt; // When the vibe was deleted
  final String? deletedBy; // User ID who deleted (should be sender)

  VibeModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.receiverId,
    required this.audioUrl,
    this.imageUrl,
    this.videoUrl,
    this.isVideo = false,
    this.isAudioOnly = false,
    required this.audioDuration,
    this.waveformData = const [],
    required this.createdAt,
    this.isFromGallery = false,
    this.originalPhotoDate,
    this.isPlayed = false,
    this.playedAt,
    this.replyVibeId,
    this.reactions = const [],
    this.transcription,
    this.widgetHook,
    this.textReplies = const [],
    this.batchId,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedBy,
  });

  factory VibeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VibeModel(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      senderAvatar: data['senderAvatar'],
      receiverId: data['receiverId'] ?? '',
      audioUrl: data['audioUrl'] ?? '',
      imageUrl: data['imageUrl'],
      videoUrl: data['videoUrl'],
      isVideo: data['isVideo'] ?? false,
      isAudioOnly: data['isAudioOnly'] ?? false,
      audioDuration: data['audioDuration'] ?? 0,
      waveformData: data['waveformData'] != null
          ? List<double>.from(data['waveformData'])
          : [],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isFromGallery: data['isFromGallery'] ?? false,
      originalPhotoDate: data['originalPhotoDate'] != null
          ? (data['originalPhotoDate'] as Timestamp).toDate()
          : null,
      isPlayed: data['isPlayed'] ?? false,
      playedAt: data['playedAt'] != null
          ? (data['playedAt'] as Timestamp).toDate()
          : null,
      replyVibeId: data['replyVibeId'],
      reactions: data['reactions'] != null
          ? (data['reactions'] as List)
                .map((r) => VibeReaction.fromMap(r))
                .toList()
          : [],
      transcription: data['transcription'],
      widgetHook: data['widgetHook'],
      textReplies: data['textReplies'] != null
          ? (data['textReplies'] as List)
                .map((t) => TextReply.fromMap(t))
                .toList()
          : [],
      batchId: data['batchId'],
      isDeleted: data['isDeleted'] ?? false,
      deletedAt: data['deletedAt'] != null
          ? (data['deletedAt'] as Timestamp).toDate()
          : null,
      deletedBy: data['deletedBy'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'receiverId': receiverId,
      'audioUrl': audioUrl,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'isVideo': isVideo,
      'isAudioOnly': isAudioOnly,
      'audioDuration': audioDuration,
      'waveformData': waveformData,
      'createdAt': Timestamp.fromDate(createdAt),
      'isFromGallery': isFromGallery,
      'originalPhotoDate': originalPhotoDate != null
          ? Timestamp.fromDate(originalPhotoDate!)
          : null,
      'isPlayed': isPlayed,
      'playedAt': playedAt != null ? Timestamp.fromDate(playedAt!) : null,
      'replyVibeId': replyVibeId,
      'reactions': reactions.map((r) => r.toMap()).toList(),
      'transcription': transcription,
      'widgetHook': widgetHook,
      'textReplies': textReplies.map((t) => t.toMap()).toList(),
      'batchId': batchId,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'deletedBy': deletedBy,
    };
  }

  VibeModel copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? receiverId,
    String? audioUrl,
    String? imageUrl,
    bool? isVideo,
    bool? isAudioOnly,
    int? audioDuration,
    List<double>? waveformData,
    DateTime? createdAt,
    bool? isFromGallery,
    DateTime? originalPhotoDate,
    bool? isPlayed,
    DateTime? playedAt,
    String? replyVibeId,
    List<VibeReaction>? reactions,
    String? transcription,
    String? widgetHook,
    List<TextReply>? textReplies,
    String? batchId,
    bool? isDeleted,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return VibeModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      receiverId: receiverId ?? this.receiverId,
      audioUrl: audioUrl ?? this.audioUrl,
      imageUrl: imageUrl ?? this.imageUrl,
      isVideo: isVideo ?? this.isVideo,
      isAudioOnly: isAudioOnly ?? this.isAudioOnly,
      audioDuration: audioDuration ?? this.audioDuration,
      waveformData: waveformData ?? this.waveformData,
      createdAt: createdAt ?? this.createdAt,
      isFromGallery: isFromGallery ?? this.isFromGallery,
      originalPhotoDate: originalPhotoDate ?? this.originalPhotoDate,
      isPlayed: isPlayed ?? this.isPlayed,
      playedAt: playedAt ?? this.playedAt,
      replyVibeId: replyVibeId ?? this.replyVibeId,
      reactions: reactions ?? this.reactions,
      transcription: transcription ?? this.transcription,
      widgetHook: widgetHook ?? this.widgetHook,
      textReplies: textReplies ?? this.textReplies,
      batchId: batchId ?? this.batchId,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
    );
  }

  /// Check if this is a "Time Travel" upload (from gallery)
  /// Only true if the photo is older than 24 hours - prevents tagging
  /// recently taken photos as "nostalgia" content
  ///
  /// FIX: Uses createdAt (upload time) instead of DateTime.now() for deterministic logic
  bool get isTimeTravel {
    if (!isFromGallery || originalPhotoDate == null) return false;

    // Photo must be at least 24 hours old AT UPLOAD TIME to be "Time Travel"
    // This is immutable - doesn't change as time passes
    final photoAge = createdAt.difference(originalPhotoDate!);
    return photoAge > const Duration(hours: 24);
  }

  /// Get the retro tag string (e.g., "OCT 24")
  String? get retroTag {
    if (!isTimeTravel || originalPhotoDate == null) return null;
    final months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return 'RETRO ${months[originalPhotoDate!.month - 1]} \'${originalPhotoDate!.year.toString().substring(2)}';
  }

  /// 🕰️ Gradient Decay Indicator (Time Travel)
  /// Provides nuanced temporal context: "LIVE", "TODAY", or "RETRO [MONTH] [YEAR]"
  String get temporalTag {
    final now = DateTime.now();
    final age = now.difference(createdAt);

    if (age.inMinutes < 15) return 'LIVE';
    if (age.inHours < 24) return 'TODAY';

    if (isTimeTravel && originalPhotoDate != null) {
      final months = [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC',
      ];
      final monthStr = months[originalPhotoDate!.month - 1];
      final yearStr = originalPhotoDate!.year.toString().substring(2);
      return 'RETRO $monthStr \'$yearStr';
    }

    return 'PAST';
  }
}

/// Reaction to a vibe
class VibeReaction {
  final String userId;
  final String emoji;
  final DateTime createdAt;

  VibeReaction({
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory VibeReaction.fromMap(Map<String, dynamic> map) {
    return VibeReaction(
      userId: map['userId'] ?? '',
      emoji: map['emoji'] ?? '👍',
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'emoji': emoji,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

/// Text reply (Visual Whispers)
class TextReply {
  final String senderId;
  final String senderName;
  final String text;
  final DateTime createdAt;

  TextReply({
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.createdAt,
  });

  factory TextReply.fromMap(Map<String, dynamic> map) {
    return TextReply(
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? '',
      text: map['text'] ?? '',
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
