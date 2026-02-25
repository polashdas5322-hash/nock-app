import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/vibe_service.dart';
import '../../features/camera/domain/services/video_processing_service.dart';
import 'package:path/path.dart' as p;

enum VibeUploadStatus { processing, uploading, success, error }

/// Represents a background upload task (session-only)
class VibeUploadTask {
  final String id;
  final List<String>
  receiverIds; // 🌟 CHANGED: Support multiple receivers (Fan-Out)
  final String? audioPath;
  final String? imagePath;
  final String? videoPath;
  final String? overlayPath;
  final int audioDuration;
  final List<double> waveformData;
  final bool isVideo;
  final bool isAudioOnly;
  final bool isFromGallery;
  final DateTime? originalPhotoDate;
  final String? replyToVibeId;
  final VibeUploadStatus status;
  final String? error;
  final DateTime createdAt;
  final bool
  isSilent; // 🌟 NEW: If true, global snackbar feedback is suppressed

  VibeUploadTask({
    required this.id,
    required this.receiverIds,
    this.audioPath,
    this.imagePath,
    this.videoPath,
    this.overlayPath,
    required this.audioDuration,
    required this.waveformData,
    this.isVideo = false,
    this.isAudioOnly = false,
    this.isFromGallery = false,
    this.originalPhotoDate,
    this.replyToVibeId,
    this.status = VibeUploadStatus.processing,
    this.error,
    required this.createdAt,
    this.isSilent = false,
  });

  VibeUploadTask copyWith({
    VibeUploadStatus? status,
    String? error,
    String? videoPath,
    String? imagePath,
    String? overlayPath,
    bool? isSilent,
  }) {
    return VibeUploadTask(
      id: id,
      receiverIds: receiverIds,
      audioPath: audioPath,
      imagePath: imagePath ?? this.imagePath,
      videoPath: videoPath ?? this.videoPath,
      overlayPath: overlayPath ?? this.overlayPath,
      audioDuration: audioDuration,
      waveformData: waveformData,
      isVideo: isVideo,
      isAudioOnly: isAudioOnly,
      isFromGallery: isFromGallery,
      originalPhotoDate: originalPhotoDate,
      replyToVibeId: replyToVibeId,
      status: status ?? this.status,
      error: error ?? this.error,
      createdAt: createdAt,
      isSilent: isSilent ?? this.isSilent,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receiverIds': receiverIds, // Store list
      'audioPath': audioPath,
      'imagePath': imagePath,
      'videoPath': videoPath,
      'overlayPath': overlayPath,
      'audioDuration': audioDuration,
      // Store waveform as list of doubles
      'waveformData': waveformData,
      'isVideo': isVideo,
      'isAudioOnly': isAudioOnly,
      'isFromGallery': isFromGallery,
      'originalPhotoDate': originalPhotoDate?.millisecondsSinceEpoch,
      'replyToVibeId': replyToVibeId,
      'status': status.index, // Store enum as int index
      'error': error,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isSilent': isSilent,
    };
  }

