import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/services/media_service.dart';
import 'package:nock/core/services/audio_service.dart';
import 'package:nock/core/services/native_service_helper.dart';
import 'package:nock/core/services/auth_service.dart';  // For user avatar in audio-only mode
import 'package:nock/core/services/vibe_service.dart';  // For direct send
import 'package:nock/shared/widgets/aura_visualization.dart';  // For consistent audio visualization
import 'package:nock/shared/widgets/glass_container.dart' as glass;  // For CircularLuminousBorderPainter (prefixed to avoid conflict)
import 'package:nock/features/squad/presentation/squad_screen.dart';  // For friendsProvider
import 'package:nock/core/models/vibe_model.dart';  // For reply context
import 'package:nock/core/providers/vibe_upload_provider.dart';
import 'package:nock/core/models/user_model.dart';  // For Smart Send Sheet friend types

// Extracted models, painters, services and widgets for better code organization
import 'package:nock/features/camera/domain/models/camera_models.dart';
import 'package:nock/features/camera/presentation/painters/camera_painters.dart';
import 'package:nock/features/camera/domain/services/video_processing_service.dart';
import 'package:nock/features/camera/presentation/widgets/camera_buttons.dart';
import 'package:nock/features/camera/presentation/widgets/waveform_visualizer.dart';
import 'package:nock/features/camera/presentation/widgets/smart_send_sheet.dart';
import 'package:nock/features/camera/presentation/widgets/edit_tools_overlay.dart';
import 'package:nock/features/camera/presentation/widgets/camera_portal_view.dart';
import 'package:nock/features/camera/presentation/widgets/bioluminescent_orb.dart'; // V2 Orb
import 'package:nock/core/services/viral_video_service.dart';  // Single source of truth for media operations

// NOTE: The following are now imported from camera_models.dart:
// - EditMode enum
// - DrawingStroke class  
// - StickerOverlay class
// - TextFontStyle enum + extension
// - TextOverlay class


/// NoteIt-style Camera Screen with INLINE editing
/// 
/// 2025 UX: 
/// - No duplicate buttons for navigation (gestures only)
/// - Vault/Memories accessible via bottom button -> modal sheet
/// - Settings via profile icon -> modal sheet
class CameraScreenNew extends ConsumerStatefulWidget {
  const CameraScreenNew({
    super.key,
    this.onOpenVault,
    this.onOpenSettings,
    this.onDrawingModeChanged,
    this.onCaptureStateChanged,
    this.isVisible = true,
    this.isAudioOnly = false,
    this.recipientId,
    this.replyTo,
  });

  final VibeModel? replyTo;
  final String? recipientId;
  final bool isAudioOnly;

  final VoidCallback? onOpenVault;
  final VoidCallback? onOpenSettings;
  final ValueChanged<bool>? onDrawingModeChanged;
  /// Called when capture state changes (recording, captured, or back to idle)
  /// True = active state (recording or captured), False = idle initial state
  final ValueChanged<bool>? onCaptureStateChanged;

  /// Visibility status from parent (e.g. PageView)
  final bool isVisible;

  @override
  ConsumerState<CameraScreenNew> createState() => _CameraScreenNewState();
}

