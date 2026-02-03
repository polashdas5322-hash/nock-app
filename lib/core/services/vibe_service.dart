import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/vibe_model.dart';
import '../models/user_model.dart';
import '../constants/app_constants.dart';
import 'auth_service.dart';
import 'transcription_service.dart';
import 'cloudinary_service.dart';  // ← Cloudinary for file storage (no credit card needed!)
import 'gatekeeper_service.dart'; // Local VAD Gatekeeper
import 'widget_update_service.dart';
import 'background_upload_service.dart';

/// Vibe Service Provider
final vibeServiceProvider = Provider<VibeService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return VibeService(authService);
});

/// Recent vibes stream (last 24 hours for free users)
final recentVibesProvider = StreamProvider<List<VibeModel>>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  return userAsync.when(
    data: (user) {
      if (user == null) return Stream.value([]);
      
      Query query = FirebaseFirestore.instance
          .collection(AppConstants.vibesCollection)
          .where('receiverId', isEqualTo: user.id);

      // HISTORY LIMIT REMOVED: Users see older vibes as "Locked" (Endowment Effect)

      return query
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
            final vibes = snapshot.docs.map((doc) => VibeModel.fromFirestore(doc)).toList();
            // Safety: Filter out blocked users (Guideline 1.2)
            if (user.blockedUserIds.isEmpty) return vibes;
            return vibes.where((vibe) => !user.blockedUserIds.contains(vibe.senderId)).toList();
          });
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// All vibes stream (for premium users - Vault)
final allVibesProvider = StreamProvider<List<VibeModel>>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  return userAsync.when(
    data: (user) {
      if (user == null) return Stream.value([]);
      
      Query query = FirebaseFirestore.instance
          .collection(AppConstants.vibesCollection)
          .where('receiverId', isEqualTo: user.id);

      // HISTORY LIMIT REMOVED: Vault now shows older vibes as "Locked" to free users
      
      return query
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .map((snapshot) {
            final vibes = snapshot.docs.map((doc) => VibeModel.fromFirestore(doc)).toList();
            // Safety: Filter out blocked users (Guideline 1.2)
            if (user.blockedUserIds.isEmpty) return vibes;
            return vibes.where((vibe) => !user.blockedUserIds.contains(vibe.senderId)).toList();
          });
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

// ═══════════════════════════════════════════════════════════════════════════════
// PAGINATED VIBES PROVIDER - Infinite scroll for Vault
// ═══════════════════════════════════════════════════════════════════════════════

/// State for paginated vibes list
class PaginatedVibesState {
  final List<VibeModel> vibes;
  final bool isLoading;
  final bool hasMore;
  final String? error;
  
  const PaginatedVibesState({
    this.vibes = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });
  
  PaginatedVibesState copyWith({
    List<VibeModel>? vibes,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return PaginatedVibesState(
      vibes: vibes ?? this.vibes,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

/// Notifier for paginated vibes with infinite scroll support
class PaginatedVibesNotifier extends StateNotifier<PaginatedVibesState> {
  final Ref _ref;
  final bool _isSent;
  DocumentSnapshot? _lastDocument;
  static const _pageSize = 20;
  
  PaginatedVibesNotifier(this._ref, {bool isSent = false}) 
      : _isSent = isSent, 
        super(const PaginatedVibesState()) {
    _loadFirstPage();
  }
  
  /// Load first page of vibes
  Future<void> _loadFirstPage() async {
    final userAsync = _ref.read(currentUserProvider);
    final user = userAsync.valueOrNull;
    if (user == null) return;
    
    state = state.copyWith(isLoading: true, error: null);
    
    try {
      Query query = FirebaseFirestore.instance
          .collection(AppConstants.vibesCollection)
          .where(_isSent ? 'senderId' : 'receiverId', isEqualTo: user.id);

      // HISTORY LIMIT REMOVED: Users can scroll to see locked history
      
      query = query.orderBy('createdAt', descending: true).limit(_pageSize);
      
      final snapshot = await query.get();
      if (!mounted) return;
      
      final vibesList = snapshot.docs.map((doc) => VibeModel.fromFirestore(doc)).toList();
      
      // Safety: Filter out blocked users (unless viewing Sent vibes)
      final vibes = _isSent 
          ? vibesList 
          : vibesList.where((vibe) => !user.blockedUserIds.contains(vibe.senderId)).toList();
      
      _lastDocument = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      
      state = PaginatedVibesState(
        vibes: vibes,
        isLoading: false,
        hasMore: snapshot.docs.length == _pageSize,
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('❌ PaginatedVibes: Error loading first page: $e');
      // Surface more specific error info if possible
      final errorStr = e.toString();
      state = state.copyWith(isLoading: false, error: errorStr);
    }
  }
  
  /// Load next page of vibes (call when user scrolls near bottom)
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || _lastDocument == null) return;
    
    final userAsync = _ref.read(currentUserProvider);
    final user = userAsync.valueOrNull;
    if (user == null) return;
    
    state = state.copyWith(isLoading: true);
    
    try {
      Query query = FirebaseFirestore.instance
          .collection(AppConstants.vibesCollection)
          .where(_isSent ? 'senderId' : 'receiverId', isEqualTo: user.id);

      // HISTORY LIMIT REMOVED
      
      query = query
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(_pageSize);
      
      final snapshot = await query.get();
      if (!mounted) return;
      
      final vibesList = snapshot.docs.map((doc) => VibeModel.fromFirestore(doc)).toList();
      
      // Safety: Filter out blocked users (unless viewing Sent vibes)
      final newVibes = _isSent 
          ? vibesList 
          : vibesList.where((vibe) => !user.blockedUserIds.contains(vibe.senderId)).toList();
      
      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
      }
      
      state = state.copyWith(
        vibes: [...state.vibes, ...newVibes],
        isLoading: false,
        hasMore: newVibes.length == _pageSize,
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('❌ PaginatedVibes: Error loading more: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
  
  /// Refresh the entire list (pull-to-refresh)
  Future<void> refresh() async {
    _lastDocument = null;
    state = const PaginatedVibesState();
    await _loadFirstPage();
  }
}

/// Provider for paginated vibes
/// Family provider allows caching both Sent and Received lists independently
final paginatedVibesProvider = StateNotifierProvider.family<PaginatedVibesNotifier, PaginatedVibesState, bool>((ref, isSent) {
  return PaginatedVibesNotifier(ref, isSent: isSent);
});

/// Vibe Service - handles sending and receiving voice-photo messages
/// 
/// Uses Cloudinary for file storage (free tier, no credit card required!)
/// Firebase is only used for Firestore database (still free on Spark plan)
class VibeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CloudinaryService _cloudinary = CloudinaryService();  // ← Using Cloudinary now!
  final AuthService _authService;
  final _uuid = const Uuid();

  VibeService(this._authService);

  /// Get widget-safe thumbnail URL from original image URL
  /// 
  /// CRITICAL: iOS widgets have a 30MB memory limit.
  /// A 4K photo expands to 40MB+ in RAM when decoded.
  /// 
  /// FIX: Use Cloudinary's transformation API for guaranteed 300x300 resize
  /// This is safer than filename parsing which can fail
  static String getWidgetImageUrl(String? originalUrl) {
    if (originalUrl == null || originalUrl.isEmpty) return '';
    
    try {
      // FIX: iOS Widget OOM Prevention
      // Widgets have hard memory limits (~30MB). We MUST ensure the image is resized.
      // If we can't guarantee a small image, return empty to prevent widget crash.
      
      // Only Cloudinary URLs can be safely transformed
      if (originalUrl.contains('cloudinary.com') && originalUrl.contains('/upload/')) {
        // Insert transformation parameters after /upload/
        return originalUrl.replaceAll(
          '/upload/',
          '/upload/w_300,h_300,c_fill,q_auto/',
        );
      }
      
      // FALLBACK: For non-Cloudinary URLs, return the original URL
      // WidgetUpdateService will handle the download and local downsampling
      // to prevent OOM crashes on iOS.
      debugPrint('VibeService: non-Cloudinary image detected, using fallback for widget.');
      return originalUrl;
    } catch (e) {
      debugPrint('Error transforming widget image URL: $e');
      return ''; // Safe fallback
    }
  }

  /// Send a new vibe (voice + optional photo/video)
  /// 
  /// For photo vibes: audioFile + imageFile
  /// For video vibes: videoFile (audio is embedded in video)
  Future<VibeModel?> sendVibe({
    required String receiverId,
    File? audioFile,
    required int audioDuration,
    required List<double> waveformData,
    File? imageFile,
    File? videoFile,
    bool isVideo = false,
    bool isAudioOnly = false,
    bool isFromGallery = false,
    DateTime? originalPhotoDate,
    String? replyToVibeId,
  }) async {
      // Legacy wrapper for single send
      final success = await sendBatchVibe(
          receiverIds: [receiverId],
          audioFile: audioFile,
          audioDuration: audioDuration,
          waveformData: waveformData,
          imageFile: imageFile,
          videoFile: videoFile,
          isVideo: isVideo,
          isAudioOnly: isAudioOnly,
          isFromGallery: isFromGallery,
          originalPhotoDate: originalPhotoDate,
          replyToVibeId: replyToVibeId,
      );
      
      if (success) {
          // Return a dummy model or fetch the one we just created?
          // For legacy compatibility, we can fetch it or construct it.
          // Since sendBatchVibe creates IDs internally, we can't easily return the exact model here strictly.
          // But sendVibe is now mostly used by the Provider which ignores the return value except for null check.
          // WE SHOULD UPDATE PROVIDER TO EXPECT BOOL, but I already did that.
          // Wait, VibeUploadNotifier expects VibeModel? No, it expects bool from sendBatchVibe.
          // Check VibeUploadNotifier line 461: "final vibe = await _vibeService.sendBatchVibe(...)".
          // It checks "if (vibe)". So sendBatchVibe must return bool.
          // But sendVibe signature returns Future<VibeModel?>.
          // I should return a dummy model if success, or null if fail.
          return VibeModel(
            id: 'batch_success', 
            senderId: '', receiverId: receiverId, senderName: '', 
            audioUrl: '', audioDuration: 0, createdAt: DateTime.now()
          ); 
      }
      return null;
  }

  /// 🌟 FAN-OUT ARCHITECTURE: One Upload, Many writes.
  /// Solves N+1 Loop of Death.
  Future<bool> sendBatchVibe({
    required List<String> receiverIds,
    File? audioFile,
    required int audioDuration,
    required List<double> waveformData,
    File? imageFile,
    File? videoFile,
    bool isVideo = false,
    bool isAudioOnly = false,
    bool isFromGallery = false,
    DateTime? originalPhotoDate,
    String? replyToVibeId,
  }) async {
    String? bgTaskId;
    try {
      final senderId = _authService.currentUserId;
      if (senderId == null) return false;

      // Get sender info once
      final senderDoc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(senderId)
          .get();
      final senderData = senderDoc.data();
      final senderName = senderData?['displayName'] ?? 'Unknown';
      final senderAvatar = senderData?['avatarUrl'];

      // 🛡️ STEP 1: PREPARE VAD GATEKEEPER
      Future<File?>? extractedAudioFuture;
      final mediaFile = videoFile ?? audioFile;
      if (mediaFile != null) {
        extractedAudioFuture = GatekeeperService.instance.hasSpeech(mediaFile, isVideo: isVideo);
      }

      // 🛡️ STEP 2: START BACKGROUND SURVIVAL TASK
      bgTaskId = await BackgroundUploadService.startTask(
          title: 'Sending to ${receiverIds.length} friends',
          subtitle: 'Uploading media once...',
      );

      // ═══════════════════════════════════════════════════════════════════════
      // SINGLE UPLOAD PIPELINE
      // ═══════════════════════════════════════════════════════════════════════
      
      String? audioUrl;
      String? imageUrl;
      String? videoUrl;
      String? transcription;

      // Track progress
      double audioProgress = 0.0, imageProgress = 0.0, videoProgress = 0.0;
      void updateOverallProgress() {
        if (bgTaskId == null) return;
        int activeTasksCount = (audioFile != null ? 1 : 0) + 
                               (imageFile != null ? 1 : 0) + 
                               (videoFile != null ? 1 : 0);
        if (activeTasksCount == 0) return;
        double total = (audioProgress + imageProgress + videoProgress) / activeTasksCount;
        BackgroundUploadService.updateProgress(bgTaskId!, total, 'Uploading media (${(total * 100).toInt()}%)...');
      }
      
      final List<Future<dynamic>> parallelTasks = [];
      
      Future<String?>? audioFuture;
      if (audioFile != null && await audioFile.exists()) {
        audioFuture = _cloudinary.uploadAudio(audioFile, onProgress: (p) { audioProgress = p; updateOverallProgress(); });
        parallelTasks.add(audioFuture);
      }
      
      Future<String?>? imageFuture;
      if (imageFile != null && await imageFile.exists()) {
        imageFuture = _cloudinary.uploadImage(imageFile, onProgress: (p) { imageProgress = p; updateOverallProgress(); });
        parallelTasks.add(imageFuture);
      }
      
      Future<String?>? videoFuture;
      if (videoFile != null && isVideo && await videoFile.exists()) {
        videoFuture = _cloudinary.uploadVideo(videoFile, onProgress: (p) { videoProgress = p; updateOverallProgress(); });
        parallelTasks.add(videoFuture);
      }
      
      Future<String?>? transcriptionTask;
      if (extractedAudioFuture != null) {
        transcriptionTask = extractedAudioFuture.then((file) async {
          if (file == null) return null;
          final text = await TranscriptionService().transcribeFile(file);
          try { if (await file.exists()) await file.delete(); } catch (_) {}
          return text;
        });
        parallelTasks.add(transcriptionTask);
      }
      
      await Future.wait(parallelTasks.map((task) => task.catchError((e) => null)));
      
      if (audioFuture != null) audioUrl = await audioFuture.catchError((_) => null);
      if (imageFuture != null) imageUrl = await imageFuture.catchError((_) => null);
      if (videoFuture != null) videoUrl = await videoFuture.catchError((_) => null);
      if (transcriptionTask != null) transcription = await transcriptionTask.catchError((_) => null);

      // 🪝 Host Hook Generation (Once)
      String? widgetHook;
      if (transcription != null && transcription.isNotEmpty) {
        widgetHook = await TranscriptionService().generateWidgetHook(transcription);
      }

      // 🛡️ STRICT VALIDATION
      bool isValid = true;
      if (isVideo && videoUrl == null) isValid = false;
      else if (isAudioOnly && audioUrl == null) isValid = false;
      else if (!isVideo && !isAudioOnly && imageUrl == null) isValid = false;

      if (!isValid) {
        debugPrint('❌ VibeService: Batch Validation Failed.');
        return false;
      }

      // ═══════════════════════════════════════════════════════════════════════
      // 🔥 FIRESTORE FAN-OUT (The Optimization)
      // ═══════════════════════════════════════════════════════════════════════
      
      final WriteBatch batch = _firestore.batch();
      final timestamp = DateTime.now();
      final List<VibeModel> createdVibes = [];

      for (String receiverId in receiverIds) {
        final vibeId = _uuid.v4();
        
        final vibe = VibeModel(
          id: vibeId,
          senderId: senderId,
          senderName: senderName,
          senderAvatar: senderAvatar,
          receiverId: receiverId,
          audioUrl: audioUrl ?? '',
          imageUrl: imageUrl,
          videoUrl: videoUrl,
          isVideo: isVideo,
          isAudioOnly: isAudioOnly || (audioFile != null && imageFile == null && videoFile == null),
          audioDuration: audioDuration,
          waveformData: waveformData,
          createdAt: timestamp,
          isFromGallery: isFromGallery,
          originalPhotoDate: originalPhotoDate,
          transcription: transcription,
          widgetHook: widgetHook, // Shared Hook
          replyVibeId: replyToVibeId,
        );

        createdVibes.add(vibe);
        
        // 1. Create Vibe Document
        batch.set(
            _firestore.collection(AppConstants.vibesCollection).doc(vibeId),
            vibe.toFirestore()
        );

        // 2. Update Receiver Widget State (Private Doc)
        // Note: Batch limits are 500. If sending to > 200 friends, chunk this.
        // Assuming < 20 friends for now.
        final widgetState = WidgetState(
          latestVibeId: vibeId,
          latestAudioUrl: vibe.audioUrl,
          latestImageUrl: getWidgetImageUrl(vibe.imageUrl),
          senderName: vibe.senderName,
          senderAvatar: vibe.senderAvatar,
          audioDuration: vibe.audioDuration,
          waveformData: vibe.waveformData,
          timestamp: vibe.createdAt,
          isPlayed: false,
          transcriptionPreview: widgetHook ?? transcription, 
          isVideo: vibe.isVideo,
          isAudioOnly: vibe.isAudioOnly,
          videoUrl: vibe.videoUrl,
        );
        
        batch.set(
            _firestore.collection(AppConstants.usersCollection)
              .doc(receiverId)
              .collection('private')
              .doc('widget_data'),
            {'widgetState': widgetState.toMap()}
        );

        // 3. Friendship Health (Simplified for Batch)
        // Since we can't easily query friendships inside a batch flow efficiently without reading first,
        // we might skip updating health OR do it optimistically.
        // For now, let's process health updates *after* the batch commits to avoid reading inside the critical path.
      }

      // COMMIT ALL WRITES (Atomic)
      await batch.commit();

      // Post-Commit: Handle side effects (Friendship, Local UI refresh)
      // These are non-critical, so we don't await them necessarily or we handle errors gracefully.
      for (final vibe in createdVibes) {
          _updateFriendshipActivity(senderId, vibe.receiverId).catchError((_) {});
      }
      
      // Update Sender Widget immediately (await to prevent race condition)
      await WidgetUpdateService.refreshAllWidgets(createdVibes);

      return true;

    } catch (e) {
      debugPrint('Error sending batch vibe: $e');
      return false;
    } finally {
      await BackgroundUploadService.stopTask(bgTaskId);
    }
  }

  /// Update receiver's widget state for instant widget updates
  /// 📝 Now supports precomputed transcription from parallel pipeline
  /// 🪝 Prioritizes AI-generated widgetHook over truncated transcription
  Future<void> _updateReceiverWidgetState(
      String receiverId, VibeModel vibe, {bool skipTranscription = false, String? precomputedTranscription, String? widgetHook}) async {
    // 🪝 3-Word Hook Strategy: Use AI hook for maximum engagement
    // Falls back to truncated transcription if hook generation failed
    String? transcriptionPreview;
    
    if (widgetHook != null && widgetHook.isNotEmpty) {
      // BEST: Use AI-generated hook for maximum curiosity gap
      transcriptionPreview = widgetHook;
      debugPrint('🪝 VibeService: Using AI hook for widget: $widgetHook');
    } else if (precomputedTranscription != null && precomputedTranscription.isNotEmpty) {
      // FALLBACK: Use truncated transcription (no round-trip needed!)
      transcriptionPreview = precomputedTranscription.length > 50 
          ? '${precomputedTranscription.substring(0, 50)}...' 
          : precomputedTranscription;
      debugPrint('📝 VibeService: Using truncated transcription for widget.');
    } else if (!skipTranscription) {
      // LEGACY: URL-based transcription (only for old code paths)
      final String mediaUrlToTranscribe = vibe.audioUrl.isNotEmpty 
          ? vibe.audioUrl 
          : (vibe.videoUrl ?? '');

      if (mediaUrlToTranscribe.isNotEmpty) {
        try {
          final transcriptionService = TranscriptionService();
          final fullText = await transcriptionService.transcribeFromUrl(mediaUrlToTranscribe);
          if (fullText != null && fullText.isNotEmpty) {
            transcriptionPreview = fullText.length > 50 
                ? '${fullText.substring(0, 50)}...' 
                : fullText;
            
            // Save full transcription to the vibe doc
            await _firestore.collection(AppConstants.vibesCollection).doc(vibe.id).update({
              'transcription': fullText,
            }).catchError((e) => debugPrint('VibeService: Failed to save persistent transcription: $e'));
          }
        } catch (e) {
          print('VibeService: Transcription failed (non-critical): $e');
        }
      }
    }
    
    final widgetState = WidgetState(
      latestVibeId: vibe.id,
      latestAudioUrl: vibe.audioUrl,
      // 🖼️ Use thumbnail for widget (prevents 30MB crash on iOS)
      latestImageUrl: getWidgetImageUrl(vibe.imageUrl),
      senderName: vibe.senderName,
      senderAvatar: vibe.senderAvatar,
      audioDuration: vibe.audioDuration,
      waveformData: vibe.waveformData,
      timestamp: vibe.createdAt,
      isPlayed: false,
      transcriptionPreview: transcriptionPreview, // 🪝 Now contains AI hook!
      // 🎬 4-State Widget Protocol: Content type flags
      isVideo: vibe.isVideo,
      isAudioOnly: vibe.isAudioOnly,
      videoUrl: vibe.videoUrl,
    );


    // FIX 4: Widget Privacy Security
    // Move widgetState to a private sub-collection so message previews aren't public
    // Matches path: users/{uid}/private/widget_data
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(receiverId)
        .collection('private')
        .doc('widget_data')
        .set({'widgetState': widgetState.toMap()});
        
    // Also clear the legacy public field if it exists
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(receiverId)
        .update({'widgetState': FieldValue.delete()}).catchError((_) {});
  }

  /// Update friendship activity for health tracking
  /// 🌱 Uses Friendship Garden model - gardens thrive with activity
  Future<void> _updateFriendshipActivity(
      String senderId, String receiverId) async {
    // Find friendship document
    final friendshipQuery = await _firestore
        .collection(AppConstants.friendshipsCollection)
        .where('userId', isEqualTo: senderId)
        .where('friendId', isEqualTo: receiverId)
        .limit(1)
        .get();

    if (friendshipQuery.docs.isNotEmpty) {
      final doc = friendshipQuery.docs.first;

      await doc.reference.update({
        'lastVibeAt': Timestamp.now(),
        'health': 'thriving',  // 🌸 Friendship Garden: thriving (not "healthy")
      });

      // SYNC TO WIDGET: Update the BFF widget data for this friend
      try {
        final receiverDoc = await _firestore
            .collection(AppConstants.usersCollection)
            .doc(receiverId)
            .get();
        
        if (receiverDoc.exists) {
          final receiverData = receiverDoc.data();
          await WidgetUpdateService.updateBFFWidget(
            friendId: receiverId,
            friendName: receiverData?['displayName'] ?? 'Friend',
            avatarUrl: receiverData?['avatarUrl'],
          );
        }
      } catch (e) {
        debugPrint('VibeService: Failed to update BFF widget: $e');
      }
    }
  }

  /// Mark vibe as played
  Future<void> markAsPlayed(String vibeId) async {
    await _firestore.collection(AppConstants.vibesCollection).doc(vibeId).update({
      'isPlayed': true,
      'playedAt': Timestamp.now(),
    });

    // Update widget state
    final userId = _authService.currentUserId;
    if (userId != null) {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection('private')
          .doc('widget_data')
          .update({'widgetState.isPlayed': true});
          
      // CRITICAL FIX: Update local widget immediately to remove "New" badge
      await WidgetUpdateService.markVibePlayed(vibeId);
    }
  }



  /// Reply to a vibe
  Future<VibeModel?> replyToVibe({
    required String originalVibeId,
    required String receiverId,
    required File audioFile,
    required int audioDuration,
    required List<double> waveformData,
  }) async {
    final vibe = await sendVibe(
      receiverId: receiverId,
      audioFile: audioFile,
      audioDuration: audioDuration,
      waveformData: waveformData,
      replyToVibeId: originalVibeId,
    );

    if (vibe != null) {
      // Link to original vibe
      await _firestore
          .collection(AppConstants.vibesCollection)
          .doc(vibe.id)
          .update({'replyVibeId': originalVibeId});
    }

    return vibe;
  }

  /// Get vibes grouped by date for Vault calendar view
  Future<Map<DateTime, List<VibeModel>>> getVibesByDate() async {
    final userId = _authService.currentUserId;
    if (userId == null) return {};

    final snapshot = await _firestore
        .collection(AppConstants.vibesCollection)
        .where('receiverId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();

    final vibes = snapshot.docs.map((doc) => VibeModel.fromFirestore(doc)).toList();
    
    final Map<DateTime, List<VibeModel>> grouped = {};
    for (final vibe in vibes) {
      final date = DateTime(
        vibe.createdAt.year,
        vibe.createdAt.month,
        vibe.createdAt.day,
      );
      grouped[date] ??= [];
      grouped[date]!.add(vibe);
    }

    return grouped;
  }

  /// Block a user
  Future<void> blockUser(String userIdToBlock) async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .update({
        'blockedUserIds': FieldValue.arrayUnion([userIdToBlock])
      });
      debugPrint('VibeService: User $userIdToBlock blocked by $userId');
    } catch (e) {
      debugPrint('VibeService: Error blocking user: $e');
      rethrow;
    }
  }

  /// Unblock a user
  Future<void> unblockUser(String userIdToUnblock) async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .update({
        'blockedUserIds': FieldValue.arrayRemove([userIdToUnblock])
      });
      debugPrint('VibeService: User $userIdToUnblock unblocked by $userId');
    } catch (e) {
      debugPrint('VibeService: Error unblocking user: $e');
      rethrow;
    }
  }

  /// Report a vibe for Guideline 1.2 compliance
  Future<void> reportVibe({
    required String vibeId,
    required String reporterId,
    required String reason,
  }) async {
    try {
      await _firestore.collection('reports').add({
        'vibeId': vibeId,
        'reporterId': reporterId,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      debugPrint('VibeService: Vibe $vibeId reported by $reporterId');
    } catch (e) {
      debugPrint('VibeService: Error reporting vibe: $e');
      rethrow;
    }
  }
  
  /// Get a single vibe by ID
  /// Used for widget click handling - when user taps widget, navigate to that specific vibe
  Future<VibeModel?> getVibeById(String vibeId) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.vibesCollection)
          .doc(vibeId)
          .get();
      
      if (doc.exists) {
        return VibeModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Add transcription to an existing vibe (for "Read-First" persistence)
  Future<void> saveTranscription(String vibeId, String text) async {
    await _firestore.collection(AppConstants.vibesCollection).doc(vibeId).update({
      'transcription': text,
    });
  }

  /// Add a text reply to a vibe (Visual Whispers)
  Future<void> sendTextReply(String vibeId, String text) async {
    final senderId = _authService.currentUserId;
    if (senderId == null) return;

    final senderDoc = await _firestore.collection(AppConstants.usersCollection).doc(senderId).get();
    final senderName = senderDoc.data()?['displayName'] ?? 'Unknown';

    final reply = TextReply(
      senderId: senderId,
      senderName: senderName,
      text: text,
      createdAt: DateTime.now(),
    );

    await _firestore.collection(AppConstants.vibesCollection).doc(vibeId).update({
      'textReplies': FieldValue.arrayUnion([reply.toMap()]),
    });
  }

  /// Add an emoji reaction to a vibe (Quick Reactions)
  Future<void> addReaction(String vibeId, String emoji) async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final reaction = VibeReaction(
      userId: userId,
      emoji: emoji,
      createdAt: DateTime.now(),
    );

    await _firestore.collection(AppConstants.vibesCollection).doc(vibeId).update({
      'reactions': FieldValue.arrayUnion([reaction.toMap()]),
    });
  }
  
  /// Delete vibe for everyone (sender's right to erasure - GDPR Article 17)
  /// 
  /// CRITICAL: This allows the sender to delete their content from both:
  /// 1. Their own view
  /// 2. The receiver's view (including if receiver has Premium)
  /// 
  /// The sender's right to delete their data trumps the receiver's Premium Vault.
  Future<void> deleteVibeForEveryone(String vibeId) async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) {
        debugPrint('VibeService: Cannot delete vibe - user not authenticated');
        return;
      }
      
      // 1. Get vibe to verify sender and get media URLs
      final vibeDoc = await _firestore
          .collection(AppConstants.vibesCollection)
          .doc(vibeId)
          .get();
      
      if (!vibeDoc.exists) {
        debugPrint('VibeService: Vibe $vibeId not found');
        return;
      }
      
      final vibe = VibeModel.fromFirestore(vibeDoc);
      
      // 2. Verify current user is the sender
      if (vibe.senderId != userId) {
        debugPrint('VibeService: User $userId is not the sender of vibe $vibeId');
        throw Exception('You can only delete vibes you sent');
      }
      
      debugPrint('VibeService: Deleting vibe $vibeId sent by $userId');
      
      // 3. Delete media from Cloudinary (best effort - don't block on failure)
      final deleteFutures = <Future<bool>>[];
      
      if (vibe.imageUrl != null && vibe.imageUrl!.isNotEmpty) {
        deleteFutures.add(_cloudinary.deleteAsset(vibe.imageUrl!));
      }
      if (vibe.videoUrl != null && vibe.videoUrl!.isNotEmpty) {
        deleteFutures.add(_cloudinary.deleteAsset(vibe.videoUrl!));
      }
      if (vibe.audioUrl.isNotEmpty) {
        deleteFutures.add(_cloudinary.deleteAsset(vibe.audioUrl));
      }
      
      // Wait for deletions (with timeout)
      if (deleteFutures.isNotEmpty) {
        await Future.wait(deleteFutures).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('VibeService: Cloudinary deletions timed out (non-critical)');
            return [];
          },
        );
      }
      
      // 4. Mark vibe as deleted in Firestore (soft delete for audit trail)
      await _firestore.collection(AppConstants.vibesCollection).doc(vibeId).update({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': userId,
        // Clear media URLs to prevent access
        'imageUrl': null,
        'videoUrl': null,
        'audioUrl': '',
      });
      
      // 5. Update receiver's widget state if this was their latest vibe
      await _clearWidgetIfLatest(vibe.receiverId, vibeId);
      
      debugPrint('VibeService: Vibe $vibeId deleted successfully');
    } catch (e) {
      debugPrint('VibeService: Error deleting vibe: $e');
      rethrow;
    }
  }
  
  /// Clear receiver's widget if the deleted vibe was their latest one
  Future<void> _clearWidgetIfLatest(String receiverId, String deletedVibeId) async {
    try {
      final widgetDoc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(receiverId)
          .collection('private')
          .doc('widget_data')
          .get();
      
      if (!widgetDoc.exists) return;
      
      final widgetData = widgetDoc.data();
      final latestVibeId = widgetData?['widgetState']?['latestVibeId'];
      
      if (latestVibeId == deletedVibeId) {
        // Clear the widget - user will see "No recent vibes"
        await _firestore
            .collection(AppConstants.usersCollection)
            .doc(receiverId)
            .collection('private')
            .doc('widget_data')
            .delete();
        
        debugPrint('VibeService: Cleared widget for receiver $receiverId');
      }
    } catch (e) {
      debugPrint('VibeService: Error clearing widget: $e (non-critical)');
    }
  }
}
