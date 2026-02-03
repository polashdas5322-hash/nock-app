import 'package:cloud_firestore/cloud_firestore.dart';
import 'vibe_model.dart';

/// Squad model - represents a group of close friends
class SquadModel {
  final String id;
  final String name;
  final String? iconUrl;
  final String creatorId;
  final List<String> memberIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SquadLastMessage? lastMessage;

  SquadModel({
    required this.id,
    required this.name,
    this.iconUrl,
    required this.creatorId,
    required this.memberIds,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage,
  });

  factory SquadModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SquadModel(
      id: doc.id,
      name: data['name'] ?? '',
      iconUrl: data['iconUrl'],
      creatorId: data['creatorId'] ?? '',
      memberIds: List<String>.from(data['memberIds'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMessage: data['lastMessage'] != null
          ? SquadLastMessage.fromMap(data['lastMessage'])
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'iconUrl': iconUrl,
      'creatorId': creatorId,
      'memberIds': memberIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'lastMessage': lastMessage?.toMap(),
    };
  }

  SquadModel copyWith({
    String? id,
    String? name,
    String? iconUrl,
    String? creatorId,
    List<String>? memberIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    SquadLastMessage? lastMessage,
  }) {
    return SquadModel(
      id: id ?? this.id,
      name: name ?? this.name,
      iconUrl: iconUrl ?? this.iconUrl,
      creatorId: creatorId ?? this.creatorId,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}

/// Denormalized last message for quick squad list rendering
class SquadLastMessage {
  final String senderId;
  final String senderName;
  final int audioDuration;
  final DateTime sentAt;
  final bool hasImage;

  SquadLastMessage({
    required this.senderId,
    required this.senderName,
    required this.audioDuration,
    required this.sentAt,
    this.hasImage = false,
  });

  factory SquadLastMessage.fromMap(Map<String, dynamic> map) {
    return SquadLastMessage(
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? '',
      audioDuration: map['audioDuration'] ?? 0,
      sentAt: map['sentAt'] != null
          ? (map['sentAt'] as Timestamp).toDate()
          : DateTime.now(),
      hasImage: map['hasImage'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'audioDuration': audioDuration,
      'sentAt': Timestamp.fromDate(sentAt),
      'hasImage': hasImage,
    };
  }
}

/// Friendship model for tracking connections between users
/// Uses "Friendship Garden" model - relationships grow, never die
class FriendshipModel {
  final String id;
  final String userId;
  final String friendId;
  final FriendshipStatus status;
  final DateTime createdAt;
  final DateTime? lastVibeAt;
  
  /// Total memories shared (ACCUMULATES, never resets)
  /// This is the "Garden" model - your friendship grows over time
  final int memoriesShared;
  
  /// Vibe Level - positive framing (bloom/steady/chill)
  /// Unlike "streaks", chill connections don't die - they just wait
  final VibeLevel vibeLevel;

  FriendshipModel({
    required this.id,
    required this.userId,
    required this.friendId,
    this.status = FriendshipStatus.pending,
    required this.createdAt,
    this.lastVibeAt,
    this.memoriesShared = 0,
    this.vibeLevel = VibeLevel.bloom,
  });

  factory FriendshipModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FriendshipModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      friendId: data['friendId'] ?? '',
      status: FriendshipStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => FriendshipStatus.pending,
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastVibeAt: data['lastVibeAt'] != null
          ? (data['lastVibeAt'] as Timestamp).toDate()
          : null,
      // Support legacy 'vibeStreak' field for migration
      memoriesShared: data['memoriesShared'] ?? data['vibeStreak'] ?? 0,
      vibeLevel: VibeLevel.values.firstWhere(
        (e) => e.name == data['vibeLevel'] || e.name == data['health'],
        orElse: () => VibeLevel.bloom,
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'friendId': friendId,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastVibeAt': lastVibeAt != null ? Timestamp.fromDate(lastVibeAt!) : null,
      'memoriesShared': memoriesShared,
      'vibeLevel': vibeLevel.name,
    };
  }
  /// 🌻 Friendship Garden Visual State
  /// Maps raw stats to a biological metaphor
  GardenStatus get gardenStatus {
    if (memoriesShared < 10) return GardenStatus.seedling;
    if (memoriesShared < 50) return GardenStatus.budding;
    return GardenStatus.blooming;
  }
}

/// 🌻 Garden Status - The visual metaphor for friendship depth
enum GardenStatus {
  /// 🌱 Just planted, needs care (0-10 vibes)
  seedling,
  
  /// 🌿 Growing strong, showing potential (10-50 vibes)
  budding,
  
  /// 🌸 Fully in bloom, thriving connection (50+ vibes)
  blooming,
}

enum FriendshipStatus {
  pending,
  accepted,
  blocked,
}

/// ⚡ Vibe Level (Friendship History Model)
/// 
/// POSITIVE REINFORCEMENT MODEL:
/// - Levels grow with interaction
/// - Levels stay steady or go "Chill" when inactive, but NEVER disappear
/// - No anxiety, no "streak" pressure, no punishment
enum VibeLevel {
  /// 🌸 Bloom - Active connection, exchanged vibes recently
  bloom,
  
  /// ⚡ Steady - Consistent history, building momentum
  steady,
  
  /// 🌫️ Chill - Low-key, resting but NOT dead. 
  /// This is the key difference from "decay" - chill = resting, not dying
  chill,
}