class _CameraScreenNewState extends ConsumerState<CameraScreenNew>
    with WidgetsBindingObserver, TickerProviderStateMixin, AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true; // 🧭 CRITICAL: Prevent destruction on PageView swipe
  
  // Capture state
  File? _capturedImage;
  File? _capturedVideo;
  bool _isRecordingVideo = false;
  DateTime? _recordingActualStartTime; // Track valid capture duration
  
  // Ghost Recording Synchronization
  // Allows background tasks (like Direct Send) to wait for hardware to finish
  Completer<void>? _ghostRecordingCompleter;
  
  bool get _hasCaptured => _capturedImage != null || _capturedVideo != null || (_isAudioOnlyMode && _recordedAudioFile != null);
  
  // Video preview player
  VideoPlayerController? _videoPreviewController;
  bool _isVideoPreviewReady = false;
  
  // Front camera selfie tracking (for mirroring preview)
  bool _wasFrontCamera = false;
  
  // Inline editing state
  EditMode _currentEditMode = EditMode.none;
  final List<DrawingStroke> _drawingStrokes = [];
  // PERFORMANCE FIX: Use ValueNotifier to avoid full screen rebuilds on drag
  final ValueNotifier<List<Offset>> _currentStrokeNotifier = ValueNotifier([]);
  // PERFORMANCE FIX: Use ValueNotifier for Stickers
  final ValueNotifier<List<StickerOverlay>> _stickersNotifier = ValueNotifier([]);
  // PERFORMANCE FIX: Use ValueNotifier for Text Overlays
  final ValueNotifier<List<TextOverlay>> _textOverlaysNotifier = ValueNotifier([]);
  int? _selectedStickerIndex;
  int? _selectedTextIndex;
  
  // Drawing options
  Color _currentDrawColor = Colors.white;
  double _currentStrokeWidth = 5.0;
  
  // Audio recording state  
  File? _recordedAudioFile;
  int _audioDuration = 0;
  bool _isRecordingAudio = false;
  
  // 0: Camera (default), 1: Dashboard (swipe up)
  final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;
  
  // FIX: Edge Guard + Drawing Mode Lock for Gesture Conflict
  ScrollPhysics _pagePhysics = const BouncingScrollPhysics(parent: PageScrollPhysics());
  bool _isDrawingMode = false; // Locks page swipe when camera is in drawing mode
  
  // 2026 UX: Main Send Button Feedback State (Spinner -> Checkmark)
  bool _isMainSendLoading = false;
  bool _showMainSendCheckmark = false;

  bool _isCameraActive = false; // Hides history indicator when camera is recording/captured
  Timer? _statusHeartbeat; // Heartbeat to keep user online
  StreamSubscription? _widgetClickedSubscription; // FIX: Memory Leak - Store for cancellation
  
  // Audio-Only Mode State
  bool _isAudioOnlyMode = false;
  bool _isMicPermissionGranted = false;
  
  // Text Editing State
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  bool _isEditingText = false;
  TextFontStyle _currentFontStyle = TextFontStyle.classic;
  double _currentTextSize = 28.0;

  // Camera Curtain Animation (Smooth Black Transition)
  bool _showCurtain = false;
  Timer? _curtainTimer;


  // Pre-Selection State (2026 UX: Select recipients BEFORE capture)
  // When user taps Face Pile and selects friends, IDs are stored here.
  // Send button checks this first for instant send.
  Set<String> _preSelectedRecipientIds = {};
  
  // Storage Key for persistence
  static const String _preSelectedFriendsKey = 'camera_pre_selected_friends';

  /// Load pre-selected friends from storage (restore previous session)
  Future<void> _loadPreSelectedFriends() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedList = prefs.getStringList(_preSelectedFriendsKey);
      if (savedList != null && savedList.isNotEmpty && mounted) {
        setState(() {
          _preSelectedRecipientIds = savedList.toSet();
        });
      }
    } catch (e) {
      debugPrint('Error loading pre-selected friends: $e');
    }
  }

  
  // Capture key for exporting
  // 🧭 STABILITY FIX: Use LabeledGlobalKey for identifying the portal in the tree
  final GlobalKey _captureKey = LabeledGlobalKey('CameraPortalKey');
  
  // Gesture State (Listener-based for precise control)
  DateTime? _pointerDownTime;
  Timer? _longPressTimer;
  static const Duration _tapThreshold = Duration(milliseconds: 500); // 500ms for deliberate tap
  
  // Zoom State (Snapchat Slide)
  double _dragStartY = 0;
  double _baseZoom = 1.0;
  double _initialScaleZoom = 1.0; // For pinch-to-zoom (Portal Scale)
  
  // State guards
  bool _isProcessingCapture = false;
  bool _isFromGallery = false;
  
  // HUD / Telemetry state
  Offset? _focusPoint;
  bool _showFocusReticle = false;
  Timer? _focusTimer;
  
  // Animation controllers
  late AnimationController _shutterController;
  late Animation<double> _shutterAnimation;
  late AnimationController _recordingProgressController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  static const int maxRecordingDuration = 15;
  
  // Colors for UI (Luminescent - True Black)
  static const List<Color> _backgroundGradient = [
    AppColors.background,
    AppColors.background,
  ];
  
  // Drawing colors (Luminescent Palette)
  static const List<Color> _drawColors = [
    Color(0xFFF0F0F0), // Ghost White
    Color(0xFF39FF14), // Acid Green
    Color(0xFF00F0FF), // Electric Cyan
    Color(0xFFFF2A6D), // Glitch Red
    Color(0xFF00FF9F), // Spring Green
    Color(0xFF586069), // Gunmetal Grey
    Colors.black,
  ];
  
  // Sticker emoji sets
  static const List<String> _stickerEmojis = [
    '😀', '😂', '🥰', '😍', '🤩', '😎', '🥳', '😜', '🤪', '😇',
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '💕', '💖', '💝',
    '👍', '👎', '👌', '✌️', '🤞', '🤟', '👏', '🙌', '💪', '🔥',
    '⭐', '✨', '🌟', '💫', '🎉', '🎊', '🎈', '🎁', '🏆', '🥇',
  ];

  /// Helper to switch modes and notify parent (Fix 1: Gesture Conflict)
  void _changeEditMode(EditMode mode) {
    setState(() => _currentEditMode = mode);
    
    // Notify parent to lock/unlock scrolling
    final bool isInteractive = mode == EditMode.draw || mode == EditMode.text;
    widget.onDrawingModeChanged?.call(isInteractive);

    if (mode == EditMode.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tap anywhere on the photo to add text'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.black87,
        ),
      );
    }
  }
  
  /// Helper to notify HomeScreen about capture state for history indicator visibility
  /// isActive = true when actively recording or has captured content
  void _notifyCaptureState() {
    final isActive = _isRecordingVideo || _isRecordingAudio || _hasCaptured;
    widget.onCaptureStateChanged?.call(isActive);
  }

  /// Fix 2: Tap-to-Place Text Logic
  void _addTextAtPosition(Offset position) {
    final newText = TextOverlay(
      text: '',
      position: position,
      color: _currentDrawColor,
      fontStyle: _currentFontStyle,
      fontSize: _currentTextSize,
    );
    
    final currentTexts = List<TextOverlay>.from(_textOverlaysNotifier.value);
    currentTexts.add(newText);
    _textOverlaysNotifier.value = currentTexts;

    setState(() {
      _selectedTextIndex = _textOverlaysNotifier.value.length - 1;
      _isEditingText = true;
      // Also ensure we are in text mode
      _currentEditMode = EditMode.text;
    });
    // Give focus immediately
    _textFocusNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _isAudioOnlyMode = widget.isAudioOnly;
    WidgetsBinding.instance.addObserver(this);
    
    // Restore pre-selected friends from persistence
    _loadPreSelectedFriends();
    
    // PERMISSION OPTIMIZATION: Only initialize camera if NOT in audio-only mode.
    // This follows App Store Guideline 5.1.1 by not requesting camera permission
    // for a feature that doesn't need it.
    if (widget.isVisible && !_isAudioOnlyMode) {
      _initializeCamera();
    } else if (_isAudioOnlyMode) {
      _checkMicPermission();
    }

    
    _shutterController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _shutterAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _shutterController, curve: Curves.easeInOut),
    );
    
    _recordingProgressController = AnimationController(
      duration: Duration(seconds: maxRecordingDuration),
      vsync: this,
    );
    _recordingProgressController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _isRecordingVideo) {
        _stopVideoRecording();
      }
    });
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // FIX Issue 1: Check for pending video from interrupted recording
    _recoverPendingVideo();
  }
  
  /// FIX Issue 1: Recover video if app was killed during backgrounding
  Future<void> _recoverPendingVideo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingPath = prefs.getString('pending_video_path');
      if (pendingPath != null && pendingPath.isNotEmpty) {
        final file = File(pendingPath);
        if (await file.exists()) {
          debugPrint('Recovered pending video: $pendingPath');
          if (mounted) {
            setState(() {
              _capturedVideo = file;
              _isRecordingVideo = false;
            });
            _initializeVideoPreview(pendingPath, ++_initGeneration);
          }
        }
        // Clear the pending path after recovery attempt
        await prefs.remove('pending_video_path');
      }
    } catch (e) {
      debugPrint('Error recovering pending video: $e');
    }
  }

  Future<void> _initializeCamera() async {
    // 1. RESOURCE ARBITRATION: Force stop the background service to free the Mic
    // This prevents the infinite "Starting Camera..." hang on Android.
    await NativeServiceHelper.stopBackgroundService();
    
    // REFACTOR: Removed time-based "BUFFER" (Future.delayed).
    // We now rely on the CameraControllerNotifier's strict `_initGeneration` logic
    // to handle hardware locking state deterministically.

    final success = await ref.read(cameraControllerProvider.notifier).initializeCamera();
    
    // IF PERMISSION MISSING: It will now fail with error 'Camera permission required'
    // We handle that in build() by checking cameraState.error
    
    // 3. State-Based UI Transition
    if (mounted) {
      if (success) {
         // Immediate reliable transition
         setState(() => _showCurtain = false);
      } else {
         // Even if failed, lift curtain to show the Error UI (provided by CameraState.error)
         setState(() => _showCurtain = false);
      }
    }
  }

  Future<void> _checkMicPermission() async {
    final status = await Permission.microphone.status;
    if (mounted) {
      setState(() {
        _isMicPermissionGranted = status.isGranted;
      });
    }
  }


  /// Intelligent camera resumption logic
  /// Cold boots the camera if it was disposed (e.g. after backgrounding)
  /// or simply resumes the preview if it was paused.
  Future<void> _resumeCamera() async {
    final cameraState = ref.read(cameraControllerProvider);
    if (cameraState.controller == null || !cameraState.isInitialized) {
      debugPrint('📸 Camera was disposed/uninitialized, performing cold boot...');
      await _initializeCamera();
    } else {
      debugPrint('📸 Resuming active camera preview...');
      try {
        // [FIX APPLIED] SAFE RESUME: Wrap in try-catch.
        // If hardware was disconnected, catch error and force full re-init.
        await cameraState.controller?.resumePreview();
        // FIX Issue 2: Ensure curtain is lifted if it was shown during pause/transition
        if (mounted && _showCurtain) {
          setState(() => _showCurtain = false);
        }
      } catch (e) {
        debugPrint('❌ Warm boot failed (Hardware disconnected): $e');
        debugPrint('🔄 Falling back to Cold Boot...');
        await _initializeCamera();
      }
    }
  }

  @override
  void didUpdateWidget(CameraScreenNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 🧭 DEFINITIVE FIX: Warm Boot Refactoring
    // Instead of killing the sensor (reset), we use Standby mode (pausePreview).
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        debugPrint('📸 Camera: Visibility restored. Checking mode...');
        if (!_isAudioOnlyMode) {
          _resumeCamera();
        } else {
          _checkMicPermission();
        }
      } else {
        // [FIX APPLIED] STOP THE VAMPIRE: Pause hardware when swiping away.
        // This stops the green dot (on some devices) and saves massive battery.
        debugPrint('📸 Camera: Widget hidden. Pausing preview to save battery.');
        ref.read(cameraControllerProvider).controller?.pausePreview();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    // 1. App Paused or Inactive: Safe Lifecycle Management
    // Trigger on inactive (earlier) to gain extra milliseconds on iOS
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (mounted) setState(() => _showCurtain = true);
      
      // STOP PLAYBACK IMMEDIATELY to prevent "Zombie Audio"
      ref.read(audioServiceProvider).stop();
      
      final cameraState = ref.read(cameraControllerProvider);
      final controller = cameraState.controller;
      
      // TRACK AND RELEASE ALL HARDWARE CONCURRENTLY
      final List<Future<dynamic>> stopFutures = [];
      
      // A. Video Stop Future - with crash recovery save
      if (controller != null && controller.value.isInitialized && controller.value.isRecordingVideo) {
        final videoFuture = controller.stopVideoRecording().then((videoFile) async {
          // FIX Issue 1: Save to SharedPreferences IMMEDIATELY, before mounted check
          // This ensures the path persists even if OS kills the app mid-callback
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('pending_video_path', videoFile.path);
            debugPrint('Video path saved for recovery: ${videoFile.path}');
          } catch (e) {
            debugPrint('Error saving video path to prefs: $e');
          }
          
          // Then update UI state if still mounted
          if (mounted) {
            setState(() {
              _capturedVideo = File(videoFile.path);
              _isRecordingVideo = false;
            });
            debugPrint('Video saved during app pause: ${videoFile.path}');
          }
        }).catchError((e) {
          debugPrint('Error stopping video recording during pause: $e');
        });
        stopFutures.add(videoFuture);
      }
      
      // B. Audio Stop Future
      if (_isRecordingAudio) {
        final audioFuture = ref.read(recordingStateProvider.notifier).stopRecording().then((path) {
          if (mounted) {
            if (path != null) {
              final timerDuration = ref.read(recordingDurationProvider);
              setState(() {
                _isRecordingAudio = false;
                _recordedAudioFile = File(path);
                _audioDuration = timerDuration > 0 ? timerDuration : 1;
              });
              debugPrint('Audio recording SAVED during app pause: $path');
            } else {
              setState(() {
                _isRecordingAudio = false;
                _recordedAudioFile = null;
                _audioDuration = 0;
              });
            }
          }
        }).catchError((e) {
          debugPrint('Error stopping audio recording during pause: $e');
        });
        stopFutures.add(audioFuture);
      }
      
      // Fire both immediately; only await if they exist
      if (stopFutures.isNotEmpty) {
        await Future.wait(stopFutures);
      }
      
      // C. Safe state reset via notifier (handles disposal and cancellation)
      if (mounted) {
        ref.read(cameraControllerProvider.notifier).reset();
      }
    } 
    // 2. App Resumed: Init camera BEHIND curtain (ONLY if no capture exists)
    else if (state == AppLifecycleState.resumed) {
      // If we have a captured video from interruption, show preview
      if (_capturedVideo != null && !_isVideoPreviewReady) {
        _initializeVideoPreview(_capturedVideo!.path, ++_initGeneration);
      }
      
      if (!_hasCaptured && !_isAudioOnlyMode) {
        _initializeCamera();
      } else {
        // [FIX] AUDIO MODE PERMISSION TRAP
        // If we are in Audio Mode, we MUST re-check permissions on resume.
        // Otherwise, if user went to Settings -> Granted -> Returned, UI stays stuck.
        if (_isAudioOnlyMode) {
          _checkMicPermission();
        }

        // If we have a capture or are in audio-only mode, ensure curtain is lifted immediately
        if (mounted) {
          setState(() => _showCurtain = false);
        }
      }
    }
}

  @override
  void dispose() {
    _currentStrokeNotifier.dispose(); // Dispose notifier
    _stickersNotifier.dispose();
    _textOverlaysNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _shutterController.dispose();
    _recordingProgressController.dispose();
    _pulseController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    _curtainTimer?.cancel();
    _longPressTimer?.cancel();
    _disposeVideoPreview();
    
    // 🧭 RELEASE HARDWARE: Only when navigating away from the screen entirely
    try {
      // Use a final check to avoid Bad state: Cannot use "ref" after the widget was disposed.
      // In some edge cases, disposal happens so fast that ref is gone before this line.
      if (mounted) {
        ref.read(cameraControllerProvider.notifier).reset();
      }
    } catch (e) {
       debugPrint('Camera: Hardware release bypassed (already disposed)');
    }
    
    super.dispose();
  }


  // ============ CAPTURE METHODS ============


  Future<void> _takePhoto() async {
    // PREVENT CONCURRENT CAPTURE
    if (_isProcessingCapture) return;
    
    // GESTURE SAFEGUARD: If we are recording a video, a tap should be ...
    if (_isRecordingVideo) {
      debugPrint('📸 _takePhoto blocked: Already recording video. Redirecting to stop.');
      _stopVideoRecording();
      return;
    }

    _isProcessingCapture = true;
    HapticFeedback.mediumImpact();
    _shutterController.forward().then((_) {
      if (mounted) _shutterController.reverse();
    });

    final cameraState = ref.read(cameraControllerProvider);
    final cameraNotifier = ref.read(cameraControllerProvider.notifier);
    
    try {
      final photo = await cameraNotifier.takePhoto();
      
      if (photo != null && mounted) {
        setState(() {
          _capturedImage = photo;
          _capturedVideo = null;
          _wasFrontCamera = cameraState.isFrontCamera; // Track camera for mirror
          _clearAllOverlays();
        });
        // Stop the sensor to kill the Green Dot when previewing capture
        await cameraState.controller?.pausePreview();
        
        _notifyCaptureState(); // Hide history indicator
      }
    } catch (e) {
      debugPrint('❌ Photo capture error: $e');
    } finally {
      if (mounted) setState(() => _isProcessingCapture = false);
    }
  }

  Future<void> _startVideoRecording() async {
    if (_isProcessingCapture) {
      debugPrint('⚠️ _startVideoRecording blocked: Capture already in progress');
      return;
    }
    
    final cameraState = ref.read(cameraControllerProvider);
    if (cameraState.controller == null || !cameraState.isInitialized) {
      debugPrint('⚠️ Cannot record: Camera not initialized');
      if (mounted) setState(() => _isProcessingCapture = false);
      return;
    }
    
    // Prevent double start
    if (_isRecordingVideo || cameraState.controller!.value.isRecordingVideo) {
      debugPrint('⚠️ Already recording video, ignoring start request');
      if (mounted) setState(() => _isProcessingCapture = false);
      return;
    }
    
    _isProcessingCapture = true;
    HapticFeedback.heavyImpact();
    
    // FIX: Stop any active audio playback before starting video recording
    ref.read(audioServiceProvider).stop();
    
    setState(() => _isRecordingVideo = true);
    _notifyCaptureState(); // Hide history indicator
    
    _recordingProgressController.reset();
    _recordingProgressController.forward();
    _pulseController.repeat(reverse: true);
    
    try {
      debugPrint('🎥 Starting video recording...');
      
      // JIT MICROPHONE PERMISSION
      // 1. Check/Request Mic Permission
      var micStatus = await Permission.microphone.status;
      if (micStatus.isDenied || micStatus.isRestricted) {
         debugPrint('🎤 Requesting mic permission JIT...');
         
         // Pause preview/UI if needed (optional)
         micStatus = await Permission.microphone.request();
         if (!micStatus.isGranted) {
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Microphone needed for video audio')),
             );
           }
         }
      }
      
      // 2. Re-initialize with Audio if granted
      if (micStatus.isGranted) {
        await ref.read(cameraControllerProvider.notifier).enableAudio();
      }
      
      // 3. IMPORTANT: Refresh cameraState to get the NEW controller after enableAudio()
      final freshState = ref.read(cameraControllerProvider);
      
      // Safety check: Ensure we still have a valid controller
      if (freshState.controller == null || !freshState.isInitialized) {
        debugPrint('❌ Recording aborted: New camera controller failed to initialize');
        throw CameraException('InitializationFailure', 'New controller failed to initialize');
      }

      // Initialize ghost synchronization
      _ghostRecordingCompleter = Completer<void>();
      
      // Safety Check: If the user released their finger while we were async-initializing,
      // then _isRecordingVideo will have been set to false by _handlePointerUp.
      if (!_isRecordingVideo) {
        debugPrint('⏹️ Recording aborted: User released finger during hardware init');
        if (mounted) setState(() => _isProcessingCapture = false);
        _ghostRecordingCompleter?.complete();
        return;
      }

      // 4. Start Recording on the NEW controller
      await freshState.controller!.startVideoRecording();
      _recordingActualStartTime = DateTime.now(); // Track when it actually starts
      debugPrint('✅ Video recording started at $_recordingActualStartTime');
      
      // FIX: Check if stop was requested while we were starting
      if (!_isRecordingVideo) {
        debugPrint('⏹️ Stop requested during start sequence - stopping hardware immediately');
        await _ghostStopHardware();
      }
    } catch (e) {
      debugPrint('❌ Error starting video recording: $e');
      if (mounted) {
        setState(() {
          _isRecordingVideo = false;
          _isProcessingCapture = false;
        });
        _recordingProgressController.reset();
        _pulseController.stop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: ${e.toString().split(":").last}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// The "Ghost Thread": Finishes hardware recording in the background
  /// while the UI is already responsive and interactive.
  Future<void> _ghostStopHardware() async {
    if (_isStoppingVideo) return;
    _isStoppingVideo = true;
    
    debugPrint('👻 Ghost Mode: Finalizing hardware recording...');
    
    final cameraState = ref.read(cameraControllerProvider);
    final controller = cameraState.controller;

    try {
      if (controller == null || !controller.value.isRecordingVideo) {
         debugPrint('👻 Ghost Mode: Hardware not recording, skipping stop.');
         if (mounted) {
           setState(() {
             _isProcessingCapture = false;
             _isRecordingVideo = false;
           });
         }
         if (_ghostRecordingCompleter != null && !_ghostRecordingCompleter!.isCompleted) {
            _ghostRecordingCompleter?.complete();
         }
         return;
      }

      // 1. HARDWARE SAFETY BUFFER (Competitive baseline: 800ms)
      // MP4 headers on many Android/iOS hardware require a minimum bitstream
      if (_recordingActualStartTime != null) {
        final elapsed = DateTime.now().difference(_recordingActualStartTime!);
        if (elapsed < const Duration(milliseconds: 800)) {
          final pad = const Duration(milliseconds: 800) - elapsed;
          debugPrint('👻 Ghost Padding hardware for ${pad.inMilliseconds}ms...');
          await Future.delayed(pad);
        }
      }

      // 2. STOP HARDWARE
      final XFile videoFile = await controller.stopVideoRecording();
      final videoPath = videoFile.path;
      final file = File(videoPath);
      
      // 3. VALIDATION
      if (!file.existsSync() || file.lengthSync() < 1000) {
         // Discard silently if it's garbage
         debugPrint('👻 Ghost Discard: File too small or missing (${file.lengthSync()} bytes)');
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Hold longer to record video')),
           );
         }
         throw Exception('Ghost clip too short');
      }

      debugPrint('✅ Ghost Success: $videoPath (${file.lengthSync()} bytes)');

      if (mounted) {
        setState(() {
          _isProcessingCapture = false;
          _capturedVideo = file;
          _capturedImage = null;
          _wasFrontCamera = cameraState.isFrontCamera;
        });

        // Kill green dot sensor
        await controller.pausePreview();
        _notifyCaptureState();

        // 4. INITIALIZE PREVIEW (Generation check handles concurrency)
        _initGeneration++;
        await _initializeVideoPreview(videoPath, _initGeneration);
      }
    } catch (e) {
      debugPrint('❌ Ghost Hardware Error: $e');
      if (mounted) {
        setState(() {
          _isProcessingCapture = false;
          _capturedVideo = null;
        });
      }
    } finally {
      _isStoppingVideo = false;
      if (_ghostRecordingCompleter != null && !_ghostRecordingCompleter!.isCompleted) {
        _ghostRecordingCompleter!.complete();
      }
    }
  }

  bool _isStoppingVideo = false;
  int _initGeneration = 0; // FIX: Prevent stale preview initializations

  Future<void> _stopVideoRecording() async {
    // Legacy wrapper for Ghost Mode
    if (_isRecordingVideo) {
      setState(() => _isRecordingVideo = false);
      _recordingProgressController.stop();
      _pulseController.stop();
    }
    
    await _ghostStopHardware();
  }
  
  /// Initialize video preview player for looping playback
  Future<void> _initializeVideoPreview(String path, int generation) async {
  // 1. Dispose existing if any
  await _videoPreviewController?.dispose();
  
  // 2. Create LOCALLY first
  final newController = VideoPlayerController.file(File(path));
  
  try {
    // 3. Initialize the LOCAL variable with timeout to prevent infinite hang
    await newController.initialize().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('Video initialization timed out');
      },
    );
    
    // 4. Critical Safety Check:
    // If widget was disposed or controller changed while we waited, abort.
    // ALSO check if generation matches to prevent stale init
    if (!mounted || _initGeneration != generation) {
      newController.dispose(); // Clean up the orphan
      return;
    }
    
    // FIX #2: Check if user tapped Retake while we were initializing
    // If _capturedVideo is now null, user discarded the video - abort
    if (_capturedVideo == null) {
      newController.dispose(); // Clean up the orphan
      debugPrint('Video preview aborted: user discarded video during init');
      return;
    }

    await newController.setLooping(true);
    await newController.setVolume(1.0); // Ensure sound is on
    
    // 5. Only now assign to state and play
    setState(() {
      _videoPreviewController = newController;
      _isVideoPreviewReady = true;
    });
    
    // 6. Final safety play - some Android devices need a frame delay
    // to initialize the surface before playback begins
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted && _videoPreviewController == newController) {
      await newController.play();
    }
    
  } catch (e) {
    debugPrint('Error initializing video preview: $e');
    // Important: Dispose the local controller on error to prevent leaks
    newController.dispose();
    
    // FIX: Prevent infinite "Preparing video..." spinner
    // Set _isVideoPreviewReady = true to exit loading state
    // The UI will show a fallback (video badge + tap to retry message)
    if (mounted && _capturedVideo != null) {
      setState(() {
        _videoPreviewController = null; // Ensure no broken controller
        _isVideoPreviewReady = true; // Exit loading state to show fallback
      });
      
      // Show error snackbar so user knows something went wrong
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Video preview failed. You can still send it.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
  
  /// Dispose video preview player
  void _disposeVideoPreview() {
    _videoPreviewController?.dispose();
    _videoPreviewController = null;
    _isVideoPreviewReady = false;
  }

  void _clearAllOverlays() {
    _drawingStrokes.clear();
    _currentStrokeNotifier.value = [];
    _stickersNotifier.value = [];
    _textOverlaysNotifier.value = [];
    _selectedStickerIndex = null;
    _selectedTextIndex = null;
    _currentEditMode = EditMode.none;
  }

  void _discardCapture() {
    HapticFeedback.lightImpact();
    _disposeVideoPreview(); // Clean up video player
    
    // FIX: Stop any active audio playback when discarding
    ref.read(audioServiceProvider).stop();
    
    setState(() {
      _capturedImage = null;
      _capturedVideo = null;
      _recordedAudioFile = null; // Clear recorded audio
      _audioDuration = 0;
      _isRecordingAudio = false;
      _clearAllOverlays();
    });
    _notifyCaptureState(); // Show history indicator (back to idle)
    // Wake up the camera sensor for retake
    _resumeCamera();
  }

  /// TAP-TO-FOCUS: Standard camera feature
  /// Calculates normalized offset (0.0-1.0) and sets focus/exposure point
  void _handleTapToFocus(Offset localPosition, CameraState cameraState) {
    final controller = cameraState.controller;
    if (controller == null || !controller.value.isInitialized) return;
    
    // Get the render box to calculate relative position
    final RenderBox? renderBox = _captureKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final size = renderBox.size;
    
    // Calculate normalized offset (0.0 to 1.0)
    final double x = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final double y = (localPosition.dy / size.height).clamp(0.0, 1.0);
    final offset = Offset(x, y);
    
    // Visual feedback
    HapticFeedback.lightImpact();
    setState(() {
      _focusPoint = localPosition;
      _showFocusReticle = true;
    });
    
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showFocusReticle = false);
    });
    
    // Set focus and exposure point
    try {
      controller.setFocusPoint(offset);
      controller.setExposurePoint(offset);
      debugPrint('Tap-to-focus: Set focus at ($x, $y)');
    } catch (e) {
      debugPrint('Tap-to-focus failed: $e');
    }
  }

  Widget _buildFocusReticle() {
    return Positioned(
      left: _focusPoint!.dx - 40,
      top: _focusPoint!.dy - 40,
      child: Container(
        width: 80,
        height: 80,
        child: CustomPaint(
          painter: FocusBracketPainter(color: AppColors.telemetry),
        ),
      ),
    );
  }

  Widget _buildHUDOverlay() {
    final cameraState = ref.watch(cameraControllerProvider);
    if (cameraState.zoomLevel <= 1.05 && !_isRecordingVideo) return const SizedBox.shrink();
    
    return Positioned(
      bottom: 20,
      left: 0, right: 0,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: (cameraState.zoomLevel > 1.05 || _isRecordingVideo) ? 1.0 : 0.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              '${cameraState.zoomLevel.toStringAsFixed(1)}x',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHUDItem(String label, String value, {String? unit}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceMono(
            color: AppColors.telemetry.withOpacity(0.7),
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: GoogleFonts.spaceMono(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (unit != null)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  unit,
                  style: GoogleFonts.spaceMono(
                    color: AppColors.telemetry.withOpacity(0.5),
                    fontSize: 8,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ============ EDIT MODE METHODS ============

  void _setEditMode(EditMode mode) {
    HapticFeedback.selectionClick();
    
    // If clicking the same mode, toggle off
    if (_currentEditMode == mode) {
      setState(() {
        _currentEditMode = EditMode.none;
        _selectedStickerIndex = null;
        _selectedTextIndex = null;
        _isEditingText = false;
        _textFocusNode.unfocus();
      });
      return;
    }
    
    setState(() {
      _currentEditMode = mode;
      _selectedStickerIndex = null;
      _selectedTextIndex = null;
      
      // Update audio mode flag
      if (mode == EditMode.audio) {
        _isAudioOnlyMode = true;
      } else if (mode != EditMode.none) {
        // If switching to any visual mode, we are no longer in audio-only
        _isAudioOnlyMode = false;
        
        // JIT CAMERA INIT: If we were in audio mode and now need camera
        final cameraState = ref.read(cameraControllerProvider);
        if (!cameraState.isInitialized && cameraState.error == null) {
          _initializeCamera();
        }
      }
    });
    
    // NoteIt-style: Auto-action based on mode
    switch (mode) {
      case EditMode.text:
        // Immediately add text and open keyboard
        _addTextImmediate();
        break;
      case EditMode.sticker:
        // Show sticker picker in bottom sheet
        _showStickerBottomSheet();
        break;
      case EditMode.draw:
        // Draw mode just activates, user can start drawing
        break;
      case EditMode.audio:
        // Audio mode just activates, user holds mic to record
        break;
      case EditMode.none:
        break;
    }
  }

  // ============ DRAWING METHODS ============

  void _onPanStart(DragStartDetails details) {
    if (_currentEditMode == EditMode.draw) {
      final RenderBox? renderBox = _captureKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      
      final size = renderBox.size;
      final normalizedPoint = Offset(
        details.localPosition.dx / size.width,
        details.localPosition.dy / size.height,
      );

      setState(() {
        // Just prepare logic, but actual points are handled by notifier
        _currentStrokeNotifier.value = [normalizedPoint];
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_currentEditMode == EditMode.draw) {
      final RenderBox? renderBox = _captureKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      
      final size = renderBox.size;
      final normalizedPoint = Offset(
        details.localPosition.dx / size.width,
        details.localPosition.dy / size.height,
      );

      // PERFORMANCE: Update notifier directly without setState
      final newPoints = List<Offset>.from(_currentStrokeNotifier.value)..add(normalizedPoint);
      _currentStrokeNotifier.value = newPoints;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentEditMode == EditMode.draw && _currentStrokeNotifier.value.isNotEmpty) {
      setState(() {
        _drawingStrokes.add(DrawingStroke(
          points: List.from(_currentStrokeNotifier.value),
          color: _currentDrawColor,
          strokeWidth: _currentStrokeWidth,
        ));
        _currentStrokeNotifier.value = [];
      });
    }
  }

  void _undoLastStroke() {
    if (_drawingStrokes.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _drawingStrokes.removeLast();
      });
      // 🐛 FIX: Force the ValueListenableBuilder to rebuild the CustomPaint
      // The DrawingPainter's shouldRepaint checks reference equality on strokes,
      // but _drawingStrokes is the same list instance. By updating the notifier,
      // we trigger a rebuild of the ValueListenableBuilder which recreates the
      // DrawingPainter with the updated strokes list.
      _currentStrokeNotifier.value = List.from(_currentStrokeNotifier.value);
    }
  }

  // ============ STICKER METHODS ============

  void _addSticker(String emoji) {
    HapticFeedback.lightImpact();
    // Normalize: Center of the portal
    final newSticker = StickerOverlay(
      emoji: emoji,
      position: const Offset(0.5, 0.4), 
    );
    
    // Update Notifier
    final currentStickers = List<StickerOverlay>.from(_stickersNotifier.value);
    currentStickers.add(newSticker);
    _stickersNotifier.value = currentStickers;
    
    setState(() {
      _selectedStickerIndex = _stickersNotifier.value.length - 1;
    });
  }

  void _deleteSelectedSticker() {
    if (_selectedStickerIndex != null) {
      HapticFeedback.mediumImpact();
      final currentStickers = List<StickerOverlay>.from(_stickersNotifier.value);
      currentStickers.removeAt(_selectedStickerIndex!);
      _stickersNotifier.value = currentStickers;
      
      setState(() {
        _selectedStickerIndex = null;
      });
    }
  }

  // ============ TEXT METHODS ============

  /// NoteIt-style: Immediately add text and open keyboard
  void _addTextImmediate() {
    HapticFeedback.lightImpact();
    // Normalize: Center-ish position (0.1, 0.3)
    final newText = TextOverlay(
      text: '',
      position: const Offset(0.1, 0.3), 
      color: _currentDrawColor,
      fontSize: _currentTextSize,
      fontStyle: _currentFontStyle,
    );
    
    final currentTexts = List<TextOverlay>.from(_textOverlaysNotifier.value);
    currentTexts.add(newText);
    _textOverlaysNotifier.value = currentTexts;
    
    setState(() {
      _selectedTextIndex = _textOverlaysNotifier.value.length - 1;
      _isEditingText = true;
      _textController.text = '';
    });
    
    // Small delay to ensure widget is built before focusing
    Future.delayed(const Duration(milliseconds: 100), () {
      _textFocusNode.requestFocus();
    });
  }

  void _addText() {
    _addTextImmediate();
  }

  void _finishTextEditing() {
    if (_selectedTextIndex != null && _textController.text.isNotEmpty) {
      // Logic for updating specific text item in notifier list
      final currentTexts = List<TextOverlay>.from(_textOverlaysNotifier.value);
      currentTexts[_selectedTextIndex!].text = _textController.text;
      _textOverlaysNotifier.value = currentTexts; // Notify listeners
      
      setState(() {
        _isEditingText = false;
        _currentEditMode = EditMode.none;
      });
    } else if (_selectedTextIndex != null && _textController.text.isEmpty) {
      // Remove empty text overlay
      final currentTexts = List<TextOverlay>.from(_textOverlaysNotifier.value);
      currentTexts.removeAt(_selectedTextIndex!);
      _textOverlaysNotifier.value = currentTexts;

      setState(() {
        _selectedTextIndex = null;
        _isEditingText = false;
        _currentEditMode = EditMode.none;
      });
    }
    _textFocusNode.unfocus();
  }

  void _deleteSelectedText() {
    if (_selectedTextIndex != null) {
      HapticFeedback.mediumImpact();
      final currentTexts = List<TextOverlay>.from(_textOverlaysNotifier.value);
      currentTexts.removeAt(_selectedTextIndex!);
      _textOverlaysNotifier.value = currentTexts;
      
      setState(() {
        _selectedTextIndex = null;
        _isEditingText = false;
      });
    }
  }
  
  /// Update font style for selected text
  void _setFontStyle(TextFontStyle style) {
    if (_selectedTextIndex != null) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentFontStyle = style;
        final currentTexts = List<TextOverlay>.from(_textOverlaysNotifier.value);
        currentTexts[_selectedTextIndex!].fontStyle = style;
        _textOverlaysNotifier.value = currentTexts;
      });
    }
  }
  
  /// Update text size for selected text
  void _setTextSize(double size) {
    if (_selectedTextIndex != null) {
      setState(() {
        _currentTextSize = size;
        final currentTexts = List<TextOverlay>.from(_textOverlaysNotifier.value);
        currentTexts[_selectedTextIndex!].fontSize = size;
        _textOverlaysNotifier.value = currentTexts;
      });
    }
  }
  
  // ============ STICKER BOTTOM SHEET ============
  
  void _showStickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.3,
        maxChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('Stickers', style: AppTypography.headlineSmall),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            
            // Sticker grid
            Expanded(
              child: GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: _stickerEmojis.length,
                itemBuilder: (context, index) {
                  final emoji = _stickerEmojis[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _addSticker(emoji);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(emoji, style: const TextStyle(fontSize: 28)),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============ EXPORT & SEND ============

  Future<void> _sendVibe() async {
    // Prevent double-taps
    if (_isMainSendLoading || _showMainSendCheckmark) return;
    
    HapticFeedback.mediumImpact();
    
    // Priority 1: Widget recipient (Walkie-Talkie mode from deep links/replies)
    if (widget.recipientId != null) {
      if (_isAudioOnlyMode) {
        await _performAudioOnlyDirectSend(widget.recipientId!);
      } else {
        await _performDirectSend(widget.recipientId!);
        // Manual discard for Walkie Talkie mode (since we removed it from helper)
        if (mounted) _discardCapture();
      }
      return;
    }
    
    // Priority 2: Pre-selected recipients (2026 UX: Face Pile pre-selection)
    // If user selected friends via Face Pile before capturing, instant send with feedback!
    if (_preSelectedRecipientIds.isNotEmpty) {
      setState(() => _isMainSendLoading = true); // 1. Start Spinner
      
      try {
        final recipients = _preSelectedRecipientIds.toList();
        // Don't clear yet, wait for success
        
        for (final id in recipients) {
          if (_isAudioOnlyMode) {
             await _performAudioOnlyDirectSend(id);
          } else {
             // Await the task creation (returns task ID now)
             await _performDirectSend(id);
          }
        }
        
        // 2. Artificial Handoff Delay (Trust)
        await Future.delayed(const Duration(milliseconds: 600));

        if (mounted) {
          setState(() {
            _isMainSendLoading = false;
            _showMainSendCheckmark = true; // 3. Show Checkmark
            // OPTION B: KEEP SELECTION (Rapid Fire Mode)
            // _preSelectedRecipientIds.clear(); // REMOVED
          });
          
          HapticFeedback.heavyImpact();

          // 4. Reset UI after checkmark
          await Future.delayed(const Duration(milliseconds: 1000));
          if (mounted) {
             setState(() => _showMainSendCheckmark = false);
             _discardCapture(); // Reset camera
          }
        }
      } catch (e) {
        // Handle Error
        debugPrint('Error sending to pre-selected: $e');
        if (mounted) setState(() => _isMainSendLoading = false);
      }
      return;
    }
    
    // Priority 3: Show friend picker (no pre-selection)
    _showFriendPicker();
  }


  /// Show gallery picker directly (unified Photo + Video)
  void _showGalleryPicker() {
    HapticFeedback.selectionClick();
    _showAssetPickerSheet(RequestType.common);
  }

  /// Show the actual asset picker sheet
  void _showAssetPickerSheet(RequestType type) {
    // Update the provider to fetch requested type
    ref.read(galleryRequestTypeProvider.notifier).state = type;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Consumer(
          builder: (ctx, ref, _) {
            final assetsAsync = ref.watch(galleryAssetsProvider);
            
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent ${type == RequestType.common ? 'Media' : type == RequestType.image ? 'Photos' : 'Videos'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10),
                Expanded(
                  child: assetsAsync.when(
                    data: (assets) {
                      if (assets.isEmpty) {
                        return const Center(
                          child: Text('No assets found', style: TextStyle(color: Colors.white54)),
                        );
                      }
                      
                      return GridView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: assets.length,
                        itemBuilder: (ctx, index) {
                          final asset = assets[index];
                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              _handleAssetSelection(asset);
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                AssetEntityImage(
                                  asset,
                                  isOriginal: false,
                                  thumbnailSize: const ThumbnailSize.square(200),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.grey[900],
                                    child: const Icon(Icons.broken_image, color: Colors.white24),
                                  ),
                                ),
                                if (asset.type == AssetType.video)
                                  Positioned(
                                    bottom: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _formatAssetDuration(asset.videoDuration),
                                        style: const TextStyle(color: Colors.white, fontSize: 10),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.primaryAction),
                    ),
                    error: (err, _) => Center(
                      child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatAssetDuration(Duration duration) {
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  /// Handle selection of an asset from gallery
  Future<void> _handleAssetSelection(AssetEntity asset) async {
    // Check duration limits
    if (asset.type == AssetType.video && asset.videoDuration.inSeconds > 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video must be 15s or less')),
      );
      return;
    }
    if (asset.type == AssetType.audio) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please record audio vibes in real-time')),
      );
      return;
    }

    final file = await asset.file;
    if (file == null) return;

    setState(() {
      _isFromGallery = true;
      if (asset.type == AssetType.image) {
        _capturedImage = file;
        _capturedVideo = null;
        _recordedAudioFile = null;
        _isAudioOnlyMode = false;
      } else if (asset.type == AssetType.video) {
        _capturedVideo = file;
        _capturedImage = null;
        _recordedAudioFile = null;
        _isAudioOnlyMode = false;
        _initializeVideoPreview(file.path, ++_initGeneration);
      }
      _clearAllOverlays();
    });
    
    _notifyCaptureState(); // Update global state
  }


  /// Show Smart Send Sheet (Material Design 3 / Snapchat pattern)
  /// Features: Quick Send Row (top) + Multi-Select List (bottom)
  void _showFriendPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allows larger height
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.75, // 75% of screen height like Snapchat/IG
        child: SmartSendSheet(
          isAudioOnly: _isAudioOnlyMode,
          // 🐛 FIX: Pass pre-selected friends so they appear checked in send sheet
          initialSelectedIds: _preSelectedRecipientIds,
          onSendToOne: (String userId) async {
            // REMOVED: Navigator.pop(ctx); <-- Keep sheet open for feedback!
            if (_isAudioOnlyMode) {
              return await _performAudioOnlyDirectSend(userId);
            } else {
              // Return Task ID for the UI spinner
              return await _performDirectSend(userId);
            }
          },
          onSendToMany: (List<String> userIds) async {
            // Send to all selected friends IN PARALLEL (Fan-Out)
            // This uses the new Batch Upload logic: 1 Process -> 1 Upload -> N Writes.
            
            // 1. Prepare ONE payload (wait for ghost, generate overlay once)
            final payload = await _prepareMediaPayload();
            if (payload == null) {
               throw Exception("Failed to prepare media (ghost sync or overlay)");
            }

            // 2. Trigger BATCH upload
            await ref.read(vibeUploadProvider.notifier).addBatchUploadBlocking(
              receiverIds: userIds,
              audioPath: payload['audioPath'],
              imagePath: payload['imagePath'],
              videoPath: payload['videoPath'],
              overlayPath: payload['overlayPath'],
              audioDuration: payload['duration'],
              waveformData: payload['waveformData'],
              isVideo: payload['isVideo'],
              isAudioOnly: payload['isAudioOnly'],
              isFromGallery: payload['isFromGallery'],
              originalPhotoDate: payload['originalPhotoDate'], // Add if tracked
              replyToVibeId: payload['replyToVibeId'],
            );
            
            return ["batch_success"]; // Signal success to SmartSendSheet
          },
        ),
      ),
    ).whenComplete(() {
      // 2026 UX Fix: "Premature Discard".
      // Only discard the capture AFTER the sheet (and its success animation) closes.
      // This keeps the photo visible behind the "Checkmark".
      if (mounted && _hasCaptured) {
         _discardCapture();
         _isFromGallery = false; // Reset gallery flag too
      }
    });
  }

  /// Helper class to hold prepared media payload
  /// Ensures we only capture/generate overlays ONCE.
  Future<Map<String, dynamic>?> _prepareMediaPayload() async {
    // 0. GHOST SYNC: If we are in Walkie-Talkie mode and the ghost is still recording,
    // wait for it to finish hardware capture before we can start uploading.
    if (_ghostRecordingCompleter != null) {
      debugPrint('⏳ Prepare Send waiting for Ghost Recording to finish...');
      await _ghostRecordingCompleter!.future;
    }
    
    // Safety check
    if (!mounted) return null;

    // 1. Capture Metadata
    int duration = 5;
    if (_videoPreviewController != null && _isVideoPreviewReady) {
      duration = _videoPreviewController!.value.duration.inSeconds;
      if (duration <= 0) duration = _audioDuration > 0 ? _audioDuration : 5;
    } else if (_recordedAudioFile != null && _audioDuration > 0) {
      duration = _audioDuration;
    }
    
    final waveform = ref.read(waveformDataProvider);
    
    // 2. Prepare Files
    File? audioFile = _recordedAudioFile;
    File? imageFile;
    File? videoFile;
    String? overlayPath;
    bool isVideo = false;
    
    if (_capturedVideo != null) {
      isVideo = true;
      videoFile = _capturedVideo;
      
      // IMPORTANT: Generate Overlay ONCE
      final videoSize = Size(
        _videoPreviewController?.value.size.width ?? 1080,
        _videoPreviewController?.value.size.height ?? 1920,
      );
      final targetSize = VideoProcessingService.calculateTargetResolution(videoSize);
      final overlayImage = await _createOverlayImage(targetSize, isFrontCamera: _wasFrontCamera);
      
      if (overlayImage == null) {
         debugPrint('Warning: Video overlay creation failed');
         // We continue, but it might be raw video.
         // In strict mode we might return null.
      }
      overlayPath = overlayImage?.path;
      
    } else if (_capturedImage != null) {
      // PHOTO: Composite immediately
      imageFile = await _compositeImageWithOverlays();
      if (imageFile == null) imageFile = _capturedImage;
    } else if (_isAudioOnlyMode && _recordedAudioFile != null) {
      // 🛑 FIX: Audio-Only Support (Fan-Out)
      // Generate the Aura/Orb snapshot just like Single Send does
      imageFile = await _compositeImageWithOverlays();
      // Note: _compositeImageWithOverlays handles the "Audio Mode" UI capture automatically
      if (imageFile == null) {
         debugPrint('Warning: Audio composite generation failed');
         // We should probably fail here or use a placeholder?
         // For now, let it return null imageFile if failures, validation will catch it later.
      }
    } else {
       return null; // Nothing to send

    }

    return {
      'audioPath': audioFile?.path,
      'imagePath': imageFile?.path,
      'videoPath': videoFile?.path,
      'overlayPath': overlayPath,
      'duration': duration,
      'waveformData': waveform,
      'isVideo': isVideo,
      'isAudioOnly': _isAudioOnlyMode,
      'isFromGallery': _isFromGallery,
      'replyToVibeId': widget.replyTo?.id,
    };
  }

  /// Perform direct send without going through preview screen
  /// Returns the Task ID string if successful
  Future<String?> _performDirectSend(String receiverId) async {
    // REMOVED: Navigator.pop(context); <-- This was the "Fire and Forget" bug!
    // We now let the caller (SmartSendSheet) handle closing after feedback.

    // Safety check: Ensure widget is still active
    if (!mounted) return null;
  
    try {
      // Use Helper to prepare ONE payload
      final payload = await _prepareMediaPayload();
      if (payload == null) return null;

      debugPrint('📤 [CameraScreen] Triggering BLOCKING upload (Single)');
      
      await ref.read(vibeUploadProvider.notifier).addUploadBlocking(
          receiverId: receiverId,
          audioPath: payload['audioPath'],
          imagePath: payload['imagePath'],
          videoPath: payload['videoPath'],
          overlayPath: payload['overlayPath'],
          audioDuration: payload['duration'],
          waveformData: payload['waveformData'],
          isVideo: payload['isVideo'],
          isAudioOnly: payload['isAudioOnly'],
          isFromGallery: payload['isFromGallery'],
          replyToVibeId: payload['replyToVibeId'],
      );
        
      return "blocking_success"; // Dummy return as we are blocking

    } catch (e) {
      debugPrint('Error initiating send: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      return null;
    }
  }


      }
      
      return null; // Should not reach here if content exists

    } catch (e) {
      debugPrint('Error initiating send: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  /// Ask for notification permission contextually after user sends first vibe
  /// This is the "magic moment" - user just sent a message and wants to know when reply comes
  /// Much higher opt-in rate than asking during app launch or onboarding
  Future<void> _askForNotificationsContextually() async {
    // Only ask if we haven't already granted
    final status = await Permission.notification.status;
    if (status.isDenied) {
      // Small delay so user sees "Vibe sent!" first
      await Future.delayed(const Duration(milliseconds: 1500));
      await Permission.notification.request();
    }
  }

  bool get _hasOverlays => _drawingStrokes.isNotEmpty || _stickersNotifier.value.isNotEmpty || _textOverlaysNotifier.value.isNotEmpty;

  /// Extract first frame from video as thumbnail
  /// Now delegated to VideoProcessingService
  Future<File?> _extractVideoThumbnail(String videoPath) async {
    return VideoProcessingService.extractVideoThumbnail(videoPath);
  }

  /// Get safe pixel ratio to prevent OOM crashes on high-end devices
  /// 
  /// CRITICAL OOM FIX: Lowered from 4096px to 2048px.
  /// 4096x4096px = 64MB (Exceeds 30MB iOS Widget limit).
  /// 2048x2048px = 16MB (Safe for iOS Widgets).
  double _getSafePixelRatio(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const double maxTextureDimension = 2048.0;
    
    final double maxRatioWidth = maxTextureDimension / size.width;
    final double maxRatioHeight = maxTextureDimension / size.height;
    
    // Use device ratio but strictly capped at GPU/Memory limits
    final double nativeRatio = MediaQuery.of(context).devicePixelRatio;
    return math.min(nativeRatio, math.min(maxRatioWidth, maxRatioHeight));
  }

  /// 2026 FIX: Isolate-based image export to prevent UI thread freeze.
  /// Captures raw bytes on UI thread (fast), then offloads PNG encoding
  /// to a background Isolate matching the VideoProcessingService pattern.
   Future<File?> _compositeImageWithOverlays() async {
    debugPrint('🔍 [CameraScreen] Starting aura/image composition...');
    try {
      // Hide selections for clean capture
      setState(() {
        _selectedStickerIndex = null;
        _selectedTextIndex = null;
      });
      
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return null;
      
      final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('❌ [CameraScreen] Composition failed: RenderRepaintBoundary is null');
        return null;
      }
      
      // FIX: Use safe pixel ratio to prevent OOM on high-end devices
      final double safeRatio = _getSafePixelRatio(context);
      debugPrint('🔍 [CameraScreen] Capturing image with ratio: $safeRatio');
      final image = await boundary.toImage(pixelRatio: safeRatio);
      
      // CRITICAL 2026 FIX: Extract raw RGBA bytes (fast GPU readback)
      // This avoids the expensive PNG compression on the UI thread
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final int width = image.width;
      final int height = image.height;
      debugPrint('🔍 [CameraScreen] Raw RGBA extracted: ${width}x${height}');
      
      // Explicitly dispose of the GPU handle immediately
      image.dispose();
      
      if (byteData == null) {
        debugPrint('❌ [CameraScreen] Composition failed: ByteData is null');
        return null;
      }
      
      // HEAVY LIFTING: Offload PNG encoding to Background Isolate
      // This prevents the 300-800ms "Jank" during save
      debugPrint('🔍 [CameraScreen] Offloading PNG encoding to Isolate...');
      final pngBytes = await VideoProcessingService.encodeImageInIsolate(
        byteData.buffer.asUint8List(),
        width,
        height,
      );
      
      final tempDir = await getTemporaryDirectory();
      final fileName = 'vibe_edited_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);
      debugPrint('🔍 [CameraScreen] Composition complete: ${file.path}');
      
      return file;
    } catch (e) {
      debugPrint('❌ [CameraScreen] Error compositing image: $e');
      return null;
    }
  }

  /// Create a transparent overlay image for video compositing
  /// Now delegated to VideoProcessingService
  Future<File?> _createOverlayImage(Size videoSize, {bool isFrontCamera = false}) async {
    // Hide selections for clean capture
    setState(() {
      _selectedStickerIndex = null;
      _selectedTextIndex = null;
    });
    
    await Future.delayed(const Duration(milliseconds: 50));
    
    // Get the render box to understand the layout
    final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    
    final renderSize = boundary.size;
    
    // Create overlay content from current state
    final content = OverlayContent(
      strokes: _drawingStrokes,
      stickers: _stickersNotifier.value,
      textOverlays: _textOverlaysNotifier.value,
    );
    
    return VideoProcessingService.createOverlayImage(
      videoSize: videoSize,
      renderSize: renderSize,
      content: content,
      isFrontCamera: isFrontCamera,  // Pass through for selfie mirror alignment
    );
  }

  /// Composite video with overlay using FFmpeg
  /// Burns drawings, stickers, and text onto the video
  Future<File?> _compositeVideoWithOverlays() async {
    if (_capturedVideo == null) return null;
    
    try {
      // Show processing indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('Processing video with overlays...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }
      
      // Get video dimensions
      Size videoSize = const Size(1080, 1920); // Default 9:16 portrait
      if (_videoPreviewController != null && _isVideoPreviewReady) {
        final videoValue = _videoPreviewController!.value;
        if (videoValue.size.width > 0 && videoValue.size.height > 0) {
          videoSize = videoValue.size;
        }
      }
      
      // Calculate smart target resolution (downscale 4K to 1080p, no upscaling)
      final targetSize = VideoProcessingService.calculateTargetResolution(videoSize);
      
      debugPrint('Video: ${videoSize.width}x${videoSize.height} → ${targetSize.width}x${targetSize.height}');
      
      // Get camera state to check for front camera (for selfie mirroring)
      // MUST be fetched BEFORE creating overlay so we can flip the overlay canvas
      final cameraState = ref.read(cameraControllerProvider);
      final isFrontCamera = cameraState.isFrontCamera;
      
      // Create overlay at target resolution
      // SELFIE FIX: Pass isFrontCamera so stickers/drawings are flipped to align with hflipped video
      final overlayImage = await _createOverlayImage(targetSize, isFrontCamera: isFrontCamera);
      if (overlayImage == null) {
        debugPrint('Failed to create overlay image');
        _hideProcessingIndicator();
        return null;
      }
      
      // Composite using VideoProcessingService
      // PORTAL PARADOX FIX: Pass isFrontCamera for selfie mirroring (hflip)
      final result = await VideoProcessingService.compositeVideoWithOverlay(
        videoPath: _capturedVideo!.path,
        overlayImage: overlayImage,
        targetSize: targetSize,
        isFrontCamera: isFrontCamera,  // FIX: Pass for selfie mirroring
      );
      
      _hideProcessingIndicator();
      
      if (result == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add overlays to video. Sending original.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      
      return result;
    } catch (e) {
      debugPrint('Error compositing video with overlays: $e');
      _hideProcessingIndicator();
      return null;
    }
  }
  
  void _hideProcessingIndicator() {
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  // ============ BUILD METHODS ============

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final cameraState = ref.watch(cameraControllerProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    // UI SYNC: Listen for auto-stop from service (e.g. 15s limit)
    ref.listen<RecordingState>(recordingStateProvider, (previous, next) {
      if (next == RecordingState.stopped && _isRecordingAudio) {
        debugPrint('🛑 UI Sync: Service stopped recording (Auto-stop or manual)');
        final notifier = ref.read(recordingStateProvider.notifier);
        final path = notifier.currentPath;
        final duration = ref.read(recordingDurationProvider);
        
        if (path != null && mounted) {
           setState(() {
             _isRecordingAudio = false;
             _recordedAudioFile = File(path);
             _audioDuration = duration > 0 ? duration : 1;
             // _hasCaptured will now be true
           });
           
           // If in audio-only mode, we stay there but show the review controls
           // If in camera mode (holding mic button), we just show the review controls
           _notifyCaptureState();
        }
      }
    });
    
    // STATE-BASED CURTAIN LIFT & FALL
    // 1. Lifts curtain immediately when camera reports isInitialized
    // 2. Drops curtain when camera resets (e.g. enableAudio) to hide "Starting camera..." spinner
    ref.listen<CameraState>(cameraControllerProvider, (prev, next) {
      // Lift curtain (Init Success)
      if (_showCurtain && next.isInitialized && next.error == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _showCurtain = false);
        });
      }
      
      // Drop curtain (Re-Init Started)
      // Fixes Issue 1: Prevent "Starting camera" spinner flash during audio re-init
      if (prev?.isInitialized == true && next.isInitialized == false && next.error == null) {
         if (mounted && !_showCurtain) {
            setState(() => _showCurtain = true);
         }
      }
    });

    
    // 2025 FIX: Flex-based layout (Column + Expanded)
    // No more manual pixel math or 0.68 multipliers.
    // The layout engine handles responsiveness for us.

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.background, // Fallback color
      body: Stack(
        children: [
          // 1. Background (Gradient) - Fills entire screen
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _backgroundGradient,
              ),
            ),
          ),
          _buildBackgroundDecorations(),
          
          // 2. Main Flex Layout
          Column(
            children: [
              // A. Top Bar (Title + Buttons)
              // We use a fixed height container that respects safe area
              Container(
                height: topPadding + kToolbarHeight + 12, // Sufficient space for top controls
                width: double.infinity,
                padding: EdgeInsets.only(top: topPadding),
                child: Stack(
                  children: [
                    // We pass 0 because the padding is handled by the Container
                    // _buildAppTitle(0), // REMOVED: User request to clean UI
                    _buildTopLeftButton(0),
                    _buildTopRightButton(0),
                  ],
                ),
              ),
              
              // B. Camera Frame - "PORTAL VIEW" (Widget-First Framing)
              // Uses fixed 1:1 aspect ratio with rounded corners to match widget
              // This ensures WYSIWYG: What You See Is What You Get
              Expanded(
                child: Container(
                  // Removed black surround - let gradient background show through
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // NoteIt-style camera: FULL WIDTH, 1:1 aspect ratio (square)
                      // Width = full screen width with small margin for rounded corners
                      // Height = Width × 3/4 (so width > height, like NoteIt)
                      
                      // NEW (Full Screen Width)
final portalWidth = constraints.maxWidth;
                      
                      // 1:1 aspect ratio (TESTING)
                      // Square - height equals width, but limited by available height to prevent overlap
                      final portalHeight = math.min(portalWidth, constraints.maxHeight);
                      
                      // Note: Audio mode now uses the same portal style as camera
                      // for visual consistency (removed the full-screen bypass)
                      
                      // Position CENTERED (not top-aligned)
                      return Align(
                        alignment: Alignment.center,
                        child: Container(
                            width: portalWidth,
                            height: portalHeight,
                            decoration: BoxDecoration(
                              color: AppColors.surface, // FIXED: Use Surface color for contrast against background
                              borderRadius: BorderRadius.circular(24), // Locket-style corners
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.5),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: RepaintBoundary(
                                key: _captureKey,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // 1. Camera/Content Layer
                                    // 1. Camera/Content Layer
                                    CameraPortalView(
                                      cameraState: cameraState,
                                      showCurtain: _showCurtain,
                                      capturedImage: _capturedImage,
                                      capturedVideo: _capturedVideo,
                                      isRecordingVideo: _isRecordingVideo,
                                      isAudioOnlyMode: _isAudioOnlyMode,
                                      isMicPermissionGranted: _isMicPermissionGranted,
                                      isVideoPreviewReady: _isVideoPreviewReady,
                                      videoPreviewController: _videoPreviewController,
                                      wasFrontCamera: _wasFrontCamera,
                                      replyTo: widget.replyTo,
                                      currentEditMode: _currentEditMode,
                                      onTapToPlaceText: _addTextAtPosition,
                                      onRetryCameraInit: () => ref.read(cameraControllerProvider.notifier).initializeCamera(),
                                      onRequestCameraPermission: _requestCameraPermission,
                                      onRequestMicPermission: _requestMicPermission,
                                      onInitializeVideoPreview: (path, gen) {
                                          setState(() => _isVideoPreviewReady = false);
                                          _initializeVideoPreview(path, gen);
                                      },
                                      initGeneration: _initGeneration,
                                      onToggleVideoPlayback: () {
                                          setState(() {
                                            if (_videoPreviewController!.value.isPlaying) {
                                              _videoPreviewController!.pause();
                                            } else {
                                              _videoPreviewController!.play();
                                            }
                                          });
                                      },
                                      // PASS THE AUDIO STATE:
                                      isRecordingAudio: _isRecordingAudio,
                                      audioDuration: ref.watch(recordingDurationProvider), 
                                      audioAmplitude: ref.watch(waveformDataProvider).isNotEmpty 
                                          ? ref.watch(waveformDataProvider).last 
                                          : 0.0,
                                      onToggleAudioRecording: () {
                                         if (_isRecordingAudio) {
                                           _stopAudioOnlyRecording();
                                         } else {
                                           _startAudioOnlyRecording();
                                         }
                                      },
                                    ),
                                    
                                    // 2. Edit Layers (Drawing Overlays)
                                    // PERFORMANCE: Use ValueListenableBuilder to rebuild only the drawing layer
                                    if (_drawingStrokes.isNotEmpty || _currentEditMode == EditMode.draw)
                                      Positioned.fill(
                                        child: RepaintBoundary(
                                          child: ValueListenableBuilder<List<Offset>>(
                                            valueListenable: _currentStrokeNotifier,
                                            builder: (context, currentPoints, child) {
                                              return CustomPaint(
                                                painter: DrawingPainter(
                                                  strokes: _drawingStrokes,
                                                  currentStroke: currentPoints,
                                                  currentColor: _currentDrawColor,
                                                  currentStrokeWidth: _currentStrokeWidth,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                        
                                    // 3. Interaction Layer (Taps, Focus, Drawing)
                                    // 🧭 PERMISSION FIX: Disable interaction layer if camera is not initialized 
                                    // and we have no content. This ensures the "Allow Access" button is clickable.
                                    if (_hasCaptured || (cameraState.error == null && cameraState.isInitialized))
                                      Positioned.fill(
                                        child: GestureDetector(
                                          // 2026 FIX: Dynamic HitTestBehavior based on mode
                                          // OPAQUE when drawing (capture all touches for strokes)
                                          // TRANSLUCENT otherwise (allow touches to reach stickers/text above)
                                          behavior: _currentEditMode == EditMode.draw 
                                              ? HitTestBehavior.opaque 
                                              : HitTestBehavior.translucent,
                                          
                                          // UNIFIED GESTURE HANDLING (Best Practice)
                                          // Pan is just specific Scale (1.0). Consolidate logic here.
                                          
                                          onScaleStart: (details) {
                                             if (_currentEditMode == EditMode.draw) {
                                                // DRAWING: Start stroke (Pan logic)
                                                // Manually map Scale details to Pan logic
                                                _onPanStart(DragStartDetails(
                                                  globalPosition: details.focalPoint,
                                                  localPosition: details.localFocalPoint,
                                                ));
                                             } else if (!_hasCaptured && _currentEditMode == EditMode.none) {
                                                // INTERACTION: Start Zoom (Scale logic)
                                                _initialScaleZoom = cameraState.zoomLevel;
                                             }
                                          },
                                          
                                          onScaleUpdate: (details) {
                                             if (_currentEditMode == EditMode.draw) {
                                                // DRAWING: Update stroke (Pan logic)
                                                _onPanUpdate(DragUpdateDetails(
                                                  globalPosition: details.focalPoint,
                                                  localPosition: details.localFocalPoint,
                                                  delta: details.focalPointDelta, 
                                                ));
                                             } else if (!_hasCaptured && _currentEditMode == EditMode.none && details.pointerCount > 1) {
                                                // INTERACTION: Update Zoom (Scale logic)
                                                // Only zoom if 2 pointers (pinch) to check intent
                                                final cameraNotifier = ref.read(cameraControllerProvider.notifier);
                                                final maxZoom = cameraState.isFrontCamera ? 3.0 : cameraState.maxZoom;
                                                final newZoom = (_initialScaleZoom * details.scale).clamp(cameraState.minZoom, maxZoom);
                                                cameraNotifier.setZoomLevel(newZoom);
                                             }
                                          },
                                          
                                          onScaleEnd: (details) {
                                             if (_currentEditMode == EditMode.draw) {
                                                // DRAWING: End stroke
                                                _onPanEnd(DragEndDetails(velocity: details.velocity));
                                             }
                                             // INTERACTION: No specific end logic needed for zoom usually
                                          },
                                          
                                          // TAP HANDLING (Remains separate as it's distinct from continuous gestures)
                                          onTapUp: (details) {
                                             if (_currentEditMode != EditMode.draw) {
                                               // Deselect stickers/text
                                               setState(() {
                                                 _selectedStickerIndex = null;
                                                 _selectedTextIndex = null;
                                               });
                                             }
                                             
                                             // TAP-TO-FOCUS
                                             if (!_hasCaptured && _currentEditMode == EditMode.none) {
                                               _handleTapToFocus(details.localPosition, cameraState);
                                             }
                                          },
                                        ),
                                      ),

                                    // 4. Sticker Layer (RepaintBoundary)
                                    // 2026 FIX: IgnorePointer when in Draw Mode to allow drawing OVER stickers
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        ignoring: _currentEditMode == EditMode.draw,
                                        child: RepaintBoundary(
                                          child: ValueListenableBuilder<List<StickerOverlay>>(
                                            valueListenable: _stickersNotifier,
                                            builder: (context, stickers, _) {
                                              if (stickers.isEmpty) return const SizedBox.shrink();
                                              return Stack(
                                                children: _buildStickerWidgetsFromList(stickers, portalWidth, portalHeight),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),

                                    // 5. Text Layer (RepaintBoundary)
                                    // 2026 FIX: IgnorePointer when in Draw Mode to allow drawing OVER text
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        ignoring: _currentEditMode == EditMode.draw,
                                        child: RepaintBoundary(
                                          child: ValueListenableBuilder<List<TextOverlay>>(
                                            valueListenable: _textOverlaysNotifier,
                                            builder: (context, textOverlays, _) {
                                              if (textOverlays.isEmpty) return const SizedBox.shrink();
                                              return Stack(
                                                children: _buildTextWidgetsFromList(textOverlays, portalWidth, portalHeight),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),

                                    // 6. HUD Layer
                                    if (!_hasCaptured && !_isAudioOnlyMode)
                                      _buildHUDOverlay(),


                                    // 7. Feedback Layers (Focus Reticle, Recording Progress)
                                    if (_showFocusReticle && _focusPoint != null)
                                      _buildFocusReticle(),
                                    
                                    if (_isRecordingVideo) ...[
                                      _buildRecordingIndicator(),
                                      Positioned.fill(
                                        child: AnimatedBuilder(
                                          animation: _recordingProgressController,
                                          builder: (context, child) {
                                            return CustomPaint(
                                              painter: CornerProgressPainter(
                                                progress: _recordingProgressController.value,
                                                color: AppColors.error,
                                                strokeWidth: 6,
                                                cornerRadius: 24, // Match portal corners
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              
              
              // C. Bottom Controls (Anchored to bottom)
              SafeArea(
                top: false,
                // OFFICIAL FIX: Use 'minimum' to set a floor for padding.
                // This ensures 90px spacing on devices with 0px safe area,
                // but overlaps with the system safe area (e.g., 34px) on modern phones
                // so you don't get 90 + 34 = 124px gaps.
                minimum: const EdgeInsets.only(top: 8, bottom: 90),
                child: Container(
                  width: double.infinity,
                  // REMOVED: padding inside Container (handled by SafeArea minimum)
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       // 1. Toolbar (Colors/Sliders)
                       if (_hasCaptured && _currentEditMode != EditMode.none && !_isEditingText)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: EditToolsOverlay(
                                currentEditMode: _currentEditMode,
                                drawColors: _drawColors,
                                currentDrawColor: _currentDrawColor,
                                currentStrokeWidth: _currentStrokeWidth,
                                currentTextSize: _currentTextSize,
                                currentFontStyle: _currentFontStyle,
                                onColorChanged: (color) {
                                  setState(() {
                                    _currentDrawColor = color;
                                    if (_currentEditMode == EditMode.text && _selectedTextIndex != null) {
                                        final currentTexts = List<TextOverlay>.from(_textOverlaysNotifier.value);
                                        currentTexts[_selectedTextIndex!].color = color;
                                        _textOverlaysNotifier.value = currentTexts; 
                                    }
                                  });
                                },
                                onStrokeWidthChanged: (width) => setState(() => _currentStrokeWidth = width),
                                onTextSizeChanged: (size) => _setTextSize(size),
                                onFontStyleChanged: (style) => _setFontStyle(style),
                                onFinishTextEditing: _finishTextEditing,
                                textOverlaysNotifier: _textOverlaysNotifier,
                                selectedTextIndex: _selectedTextIndex,
                                textController: _textController,
                                textFocusNode: _textFocusNode,
                                isEditingText: _isEditingText,
                              ),
                          ),
                          
                       // 2. Camera Controls (Flash/Flip) - before capture only
                       // [FIX APPLIED] LOCK CONTROLS: Only show if initialized, curtain down, AND NOT RECORDING
                       if (!_hasCaptured && !_showCurtain && cameraState.isInitialized && !_isRecordingVideo && !_isRecordingAudio)
                         Visibility(
                           visible: !_isAudioOnlyMode,
                           maintainSize: true,
                           maintainAnimation: true,
                           maintainState: true,
                           child: Padding(
                             padding: const EdgeInsets.only(bottom: 16),
                             child: _buildCameraControls(),
                           ),
                         ),
                          
                       // 3. Edit Mode Buttons (Draw/Sticker) - after capture only
                       // HIDE when editing text to follow user request "keyboard should coverAll editing option"
                       if (_hasCaptured && !_isEditingText)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildEditOptions(),
                          ),
                          
                       // 4. Main Action Buttons (Shutter / Retake&Send)
                       // HIDE when editing text to prevent layout shifts and focus user on typing
                       if (!_hasCaptured)
                         _buildMainBottomControls()
                       else if (!_isEditingText)
                         _buildCapturedBottomControls(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Top Camera Controls REMOVED - now shown in bottom area before capture

          // 4. Text Input Overlay (Root Stack, z-index top)
          if (_isEditingText)
            EditToolsOverlay(
              currentEditMode: _currentEditMode,
              drawColors: _drawColors,
              currentDrawColor: _currentDrawColor,
              currentStrokeWidth: _currentStrokeWidth,
              currentTextSize: _currentTextSize,
              currentFontStyle: _currentFontStyle,
              onColorChanged: (color) {
                setState(() {
                  _currentDrawColor = color;
                  if (_currentEditMode == EditMode.text && _selectedTextIndex != null) {
                      final currentTexts = List<TextOverlay>.from(_textOverlaysNotifier.value);
                      currentTexts[_selectedTextIndex!].color = color;
                      _textOverlaysNotifier.value = currentTexts; 
                  }
                });
              },
              onStrokeWidthChanged: (width) => setState(() => _currentStrokeWidth = width),
              onTextSizeChanged: (size) => _setTextSize(size),
              onFontStyleChanged: (style) => _setFontStyle(style),
              onFinishTextEditing: _finishTextEditing,
              textOverlaysNotifier: _textOverlaysNotifier,
              selectedTextIndex: _selectedTextIndex,
              textController: _textController,
              textFocusNode: _textFocusNode,
              isEditingText: _isEditingText,
            ),
        ],
      ),
    );
  }

  Widget _buildBackgroundDecorations() {
    return Stack(
      children: [
        Positioned(
          top: -50,
          right: -50,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.glassBackground, // Was alpha 25
            ),
          ),
        ),
        Positioned(
          bottom: 100,
          left: -80,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.glassBackgroundDark, // Was alpha 20
            ),
          ),
        ),
      ],
    );
  }

  // REMOVED: _buildAppTitle (User request to clean UI)

  Widget _buildTopLeftButton(double statusBarHeight) {
    // Hide during recording or text editing for focus
    if (_isRecordingVideo || _isRecordingAudio || _isEditingText) {
      return const SizedBox.shrink();
    }
    
    // When drawing, show undo button
    if (_currentEditMode == EditMode.draw && _drawingStrokes.isNotEmpty) {
      return Positioned(
        top: statusBarHeight + 12,
        left: 16,
        child: GlassButton(
          icon: Icons.undo,
          onPressed: _undoLastStroke,
        ),
      );
    }
    
    // Default: Show profile/settings avatar
    return Positioned(
      top: statusBarHeight + 12,
      left: 16,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          if (widget.onOpenSettings != null) {
            widget.onOpenSettings!();
          }
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.glassBackground, // Was Colors.white.withAlpha(25)
            border: Border.all(color: AppColors.glassBorder, width: 1), // Was 51
          ),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildTopRightButton(double statusBarHeight) {
    // Hide during recording or text editing for focus
    if (_isRecordingVideo || _isRecordingAudio || _isEditingText) {
      return const SizedBox.shrink();
    }
    
    // Contextual Delete Buttons for Edit Modes
    if (_selectedStickerIndex != null) {
      return Positioned(
        top: statusBarHeight + 12,
        right: 16,
        child: GlassButton(
          icon: Icons.delete,
          onPressed: _deleteSelectedSticker,
          color: AppColors.error,
        ),
      );
    }
    if (_selectedTextIndex != null) {
      return Positioned(
        top: statusBarHeight + 12,
        right: 16,
        child: GlassButton(
          icon: Icons.delete,
          onPressed: _deleteSelectedText,
          color: AppColors.error,
        ),
      );
    }
    // NOTE: Redundant close button removed (Material Design 3 / Snapchat/Locket pattern)
    // Retake button at bottom handles discarding. Face Pile shows in preview for status.
    
    // Face Pile: Show friend avatars (HTML-style top-right friends list)
    return Positioned(
      top: statusBarHeight + 12,
      right: 16,
      child: Consumer(
        builder: (context, ref, _) {
          final friendsAsync = ref.watch(friendsProvider);

          return friendsAsync.when(
            data: (friends) {
              // No Friends? Show "Add Friend" button
              if (friends.isEmpty) {
                return GlassButton(
                  icon: Icons.person_add_rounded,
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    context.push('/add-friends');
                  },
                );
              }

              // Friends available: Determine what to show based on selection state
              final bool hasPreSelection = _preSelectedRecipientIds.isNotEmpty;
              List<UserModel> displayFriends;
              int badgeCount = 0;

              if (!hasPreSelection) {
                // STATE 1: No Selection -> Show top 3 friends + remaining count
                displayFriends = friends.take(3).toList();
                badgeCount = (friends.length > 3) ? (friends.length - 3) : 0;
              } else {
                // STATE 2: Selection Active -> Show selected friends + remaining SELECTED count
                // Filter friends list to finding the user objects for selected IDs
                final selectedFriendsList = friends.where((f) => _preSelectedRecipientIds.contains(f.id)).toList();
                
                // If we have selected IDs but can't find them in the friends list (edge case),
                // we might show fewer avatars, but the badge should reflect the total selection.
                
                displayFriends = selectedFriendsList.take(3).toList();
                
                // Badge shows how many *selected* users are hidden
                // Use _preSelectedRecipientIds.length as the truth for total selection count
                badgeCount = (_preSelectedRecipientIds.length > 3) ? (_preSelectedRecipientIds.length - 3) : 0;
              }

              // Dynamic width calculation
              const double overlap = 22.0;
              const double avatarSize = 32.0;
              final double badgeWidth = (badgeCount > 0) ? 28.0 : 0.0;
              
              // Calculate width based on ACTUAL displayed avatars
              final int visibleCount = displayFriends.length;
              final double containerWidth = visibleCount == 0 
                  ? 48.0 // Fallback if nothing to show
                  : ((visibleCount - 1) * overlap) + avatarSize + badgeWidth;

              return GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  _showPreSelectionSheet();
                },
                child: Container(
                  height: 48,
                  width: containerWidth + 8, // Add padding for safety
                  // NO VISUAL NOISE: Removed GlassContainer background entirely
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Avatars
                      if (visibleCount > 0)
                        Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            SizedBox(
                              width: ((visibleCount - 1) * overlap) + avatarSize,
                              height: avatarSize,
                            ),
                            // Render avatars with overlap (last drawn = on top)
                            ...List.generate(visibleCount, (index) {
                              final friend = displayFriends[index];
                              return Positioned(
                                left: index * overlap,
                                child: Container(
                                  width: avatarSize,
                                  height: avatarSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    color: Colors.grey[800],
                                    image: friend.avatarUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(friend.avatarUrl!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      )
                                    ],
                                  ),
                                  child: friend.avatarUrl == null
                                      ? Center(
                                          child: Text(
                                            friend.displayName.isNotEmpty
                                                ? friend.displayName[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              );
                            }),
                          ],
                        ),
                        
                      // Badge (Context-aware: either "more friends" or "more selected")
                      if (badgeCount > 0) ...[
                        const SizedBox(width: 4), // Tighter gap
                        Container(
                          width: 24, // Slightly wider for double digits
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Colors.transparent, 
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '+$badgeCount',
                              style: TextStyle(
                                color: hasPreSelection ? AppColors.primaryAction : Colors.white.withOpacity(0.8),
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
            // Loading/Error states: show nothing to avoid layout shift
            loading: () => const SizedBox.shrink(),
            error: (_, __) => GlassButton(
              icon: Icons.people_outline,
              onPressed: () => context.push('/add-friends'),
            ),
          );
        },
      ),
    );
  }
  
  /// Show pre-selection sheet (accessed from Face Pile in top-right)
  /// Allows selecting friends BEFORE capture for instant sending later.
  void _showPreSelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.75,
        child: SmartSendSheet(
          isAudioOnly: _isAudioOnlyMode,
          isPreSelectionMode: true, // Enable pre-selection mode
          initialSelectedIds: _preSelectedRecipientIds, // Preserve state
          onPreSelect: (Set<String> selectedIds) {
            setState(() {
              _preSelectedRecipientIds = selectedIds;
            });
            // Save to persistence
            SharedPreferences.getInstance().then((prefs) {
              prefs.setStringList(_preSelectedFriendsKey, selectedIds.toList());
            });
          },
        ),
      ),
    );
  }



  List<Widget> _buildStickerWidgetsFromList(List<StickerOverlay> stickers, double portalWidth, double portalHeight) {
    return stickers.asMap().entries.map((entry) {
      final index = entry.key;
      final sticker = entry.value;
      
      // Use local variables to track scale/rotation during a gesture
      double _startScale = 1.0;
      double _startRotation = 0.0;

      return Positioned(
        left: sticker.position.dx * portalWidth,
        top: sticker.position.dy * portalHeight,
        child: Semantics(
          label: 'Sticker: ${sticker.emoji}',
          selected: index == _selectedStickerIndex,
          child: RepaintBoundary(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedStickerIndex = index);
              },
              onScaleStart: (details) {
                _startScale = sticker.scale;
                _startRotation = sticker.rotation;
                setState(() => _selectedStickerIndex = index);
              },
              onScaleUpdate: (details) {
                // Simultaneous Pan, Scale, and Rotate
                sticker.position += Offset(
                  details.focalPointDelta.dx / portalWidth,
                  details.focalPointDelta.dy / portalHeight,
                );
                
                if (details.scale != 1.0) {
                  sticker.scale = (_startScale * details.scale).clamp(0.5, 4.0);
                }
                
                if (details.rotation != 0.0) {
                  sticker.rotation = _startRotation + details.rotation;
                }
                
                // PERFORMANCE: Update notifier to trigger repaint of THIS layer only
                _stickersNotifier.value = List.from(stickers);
              },
              child: Transform.translate(
                offset: const Offset(-24, -24), // Center the pivot point (emoji is ~48px)
                child: Transform.rotate(
                  angle: sticker.rotation,
                  child: Transform.scale(
                    scale: sticker.scale,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: index == _selectedStickerIndex && !_isEditingText
                          ? BoxDecoration(
                              border: Border.all(color: AppColors.primaryAction.withOpacity(0.5), width: 1),
                              borderRadius: BorderRadius.circular(8),
                            )
                          : null,
                      child: Text(
                        sticker.emoji, 
                        style: const TextStyle(fontSize: 48)
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildTextWidgetsFromList(List<TextOverlay> textOverlays, double portalWidth, double portalHeight) {
    return textOverlays.asMap().entries.map((entry) {
      final index = entry.key;
      final textItem = entry.value;
      final isSelected = index == _selectedTextIndex;
      
      // Don't show empty text (being edited) OR the currently selected text item
      // because it's being rendered by the _buildTextInputField layer.
      if ((textItem.text.isEmpty && !isSelected) || (isSelected && _isEditingText)) {
        return const SizedBox.shrink();
      }
      
      double _startScale = 1.0;
      double _startRotation = 0.0;

      return Positioned(
        left: textItem.position.dx * portalWidth,
        top: textItem.position.dy * portalHeight,
        child: Semantics(
          label: 'Text: ${textItem.text}',
          selected: isSelected,
          child: RepaintBoundary(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedTextIndex = index;
                  _textController.text = textItem.text;
                  _currentFontStyle = textItem.fontStyle;
                  _currentTextSize = textItem.fontSize;
                  _currentDrawColor = textItem.color;
                  _isEditingText = true;
                  _currentEditMode = EditMode.text;
                  _textOverlaysNotifier.value = List.from(textOverlays);
                });
                _textFocusNode.requestFocus();
              },
              onScaleStart: (details) {
                _startScale = textItem.scale;
                _startRotation = textItem.rotation;
                setState(() {
                  _selectedTextIndex = index;
                  _textOverlaysNotifier.value = List.from(textOverlays);
                });
              },
              onScaleUpdate: (details) {
                textItem.position += Offset(
                  details.focalPointDelta.dx / portalWidth,
                  details.focalPointDelta.dy / portalHeight,
                );
                
                if (details.scale != 1.0) {
                  textItem.scale = (_startScale * details.scale).clamp(0.5, 5.0);
                }
                
                if (details.rotation != 0.0) {
                  textItem.rotation = _startRotation + details.rotation;
                }
                
                _textOverlaysNotifier.value = List.from(textOverlays);
              },
              child: Transform.rotate(
                angle: textItem.rotation,
                child: Transform.scale(
                  scale: textItem.scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: isSelected && !_isEditingText
                        ? BoxDecoration(
                            border: Border.all(color: AppColors.primaryAction.withOpacity(0.5), width: 1),
                            borderRadius: BorderRadius.circular(8),
                          )
                        : null,
                    child: Text(
                      textItem.text.isEmpty ? ' ' : textItem.text,
                      style: textItem.fontStyle.getStyle(textItem.fontSize, textItem.color).copyWith(
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            offset: const Offset(1, 1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildRecordingIndicator() {
    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 12, height: 12,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }


  
  void _showTextColorPicker() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Text Color', style: AppTypography.headlineSmall),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _drawColors.map((color) {
                final isSelected = _currentDrawColor == color;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _currentDrawColor = color;
                      if (_selectedTextIndex != null) {
                        final currentTexts = List<TextOverlay>.from(_textOverlaysNotifier.value);
                        currentTexts[_selectedTextIndex!].color = color;
                        _textOverlaysNotifier.value = currentTexts;
                      }
                    });
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? AppColors.primaryAction : Colors.white24,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraControls() {
  final cameraState = ref.watch(cameraControllerProvider);
  
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      // FLASH: Only show for Back Camera (Hardware limitation on front)
      if (!cameraState.isFrontCamera) ...[
        MiniPillButton(
          icon: _getFlashIcon(cameraState.flashMode),
          label: 'Flash',
          onTap: () {
            HapticFeedback.selectionClick();
            ref.read(cameraControllerProvider.notifier).toggleFlash();
          },
        ),
        const SizedBox(width: 12),
      ],
      
      MiniPillButton(
        icon: Icons.flip_camera_ios,
        label: 'Flip',
        onTap: () async {
          HapticFeedback.selectionClick();
          // Show curtain immediately for smooth transition
          if (mounted) setState(() => _showCurtain = true);
          
          await ref.read(cameraControllerProvider.notifier).switchCamera();
          
          // Curtain is now lifted by state listener in build()
          // This ensures perfect timing on both fast and slow devices
        },
      ),
    ],
  );
}

IconData _getFlashIcon(FlashMode mode) {
  switch (mode) {
    case FlashMode.off:
      return Icons.flash_off;
    case FlashMode.auto:
      return Icons.flash_auto;
    case FlashMode.always:
      return Icons.flash_on;
    case FlashMode.torch:
      return Icons.highlight;
    default:
      return Icons.flash_off;
  }
}

  Widget _buildEditOptions() {
    // When audio is recorded (photo+audio OR audio-only), show audio controller bar
    if (_recordedAudioFile != null && (_capturedImage != null || _isAudioOnlyMode)) {
      return _buildAudioControllerBar();
    }
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        EditModeButton(
          icon: Icons.brush,
          label: 'Draw',
          isActive: _currentEditMode == EditMode.draw,
          accentColor: const Color(0xFFFF6B6B), // Coral red accent
          onTap: () => _setEditMode(EditMode.draw),
        ),
        const SizedBox(width: 12),
        EditModeButton(
          icon: Icons.emoji_emotions_outlined,
          label: 'Sticker',
          isActive: _currentEditMode == EditMode.sticker,
          accentColor: const Color(0xFF4ECDC4), // Teal accent
          onTap: () => _setEditMode(EditMode.sticker),
        ),
        const SizedBox(width: 12),
        EditModeButton(
          icon: Icons.text_fields,
          label: 'Text',
          isActive: _currentEditMode == EditMode.text,
          accentColor: const Color(0xFF667EEA), // Purple accent
          onTap: () => _setEditMode(EditMode.text),
        ),
        // Audio button - only show for photos (videos already have audio)
        if (_capturedImage != null) ...[
          const SizedBox(width: 12),
          EditModeButton(
            icon: Icons.mic_none_rounded,
            label: 'Voiceover',
            isActive: _currentEditMode == EditMode.audio,
            accentColor: const Color(0xFF00F0FF), // Cyan accent
            onTap: () => _setEditMode(EditMode.audio),
          ),
        ],
      ],
    );
  }
  
  /// Audio controller bar shown when audio is recorded (matches reference design)
  /// Shows: Delete | Play | Waveform | Duration (no send icon - already have send button below)
  Widget _buildAudioControllerBar() {
    final playbackState = ref.watch(playbackStateProvider);
    final isPlaying = playbackState == PlaybackState.playing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Delete button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              ref.read(audioServiceProvider).stop();
              setState(() {
                _recordedAudioFile = null;
                _audioDuration = 0;
              });
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Play/Pause button (Real State)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              final service = ref.read(audioServiceProvider);
              if (isPlaying) {
                service.pause();
              } else {
                if (_recordedAudioFile != null) {
                   service.playFromFile(_recordedAudioFile!.path);
                }
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPlaying ? AppColors.primaryAction : Colors.white.withOpacity(0.2),
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // ⚡ ISOLATED REPAINT: Waveform updates here will NOT rebuild the Camera Screen
          const WaveformVisualizer(
            barCount: 10,
            height: 24,
          ),
          
          const SizedBox(width: 12),
          
          // Duration
          Text(
            '${(_audioDuration ~/ 60).toString().padLeft(1, '0')}:${(_audioDuration % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainBottomControls() {
    // FIX #1 & #4: Audio-Only mode now has symmetric 3-button layout matching Camera mode
    // This keeps the user's thumb in the same "Action Zone" for consistency
    if (_isAudioOnlyMode) {
      // During audio recording, only show mic button (centered) for clean UI
      if (_isRecordingAudio) {
        return Center(
          child: _buildMicCaptureButton(),
        );
      }
      
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // LEFT: Gallery (for uploading old audio)
            BottomNavButton(
              icon: Icons.photo_library_rounded,
              label: 'Gallery',
              onTap: () => _showGalleryPicker(),
            ),
            
            // CENTER: Mic Shutter Button (matches camera shutter position)
            _buildMicCaptureButton(),
            
            // RIGHT: Back to Camera
            BottomNavButton(
              icon: Icons.camera_alt_rounded,
              label: 'Camera',
              onTap: () {
                HapticFeedback.selectionClick();
                // Cancel any in-progress recording
                if (_isRecordingAudio) {
                  ref.read(recordingStateProvider.notifier).stopRecording();
                  setState(() => _isRecordingAudio = false);
                }
                setState(() => _isAudioOnlyMode = false);
                // Bring Green Dot back for Camera Mode (re-init if needed)
                _resumeCamera();
                _notifyCaptureState(); // Show history indicator
              },
            ),
          ],
        ),
      );
    }
    
    // Normal Photo/Video mode
    // During video recording, only show the shutter button (centered)
    if (_isRecordingVideo) {
      return Center(
        child: _buildCaptureButton(),
      );
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // LEFT: Gallery / Vault
          BottomNavButton(
            icon: Icons.photo_library_rounded,
            label: 'Gallery',
            onTap: () => _showGalleryPicker(),
          ),
          
          // CENTER: Capture Button
          _buildCaptureButton(),
          
          // RIGHT: Audio Mode Toggle
          BottomNavButton(
            icon: Icons.mic,
            label: 'Audio',
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _isAudioOnlyMode = !_isAudioOnlyMode;
              });
              
              if (_isAudioOnlyMode) {
                _checkMicPermission();
              }
              
              // Toggle camera sensor based on mode
              final controller = ref.read(cameraControllerProvider).controller;
              if (_isAudioOnlyMode) {
                controller?.pausePreview(); // Kill Green Dot in Audio Mode
              } else {
                _resumeCamera(); // Bring Green Dot back for Camera (re-init if needed)
              }
              
              _notifyCaptureState(); // Hide/show history indicator
            },
          ),
        ],
      ),
    );
  }
  
  /// Start audio-only recording with Tap-to-Start/Stop pattern
  void _startAudioOnlyRecording() async {
    HapticFeedback.heavyImpact();
    setState(() => _isRecordingAudio = true);
    _notifyCaptureState(); // Hide history indicator
    
    // FIX: Stop any active audio playback before starting new recording
    ref.read(audioServiceProvider).stop();
    
    final success = await ref.read(recordingStateProvider.notifier).startRecording();
    if (!success && mounted) {
      setState(() {
        _isRecordingAudio = false;
        _isMicPermissionGranted = false;
      });
      _notifyCaptureState(); // Restore history indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission required'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
  
  /// Stop audio-only recording and show friend picker (consistent with Photo/Video)
  void _stopAudioOnlyRecording() async {
    HapticFeedback.mediumImpact();
    final path = await ref.read(recordingStateProvider.notifier).stopRecording();
    
    if (path != null && mounted) {
      final timerDuration = ref.read(recordingDurationProvider);
      final actualDuration = timerDuration > 0 ? timerDuration : 1;
      
      // NOTE: We NO LONGER clear duration/waveform here 
      // because AudioService now handles clearing at the START of next recording.
      // This allows us to use the data for sending!
      
      // Store the recorded audio file - UI will show audio controller bar
      // User can preview/delete audio before tapping send button
      setState(() {
        _recordedAudioFile = File(path);
        _audioDuration = actualDuration;
        _isRecordingAudio = false;
        // _hasCaptured getter now includes audio-only mode condition
      });
      
      // NOTE: Friend picker is now triggered by the send button (checkmark)
      // This matches the reference UI design with audio controller bar
    } else {
      setState(() => _isRecordingAudio = false);
    }
  }
  
  /// Show friend picker for Audio-Only mode (consistent with Photo/Video flow)
  void _showAudioOnlyFriendPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final friendsAsync = ref.watch(friendsProvider);
          
          return Container(
            padding: const EdgeInsets.all(24),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mic, color: Color(0xFF00F0FF)),
                    const SizedBox(width: 8),
                    Text(
                      'Send Audio Vibe (${_audioDuration}s)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                Expanded(
                  child: friendsAsync.when(
                    data: (friends) {
                      if (friends.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.people_outline, color: Colors.grey, size: 48),
                              const SizedBox(height: 16),
                              const Text(
                                'No friends yet',
                                style: TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  context.push('/add-friends');
                                },
                                child: const Text('Add Friends'),
                              ),
                            ],
                          ),
                        );
                      }
                      
                      return ListView.separated(
                        itemCount: friends.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final friend = friends[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundImage: friend.avatarUrl != null
                                  ? NetworkImage(friend.avatarUrl!)
                                  : null,
                              backgroundColor: Colors.grey[800],
                              child: friend.avatarUrl == null
                                  ? Text(friend.displayName[0].toUpperCase())
                                  : null,
                            ),
                            title: Text(
                              friend.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFF00F0FF),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.send, color: Colors.black, size: 20),
                            ),
                            onTap: () => _performAudioOnlyDirectSend(friend.id),
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: Color(0xFF00F0FF)),
                    ),
                    error: (_, __) => const Center(
                      child: Text('Error loading friends', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  /// Perform direct send for audio-only vibes (consistent with Photo/Video)
  /// Returns Task ID if successful
  Future<String?> _performAudioOnlyDirectSend(String receiverId) async {
    // REMOVED: Navigator.pop(context); <-- Let caller (Sheet) handle closing/feedback

    // Safety check: Ensure widget is still active before finding Scaffold
    if (!mounted) return null;

    // REMOVED: SnackBar (Spinner handled by Sheet)
    
    try {
      // 1. Prepare Metadata
      final waveform = ref.read(waveformDataProvider);
      
      // 2. Prepare Files (MUST happen before navigation)
      final audioFile = _recordedAudioFile;
      final audioExists = await audioFile?.exists() ?? false;
      final audioSize = audioExists ? await audioFile!.length() : 0;
      debugPrint('🔍 [CameraScreen] Preparing audio-only content (audioPath=${audioFile?.path}, exists=$audioExists, size=$audioSize bytes)');
      
      if (audioExists && audioSize == 0) {
        debugPrint('⚠️ [CameraScreen] WARNING: Audio file is empty (0 bytes)!');
      }
      
      // For audio-only, we need to create a background image
      File? imageFile = await _compositeImageWithOverlays();
      debugPrint('🔍 [CameraScreen] Aura snapshot captured: exists=${imageFile != null}, path=${imageFile?.path}');
      
      // Trigger background upload
      debugPrint('📤 [CameraScreen] Triggering background upload (audio-only) to receiver $receiverId');
      final taskId = await ref.read(vibeUploadProvider.notifier).addUpload(
        receiverId: receiverId,
        audioPath: _recordedAudioFile?.path,
        audioDuration: _audioDuration,
        waveformData: waveform,
        imagePath: imageFile?.path,
        videoPath: null,
        isVideo: false,
        isAudioOnly: true,
        isFromGallery: false,
      );
      
      // 3. CONTEXT-AWARE NAVIGATION (2026 UX Best Practice)
      // Walkie-Talkie Mode: Stay in mode for rapid exchanges
      // General Camera: Return to empty camera state (Sheet handles closing)
      if (mounted) {
        final isWalkieTalkieMode = widget.recipientId != null;
        
        if (isWalkieTalkieMode) {
          // WALKIE-TALKIE: Stay in audio-only mode for continuous conversation
          setState(() {
            _recordedAudioFile = null;
            _audioDuration = 0;
            // Keep _isAudioOnlyMode = true for next recording
          });
          
          // Success feedback without navigation
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF00F0FF), size: 20),
                  SizedBox(width: 12),
                  Text('Sent! Ready for next message', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              backgroundColor: Color(0xFF1E1E1E),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 1),
            ),
          );
        } else {
          // GENERAL CAMERA: Clean state but DO NOT navigate (Sheet handles flow)
          // If we are here, it means we sent successfully.
          // We just clear the recording so the camera is ready again.
          setState(() {
            _recordedAudioFile = null;
            _audioDuration = 0;
            _isAudioOnlyMode = false; // Exit audio-only mode? Maybe keep it if user prefers?
            // Default behavior: Reset to standard camera
          });
          
          // REMOVED: context.go('/'); <-- Sheet calls this if needed, or just closes.
          if (mounted) _askForNotificationsContextually();
        }
      }
      
      return taskId;

    } catch (e) {
      debugPrint('Error initiating audio send: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      return null;
    }
  }
  
  /// Build beautiful background for Audio-Only mode in camera view
  /// Premium glassmorphic orb design with waveform visualization
  Widget _buildAudioOnlyModeBackground() {
    final userAsync = ref.watch(currentUserProvider);
    
    return Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1: Profile image or gradient base
        userAsync.when(
          data: (user) {
            if (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty) {
              return Image.network(
                user.avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildAudioModeGradient(),
              );
            }
            return _buildAudioModeGradient();
          },
          loading: () => _buildAudioModeGradient(),
          error: (_, __) => _buildAudioModeGradient(),
        ),
        
        // Layer 2: Heavy blur effect
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: Container(color: Colors.transparent),
        ),
        
        // Layer 3: Dark overlay for contrast
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.2),
                Colors.black.withOpacity(0.4),
                Colors.black.withOpacity(0.6),
              ],
            ),
          ),
        ),
        
        // Layer 4: AuraVisualization for consistent look with preview
        // Layer 4: AuraVisualization REMOVED for "Noir Void" Design (Visual Noise Reduction)
        // The background is now purely the dark overlay + blurred avatar.
        
        // Layer 5: Main content - Compact layout for portal
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Title text
              // Title text / Prompt
              Text(
                _isRecordingAudio ? 'Today, I want to tell...' : 'Tap to start',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 22, // Larger prompt size
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // MAIN: Isolated Waveform & Duration Updates
              RepaintBoundary(
                child: Consumer(
                  builder: (context, ref, _) {
                    final recordingDuration = ref.watch(recordingDurationProvider);
                    final waveform = ref.watch(waveformDataProvider);
                    // Get amplitude for reactive pulse (0.0 to 1.0)
                    final amplitude = waveform.isNotEmpty ? waveform.last : 0.0;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // V2 TRANSMODAL ORB
                        // Handles its own animations (Ripples + Progress Ring)
                        BioluminescentOrb(
                          isRecording: _isRecordingAudio,
                          durationSeconds: recordingDuration,
                          amplitude: amplitude,
                          onTap: () {
                            if (_isRecordingAudio) {
                              _stopAudioOnlyRecording();
                            } else {
                              _startAudioOnlyRecording();
                            }
                          },
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Duration display when recording
                        // Duration display moved INSIDE the Orb (V2 Design)
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  /// Format duration as MM:SS
  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
  
  /// Build bottom action bar for audio mode
  Widget _buildAudioModeActionBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Retry / Re-record button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (_isRecordingAudio) {
                // Cancel current recording
                ref.read(recordingStateProvider.notifier).stopRecording();
                setState(() => _isRecordingAudio = false);
              }
              // Clear any recorded audio
              setState(() => _recordedAudioFile = null);
            },
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: PhosphorIcon(
                PhosphorIcons.arrowsClockwise(PhosphorIconsStyle.bold),
                color: Colors.white.withOpacity(0.8),
                size: 24,
              ),
            ),
          ),
          
          const SizedBox(width: 40),
          
          // Delete button
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              if (_isRecordingAudio) {
                ref.read(recordingStateProvider.notifier).stopRecording();
              }
              setState(() {
                _isRecordingAudio = false;
                _recordedAudioFile = null;
                _isAudioOnlyMode = false; // Exit audio mode
              });
            },
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withOpacity(0.2),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: PhosphorIcon(
                PhosphorIcons.trash(PhosphorIconsStyle.regular),
                color: AppColors.error.withOpacity(0.9),
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
  


  Widget _buildCapturedBottomControls() {
    // AUDIO MODE: Show Cancel + Mic recording UI
    if (_currentEditMode == EditMode.audio) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // LEFT: Cancel / Exit audio mode
            CircleActionButton(
              icon: PhosphorIcons.x(PhosphorIconsStyle.bold),
              label: 'Cancel',
              onTap: () {
                _setEditMode(EditMode.none);
              },
            ),
            
            // CENTER: Large Mic Button (tap to start/stop recording)
            GestureDetector(
              onTap: () {
                // Tap-to-toggle recording
                if (_isRecordingAudio) {
                  _stopVoiceRecording();
                } else {
                  _startVoiceRecording();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isRecordingAudio ? 88 : 80,
                height: _isRecordingAudio ? 88 : 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecordingAudio ? AppColors.error : Colors.grey.shade700,
                  border: Border.all(
                    color: _isRecordingAudio ? AppColors.error : Colors.grey.shade500,
                    width: 3,
                  ),
                  // NO VISUAL NOISE: Removed glow/shadow from Audio Mic button
                  boxShadow: null,
                ),
                child: PhosphorIcon(
                  _isRecordingAudio ? PhosphorIcons.stop(PhosphorIconsStyle.fill) : PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            
            // RIGHT: Show recorded indicator or empty space
            _recordedAudioFile != null && !_isRecordingAudio
                ? CircleActionButton(
                    icon: PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                    label: 'Done',
                    onTap: () => _setEditMode(EditMode.none),
                  )
                : const SizedBox(width: 52),
          ],
        ),
      );
    }
    
    // NORMAL MODE: Retake, Send, Save
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CircleActionButton(
            icon: PhosphorIcons.arrowsClockwise(PhosphorIconsStyle.bold),
            label: 'Retake',
            onTap: _discardCapture,
          ),
          _buildSendButton(),
          // Save button: Hide for audio-only mode (galleries don't support audio files)
          // Show for Photo, Video, and Photo+Audio
          if (!_isAudioOnlyMode || _capturedImage != null || _capturedVideo != null)
            CircleActionButton(
              icon: PhosphorIcons.downloadSimple(PhosphorIconsStyle.bold),
              label: 'Save',
              onTap: _saveToGallery,
            )
          else
            const SizedBox(width: 52), // Placeholder to maintain layout
        ],
      ),
    );
  }
  
  // ============ GALLERY SAVE (Uses ViralVideoService as Single Source of Truth) ============
  
  /// Save captured media to device gallery
  /// 
  /// Delegates to ViralVideoService.saveToGallery() which handles:
  /// - Photo: Saves directly as image
  /// - Video: Saves directly as video
  /// - Photo + Audio: Merges to MP4 (1:1 raw format) then saves
  /// - Audio-only: Button is hidden (unsupported by galleries)
  Future<void> _saveToGallery() async {
    if (!mounted) return;
    
    HapticFeedback.mediumImpact();
    
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Saving to gallery...'),
            ],
          ),
          duration: Duration(seconds: 10),
          backgroundColor: Colors.black87,
        ),
      );
      
      // Use ViralVideoService as single source of truth for all media operations
      final mediaService = ref.read(viralVideoServiceProvider);
      
      final success = await mediaService.saveToGallery(
        imageFile: _capturedImage,
        videoFile: _capturedVideo,
        audioFile: _recordedAudioFile,
        albumName: 'Vibe',
      );
      
      // Hide loading and show result
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        if (success) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                  const SizedBox(width: 12),
                  const Text('Saved to Gallery! 📸'),
                ],
              ),
              backgroundColor: Colors.black87,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Save Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ============ AUDIO RECORDING METHODS ============
  
  void _startVoiceRecording() async {
    HapticFeedback.heavyImpact();
    setState(() => _isRecordingAudio = true);
    
    // FIX: Stop any active audio playback before starting voice recording
    ref.read(audioServiceProvider).stop();
    
    final success = await ref.read(recordingStateProvider.notifier).startRecording();
    if (!success && mounted) {
      setState(() {
        _isRecordingAudio = false;
        _isMicPermissionGranted = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission required'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
  
  void _stopVoiceRecording() async {
    HapticFeedback.mediumImpact();
    final path = await ref.read(recordingStateProvider.notifier).stopRecording();
    
    if (path != null && mounted) {
      // Get recorded duration from timer
      // If timer shows 0 but we have a file, minimum is 1 second
      final timerDuration = ref.read(recordingDurationProvider);
      
      // This prevents the fallback to 5 seconds which causes progress bar desync
      final actualDuration = timerDuration > 0 ? timerDuration : 1;
      
      setState(() {
        _recordedAudioFile = File(path);
        _audioDuration = actualDuration;
        _isRecordingAudio = false;
        _currentEditMode = EditMode.none; // Auto-exit audio mode
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              PhosphorIcon(PhosphorIcons.microphone(PhosphorIconsStyle.fill), color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('Voice note added ($_audioDuration s)'),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      setState(() => _isRecordingAudio = false);
    }
  }
  
  Widget _buildCaptureButton() {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerMove: _handlePointerMove,
      onPointerCancel: _handlePointerCancel,
      child: AnimatedBuilder(
        animation: _shutterAnimation,
        builder: (context, child) {
          // UX UPDATE: Use Starlight (Off-White) per user choice "Option B"
          final shutterColor = _isRecordingVideo ? AppColors.urgency : AppColors.textPrimary;
          
          return Transform.scale(
            scale: _shutterAnimation.value,
            child: Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: shutterColor, width: 4),
                  // NO VISUAL NOISE: Removed glow/shadow from Shutter Outer Ring
                  boxShadow: null,
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isRecordingVideo ? 32 : 68,
                    height: _isRecordingVideo ? 32 : 68,
                    decoration: BoxDecoration(
                      color: shutterColor,
                      borderRadius: BorderRadius.circular(_isRecordingVideo ? 8 : 34),
                      // NO VISUAL NOISE: Removed glow/shadow from Inner Shutter
                      boxShadow: null,
                    ),
                    child: _isRecordingVideo ? null : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('HOLD', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          Text('TO REC', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ),
                ),
            ),
          );
        },
      ),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
  if (_hasCaptured || _isProcessingCapture) return;
  
  // 🧭 JIT PERMISSION FIX: If camera is not ready, trigger request instead of silent fail
  final cameraState = ref.read(cameraControllerProvider);
  if (!cameraState.isInitialized && !_isAudioOnlyMode) {
    if (cameraState.error == 'Camera permission required' || cameraState.error == 'Camera permission denied') {
      _requestCameraPermission();
      return;
    }
  }

  _pointerDownTime = DateTime.now();
  _dragStartY = event.position.dy;
  _baseZoom = ref.read(cameraControllerProvider).zoomLevel;
  _shutterController.forward(); // Scale down button on press
  
  // Start video recording after 500ms hold
  _longPressTimer?.cancel();
  _longPressTimer = Timer(_tapThreshold, () {
    if (mounted && _pointerDownTime != null) {
      _startVideoRecording();
    }
  });
}

  void _handlePointerMove(PointerMoveEvent event) {
  if (!_isRecordingVideo || _pointerDownTime == null) return;

  // SNAPCHAT SLIDE ZOOM
  // Dragging UP (negative delta) increases zoom
  final double dragDelta = _dragStartY - event.position.dy;
  
  // Sensitivity: 200 pixels for full zoom range (approx)
  // We use the hardware limits from MediaService
  final cameraState = ref.read(cameraControllerProvider);
  final minZoom = cameraState.minZoom;
  
  // INDUSTRY STANDARD: Cap front camera zoom to prevent extreme pixelation
  // while still allowing "Dramatic Zoom" and 0.5x Ultra-wide hardware
  final maxZoom = cameraState.isFrontCamera ? 3.0 : cameraState.maxZoom;

  // Calculate new zoom level
  // 0.01 zoom per pixel of drag
  final double newZoom = (_baseZoom + (dragDelta / 150)).clamp(minZoom, maxZoom);
  
  if (newZoom != cameraState.zoomLevel) {
    ref.read(cameraControllerProvider.notifier).setZoomLevel(newZoom);
  }
}

void _handlePointerUp(PointerUpEvent event) {
  if (_pointerDownTime == null) return;
  
  final duration = DateTime.now().difference(_pointerDownTime!);
  _pointerDownTime = null;
  
  _longPressTimer?.cancel();
  _longPressTimer = null;
  
  _shutterController.reverse(); // Scale button back up
  
  if (duration < _tapThreshold) {
    // Release before 500ms -> It's a TAP (Photo)
    debugPrint('👆 Capture TAP -> Photo');
    _takePhoto();
  } else {
    // Release after 500ms -> It's a RELEASE (Stop Video)
    debugPrint('🖖 Capture RELEASE -> STOP UI (Ghost Mode)');
    
    // GHOST START: Update UI immediately
    if (_isRecordingVideo) {
      setState(() {
        _isRecordingVideo = false;
        // Do NOT set _isProcessingCapture = false yet
      });
      _recordingProgressController.stop();
      _pulseController.stop();
      HapticFeedback.mediumImpact();
      
      // Hardware stop happens in background (Ghost)
      _ghostStopHardware();
    }
  }
}

  void _handlePointerCancel(PointerCancelEvent event) {
    debugPrint('⚠️ Capture CANCELLED (Finger dragged away)');
    _handlePointerUp(PointerUpEvent(
      pointer: event.pointer,
      position: event.position,
    ));
  }
  
  /// Mic capture button for Audio-Only mode (matches camera shutter position/style)
  Widget _buildMicCaptureButton() {
    return GestureDetector(
      onTap: () {
        if (_isRecordingAudio) {
          _stopAudioOnlyRecording();
        } else {
          _startAudioOnlyRecording();
        }
      },
      child: AnimatedBuilder(
        animation: _shutterAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _shutterAnimation.value,
            child: Container(
              width: 84, height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  // UX UPDATE: Use Lavender to signal "Flow/Mental Health" (not "Emergency Red")
                  color: _isRecordingAudio ? AppColors.telemetry : AppColors.textPrimary,
                  width: 4,
                ),
                // NO VISUAL NOISE: Removed glow/shadow from Mic Outer Ring
                boxShadow: null,
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isRecordingAudio ? 32 : 68,
                  height: _isRecordingAudio ? 32 : 68,
                  decoration: BoxDecoration(
                    gradient: _isRecordingAudio 
                        ? null 
                        : LinearGradient(colors: [AppColors.textPrimary, AppColors.textPrimary.withOpacity(0.7)]),
                    color: _isRecordingAudio ? AppColors.telemetry : null,
                    borderRadius: BorderRadius.circular(_isRecordingAudio ? 8 : 34),
                    // NO VISUAL NOISE: Removed glow/shadow from Shutter Ring
                  boxShadow: null,
                  ),
                  child: Center(
                    child: PhosphorIcon(
                      _isRecordingAudio ? PhosphorIcons.stop(PhosphorIconsStyle.fill) : PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                      // VISIBILITY FIX: Black icon on Lavender background (White vanishes)
                      color: _isRecordingAudio ? Colors.black : Colors.black,
                      size: _isRecordingAudio ? 20 : 32,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSendButton() {
    return GestureDetector(
      onTap: _sendVibe,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 72, height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Green for success/loading, standard for idle
          color: (_showMainSendCheckmark || _isMainSendLoading) ? AppColors.primaryAction : AppColors.primaryAction, 
          // NO VISUAL NOISE: Removed glow/shadow from Send button
          boxShadow: null,
        ),
        child: Center(
          child: _isMainSendLoading
              ? const SizedBox(
                  width: 32, height: 32,
                  child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3),
                )
              : _showMainSendCheckmark
                  ? const Icon(Icons.check, color: Colors.black, size: 32)
                  : PhosphorIcon(PhosphorIcons.paperPlaneRight(PhosphorIconsStyle.fill), color: Colors.black, size: 28),
        ),
      ),
    );
  }



  /// New Helper: Centralized camera permission request logic
  Future<void> _requestCameraPermission() async {
    debugPrint('🔘 Requesting Camera Permission...');
    
    var status = await Permission.camera.status;
    debugPrint('   Current status before request: $status');

    if (status.isPermanentlyDenied) {
      debugPrint('   -> Status is PERMANENTLY DENIED. Opening settings...');
      await openAppSettings();
      return;
    }

    // On Android, isDenied can sometimes mean "Permanently Denied" if "Don't ask again" was checked previously
    // So we request it. If it returns immediately with denied/permanentlyDenied, we know.
    debugPrint('   Requesting permission via system dialog...');
    final newStatus = await Permission.camera.request();
    debugPrint('   -> Request result: $newStatus');

    if (newStatus.isGranted) {
      debugPrint('   -> Permission GRANTED! Initializing camera...');
      if (mounted) {
        setState(() => _showCurtain = true);
      }
      _initializeCamera();
    } else if (newStatus.isPermanentlyDenied) {
      debugPrint('   -> Status is PERMANENTLY DENIED. Opening settings...');
      openAppSettings();
    } else {
      debugPrint('   -> Permission DENIED (but not permanent? or system did not show dialog).');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera access is needed to use this feature.')),
        );
      }
    }
  }



  /// Helper: Centralized microphone permission request logic
  Future<void> _requestMicPermission() async {
    debugPrint('🔘 Requesting Microphone Permission...');
    
    var status = await Permission.microphone.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }

    final newStatus = await Permission.microphone.request();
    if (mounted) {
      setState(() {
        _isMicPermissionGranted = newStatus.isGranted;
      });
      
      if (!newStatus.isGranted && !newStatus.isPermanentlyDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone access is needed for audio vibes.')),
        );
      } else if (newStatus.isPermanentlyDenied) {
        openAppSettings();
      }
    }
  }

  /// Gradient fallback for audio mode
  Widget _buildAudioModeGradient() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            // NOIR VOID: Deep atmospheric gradient (No Rainbows)
            AppColors.voidNavy,
            AppColors.surface,
          ],
        ),
      ),
    );
  }

}

/// Smart Send Sheet Widget (Material Design 3 / Snapchat pattern)

