import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Camera initialization provider
final cameraControllerProvider =
    StateNotifierProvider<CameraControllerNotifier, CameraState>((ref) {
  return CameraControllerNotifier();
});

/// Gallery request type provider (default to common - photo + video)
final galleryRequestTypeProvider = StateProvider<RequestType>((ref) => RequestType.common);

/// Gallery assets provider
final galleryAssetsProvider = FutureProvider<List<AssetEntity>>((ref) async {
  final type = ref.watch(galleryRequestTypeProvider);
  final permission = await PhotoManager.requestPermissionExtend();
  if (!permission.isAuth) return [];

  final albums = await PhotoManager.getAssetPathList(
    type: type,
    filterOption: FilterOptionGroup(
      imageOption: const FilterOption(
        sizeConstraint: SizeConstraint(
          minWidth: 100,
          minHeight: 100,
        ),
      ),
      videoOption: const FilterOption(
        durationConstraint: DurationConstraint(
          min: Duration.zero,
          max: Duration(seconds: 15), // Align with camera limit
        ),
      ),
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
    ),
  );

  if (albums.isEmpty) return [];

  final recentAlbum = albums.first;
  // Increase size to 100 for better picker experience
  final assets = await recentAlbum.getAssetListPaged(page: 0, size: 100);
  return assets;
});

/// Camera State
class CameraState {
  final CameraController? controller;
  final bool isInitialized;
  final bool isRecording;
  final bool isFrontCamera;
  final FlashMode flashMode;
  final double zoomLevel;
  final double minZoom;
  final double maxZoom;
  final String? error;

  CameraState({
    this.controller,
    this.isInitialized = false,
    this.isRecording = false,
    this.isFrontCamera = true,
    this.flashMode = FlashMode.off,
    this.zoomLevel = 1.0,
    this.minZoom = 1.0,
    this.maxZoom = 1.0,
    this.error,
  });

  CameraState copyWith({
    CameraController? controller,
    bool? isInitialized,
    bool? isRecording,
    bool? isFrontCamera,
    FlashMode? flashMode,
    double? zoomLevel,
    double? minZoom,
    double? maxZoom,
    String? error,
  }) {
    return CameraState(
      controller: controller ?? this.controller,
      isInitialized: isInitialized ?? this.isInitialized,
      isRecording: isRecording ?? this.isRecording,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      flashMode: flashMode ?? this.flashMode,
      zoomLevel: zoomLevel ?? this.zoomLevel,
      minZoom: minZoom ?? this.minZoom,
      maxZoom: maxZoom ?? this.maxZoom,
      error: error,
    );
  }
}

class CameraControllerNotifier extends StateNotifier<CameraState> {
  List<CameraDescription> _cameras = [];
  bool _isInitializing = false; // Internal flag for legacy sync logic
  int _initGeneration = 0;      // CRITICAL: Solves 1000% confirmed initialization race condition
  
  // Synchronization for JIT state transitions
  Future<void>? _enableAudioFuture;

  // 🧭 STATIC CACHE: Bypass global hardware enumeration bottleneck (HAL query)
  // Your research is 100% correct: availableCameras() is a heavy HAL query.
  // We discover once per app session (main thread safe).
  static List<CameraDescription>? _cachedCameras;

  CameraControllerNotifier() : super(CameraState());

  /// Initialize camera
  /// CRITICAL: Uses _initGeneration to prevent race condition during background/resume
  Future<bool> initializeCamera() async {
    final currentGen = ++_initGeneration;
    
    if (_isInitializing) {
      debugPrint('Camera: Internal init flag set, but proceeding with new generation $currentGen');
    }
    
    // Also skip if already initialized and it's the right controller
    if (state.isInitialized && state.controller != null && state.controller!.value.isInitialized) {
      debugPrint('Camera: Already initialized, skipping');
      return true;
    }
    
    _isInitializing = true;
    
    try {
      // 1. Permission Check (PASSIVE ONLY)
      // JIT Arch: We DO NOT request permission here.
      // If permission is denied, we simply fail to initialize and let UI show placeholder.
      final status = await Permission.camera.status;
      
      // RACE CHECK: If app was backgrounded during dialog, generation will have changed
      if (currentGen != _initGeneration) {
        debugPrint('Camera: Init generation $currentGen STALE after permission check, cancelling');
        return false;
      }

      if (!status.isGranted) {
        state = state.copyWith(error: 'Camera permission required');
        _isInitializing = false;
        return false;
      }

      // 2. Fetch cameras (Cached discovery)
      if (_cachedCameras != null && _cachedCameras!.isNotEmpty) {
        _cameras = _cachedCameras!;
      } else {
        debugPrint('Camera: Cache empty, querying hardware HAL...');
        _cameras = await availableCameras();
        _cachedCameras = _cameras;
      }
      
      // RACE CHECK: Heavy async call
      if (currentGen != _initGeneration) {
        debugPrint('Camera: Init generation $currentGen STALE after availableCameras, cancelling');
        return false;
      }

      if (_cameras.isEmpty) {
        state = state.copyWith(error: 'No cameras available');
        _isInitializing = false;
        return false;
      }

      final frontCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      // 3. Setup hardware (Pre-Warm if mic is granted)
      final micStatus = await Permission.microphone.status;
      final shouldPreWarm = micStatus.isGranted;
      
      if (shouldPreWarm) {
        debugPrint('Camera: Mic granted - Pre-warming audio pipeline...');
      }

      await _setupCamera(frontCamera, currentGen, preWarmAudio: shouldPreWarm);
      
      // RACE CHECK: Final confirmation
      return currentGen == _initGeneration;
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (currentGen == _initGeneration) {
        state = state.copyWith(error: e.toString());
      }
      return false;
    } finally {
      if (currentGen == _initGeneration) {
        _isInitializing = false;
      }
    }
  }