  factory VibeUploadTask.fromMap(Map<String, dynamic> map) {
    return VibeUploadTask(
      id: map['id'],
      // Handle legacy single-receiver tasks by wrapping in list
      receiverIds: map['receiverIds'] != null
          ? List<String>.from(map['receiverIds'])
          : (map['receiverId'] != null ? [map['receiverId']] : []),
      audioPath: map['audioPath'],
      imagePath: map['imagePath'],
      videoPath: map['videoPath'],
      overlayPath: map['overlayPath'],
      audioDuration: map['audioDuration'],
      waveformData: List<double>.from(map['waveformData'] ?? []),
      isVideo: map['isVideo'] ?? false,
      isAudioOnly: map['isAudioOnly'] ?? false,
      isFromGallery: map['isFromGallery'] ?? false,
      originalPhotoDate: map['originalPhotoDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['originalPhotoDate'])
          : null,
      replyToVibeId: map['replyToVibeId'],
      status: VibeUploadStatus.values[map['status'] ?? 0],
      error: map['error'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      isSilent: map['isSilent'] ?? false,
    );
  }
}

/// Provider for managing background vibe uploads
final vibeUploadProvider =
    StateNotifierProvider<VibeUploadNotifier, List<VibeUploadTask>>((ref) {
      final vibeService = ref.watch(vibeServiceProvider);
      return VibeUploadNotifier(ref, vibeService);
    });

class VibeUploadNotifier extends StateNotifier<List<VibeUploadTask>> {
  final Ref _ref;
  final VibeService _vibeService;
  final Set<String> _activeTasks = {};
  static const String _storageKey = 'vibe_upload_queue';

  VibeUploadNotifier(this._ref, this._vibeService) : super([]) {
    _loadQueue(); // Load saved tasks on startup
  }

  // 💾 PERSISTENCE: Save/Load Queue
  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final restoredTasks = jsonList
            .map((j) => VibeUploadTask.fromMap(j))
            .toList();
        state = restoredTasks;

        // Auto-retry pending tasks or mark stale processing as error
        for (final task in restoredTasks) {
          if (task.status == VibeUploadStatus.uploading ||
              task.status == VibeUploadStatus.processing) {
            // Retry!
            _startUpload(task);
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [VibeUpload] Failed to load queue: $e');
    }
  }

  Future<void> _saveQueue() async {
    try {
      // Filter out successes to clean up history, keep active/errors
      final tasksToSave = state
          .where((t) => t.status != VibeUploadStatus.success)
          .toList();
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(tasksToSave.map((t) => t.toMap()).toList());
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('⚠️ [VibeUpload] Failed to save queue: $e');
    }
  }

  /// Add a new upload task to the queue
  Future<String> addUpload({
    required String receiverId,
    String? audioPath,
    String? imagePath,
    String? videoPath,
    String? overlayPath,
    required int audioDuration,
    required List<double> waveformData,
    bool isVideo = false,
    bool isAudioOnly = false,
    bool isFromGallery = false,
    DateTime? originalPhotoDate,
    String? replyToVibeId,
  }) async {
    debugPrint('🚀 [VibeUpload] addUpload called: isVideo=$isVideo');

    final taskId = const Uuid().v4();

    // SAFE COPY: Protect files from deletion by other parallel tasks
    final safeAudioPath = await _safeCopy(audioPath, taskId, 'audio');
    final safeImagePath = await _safeCopy(imagePath, taskId, 'image');
    final safeVideoPath = await _safeCopy(videoPath, taskId, 'video');
    final safeOverlayPath = await _safeCopy(overlayPath, taskId, 'overlay');

    final task = VibeUploadTask(
      id: taskId,
      receiverIds: [receiverId], // Wrap single ID in list for legacy support
      audioPath: safeAudioPath,
      imagePath: safeImagePath,
      videoPath: safeVideoPath,
      overlayPath: safeOverlayPath,
      audioDuration: audioDuration,
      waveformData: waveformData,
      isVideo: isVideo,
      isAudioOnly: isAudioOnly,
      isFromGallery: isFromGallery,
      originalPhotoDate: originalPhotoDate,
      replyToVibeId: replyToVibeId,
      status: VibeUploadStatus.processing,
      createdAt: DateTime.now(),
    );

    state = [...state, task];
    _saveQueue(); // Save immediately
    _startUpload(task);

    return task.id; // Return the ID for UI tracking
  }

  /// Helper: Copy file to a safe, task-specific location
  /// This prevents race conditions where multiple tasks share the same file
  /// and one deletes it while others are still uploading.
  Future<String?> _safeCopy(String? path, String taskId, String suffix) async {
    if (path == null) return null;
    try {
      final source = File(path);
      if (!source.existsSync()) return null;

      final ext = p.extension(path);
      final filename = '${taskId}_$suffix$ext';
      final tempDir = Directory.systemTemp;
      final newPath = p.join(tempDir.path, filename);

      await source.copy(newPath);
      // debugPrint('safeCopy: $path -> $newPath');
      return newPath;
    } catch (e) {
      debugPrint('⚠️ [VibeUpload] Failed to copy file: $e');
      return path; // Fallback to original if copy fails
    }
  }

  /// Add a new upload task to the queue AND WAIT for it to complete.
  /// (Blocking mode requested by user for reliability comfort)
  /// Add a new upload task to the queue for MULTIPLE receivers (Fan-Out)
  /// Processing happens once, uploading happens once.
  Future<void> addBatchUploadBlocking({
    required List<String> receiverIds,
    String? audioPath,
    String? imagePath,
    String? videoPath,
    String? overlayPath,
    required int audioDuration,
    required List<double> waveformData,
    bool isVideo = false,
    bool isAudioOnly = false,
    bool isFromGallery = false,
    DateTime? originalPhotoDate,
    String? replyToVibeId,
    bool isSilent = false,
  }) async {
    final completer = Completer<void>();
    final taskId = const Uuid().v4();

    // SAFE COPY: Protect files from deletion
    final safeAudioPath = await _safeCopy(audioPath, taskId, 'audio');
    final safeImagePath = await _safeCopy(imagePath, taskId, 'image');
    final safeVideoPath = await _safeCopy(videoPath, taskId, 'video');
    final safeOverlayPath = await _safeCopy(overlayPath, taskId, 'overlay');

    final task = VibeUploadTask(
      id: taskId,
      receiverIds: receiverIds,
      audioPath: safeAudioPath,
      imagePath: safeImagePath,
      videoPath: safeVideoPath,
      overlayPath: safeOverlayPath,
      audioDuration: audioDuration,
      waveformData: waveformData,
      isVideo: isVideo,
      isAudioOnly: isAudioOnly,
      isFromGallery: isFromGallery,
      originalPhotoDate: originalPhotoDate,
      replyToVibeId: replyToVibeId,
      status: VibeUploadStatus.processing,
      createdAt: DateTime.now(),
      isSilent: isSilent,
    );

    state = [...state, task];
    _saveQueue();

    try {
      await _processAndSendDirectly(task);
      completer.complete();
    } catch (e) {
      completer.completeError(e);
    }

    return completer.future;
  }

  /// Legacy Single-Receiver Blocking Upload (Wraps Batch)
  Future<void> addUploadBlocking({
    required String receiverId,
    String? audioPath,
    String? imagePath,
    String? videoPath,
    String? overlayPath,
    required int audioDuration,
    required List<double> waveformData,
    bool isVideo = false,
    bool isAudioOnly = false,
    bool isFromGallery = false,
    DateTime? originalPhotoDate,
    String? replyToVibeId,
    bool isSilent = false,
  }) async {
    return addBatchUploadBlocking(
      receiverIds: [receiverId],
      audioPath: audioPath,
      imagePath: imagePath,
      videoPath: videoPath,
      overlayPath: overlayPath,
      audioDuration: audioDuration,
      waveformData: waveformData,
      isVideo: isVideo,
      isAudioOnly: isAudioOnly,
      isFromGallery: isFromGallery,
      originalPhotoDate: originalPhotoDate,
      replyToVibeId: replyToVibeId,
      isSilent: isSilent,
    );
  }

  /// Private helper for blocking uploads that bypasses the async queue
  Future<void> _processAndSendDirectly(VibeUploadTask task) async {
    _activeTasks.add(task.id);

    // 1. Process Video if needed
    if (task.isVideo && task.videoPath != null && task.overlayPath != null) {
      updateTaskStatus(task.id, VibeUploadStatus.processing);
      final completer = Completer<VibeUploadTask>();

      final rawVideoPath = task.videoPath!;
      final overlayFile = File(task.overlayPath!);
      final targetSize = const Size(720, 720);

      VideoProcessingService.processAndUpload(
        videoPath: rawVideoPath,
        overlayImage: overlayFile,
        targetSize: targetSize,
        onProcessed: (processedFile) async {
          File? thumbFile = await VideoProcessingService.extractVideoThumbnail(
            processedFile.path,
          );
          completer.complete(
            task.copyWith(
              status: VibeUploadStatus.uploading,
              videoPath: processedFile.path,
              imagePath: thumbFile?.path,
            ),
          );
        },
        onError: (err) {
          completer.completeError(err);
        },
      );

      final processedTask = await completer.future;
      await _performFinalSend(processedTask);
    } else {
      await _performFinalSend(task);
    }
  }

  Future<void> _startUpload(VibeUploadTask task) async {
    if (_activeTasks.contains(task.id)) return;
    _activeTasks.add(task.id);

    // 1. Check if we need video processing
    if (task.isVideo && task.videoPath != null && task.overlayPath != null) {
      updateTaskStatus(task.id, VibeUploadStatus.processing);

      final rawVideoPath = task.videoPath!;
      final overlayFile = File(task.overlayPath!);

      // ASYNC FIX: Use .exists() instead of .existsSync()
      if (!await File(rawVideoPath).exists() || !await overlayFile.exists()) {
        debugPrint(
          '❌ [VibeUpload] Video or overlay file missing for task ${task.id}',
        );
        _activeTasks.remove(task.id);
        updateTaskStatus(
          task.id,
          VibeUploadStatus.error,
          error: 'Files missing',
        );
        return;
      }

      final targetSize = const Size(720, 720);

      VideoProcessingService.processAndUpload(
        videoPath: rawVideoPath,
        overlayImage: overlayFile,
        targetSize: targetSize,
        onProcessed: (processedFile) async {
          debugPrint(
            '🎬 [VibeUpload] Video processing complete for task ${task.id}',
          );

          File? thumbFile = await VideoProcessingService.extractVideoThumbnail(
            processedFile.path,
          );

          final updatedTask = task.copyWith(
            status: VibeUploadStatus.uploading,
            videoPath: processedFile.path,
            imagePath: thumbFile?.path,
          );

          state = [
            for (final t in state)
              if (t.id == task.id) updatedTask else t,
          ];

          _performFinalSend(updatedTask);
        },
        onError: (err) {
          debugPrint(
            '❌ [VibeUpload] Video processing error for task ${task.id}: $err',
          );
          _activeTasks.remove(task.id);
          updateTaskStatus(task.id, VibeUploadStatus.error, error: err);
        },
      );
      return;
    }

    _performFinalSend(task);
  }

  Future<void> _performFinalSend(VibeUploadTask task) async {
    updateTaskStatus(task.id, VibeUploadStatus.uploading);

    // ASYNC FIX: Use .exists() instead of .existsSync()
    if (task.audioPath != null) {
      final file = File(task.audioPath!);
      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      debugPrint(
        '🔍 [VibeUpload] Audio validation: exists=$exists, size=$size bytes, path=${task.audioPath}',
      );
      if (!exists || size == 0) {
        _activeTasks.remove(task.id);
        updateTaskStatus(
          task.id,
          VibeUploadStatus.error,
          error: size == 0 ? 'Audio file empty' : 'Audio file missing',
        );
        return;
      }
    }

    if (task.imagePath != null) {
      final file = File(task.imagePath!);
      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      debugPrint(
        '🔍 [VibeUpload] Image validation: exists=$exists, size=$size bytes, path=${task.imagePath}',
      );
    }

    try {
      debugPrint(
        '🚀 [VibeUpload] Handoff to VibeService for task ${task.id} (audioOnly=${task.isAudioOnly})',
      );

      final vibe = await _vibeService.sendBatchVibe(
        receiverIds: task.receiverIds, // Use the LIST
        audioFile: task.audioPath != null ? File(task.audioPath!) : null,
        audioDuration: task.audioDuration,
        waveformData: task.waveformData,
        imageFile: task.imagePath != null ? File(task.imagePath!) : null,
        videoFile: task.videoPath != null ? File(task.videoPath!) : null,
        isVideo: task.isVideo,
        isAudioOnly: task.isAudioOnly,
        isFromGallery: task.isFromGallery,
        originalPhotoDate: task.originalPhotoDate,
        replyToVibeId: task.replyToVibeId,
      );

      // sendBatchVibe returns bool success
      if (vibe) {
        debugPrint('✅ [VibeUpload] Final send success for task ${task.id}');
        // 🔄 REFRESH FIX: Invalidate dashboard providers so newly sent vibes appear
        _ref.invalidate(paginatedVibesProvider(true)); // Refresh Sent history
        _ref.invalidate(
          paginatedVibesProvider(false),
        ); // Refresh Received (rarely needed but safe)

        updateTaskStatus(task.id, VibeUploadStatus.success);

        // 🏁 COMPLETION FEEDBACK: Delay removal so UI can show "Sent!"
        Future.delayed(const Duration(seconds: 3), () => _removeTask(task.id));
      } else {
        // 🛑 FIX 1: Handle boolean failure with explicit throw
        updateTaskStatus(
          task.id,
          VibeUploadStatus.error,
          error: 'Failed to send',
        );
        Future.delayed(const Duration(seconds: 5), () => _removeTask(task.id));
        throw Exception('Server rejected upload');
      }
    } catch (e) {
      debugPrint('❌ [VibeUpload] Final send error for task ${task.id}: $e');

      // 🛑 FIX 2: Create User-Friendly Error Messages
      String userMessage = 'Failed to send';
      final errorStr = e.toString().toLowerCase();

      if (errorStr.contains('socketexception') ||
          errorStr.contains('unavailable') ||
          errorStr.contains('network') ||
          errorStr.contains('connection')) {
        userMessage = 'No internet connection';
      } else if (errorStr.contains('permission') ||
          errorStr.contains('denied')) {
        userMessage = 'Permission denied';
      } else if (errorStr.contains('timeout')) {
        userMessage = 'Request timed out';
      } else if (errorStr.contains('storage') || errorStr.contains('quota')) {
        userMessage = 'Storage limit reached';
      }

      updateTaskStatus(task.id, VibeUploadStatus.error, error: userMessage);
      Future.delayed(const Duration(seconds: 5), () => _removeTask(task.id));

      // 🛑 FIX 3: RETHROW so UI knows to show ❌ instead of ✅
      rethrow;
    }
  }

  void updateTaskStatus(String id, VibeUploadStatus status, {String? error}) {
    state = [
      for (final t in state)
        if (t.id == id) t.copyWith(status: status, error: error) else t,
    ];
    _saveQueue();
  }

  void _removeTask(String id) {
    _activeTasks.remove(id);

    final task = state.firstWhereOrNull((t) => t.id == id);
    if (task != null) {
      _cleanupFiles(task);
    }

    state = state.where((t) => t.id != id).toList();
    _saveQueue();
  }

  void _cleanupFiles(VibeUploadTask task) {
    // Delay cleanup slightly to ensure upload complete
    Future.delayed(const Duration(seconds: 2), () {
      if (task.videoPath != null) _deleteFile(task.videoPath!);
      if (task.imagePath != null) _deleteFile(task.imagePath!);
      if (task.overlayPath != null) _deleteFile(task.overlayPath!);
      if (task.audioPath != null) _deleteFile(task.audioPath!);
    });
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ [VibeUpload] Deleted temp file: $path');
      }
    } catch (e) {
      debugPrint('⚠️ [VibeUpload] Could not delete $path: $e');
    }
  }
}