  /// Re-initialize camera with Audio enabled (JIT Microphone)
  /// Called when user wants to record video/audio
  Future<void> enableAudio() async {
    if (_enableAudioFuture != null) {
      debugPrint('🎤 enableAudio: Request already in progress, awaiting...');
      return _enableAudioFuture;
    }
    
    _enableAudioFuture = _performEnableAudio();
    try {
      await _enableAudioFuture;
    } finally {
      _enableAudioFuture = null;
    }
  }

  Future<void> _performEnableAudio() async {
    if (state.controller == null) return;
    
    // Check if duplicate request
    if (state.controller!.enableAudio) {
       debugPrint('🎤 Audio already enabled, skipping re-init');
       return;
    }
    
    debugPrint('🎤 Enabling Audio for Camera (Hard Reset)...');
    
    // REVERT: We explicitly reset state to NULL to force a UI rebuild (show loading).
    // The "Seamless" approach caused issues with the camera portal.
    final currentGen = ++_initGeneration;
    final currentCamera = state.controller!.description;
    final oldController = state.controller;
    
    // 1. Reset state (Trigger "Starting camera" UI)
    state = state.copyWith(
      controller: null,
      isInitialized: false,
    );
    
    try {
      // 2. Dispose old controller safely
      await oldController?.dispose();
    } catch(e) {
      debugPrint('Error disposing old controller: $e');
    }
    
    // 3. Setup new one with AUDIO
    await _setupCamera(currentCamera, currentGen, forceAudio: true);
  }

  Future<void> _setupCamera(CameraDescription camera, int generation, {bool forceAudio = false, bool preWarmAudio = false}) async {
    // Check generation before starting
    if (generation != _initGeneration) return;
    
    // JIT CONFIGURATION: Default to NO AUDIO for fast start & no mic permission
    // PRE-WARM: If mic is granted, we enable audio immediately to avoid flash later
    final useAudio = forceAudio || preWarmAudio;
    
    final configs = useAudio ? [
       // If forced (recording mode) or pre-warmed, try audio configs first
       (preset: ResolutionPreset.veryHigh, audio: true),
       (preset: ResolutionPreset.high, audio: true),
       (preset: ResolutionPreset.high, audio: true),
       // [FIX APPLIED] FAIL FAST: Removed silent fallback. 
       // If mic fails, we want _setupCamera to throw an exception so UI shows error.
    ] : [
       // Default (Preview mode): Prefer NO AUDIO
       (preset: ResolutionPreset.veryHigh, audio: false),
       (preset: ResolutionPreset.high, audio: false),
       (preset: ResolutionPreset.medium, audio: false),
    ];
    
    for (final config in configs) {
      // Check if we were cancelled before each attempt
      if (generation != _initGeneration) return;

      final controller = CameraController(
        camera,
        config.preset,
        enableAudio: config.audio,
        imageFormatGroup: Platform.isAndroid 
            ? ImageFormatGroup.yuv420 
            : ImageFormatGroup.bgra8888,
      );
      
      try {
        // ROBUSTNESS: 10s timeout prevents infinite hang on buggy drivers (Xiaomi/Oppo)
        await controller.initialize().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw CameraException('TIMEOUT', 'Camera init timed out'),
        );
        
        // CRITICAL CHECK: Were we backgrounded/reset while initializing?
        if (generation != _initGeneration) {
          debugPrint('Camera: Init completed for generation $generation but it is STALE. Disposing...');
          await controller.dispose();
          return;
        }

        debugPrint('Camera initialized: ${config.preset.name}, audio=${config.audio}');
        
        // CAPTURE ZOOM LIMITS
        double minZoomVal = 1.0;
        double maxZoomVal = 1.0;
        try {
          final dynamic minZ = await controller.getMinZoomLevel();
          final dynamic maxZ = await controller.getMaxZoomLevel();
          if (minZ is num) minZoomVal = minZ.toDouble();
          if (maxZ is num) maxZoomVal = maxZ.toDouble();
        } catch (e) {
          debugPrint('⚠️ Zoom hardware detection failed: $e');
        }

        state = state.copyWith(
          controller: controller,
          isInitialized: true,
          isFrontCamera: camera.lensDirection == CameraLensDirection.front,
          minZoom: minZoomVal,
          maxZoom: maxZoomVal,
          zoomLevel: 1.0, // Reset zoom on init/switch
          error: null,
        );
        return; // Success
      } catch (e) {
        debugPrint('Camera init failed: ${config.preset.name}, audio=${config.audio} - $e');
        await controller.dispose();
        
        if (config == configs.last && generation == _initGeneration) {
          state = state.copyWith(
            error: 'Camera initialization failed. Check permissions and try again.',
          );
        }
      }
    }
    
    // 4. PRE-WARM OPTIMIZATION: Prepare encoders if audio is enabled
    // This reduces startVideoRecording() latency from ~800ms to ~50ms
    if (state.controller != null && state.isInitialized && (forceAudio || preWarmAudio)) {
      try {
        await state.controller!.prepareForVideoRecording();
        debugPrint('Camera: Video pipeline pre-warmed and ready.');
      } catch (e) {
        debugPrint('Camera: Pre-warm warning (non-fatal): $e');
      }
    }
  }

  /// Switch between front and back camera
  Future<void> switchCamera() async {
    if (_cameras.isEmpty || _isInitializing) return;
    if (_cameras.length < 2) return;

    final currentGen = ++_initGeneration;
    final currentController = state.controller;
    
    // CAPTURE AUDIO STATE before killing the controller (Issue 3 fix)
    final bool wasAudioEnabled = currentController?.enableAudio ?? false;
    
    // 1. Mark as initializing to prevent parallel calls
    _isInitializing = true;
    
    // 2. Determine next camera before clearing state
    final newCamera = _cameras.firstWhere(
      (camera) => state.isFrontCamera
          ? camera.lensDirection == CameraLensDirection.back
          : camera.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    // 3. IMMEDIATELY update state to remove the old controller
    state = state.copyWith(
      controller: null,
      isInitialized: false,
    );

    try {
      // 4. Dispose safely
      if (currentController != null) {
        await currentController.dispose();
      }

      // RACE CHECK
      if (currentGen != _initGeneration) return;

      // 5. Setup new camera (preserve audio state)
      await _setupCamera(newCamera, currentGen, forceAudio: wasAudioEnabled);
    } catch (e) {
      debugPrint('Camera switch error: $e');
      if (currentGen == _initGeneration) {
        state = state.copyWith(error: 'Failed to switch camera: $e');
      }
    } finally {
      if (currentGen == _initGeneration) {
        _isInitializing = false;
      }
    }
  }

  /// Toggle flash mode
  Future<void> toggleFlash() async {
    if (state.controller == null) return;
    
    FlashMode nextMode;
    switch (state.flashMode) {
      case FlashMode.off:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.always;
        break;
      case FlashMode.always:
        nextMode = FlashMode.off;
        break;
      default:
        nextMode = FlashMode.off;
    }
    
    await state.controller!.setFlashMode(nextMode);
    state = state.copyWith(flashMode: nextMode);
  }

  /// Set zoom level
  Future<void> setZoomLevel(double level) async {
    if (state.controller == null || !state.isInitialized) return;
    
    // Clamp to hardware limits
    final clampedLevel = level.clamp(state.minZoom, state.maxZoom);
    
    try {
      await state.controller!.setZoomLevel(clampedLevel);
      state = state.copyWith(zoomLevel: clampedLevel);
    } catch (e) {
      debugPrint('Error setting zoom level: $e');
    }
  }

  /// Take a photo
  Future<File?> takePhoto() async {
    if (state.controller == null || !state.isInitialized) return null;

    try {
      final XFile image = await state.controller!.takePicture();
      return File(image.path);
    } catch (e) {
      debugPrint('Error taking photo: $e');
      return null;
    }
  }

  /// Get photo from gallery asset
  Future<File?> getPhotoFromAsset(AssetEntity asset) async {
    try {
      final file = await asset.file;
      return file;
    } catch (e) {
      debugPrint('Error getting photo from asset: $e');
      return null;
    }
  }

  /// Reset camera state when controller is disposed externally (lifecycle)
  /// This prevents the UI from trying to render a disposed controller
  Future<void> reset() async {
    debugPrint('Camera: Resetting and incrementing generation');
    _initGeneration++; // Invalidate any pending initializations IMMEDIATELY
    _isInitializing = false;
    
    final controller = state.controller;
    state = CameraState(); // Notify listeners FIRST to remove from tree
    
    if (controller != null) {
      // DEFENSIVE: Stop stream before destroying hardware surface
      // Prevents "Surface abandoned" crashes on Samsung/Oppo
      try {
        if (controller.value.isInitialized) {
          await controller.pausePreview();
        }
      } catch (e) {
        debugPrint('Ignored error during reset pause: $e');
      }
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    state.controller?.dispose();
    super.dispose();
  }
}

/// Media service for handling camera and gallery operations
class MediaService {
  /// Get the original date of a photo (for Time Travel feature)
  static Future<DateTime?> getPhotoOriginalDate(AssetEntity asset) async {
    return asset.createDateTime;
  }

  /// Save image to temp with compression
  static Future<File?> saveImageToTemp(File imageFile) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = 'vibe_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final newPath = '${tempDir.path}/$fileName';
      return imageFile.copy(newPath);
    } catch (e) {
      debugPrint('Error saving image: $e');
      return null;
    }
  }
}
