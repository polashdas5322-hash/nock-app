import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/services/audio_service.dart';
import 'package:nock/core/services/vibe_service.dart';
import 'package:nock/core/services/transcription_service.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/services/viral_video_service.dart';
import 'package:nock/features/camera/domain/services/video_processing_service.dart';
import 'package:nock/core/models/vibe_model.dart';
import 'package:nock/shared/widgets/glass_container.dart';
import 'package:nock/shared/widgets/aura_visualization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ghost Player Screen - Deep link view when tapping the widget
/// Shows the photo with Aura visualization and voice playback
/// Includes instant voice reply functionality
class PlayerScreen extends ConsumerStatefulWidget {
  final VibeModel? vibe;
  final String? vibeId;
  /// When true, auto-highlights reply button after playback (opens from notification)
  final bool fromNotification;
  /// List of vibes for horizontal swipe navigation (from Vault)
  final List<VibeModel>? vibesList;
  /// Starting index in vibesList
  final int? startIndex;

  const PlayerScreen({
    super.key,
    this.vibe,
    this.vibeId,
    this.fromNotification = false,
    this.vibesList,
    this.startIndex,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // FIX: Subscription management
  StreamSubscription? _audioStateSubscription;
  StreamSubscription? _audioPositionSubscription;
  
  
  
  // FIX: Store audio service reference for safe disposal
  AudioPlayer? _scopedAudioPlayer;
  
  bool _isPlaying = false;
  bool _isBuffering = false; // NEW: Track buffering explicitly
  bool _hasPlayed = false;
  bool _isReplying = false;
  double _playbackProgress = 0.0;
  
  bool _isExportingVideo = false;
  double _exportProgress = 0.0;
  
  // FIX: Mutex for recording stop to prevent double-submit (User Tap + Timer)
  bool _isStoppingReply = false;

  // For transcription display
  bool _showTranscription = false;
  String? _transcriptionText;
  
  // Video player for video vibes
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  
  
  // INSTANT REPLY: Mic pre-warmed during playback
  bool _micPreWarmed = false;
  bool _showReplyFocus = false;  // Highlights reply after playback if from notification
  
  // Vibe State
  VibeModel? _vibe;
  bool _isLoading = true;
  String? _error;
  
  // TEXT REPLIES: Visual Whispers
  bool _isTextReplying = false;
  final TextEditingController _textReplyController = TextEditingController();
  final FocusNode _textReplyFocusNode = FocusNode();
  
  // REACTIONS: Quick Reactions widget rain
  final List<FloatingEmoji> _floatingEmojis = [];
  Timer? _emojiCleanupTimer;
  
  // SWIPE NAVIGATION: PageController for horizontal swipe through vibes list
  PageController? _pageController;
  int _currentVibeIndex = 0;
  bool get _hasSwipeNavigation => widget.vibesList != null && widget.vibesList!.length > 1;
  
  // FIX Issue 3: Track current vibe URL to cancel stale initializations
  String? _currentVibeUrl;

  // NEW: Ghost Hints state (Progressive Disclosure)
  bool _showGhostHints = false;
  Timer? _ghostHintTimer;
  static const String _ghostHintsSeenKey = 'player_ghost_hints_seen';

  // Voice Reply Preview State
  String? _pendingReplyPath; // Path of recorded audio awaiting confirmation
  bool _isPreviewingReply = false; // Is user in preview mode
  bool _isPlayingPreview = false; // Is preview audio currently playing
  AudioPlayer? _previewPlayer; // Player for preview playback
  
  // Consistency: 15s limit for voice replies
  Timer? _recordingLimitTimer;

  @override
  void initState() {
    super.initState();
    // LIFECYCLE FIX: Register observer to pause media on background
    WidgetsBinding.instance.addObserver(this);
    
    // NOTE: We no longer store _audioService. We use scoped provider on demand.

    
    // SWIPE NAVIGATION: Initialize PageController if vibesList provided
    if (_hasSwipeNavigation) {
      _currentVibeIndex = widget.startIndex ?? 0;
      _pageController = PageController(initialPage: _currentVibeIndex);
      // Set initial vibe from the list
      _vibe = widget.vibesList![_currentVibeIndex];
      _hasPlayed = !_hasAudioOrVideo(); // FIX: Immediate reply for image-only
      _isLoading = false;
      _initAnimations();
    } else if (widget.vibe != null) {
      _vibe = widget.vibe;
      _hasPlayed = !_hasAudioOrVideo(); // FIX: Immediate reply for image-only
      _isLoading = false;
      _initAnimations();
    } else if (widget.vibeId != null) {
      _fetchVibe(widget.vibeId!);
    } else {
      setState(() {
        _isLoading = false;
        _error = "Vibe not found";
      });
    }
  }
  
  Future<void> _fetchVibe(String id) async {
    try {
      final vibe = await ref.read(vibeServiceProvider).getVibeById(id);
      if (mounted) {
        setState(() {
          _vibe = vibe;
          _isLoading = false;
          if (vibe != null) {
            // FIX: Set _hasPlayed for image-only vibes (same as other init paths)
            _hasPlayed = !_hasAudioOrVideo();
            _initAnimations();
          } else {
            _error = "Vibe not found";
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Error loading vibe";
        });
      }
    }
  }
  
  /// SWIPE NAVIGATION: Handle page change when user swipes to different vibe
  void _onVibeChanged(int newIndex) {
    if (!_hasSwipeNavigation || newIndex == _currentVibeIndex) return;
    
    // Stop current playback
    _videoController?.pause();
    _scopedAudioPlayer?.stop();
    
    // Clean up video controller for previous vibe
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    _videoController = null;
    _isVideoInitialized = false;
    
    // Reset playback state
    _isPlaying = false;
    _playbackProgress = 0.0;
    
    setState(() {
      _currentVibeIndex = newIndex;
      _vibe = widget.vibesList![newIndex];
      _hasPlayed = !_hasAudioOrVideo(); // FIX: Immediate reply for image-only
    });
    
    // Initialize media for new vibe
    if (_vibe!.isVideo && _vibe!.videoUrl != null) {
      _initVideoPlayer(_vibe!.videoUrl!);
    } else {
      // Auto-play audio for non-video vibes
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playAudio();
      });
    }

    // HYBRID: Auto-load transcription for "Read-First" intake
    _loadTranscription(silent: true);
  }
  
  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();

    // NEW: Trigger Ghost Hints after a short delay (Progressive Disclosure)
    // Only show hints if user has never seen them before
    _checkAndShowGhostHints();

    // Pulse animation for "Hold to Reply" hit (always running, applied conditionally)
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.02).animate( // Subtle 2% zoom pulse
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initialize video player for video vibes (uses built-in audio, no separate audio service)
    if (_vibe != null && _vibe!.isVideo && _vibe!.videoUrl != null) {
      _initVideoPlayer(_vibe!.videoUrl!);
      // Note: Don't call _playAudio() for video vibes - video has built-in audio
    } else {
      // Photo vibes: Auto-play separate audio on entry
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playAudio();
      });
    }

    // HYBRID: Auto-load transcription for "Read-First" intake
    _loadTranscription(silent: true);
  }
  
  Future<void> _initVideoPlayer(String videoUrl) async {
    // FIX Issue 3: Track current URL to cancel stale initializations
    _currentVibeUrl = videoUrl;
    
    // Claim Hardware Resource for Video
    if (_vibe != null) {
      ref.read(activeContentIdProvider.notifier).state = _vibe!.id;
    }
    
    final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    _videoController = controller; // Keep track for dispose()

    try {
      await controller.initialize();
      
      // FIX: Ensure widget is mounted AND the controller is still the current one
      // AND the URL still matches the current target (Issue 3 - prevents stale init)
      if (!mounted || _videoController != controller || _currentVibeUrl != videoUrl) return;

      // FIX Issue 5: Enable looping for short-form video content (TikTok/Locket style)
      controller.setLooping(true);
      controller.setVolume(1.0); 
      
      // FIX: Listen to the controller for state (Buffering/Playing)
      controller.addListener(_videoListener);
      
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
      }

      // Android Stability: Short delay to ensure surface is ready
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted && _videoController == controller) {
        await controller.play();
      }
    } catch (e) {
      debugPrint('Error initializing video player: $e');
    }
  }

  // New Listener Method for Video
  void _videoListener() {
    if (!mounted || _videoController == null) return;
    
    // Check playback state via VideoPlayerValue
    final isPlaying = _videoController!.value.isPlaying;
    final isBuffering = _videoController!.value.isBuffering;
    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;
    
    // FIX: Only show playing if actually playing AND not buffering
    final shouldShowPlaying = isPlaying && !isBuffering;
    
    // Update state if anything changed
    if (_isPlaying != shouldShowPlaying || _isBuffering != isBuffering) {
      if (mounted) {
        setState(() {
          _isPlaying = shouldShowPlaying;
          _isBuffering = isBuffering;
        });
      }
    }
    
    // Handle progress updates
    if (duration.inMilliseconds > 0) {
      if (mounted) {
        setState(() {
          _playbackProgress = position.inMilliseconds / duration.inMilliseconds;
        });
      }
    }

    // Check completion
    // FIX Issue 2: Mark as played at 50% or after 3 seconds (relaxed from 90%)
    // This matches user attention spans for short-form content
    final percentComplete = duration.inMilliseconds > 0 
        ? position.inMilliseconds / duration.inMilliseconds 
        : 0.0;
    final threeSecondsWatched = position.inMilliseconds >= 3000;
        
    if (duration.inMilliseconds > 0 && 
        (percentComplete > 0.5 || threeSecondsWatched)) {
      if (!_hasPlayed) {
        setState(() {
          _hasPlayed = true;
        });
        ref.read(vibeServiceProvider).markAsPlayed(_vibe!.id);
      }
    }
  }
  
  void _onVideoPositionChanged() {
    if (!mounted || _videoController == null) return;
    
    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;
    
    if (duration.inMilliseconds > 0) {
      setState(() {
        _playbackProgress = position.inMilliseconds / duration.inMilliseconds;
      });
    }
    
    // Check if video completed
    if (_videoController!.value.position >= _videoController!.value.duration &&
        _videoController!.value.duration.inMilliseconds > 0) {
      if (!_hasPlayed) {
        setState(() {
          _isPlaying = false;
          _hasPlayed = true;
        });
        // Mark as played
        ref.read(vibeServiceProvider).markAsPlayed(_vibe!.id);
      }
    }
  }

  @override
  void dispose() {
    // LIFECYCLE FIX: Remove observer
    WidgetsBinding.instance.removeObserver(this);
    
    // FIX: Stop recording if user is currently replying (prevents mic lock on Android)
    if (_isReplying) {
      ref.read(recordingStateProvider.notifier).stopRecording().then((_) {
        debugPrint('Background recording stopped safely during dispose.');
      }).catchError((e) {
        debugPrint('Error cleaning up recording on dispose: $e');
      });
    }

    _recordingLimitTimer?.cancel();
    
    // FIX: Cancel subscriptions to prevent leaks
    _audioStateSubscription?.cancel();
    _audioPositionSubscription?.cancel();
    
    _fadeController.dispose();
    _pulseController.dispose();
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    
    // SWIPE NAVIGATION: Dispose PageController
    _pageController?.dispose();
    
    // NOTE: scopedAudioPlayerProvider is autoDispose, so we don't need manual cleanup
    // unless we want to be explicit.
    _emojiCleanupTimer?.cancel();
    _textReplyController.dispose();
    _textReplyFocusNode.dispose();
    _ghostHintTimer?.cancel();
    
    // FIX: Dispose preview player
    _previewPlayer?.dispose();
    
    super.dispose();
  }

  // LIFECYCLE FIX: Pause media when app is backgrounded
  // Prevents "zombie audio" (sound playing while app is closed)
  // and UI desync (Play button showing "Pause" when video is stopped)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 1. App Paused or Inactive: Safe Lifecycle Management
    // Trigger on inactive (earlier) to gain extra milliseconds on iOS
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Force pause video
      _videoController?.pause();

      // STOP PLAYBACK IMMEDIATELY to prevent "Zombie Audio"
      // FIX: Stop the SCOPED audio service (which is actually playing), not just the global one
      _scopedAudioPlayer?.pause();
      ref.read(audioServiceProvider).pause();
      
      // Force STOP active audio (if any) by clearing global ID
      ref.read(activeContentIdProvider.notifier).state = null;
      
      if (mounted) {
        setState(() => _isPlaying = false);
      }
      debugPrint('PlayerScreen: Stopped audio on app background to release resources');
    }
  }

  Future<void> _playAudio() async {
    // Prevent duplicate calls if already trying to play
    if (_isPlaying) return;

    HapticFeedback.mediumImpact();

    // 1. Claim Hardware Resource (Stop others)
    ref.read(activeContentIdProvider.notifier).state = _vibe!.id;

    // 2. Get Scoped Player (Auto-disposed when screen closes)
    // FIX: Assign to class member so we can stop it later!
    final audioService = ref.read(scopedAudioPlayerProvider(_vibe!.id));
    _scopedAudioPlayer = audioService;

    // FIX: Cancel old subscriptions first to prevent zombies
    await _audioPositionSubscription?.cancel();
    await _audioStateSubscription?.cancel();

    // FIX: Assign subscription to variable
    // FIX: Access direct `AudioPlayer` getters on the scoped instance
    _audioPositionSubscription = audioService.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          final totalDurationMs = (_vibe!.audioDuration * 1000).toDouble();
          // SAFETY: Check for zero to prevent NaN crash
          if (totalDurationMs > 0) {
            _playbackProgress = (position.inMilliseconds / totalDurationMs).clamp(0.0, 1.0);
          } else {
            _playbackProgress = 0.0;
          }
        });
      }
    });

    // FIX: Assign state subscription and drive _isPlaying from engine events
    // FIX: Access direct `AudioPlayer` getters on the scoped instance
    _audioStateSubscription = audioService.onPlayerStateChanged.listen((state) {
      if (mounted) {
        // Only consider 'playing' if we receive that specific state
        final bool isActuallyPlaying = state.name == 'playing';
        if (_isPlaying != isActuallyPlaying) {
          setState(() => _isPlaying = isActuallyPlaying);
        }
        
        if (state.name == 'completed') {
          setState(() {
            _isPlaying = false;
            _hasPlayed = true;
            // INSTANT REPLY: Show reply focus if opened from notification
            if (widget.fromNotification) {
              _showReplyFocus = true;
            }
          });
          // Mark as played
          ref.read(vibeServiceProvider).markAsPlayed(_vibe!.id);
        }
      }
    });

    // INSTANT REPLY: Pre-warm microphone permission during playback
    // This eliminates the permission dialog delay when user taps reply
    if (!_micPreWarmed) {
      _preWarmMicrophone();
    }

    // 🔴 CRITICAL FIX 1: Ensure audio URL is NOT empty to prevent FileNotFoundException
    // This happens for video vibes or vibes where audio upload failed.
    if (_vibe!.audioUrl.isEmpty) {
      debugPrint('PlayerScreen: Skipping audio playback (audioUrl is empty)');
      return;
    }

    // 🔴 CRITICAL FIX 2: Verify the widget is still on screen before starting playback
    // This prevents "Zombie Audio" if the screen was closed during permissions/warmup
    if (!mounted) return;

    await audioService.play(UrlSource(_vibe!.audioUrl));
  }
  
  /// Pre-warm microphone: Check permission in background during playback
  /// User sees no dialog - just prepares the system for instant recording
  Future<void> _preWarmMicrophone() async {
    try {
      final recorder = AudioRecorder();
      final hasPermission = await recorder.hasPermission();
      if (mounted) {
        setState(() => _micPreWarmed = hasPermission);
      }
      debugPrint('PlayerScreen: Mic pre-warmed, hasPermission: $hasPermission');
    } catch (e) {
      debugPrint('PlayerScreen: Mic pre-warm failed: $e');
    }
  }

  void _togglePlayback() async {
    HapticFeedback.selectionClick();
    
    // FIX: Video vibes - explicit handling with defensive checks
    if (_vibe != null && _vibe!.isVideo) {
      // DEFENSIVE: Check if controller is initialized before attempting toggle
      if (_videoController != null && _videoController!.value.isInitialized) {
        // Claim resource if not already mine (Important for resuming video)
        ref.read(activeContentIdProvider.notifier).state = _vibe!.id;
        
        if (_isPlaying) {
          _videoController!.pause();
          setState(() => _isPlaying = false);
        } else {
          // If video ended, seek to start
          if (_videoController!.value.position >= _videoController!.value.duration) {
            await _videoController!.seekTo(Duration.zero);
          }
          _videoController!.play();
          setState(() => _isPlaying = true);
        }
      }
      // CRITICAL: Stop here - do NOT fall through to audio service
      return;
    }
    
    // Photo vibes: Control AudioService
    final audioService = ref.read(scopedAudioPlayerProvider(_vibe!.id));
    
    // Claim resource if not already mine
    ref.read(activeContentIdProvider.notifier).state = _vibe!.id;
    
    if (_isPlaying) {
      await audioService.pause();
      setState(() => _isPlaying = false);
    } else {
      await audioService.resume();
      setState(() => _isPlaying = true);
    }
  }

  void _startReply() {
    // FIX: CRITICAL - Pause all media BEFORE starting recording
    // This prevents the microphone from capturing speaker output (feedback loop)
    // Clear active ID stops all players
    ref.read(activeContentIdProvider.notifier).state = null;
    _videoController?.pause();
    setState(() => _isPlaying = false);
    
    // Now start recording
    setState(() => _isReplying = true);
    ref.read(recordingStateProvider.notifier).startRecording();
    HapticFeedback.heavyImpact();

    // Consistency: Enforce 15s Limit (Sync with Camera)
    _recordingLimitTimer?.cancel();
    _recordingLimitTimer = Timer(const Duration(seconds: 15), () {
      if (_isReplying && mounted) {
        _stopReply(); // Automatically stop recording
        HapticFeedback.heavyImpact(); // Alert user it stopped
      }
    });
  }

  Future<void> _stopReply() async {
    // FIX: Mutex to prevent race condition between Timer and Manual Stop
    if (_isStoppingReply) return;
    _isStoppingReply = true;
    
    _recordingLimitTimer?.cancel();
    
    try {
      final path = await ref.read(recordingStateProvider.notifier).stopRecording();
      
      if (path != null) {
        // Enter preview mode instead of sending immediately
        setState(() {
          _pendingReplyPath = path;
          _isPreviewingReply = true;
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint('Error stopping recorder: $e');
    } catch (e) {
      debugPrint('Error stopping recorder: $e');
    } finally {
      _isStoppingReply = false; // Release mutex
      if (mounted) {
        setState(() => _isReplying = false);
      }
    }
  }
  
  /// Play the recorded audio preview
  Future<void> _playPreview() async {
    if (_pendingReplyPath == null) return;
    
    try {
      _previewPlayer ??= AudioPlayer();
      await _previewPlayer!.play(DeviceFileSource(_pendingReplyPath!));
      setState(() => _isPlayingPreview = true);
      
      // Listen for completion
      _previewPlayer!.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() => _isPlayingPreview = false);
        }
      });
    } catch (e) {
      debugPrint('Error playing preview: $e');
    }
  }
  
  /// Pause the preview playback
  Future<void> _pausePreview() async {
    await _previewPlayer?.pause();
    setState(() => _isPlayingPreview = false);
  }
  
  /// Cancel the pending reply
  Future<void> _cancelReply() async {
    // Stop preview if playing
    await _previewPlayer?.stop();
    
    // Delete the recorded file
    if (_pendingReplyPath != null) {
      try {
        await File(_pendingReplyPath!).delete();
      } catch (_) {}
    }
    
    setState(() {
      _pendingReplyPath = null;
      _isPreviewingReply = false;
      _isPlayingPreview = false;
    });
    HapticFeedback.lightImpact();
  }
  
  /// Confirm and send the reply
  Future<void> _confirmSendReply() async {
    if (_pendingReplyPath == null) return;
    
    // Stop preview if playing
    await _previewPlayer?.stop();
    
    final path = _pendingReplyPath!;
    
    // Reset preview state
    setState(() {
      _pendingReplyPath = null;
      _isPreviewingReply = false;
      _isPlayingPreview = false;
    });
    
    // Send the reply
    try {
      await ref.read(vibeServiceProvider).replyToVibe(
        originalVibeId: _vibe!.id,
        receiverId: _vibe!.senderId,
        audioFile: File(path),
        audioDuration: ref.read(recordingDurationProvider),
        waveformData: ref.read(waveformDataProvider),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reply sent!'),
            backgroundColor: AppColors.success,
          ),
        );
        
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.home);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send reply: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryAction),
        ),
      );
    }
    
    if (_error != null || _vibe == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              Text(
                _error ?? "Vibe unavailable",
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.home),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryAction,
                ),
                child: Text('Go Home', style: AppTypography.buttonText),
              ),
            ],
          ),
        ),
      );
    }

    // Determine content type
    String statusText = _getStatusText();
    Color statusColor = _getStatusColor();

    // Determine content type
    // Determine content type
    final bool isAudioOnly = _vibe!.isAudioOnly;
    final bool isVideo = _vibe!.isVideo && _vibe!.videoUrl != null;
    
    // FIX: Prioritize showing image if it exists, even if isAudioOnly flag is set
    // This prevents "Photo Only" vibes from appearing as "Audio Only" if flags are misconfigured
    final bool hasImage = !isVideo && _vibe!.imageUrl != null && _vibe!.imageUrl!.isNotEmpty;

    // ZOMBIE UI PREVENTION: Watch the scoped player to keep it alive
    ref.watch(scopedAudioPlayerProvider(_vibe!.id));
    
    // LISTEN for focus loss (Active ID changed -> Stop/Pause)
    ref.listen(activeContentIdProvider, (prev, next) {
      if (next != _vibe!.id) {
        // Someone else took audio focus!
        if (_videoController != null && _videoController!.value.isPlaying) {
          _videoController!.pause();
        }
        if (mounted) setState(() => _isPlaying = false);
      }
    });


    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false, // FIX: Prevent keyboard from squashing the "Portal"
      body: Builder( // WRAP IN BUILDER TO USE CONTEXT SAFELY
        builder: (context) {
          // REDUNDANT LISTENERS REMOVED: (ref.watch/ref.listen was here and caused crash)
          
          return LayoutBuilder(
            builder: (context, constraints) {
          final scale = constraints.maxWidth / 360;
          
          return GestureDetector(
            // Hold anywhere to reply (after playback)
            onTap: () {
              if (_isTextReplying) {
                _textReplyFocusNode.unfocus();
                setState(() => _isTextReplying = false);
              } else {
                _togglePlayback();
              }
            },
            onDoubleTap: () => _addQuickReaction('❤️'),
            // SWIPE NAVIGATION: Horizontal drag to navigate between vibes
            onHorizontalDragEnd: _hasSwipeNavigation ? (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity > 300 && _currentVibeIndex > 0) {
                // Swipe right -> previous vibe
                _onVibeChanged(_currentVibeIndex - 1);
              } else if (velocity < -300 && _currentVibeIndex < widget.vibesList!.length - 1) {
                // Swipe left -> next vibe
                _onVibeChanged(_currentVibeIndex + 1);
              }
            } : null,
            // VERTICAL DISMISS: Flick up or down to close the player
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() > 500) {
                context.pop();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ═══════════════════════════════════════════════════════════════
                // BACKGROUND: Different for each content type
                // ═══════════════════════════════════════════════════════════════
                if (isVideo && _isVideoInitialized && _videoController != null)
                  _buildVideoBackground(scale)
                else if (isVideo && !_isVideoInitialized && _vibe!.imageUrl != null && _vibe!.imageUrl!.isNotEmpty)
                  _buildImageBackground(scale)
                else if (hasImage)
                  _buildImageBackground(scale)
                else if (isAudioOnly)
                  _buildAudioOnlyBlurredBackground(scale)
                else
                  _buildCyberpunkBackground(scale),



                // ═══════════════════════════════════════════════════════════════
                // NEW: GHOST HINTS (Onboarding discovery)
                // ═══════════════════════════════════════════════════════════════
                if (_showGhostHints)
                  _buildGhostHints(scale),

                // ═══════════════════════════════════════════════════════════════
                // NEW: EMOJI RAIN (Full Screen)
                // ═══════════════════════════════════════════════════════════════
                IgnorePointer(
                  child: Stack(
                    fit: StackFit.expand,
                    children: _floatingEmojis.map((e) => Positioned(
                      left: e.x,
                      top: e.y,
                      child: Opacity(
                        opacity: e.opacity.clamp(0.0, 1.0),
                        child: Text(
                          e.emoji,
                          style: TextStyle(fontSize: 32 * scale),
                        ),
                      ),
                    )).toList(),
                  ),
                ),

                // ═══════════════════════════════════════════════════════════════
                // MAIN CONTENT OVERLAY (Safe Area Column)
                // ═══════════════════════════════════════════════════════════════
                SafeArea(
                  child: Column(
                    children: [
                      _buildLocketTopBar(statusText, statusColor, scale),
                      
                      if (_hasSwipeNavigation)
                        _buildPageIndicator(scale),

                      const Spacer(flex: 1),

                      if (isAudioOnly)
                        _buildCenteredAvatar(scale)
                      else
                        const SizedBox.shrink(),

                      const Spacer(flex: 1),

                      if (_isReplying)
                        RepaintBoundary(
                          child: Consumer(
                            builder: (context, ref, _) {
                              final waveformData = ref.watch(waveformDataProvider);
                              final recordingDuration = ref.watch(recordingDurationProvider);
                              return _buildRecordingReplyUI(recordingDuration, waveformData, scale);
                            },
                          ),
                        )
                      else if (_hasAudioOrVideo())
                        _buildPlaybackUI(scale)
                      else
                        _buildImageOnlyUI(scale),

                      SizedBox(height: 40 * scale),
                    ],
                  ),
                ),
                
                // ═══════════════════════════════════════════════════════════════
                // NEW: HYBRID PORTAL OVERLAYS (Renamed: "The Sticker Layer")
                // Placed LAST to ensure it renders ON TOP of the avatar/video
                // ═══════════════════════════════════════════════════════════════
                _buildPortalOverlays(scale),
              ],
            ),
          );
        },
      );
    },
  ),
);
  }

  /// Dynamic status text based on current state
  /// SIMPLIFIED: When playing, show nothing (slider is the indicator)
  /// When not playing, show timestamp
  String _getStatusText() {
    if (_isReplying) {
      return 'Recording...';
    } else if (_isPlaying && _hasAudioOrVideo()) {
      // SIMPLIFIED: Don't show "Now playing" - slider indicates this
      return '';
    } else {
      // Paused/Done/Image-only: Show timestamp
      return _formatTime(_vibe!.createdAt);
    }
  }

  /// Dynamic status color
  Color _getStatusColor() {
    if (_isReplying) {
      return Colors.green;
    } else if (_isPlaying && _hasAudioOrVideo()) {
      return Colors.white70;
    } else {
      return Colors.white54;
    }
  }

  /// Check if this vibe has audio or video content to play
  bool _hasAudioOrVideo() {
    if (_vibe == null) return false;
    // Video vibe
    if (_vibe!.isVideo && _vibe!.videoUrl != null && _vibe!.videoUrl!.isNotEmpty) return true;
    // Audio vibe (either audio-only or image+audio)
    if (_vibe!.audioUrl != null && _vibe!.audioUrl!.isNotEmpty) return true;
    return false;
  }

  /// SWIPE NAVIGATION: TikTok-style dots indicator
  Widget _buildPageIndicator(double scale) {
    if (!_hasSwipeNavigation) return const SizedBox.shrink();
    
    final total = widget.vibesList!.length;
    final current = _currentVibeIndex;
    
    // TikTok shows max 7 dots with scrolling window
    const maxDots = 7;
    final showDots = total <= maxDots;
    
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8 * scale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: showDots
            ? _buildDots(total, current, scale)
            : _buildScrollingDots(total, current, maxDots, scale),
      ),
    );
  }
  
  /// Build static dots for small lists
  List<Widget> _buildDots(int total, int current, double scaleFactor) {
    return List.generate(total, (index) {
      final isActive = index == current;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        margin: EdgeInsets.symmetric(horizontal: 3 * scaleFactor),
        width: isActive ? 8 * scaleFactor : 6 * scaleFactor,
        height: isActive ? 8 * scaleFactor : 6 * scaleFactor,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive 
              ? Colors.white 
              : Colors.white.withOpacity(0.4),
        ),
      );
    });
  }
  
  /// Build scrolling dots for large lists (TikTok style)
  List<Widget> _buildScrollingDots(int total, int current, int maxDots, double scaleFactor) {
    // Calculate visible window
    final halfWindow = maxDots ~/ 2;
    int start = (current - halfWindow).clamp(0, total - maxDots);
    int end = (start + maxDots).clamp(0, total);
    
    return List.generate(end - start, (i) {
      final index = start + i;
      final isActive = index == current;
      
      // Edge dots are smaller (TikTok style fade effect)
      final distanceFromCenter = (index - current).abs();
      final dotScale = distanceFromCenter <= 1 ? 1.0 : 
                       distanceFromCenter == 2 ? 0.8 : 0.6;
      
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        margin: EdgeInsets.symmetric(horizontal: 3 * scaleFactor),
        width: (isActive ? 8 : 6) * dotScale * scaleFactor,
        height: (isActive ? 8 : 6) * dotScale * scaleFactor,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive 
              ? Colors.white 
              : Colors.white.withOpacity(0.4 * dotScale),
        ),
      );
    });
  }


  /// ═══════════════════════════════════════════════════════════════════════
  /// BACKGROUND BUILDERS - Different for each content type
  /// ═══════════════════════════════════════════════════════════════════════

  /// VIDEO BACKGROUND: "Atmospheric Portal" Design
  /// - Blurred version of video fills entire screen (atmosphere)
  /// - Crisp 1:1 square video floats in center (the portal)
  /// - Drop shadow gives depth/polaroid effect
  Widget _buildVideoBackground(double scale) {
    final screenWidth = MediaQuery.of(context).size.width;
    final squareSize = screenWidth; // Match CameraScreen full width 
    final videoSize = _videoController!.value.size;
    
    return Stack(
      fit: StackFit.expand,
      children: [
        // LAYER 0: CYBERPUNK MESH BASE
        _buildCyberpunkBackground(scale),

        // ═══════════════════════════════════════════════════════════════════
        // LAYER 1: OPTIMIZED BLURRED THUMBNAIL (No Live Video Blur!)
        // ═══════════════════════════════════════════════════════════════════
        // FIX: Replaced BackdropFilter over VideoPlayer with ImageFiltered over Image
        // This saves GPU resources and prevents jank/battery drain.
        if (_vibe!.imageUrl != null && _vibe!.imageUrl!.isNotEmpty)
          Transform.scale(
            scale: 1.2,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40 * scale, sigmaY: 40 * scale),
              child: CachedNetworkImage(
                imageUrl: _vibe!.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                // MEMORY FIX: Decode at low resolution for heavy blur background
                // This saves memory (50x50 bitmap vs 1080p) and speeds up the "Pre-warm"
                memCacheWidth: 50, 
                placeholder: (_, __) => Container(color: const Color(0xFF111111)),
                errorWidget: (_, __, ___) => Container(color: const Color(0xFF111111)),
              ),
            ),
          )
        else
          // Fallback if no thumbnail: just use the cyberpunk mesh
           _buildCyberpunkBackground(scale),

        // Dimming overlay for contrast
        Container(color: Colors.black.withOpacity(0.4)),
        
        // ═══════════════════════════════════════════════════════════════════
        // LAYER 2: FLOATING 1:1 SQUARE VIDEO (the portal)
        // ═══════════════════════════════════════════════════════════════════
        Center(
          child: GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: squareSize,
              height: squareSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24 * scale),
                // Subtle backlight glow only (no drop shadow to avoid banding)
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryAction.withOpacity(0.15),
                    blurRadius: 50 * scale,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24 * scale),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The crisp 1:1 video (fills the square)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: videoSize.width,
                        height: videoSize.height,
                        child: VideoPlayer(_videoController!),
                      ),
                    ),
                    
                    // Subtle inner border for definition
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24 * scale),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                          width: 1 * scale,
                        ),
                      ),
                    ),
                    
                    // Standard Play/Pause indicator
                    _buildCenteredPlayIndicator(
                      isPlaying: _isPlaying,
                      showPauseIcon: true,
                      scale: scale,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// IMAGE + AUDIO BACKGROUND: "Atmospheric Portal" Design
  /// - Blurred version of image fills entire screen (atmosphere)
  /// - Crisp 1:1 square floats in center (the portal)
  /// - Drop shadow gives depth/polaroid effect
  Widget _buildImageBackground(double scale) {
    final screenWidth = MediaQuery.of(context).size.width;
    final squareSize = screenWidth; // Match CameraScreen full width
    
    return Stack(
      fit: StackFit.expand,
      children: [
        // LAYER 0: CYBERPUNK MESH BASE
        _buildCyberpunkBackground(scale),

        // ═══════════════════════════════════════════════════════════════════
        // LAYER 1: ATMOSPHERIC BLUR (fills entire screen)
        // ═══════════════════════════════════════════════════════════════════
        // Scale to 120% to ensure no gaps at edges when blurred
        Transform.scale(
          scale: 1.2,
          child: CachedNetworkImage(
            imageUrl: _vibe!.imageUrl!,
            fit: BoxFit.cover,
            // FIX: Uses same cache as dashboard - loads instantly
            placeholder: (_, __) => Container(color: AppColors.surface),
            errorWidget: (_, __, ___) => _buildGradientFallback(),
          ),
        ),
        
        // Heavy blur effect (sigma 40 for atmospheric feel)
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40 * scale, sigmaY: 40 * scale),
          child: Container(color: Colors.transparent),
        ),
        
        // ═══════════════════════════════════════════════════════════════════
        // LAYER 2: FLOATING 1:1 SQUARE (the portal)
        // ═══════════════════════════════════════════════════════════════════
        Center(
          child: GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: squareSize,
              height: squareSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24 * scale),
                // Subtle backlight glow only (no drop shadow to avoid banding)
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryAction.withOpacity(0.15),
                    blurRadius: 50 * scale,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24 * scale),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The crisp, uncropped 1:1 image (uses cache from dashboard)
                    CachedNetworkImage(
                      imageUrl: _vibe!.imageUrl!,
                      fit: BoxFit.cover, // Fills the square, may crop slightly
                      // FIX: Uses same cache as dashboard - loads instantly
                      placeholder: (_, __) => Container(color: Colors.grey[900]),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[900],
                        child: Center(
                          child: Icon(Icons.image_not_supported, color: Colors.white54, size: 48 * scale),
                        ),
                      ),
                    ),
                    
                    // Subtle inner border for definition
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24 * scale),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                          width: 1 * scale,
                        ),
                      ),
                    ),
                    
                    // Standard Play/Pause indicator - ONLY if has audio
                    if (_vibe!.audioUrl != null && _vibe!.audioUrl!.isNotEmpty)
                      _buildCenteredPlayIndicator(
                        isPlaying: _isPlaying,
                        isBuffering: _isBuffering, // Pass buffering state
                        showPauseIcon: false, // For photos, usually just show play arrow when paused
                        scale: scale,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// AUDIO ONLY BACKGROUND: Blurred avatar with gradient
  Widget _buildAudioOnlyBlurredBackground(double scale) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // LAYER 0: CYBERPUNK MESH BASE
        _buildCyberpunkBackground(scale),

        // Layer 1: Sender's avatar (will be blurred) - uses cache
        if (_vibe?.senderAvatar != null && _vibe!.senderAvatar!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: _vibe!.senderAvatar!,
            fit: BoxFit.cover,
            // FIX: Uses black placeholder to prevent color flash
            placeholder: (_, __) => Container(color: AppColors.surface),
            errorWidget: (_, __, ___) => _buildGradientFallback(),
          )
        else
          _buildGradientFallback(),
        
        // Layer 2: Heavy blur effect
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(color: Colors.transparent),
        ),
        
        // Layer 3: Dark gradient overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.3),
                Colors.black.withOpacity(0.4),
                Colors.black.withOpacity(0.6),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Gradient fallback for audio-only when no avatar
  /// Uses subtle dark gradient to prevent jarring color flash
  Widget _buildGradientFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.grey[900]!,
            AppColors.background,
            Colors.grey[900]!,
          ],
        ),
      ),
    );
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// CENTER CONTENT BUILDERS - Different for each content type
  /// ═══════════════════════════════════════════════════════════════════════

  /// Standardized Play indicator for the "Atmospheric Portal"
  Widget _buildCenteredPlayIndicator({
    required bool isPlaying, 
    required bool showPauseIcon, 
    bool isBuffering = false, // Optional buffering state
    required double scale,
  }) {
    // If buffering, show loading spinner regardless of play state
    if (isBuffering) {
      return Container(
        color: Colors.black.withOpacity(0.2), // Subtle dim
        child: Center(
          child: SizedBox(
            width: 50 * scale,
            height: 50 * scale,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3 * scale,
            ),
          ),
        ),
      );
    }

    return AnimatedOpacity(
      opacity: isPlaying ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            width: 72 * scale,
            height: 72 * scale,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20 * scale,
                  spreadRadius: 5 * scale,
                ),
              ],
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.black,
              size: 40 * scale,
            ),
          ),
        ),
      ),
    );
  }


  /// 2025: Locket-style minimalist top bar: [⌄]  Name • Time  [•••]
  Widget _buildLocketTopBar(String statusText, Color statusColor, double scale) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
      child: Row(
        children: [
          // Close button (chevron down)
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 40 * scale,
              height: 40 * scale,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 18 * scale,
              ),
            ),
          ),

          SizedBox(width: 12 * scale),

          // Metadata Cluster (Centered or flexible)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _vibe!.senderName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15 * scale,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2 * scale,
                  ),
                ),
                Text(
                  _formatTimeAgo(_vibe!.createdAt),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Options button (three dots)
          GestureDetector(
            onTap: () => _showOptionsSheet(),
            child: Container(
              width: 40 * scale,
              height: 40 * scale,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.more_horiz,
                color: Colors.white,
                size: 22 * scale,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Centered avatar with pulsing concentric rings (Locket style)
  Widget _buildCenteredAvatar(double scale) {
    final bool showPulse = _isPlaying;
    final double avatarSize = _isReplying ? 100.0 * scale : 120.0 * scale;

    return GestureDetector(
      onTap: _togglePlayback,
      child: SizedBox(
        width: 250 * scale,
        height: 250 * scale,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing rings (only when playing)
            if (showPulse) ...[
              // Outer ring
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final ringScale = 1.0 + (_pulseController.value * 0.15);
                  final opacity = 1.0 - (_pulseController.value * 0.7);
                  return Transform.scale(
                    scale: ringScale,
                    child: Container(
                      width: avatarSize + (80 * scale),
                      height: avatarSize + (80 * scale),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.purple.withOpacity(opacity * 0.3),
                          width: 1.5 * scale,
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Middle ring
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final ringScale = 1.0 + (_pulseController.value * 0.1);
                  final opacity = 1.0 - (_pulseController.value * 0.5);
                  return Transform.scale(
                    scale: ringScale,
                    child: Container(
                      width: avatarSize + (50 * scale),
                      height: avatarSize + (50 * scale),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.purple.withOpacity(opacity * 0.4),
                          width: 1.5 * scale,
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Inner ring
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final ringScale = 1.0 + (_pulseController.value * 0.05);
                  final opacity = 1.0 - (_pulseController.value * 0.3);
                  return Transform.scale(
                    scale: ringScale,
                    child: Container(
                      width: avatarSize + (20 * scale),
                      height: avatarSize + (20 * scale),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.purple.withOpacity(opacity * 0.5),
                          width: 1.5 * scale,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],

            // Avatar container with white border
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 3 * scale),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20 * scale,
                    spreadRadius: 5 * scale,
                  ),
                ],
              ),
              child: ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _vibe?.senderAvatar != null && _vibe!.senderAvatar!.isNotEmpty
                        ? Image.network(
                            _vibe!.senderAvatar!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildAvatarPlaceholder(),
                          )
                        : _buildAvatarPlaceholder(),
                    
                    // Standard Play/Pause indicator
                    _buildCenteredPlayIndicator(
                      isPlaying: _isPlaying,
                      showPauseIcon: true,
                      scale: scale,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade400, Colors.pink.shade400],
        ),
      ),
      child: const Icon(
        Icons.person,
        color: Colors.white,
        size: 48,
      ),
    );
  }

  /// Playback UI: Progress bar + Viral Sharing + Reply buttons
  /// SYMMETRY: Consistent 4-button action bar
  Widget _buildPlaybackUI(double scale) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildUnifiedActionPill(scale),
      ],
    );
  }

  /// Image-only vibes UI (same as playback but without audio-specific indicators)
  Widget _buildImageOnlyUI(double scale) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildUnifiedActionPill(scale),
      ],
    );
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// NEW: UNIFIED ACTION PILL (Gen Z Optimized)
  /// ═══════════════════════════════════════════════════════════════════════

  Widget _buildUnifiedActionPill(double scale) {
    // FIX: Get keyboard height to move pill above keyboard
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    
    // === PREVIEW MODE UI ===
    if (_isPreviewingReply) {
      return Padding(
        padding: EdgeInsets.only(bottom: math.max(0, (MediaQuery.viewInsetsOf(context).bottom - 20) * scale)),
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 24 * scale),
          padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(32 * scale),
            border: Border.all(
              color: AppColors.primaryAction.withOpacity(0.4),
              width: 1.5 * scale,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryAction.withOpacity(0.15),
                blurRadius: 16 * scale,
                spreadRadius: 2 * scale,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Cancel Button
              GestureDetector(
                onTap: _cancelReply,
                child: Container(
                  padding: EdgeInsets.all(12 * scale),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    color: AppColors.error,
                    size: 24 * scale,
                  ),
                ),
              ),
              
              // Play/Pause Preview Button
              GestureDetector(
                onTap: _isPlayingPreview ? _pausePreview : _playPreview,
                child: Container(
                  padding: EdgeInsets.all(16 * scale),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 2 * scale,
                    ),
                  ),
                  child: Icon(
                    _isPlayingPreview ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 28 * scale,
                  ),
                ),
              ),
              
              // Send Button
              GestureDetector(
                onTap: _confirmSendReply,
                child: Container(
                  padding: EdgeInsets.all(12 * scale),
                  decoration: BoxDecoration(
                    gradient: AppColors.auraGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.send,
                    color: Colors.white,
                    size: 24 * scale,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // === NORMAL MODE UI ===
    final bool canReply = _hasPlayed;
    final bool hasText = _textReplyController.text.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: math.max(0, (MediaQuery.viewInsetsOf(context).bottom - 20) * scale)),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Container(
            margin: EdgeInsets.symmetric(horizontal: 24 * scale),
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity! < -300 && canReply && !_isTextReplying) {
                  _navigateToCameraReply();
                }
              },
              onTap: (canReply && !_isTextReplying) 
                  ? () {
                      setState(() => _isTextReplying = true);
                      _textReplyFocusNode.requestFocus();
                    }
                  : null,
              onLongPressStart: (canReply && !_isTextReplying && !_isPreviewingReply) ? (_) => _startReply() : null,
              onLongPressEnd: (canReply && !_isTextReplying) ? (_) => _stopReply() : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 12 * scale),
                decoration: BoxDecoration(
                  color: AppColors.surface, 
                  borderRadius: BorderRadius.circular(32 * scale),
                  border: Border.all(
                    color: _isTextReplying 
                        ? AppColors.primaryAction.withOpacity(0.3)
                        : Colors.white.withOpacity(0.08),
                    width: 1 * scale,
                  ),
                  boxShadow: [
                    if (_isReplying)
                      BoxShadow(
                        color: AppColors.error.withOpacity(0.3), // âœ¨ Thermal Orange Glow
                        blurRadius: 25 * scale,
                        spreadRadius: 8 * scale,
                      ),
                    if (_isTextReplying)
                      BoxShadow(
                        color: AppColors.primaryAction.withOpacity(0.1),
                        blurRadius: 15 * scale,
                        spreadRadius: 2 * scale,
                      ),
                  ],
                ),
                child: Row(
                  children: [
                    // LEFT: Camera Icon
                    GestureDetector(
                      onTap: (canReply && !_isTextReplying) ? _navigateToCameraReply : null,
                      child: Container(
                        padding: EdgeInsets.all(8 * scale),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          color: Colors.white.withOpacity(canReply ? 0.8 : 0.2),
                          size: 20 * scale,
                        ),
                      ),
                    ),
                    
                    SizedBox(width: 12 * scale),
      
                    // CENTER: Input / Label
                    Expanded(
                      child: _isTextReplying 
                        ? TextField(
                            controller: _textReplyController,
                            focusNode: _textReplyFocusNode,
                            style: TextStyle(color: Colors.white, fontSize: 15 * scale),
                            cursorColor: AppColors.primaryAction,
                            decoration: InputDecoration(
                              hintText: 'Reply...',
                              hintStyle: TextStyle(color: Colors.white24, fontSize: 15 * scale),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (val) => setState(() {}),
                            onSubmitted: (_) => _sendTextReply(),
                          )
                        : Center(
                            child: Text(
                              _isReplying 
                                ? 'RECORDING VIBE...' 
                                : (canReply ? 'Reply or Hold to record' : 'LISTEN FIRST'),
                              style: TextStyle(
                                color: canReply ? Colors.white70 : Colors.white24,
                                fontSize: 13 * scale,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5 * scale,
                              ),
                            ),
                          ),
                    ),
      
                    SizedBox(width: 12 * scale),
      
                    // RIGHT: Mic / Send
                    GestureDetector(
                      onTap: (hasText && _isTextReplying) ? _sendTextReply : null,
                      child: Container(
                        padding: EdgeInsets.all(8 * scale),
                        decoration: BoxDecoration(
                          color: (_isTextReplying && hasText) 
                              ? AppColors.primaryAction.withOpacity(0.2)
                              : Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          (_isTextReplying && hasText) ? Icons.send : Icons.mic,
                          color: (_isTextReplying && hasText) 
                              ? AppColors.primaryAction 
                              : (_isReplying 
                                  ? AppColors.error 
                                  : Colors.white.withOpacity(canReply ? 0.8 : 0.2)),
                          size: 20 * scale,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // INTEGRATED PROGRESS BAR
          if (_hasAudioOrVideo() && !_isReplying && !_isTextReplying)
            Positioned(
              top: 0,
              left: 56 * scale, 
              right: 56 * scale,
              child: Container(
                height: 2 * scale,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(1 * scale),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _playbackProgress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primaryAction,
                      borderRadius: BorderRadius.circular(1 * scale),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryAction.withOpacity(0.5),
                          blurRadius: 4 * scale,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _navigateToCameraReply() {
    HapticFeedback.mediumImpact();
    context.pushNamed(
      AppRoutes.camera,
      extra: _vibe, // Pass the VibeModel directly for the router to cast
    );
  }

  /// Unified Action Button (Viral / Secondary)
  Widget _buildModernActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Color? backgroundColor,
    Color? borderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
          border: borderColor != null ? Border.all(color: borderColor, width: 1) : null,
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  /// Unified Primary Button (Reply Mic)
  Widget _buildPrimaryActionButton({
    required IconData icon,
    required VoidCallback? onTap,
    Color? glowColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: glowColor ?? const Color(0xFF9C5BF5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: onTap != null ? Colors.white : Colors.white24, size: 28),
      ),
    );
  }

  Widget _buildRecordingReplyUI(int duration, List<double> waveformData, double scale) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24 * scale),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end, // Force to bottom
        children: [
          // Timer pill (red background)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20 * scale),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8 * scale,
                  height: 8 * scale,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8 * scale),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 16 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 24 * scale),

          // Waveform visualization
          SizedBox(
            height: 40 * scale,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                20,
                (index) {
                  double value = 0.5;
                  bool hasData = false;
                  if (waveformData.isNotEmpty) {
                    // Sample the waveform data to match 20 bars
                    final step = waveformData.length / 20;
                    final dataIndex = (index * step).floor().clamp(0, waveformData.length - 1);
                    value = waveformData[dataIndex];
                    hasData = true;
                  }

                  final barHeight = hasData
                      ? (value * 35).clamp(4.0, 35.0) * scale
                      : (5 + (index % 3) * 10).toDouble() * scale;
                  return Container(
                    width: 4 * scale,
                    height: barHeight,
                    margin: EdgeInsets.symmetric(horizontal: 2 * scale),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(2 * scale),
                    ),
                  );
                },
              ),
            ),
          ),

          SizedBox(height: 32 * scale),

          // Large mic button with glow
          Container(
            width: 80 * scale,
            height: 80 * scale,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.4),
                  blurRadius: 30 * scale,
                  spreadRadius: 10 * scale,
                ),
              ],
            ),
            child: Icon(
              Icons.mic,
              color: Colors.white,
              size: 36 * scale,
            ),
          ),

          SizedBox(height: 16 * scale),

          // "Release to send" text
          Text(
            'Release to send',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14 * scale,
            ),
          ),
        ],
      ),
    );
  }

  /// Format duration as "0:04" style
  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _showOptionsSheet() {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // AI Transcription Tool
            ListTile(
              leading: const Icon(Icons.text_snippet, color: AppColors.secondaryAction),
              title: const Text('Read AI Transcript', style: TextStyle(color: Colors.white)),
              subtitle: const Text('View voice-to-text conversion', style: TextStyle(color: Colors.white54)),
              onTap: () async {
                Navigator.pop(context);
                await _loadTranscription();
              },
            ),
            const Divider(color: Colors.white10),

            // Social Sharing Options

            ListTile(
              leading: Icon(Icons.movie, color: Colors.purple[400]),
              title: const Text('Instagram Reels', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                await _shareToInstagramReels();
              },
            ),

            ListTile(
              leading: const Icon(Icons.video_library, color: AppColors.primaryAction),
              title: const Text('Share Video', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Other platforms (WhatsApp, etc)', style: TextStyle(color: Colors.white54)),
              onTap: () async {
                Navigator.pop(context);
                await _shareAsViralVideo();
              },
            ),
            const Divider(color: Colors.white10),

            // Delete (only for sender)
            if (_vibe!.senderId == ref.read(authServiceProvider).currentUserId)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.urgency),
                title: const Text('Delete for Everyone', style: TextStyle(color: AppColors.urgency)),
                subtitle: const Text('Remove from both devices', style: TextStyle(color: Colors.white24, fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteVibe();
                },
              ),
            if (_vibe!.senderId == ref.read(authServiceProvider).currentUserId)
              const Divider(color: Colors.white10),

            // Safety
            ListTile(
              leading: const Icon(Icons.flag, color: AppColors.error),
              title: const Text('Report Vibe', style: TextStyle(color: AppColors.error)),
              subtitle: const Text('Inappropriate content', style: TextStyle(color: Colors.white24, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _reportVibe();
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: AppColors.error),
              title: const Text('Block User', style: TextStyle(color: AppColors.error)),
              subtitle: Text('Stop seeing ${_vibe?.senderName}\'s vibes', style: const TextStyle(color: Colors.white24, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _blockUser();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

  void _reportVibe() async {
    final vibe = _vibe;
    if (vibe == null) return;
    
    final reasons = ['Inappropriate content', 'Spam', 'Harassment', 'Other'];
    
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Report Content', 
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 16),
            ...reasons.map((r) => ListTile(
              title: Text(r, style: const TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white24),
              onTap: () => Navigator.pop(context, r),
            )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (reason != null && mounted) {
      try {
        await ref.read(vibeServiceProvider).reportVibe(
          vibeId: vibe.id,
          reporterId: ref.read(authServiceProvider).currentUserId ?? 'unknown',
          reason: reason,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Thank you. We will review this vibe within 24 hours.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error reporting: $e')),
          );
        }
      }
    }
  }

  void _blockUser() async {
    final vibe = _vibe;
    if (vibe == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Block ${vibe.senderName}?', style: const TextStyle(color: Colors.white)),
        content: const Text(
          'You will no longer see vibes from this user. This action is permanent.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      try {
        await ref.read(vibeServiceProvider).blockUser(vibe.senderId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Blocked ${vibe.senderName}')),
          );
          // Auto-skip to next vibe if available
          if (_hasSwipeNavigation && _currentVibeIndex < widget.vibesList!.length - 1) {
            _pageController?.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          } else {
            Navigator.of(context).pop(); // Exit player if no more vibes
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error blocking: $e')),
          );
        }
      }
    }
  }

  /// Share as a viral video (MP4) for TikTok/Instagram
  Future<void> _shareAsViralVideo() async {
    final imageUrl = _vibe!.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image available for video')),
      );
      return;
    }

    setState(() {
      _isExportingVideo = true;
      _exportProgress = 0.0;
    });

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Creating Video', style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Generating TikTok-ready video...',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _exportProgress,
                  backgroundColor: AppColors.surfaceLight,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryAction),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_exportProgress * 100).toInt()}%',
                  style: const TextStyle(color: AppColors.primaryAction),
                ),
              ],
            );
          },
        ),
      ),
    );

    try {
      // Use ViralVideoService which has proper FFmpeg MP4 generation
      // (replaced deleted VideoExportService which only shared separate files)
      final viralVideoService = ref.read(viralVideoServiceProvider);
      final File? videoFile;
      
      if (_vibe!.isVideo && _vibe!.videoUrl != null) {
        videoFile = await viralVideoService.downloadVideo(
          _vibe!.videoUrl!,
          onProgress: (progress) {
            if (mounted) setState(() => _exportProgress = progress);
          },
        );
      } else {
        videoFile = await viralVideoService.generateFromUrls(
          imageUrl: imageUrl,
          audioUrl: _vibe!.audioUrl,
          onProgress: (progress) {
            if (mounted) setState(() => _exportProgress = progress);
          },
        );
      }

      Navigator.pop(context); // Close progress dialog

      if (videoFile != null && mounted) {
        // Share the generated MP4 video
        await viralVideoService.shareToSystem(
          videoFile.path,
          '🎤 Listen to this Vibe from ${_vibe!.senderName}!\n\nDownload Vibe: https://getvibe.app',
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to prepare content')),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close progress dialog
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isExportingVideo = false);
    }
  }

  /// Share to Instagram Stories (VIRAL - Full Screen Video)
  Future<void> _shareToInstagramStories() async {
    await _shareViralVideo('instagram');
  }

  /// Share to Instagram Reels
  Future<void> _shareToInstagramReels() async {
    await _shareViralVideo('reels');
  }

  /// Share to TikTok
  Future<void> _shareToTikTok() async {
    await _shareViralVideo('tiktok');
  }

  /// Core viral video sharing method
  Future<void> _shareViralVideo(String platform) async {
    // VIRAL FIX: For audio-only vibes, fallback to sender avatar
    final imageUrl = _vibe!.imageUrl ?? _vibe!.senderAvatar;
    
    if (imageUrl == null || imageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image or avatar available for video creation')),
      );
      return;
    }

    setState(() {
      _isExportingVideo = true;
      _exportProgress = 0.0;
    });



    // VIRAL FIX: Background processing (remove blocking dialog)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Creating ${platform == 'tiktok' ? 'TikTok' : 'Instagram'} video in background...'),
        duration: const Duration(seconds: 2),
        backgroundColor: platform == 'tiktok' ? Colors.cyan.withOpacity(0.8) : Colors.pink.withOpacity(0.8),
      ),
    );

    try {
      final viralService = ref.read(viralVideoServiceProvider);
      
      // Generate or download the video
      final File? videoFile;
      if (_vibe!.isVideo && _vibe!.videoUrl != null) {
        videoFile = await viralService.downloadVideo(
          _vibe!.videoUrl!,
          onProgress: (progress) {
            if (mounted) setState(() => _exportProgress = progress);
          },
        );
      } else {
        videoFile = await viralService.generateFromUrls(
          imageUrl: imageUrl,
          audioUrl: _vibe!.audioUrl,
          onProgress: (progress) {
            if (mounted) setState(() => _exportProgress = progress);
          },
        );
      }

      // Navigator.pop(context); // REMOVED: Blocking dialog

      if (videoFile != null && mounted) {
        // Share to the selected platform
        String result;
        switch (platform) {
          case 'instagram':
            result = await viralService.shareToInstagramStories(
              videoPath: videoFile.path,
              attributionUrl: 'https://getvibe.app',
            );
            break;
          case 'reels':
            result = await viralService.shareToInstagramReels(videoFile.path);
            break;
          case 'tiktok':
            result = await viralService.shareToTikTok(videoFile.path);
            break;
          default:
            result = await viralService.shareToSystem(
              videoFile.path,
              '🎤 Listen to this Vibe from ${_vibe!.senderName}!\n\nDownload Vibe: https://getvibe.app',
            );
        }
        
        debugPrint('Share result: $result');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video ready!'), backgroundColor: AppColors.success),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create video')),
        );
      }
    } catch (e) {
      // Navigator.pop(context); // REMOVED: Blocking dialog
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isExportingVideo = false);
    }
  }

  /// Load AI transcription
  /// [silent] is true when auto-loading on entry (no snackbar/dialog)
  Future<void> _loadTranscription({bool silent = false}) async {
    // If transcription already exists on the model, just use it
    if (_vibe?.transcription != null && _vibe!.transcription!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _transcriptionText = _vibe!.transcription;
          _showTranscription = true;
        });
      }
      return;
    }

    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Transcribing voice...'),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }

    try {
      final transcriptionService = ref.read(transcriptionServiceProvider);
      String? text;

      // Support both audio and video transcription (Whisper handles both)
      final String mediaUrlToTranscribe = _vibe!.audioUrl.isNotEmpty 
          ? _vibe!.audioUrl 
          : (_vibe!.videoUrl ?? '');

      if (mediaUrlToTranscribe.isNotEmpty) {
        text = await transcriptionService.transcribeFromUrl(mediaUrlToTranscribe);
      }

      if (text != null && mounted) {
        setState(() {
          _transcriptionText = text;
          _showTranscription = true;
        });
        
        // PERSISTENCE: Save transcription to Firestore via service
        ref.read(vibeServiceProvider).saveTranscription(_vibe!.id, text);
        
        if (!silent) {
          _showTranscriptionDialog(text);
        }
      } else if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not transcribe audio')),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transcription error: $e')),
        );
      }
    }
  }

  /// Show transcription in a dialog
  void _showTranscriptionDialog(String text) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            const Icon(Icons.text_snippet, color: AppColors.primaryAction),
            const SizedBox(width: 8),
            Text(
              'Transcription',
              style: AppTypography.headlineSmall.copyWith(color: Colors.white),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'From ${_vibe!.senderName}:',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  text,
                  style: AppTypography.bodyLarge.copyWith(
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy', style: TextStyle(color: AppColors.primaryAction)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Share the current vibe
  Future<void> _shareVibe() async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Preparing share...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      // Use share_plus to share actual files
      await _shareVibeFiles();
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    }
  }

  /// Share actual audio/image files (not just text)
  Future<void> _shareVibeFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = <XFile>[];
      
      // Download and add image if available
      final imageUrl = _vibe!.imageUrl;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final imageFile = File('${tempDir.path}/vibe_share_${_vibe!.id}.jpg');
          if (imageUrl.startsWith('http')) {
            final response = await http.get(Uri.parse(imageUrl));
            await imageFile.writeAsBytes(response.bodyBytes);
          }
          files.add(XFile(imageFile.path));
        } catch (e) {
          debugPrint('Failed to download image: $e');
        }
      }
      
      // Download and add audio if available
      if (_vibe!.audioUrl.isNotEmpty) {
        try {
          final audioFile = File('${tempDir.path}/vibe_audio_${_vibe!.id}.m4a');
          if (_vibe!.audioUrl.startsWith('http')) {
            final response = await http.get(Uri.parse(_vibe!.audioUrl));
            await audioFile.writeAsBytes(response.bodyBytes);
          }
          files.add(XFile(audioFile.path));
        } catch (e) {
          debugPrint('Failed to download audio: $e');
        }
      }

      // Download and add video if available
      if (_vibe!.isVideo && _vibe!.videoUrl != null && _vibe!.videoUrl!.isNotEmpty) {
        try {
          final videoFile = File('${tempDir.path}/vibe_video_${_vibe!.id}.mp4');
          if (_vibe!.videoUrl!.startsWith('http')) {
            final response = await http.get(Uri.parse(_vibe!.videoUrl!));
            await videoFile.writeAsBytes(response.bodyBytes);
          }
          files.add(XFile(videoFile.path));
        } catch (e) {
          debugPrint('Failed to download video: $e');
        }
      }
      
      // Build share message
      final shareText = '🎤 Listen to this Vibe from ${_vibe!.senderName}!\n\n'
          '${_vibe!.isFromGallery && _vibe!.originalPhotoDate != null 
              ? "📅 Time Travel from ${_formatDate(_vibe!.originalPhotoDate!)}\n\n" 
              : ""}'
          'Download Vibe to hear it: https://getvibe.app';
      
      // Share files if we have any, otherwise just share text
      if (files.isNotEmpty) {
        await Share.shareXFiles(
          files,
          text: shareText,
          subject: 'Nock from ${_vibe!.senderName}',
        );
      } else {
        await Share.share(
          shareText,
          subject: 'Nock from ${_vibe!.senderName}',
        );
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shared successfully!')),
        );
      }
    } catch (e) {
      debugPrint('Share error: $e');
      // Fallback to text-only share
      if (mounted) {
        await Share.share(
          '🎤 Listen to this Vibe from ${_vibe!.senderName}!\n\nDownload Vibe: https://getvibe.app',
          subject: 'Nock from ${_vibe!.senderName}',
        );
      }
    }
  }

  Future<void> _shareAppLink() async {
    const shareText = '✨ I\'m using Vibe to send voice messages that appear on my friends\' home screens!\n\n'
        'Download Vibe: https://getvibe.app';
    await Share.share(shareText, subject: 'Check out Vibe!');
  }

  String _formatDate(DateTime date) {
    final months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HYBRID MULTIMODAL HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  void _startTextReply() {
    setState(() {
      _isTextReplying = true;
    });
    _textReplyFocusNode.requestFocus();
    HapticFeedback.lightImpact();
  }

  Future<void> _sendTextReply() async {
    final text = _textReplyController.text.trim();
    if (text.isEmpty) return;

    final vibeId = _vibe!.id;
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    
    _textReplyFocusNode.unfocus();
    _textReplyController.clear();
    
    // FIX: OPTIMISTIC UPDATE - Add reply to local state immediately
    // This prevents "Ghost Replies" where user sends but doesn't see the result
    final newReply = TextReply(
      senderId: currentUser?.id ?? '',
      senderName: currentUser?.displayName ?? 'You',
      text: text,
      createdAt: DateTime.now(),
    );
    
    setState(() {
      _isTextReplying = false;
      _vibe = _vibe!.copyWith(
        textReplies: [..._vibe!.textReplies, newReply],
      );
    });

    try {
      await ref.read(vibeServiceProvider).sendTextReply(vibeId, text);
      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('Error sending text reply: $e');
      // Optionally: Revert optimistic update on error
    }
  }

  void _addQuickReaction(String emoji) {
    HapticFeedback.mediumImpact();
    
    // Send to service
    ref.read(vibeServiceProvider).addReaction(_vibe!.id, emoji);
    
    // Trigger local animation (Emoji Rain)
    _triggerEmojiRain(emoji);
  }

  void _triggerEmojiRain(String emoji) {
    final random = math.Random();
    final screenWidth = MediaQuery.of(context).size.width;
    
    setState(() {
      for (int i = 0; i < 15; i++) {
        _floatingEmojis.add(FloatingEmoji(
          emoji: emoji,
          x: random.nextDouble() * screenWidth,
          y: -50.0, // Start ABOVE screen for "cascade down" effect
          speed: 3.0 + random.nextDouble() * 5.0, // Slightly faster fall
          opacity: 1.0,
        ));
      }
    });

    // Start cleanup timer if not running
    if (_emojiCleanupTimer == null || !_emojiCleanupTimer!.isActive) {
      _emojiCleanupTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          final screenHeight = MediaQuery.of(context).size.height;
          for (var emoji in _floatingEmojis) {
            emoji.y += emoji.speed; // REVERSED GRAVITY: Move DOWN
            emoji.opacity -= 0.005; // Slower fade
          }
          _floatingEmojis.removeWhere((e) => e.y > screenHeight + 50 || e.opacity <= 0);
        });

        if (_floatingEmojis.isEmpty) {
          timer.cancel();
          _emojiCleanupTimer = null;
        }
      });
    }
  }

  Widget _buildPortalOverlays(double scale) {
    final screenWidth = MediaQuery.of(context).size.width;
    final squareSize = screenWidth * 0.9;

    return Center(
      child: SizedBox(
        width: squareSize,
        height: squareSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. DYNAMIC KARAOKE SUBTITLES (Transcription)
            if (_showTranscription && _transcriptionText != null)
              Positioned(
                bottom: 40 * scale,
                left: 24 * scale,
                right: 24 * scale,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _isPlaying ? 1.0 : 0.6,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.0), Colors.black.withOpacity(0.4), Colors.black.withOpacity(0.0)],
                      ),
                    ),
                    child: Text(
                      _transcriptionText!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 10 * scale),
                        ],
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),

            // 2. STICKY NOTES (Visual Whispers)
            if (_vibe != null && _vibe!.textReplies.isNotEmpty)
              ..._buildStickyNotes(scale),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStickyNotes(double scale) {
    if (_vibe!.textReplies.isEmpty) return [];
    
    // 1. Show only the LATEST note
    final latestReply = _vibe!.textReplies.last;
    final count = _vibe!.textReplies.length;

    return [
      Positioned(
        bottom: 120 * scale, // Position above the pill
        left: 32 * scale,    // Slightly more margin
        child: Transform.rotate(
          angle: -0.025, // Subtle 1.5 degree rotation for "Sticky Note" feel
          child: GestureDetector(
            onTap: () => _showAllCommentsSheet(), 
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The Note (Sticky Note Style)
                GlassContainer(
                  padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 12 * scale),
                  // Standardized glass aesthetic (Removed yellow tint)
                  backgroundColor: AppColors.glassBackground, 
                  borderRadius: 12 * scale,
                  borderColor: AppColors.glassBorder,
                  showGlow: true, 
                  useSmallGlow: true, 
                  glowColor: AppColors.primaryAction.withOpacity(0.1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          latestReply.senderName.toUpperCase(), 
                          style: TextStyle(
                            fontSize: 7 * scale, 
                            fontWeight: FontWeight.w900, 
                            color: Colors.white.withOpacity(0.7),
                            letterSpacing: 1 * scale,
                          )
                      ),
                      SizedBox(height: 4 * scale),
                      Text(
                          latestReply.text, 
                          style: TextStyle(
                            color: Colors.white, 
                            fontSize: 14 * scale,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2 * scale,
                          )
                      ),
                    ],
                  ),
                ),
                
                // The Counter Badge (if more than 1) - Positioned relative to the rotated note
                if (count > 1)
                  Positioned(
                    right: -6 * scale,
                    top: -6 * scale,
                    child: Container(
                      padding: EdgeInsets.all(6 * scale),
                      decoration: BoxDecoration(
                        color: AppColors.primaryAction, 
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 4 * scale, spreadRadius: 1 * scale),
                        ],
                      ),
                      child: Text(
                        '+${count - 1}', 
                        style: TextStyle(color: Colors.white, fontSize: 9 * scale, fontWeight: FontWeight.bold)
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      )
    ];
  }

  void _showAllCommentsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: _vibe!.textReplies.length,
        itemBuilder: (context, index) {
          final r = _vibe!.textReplies[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            title: Text(r.senderName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text(r.text, style: const TextStyle(color: Colors.white70)),
            leading: CircleAvatar(
              backgroundColor: Colors.white10,
              child: Text(r.senderName[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
            ),
          );
        },
      ),
    );
  }


  Widget _buildReactionsRow() {
    // Unique list of emojis to avoid clutter
    final uniqueEmojis = _vibe!.reactions.map((r) => r.emoji).toSet().toList();
    // Limit to 4 for clean UI
    final displayEmojis = uniqueEmojis.take(4).toList();
    final count = _vibe!.reactions.length;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...displayEmojis.map((e) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Text(e, style: const TextStyle(fontSize: 12)),
            )),
            if (count > displayEmojis.length)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  '+${count - displayEmojis.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }





  /// ═══════════════════════════════════════════════════════════════════════
  /// GHOST HINTS (Onboarding discovery) - Progressive Disclosure
  /// ═══════════════════════════════════════════════════════════════════════

  /// Check SharedPreferences and only show hints if user hasn't seen them
  Future<void> _checkAndShowGhostHints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenHints = prefs.getBool(_ghostHintsSeenKey) ?? false;
      
      if (hasSeenHints) {
        // User has already seen hints - don't show again (Progressive Disclosure)
        debugPrint('PlayerScreen: Ghost hints already seen, skipping');
        return;
      }
      
      // Show hints after delay for first-time users
      _ghostHintTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && !_hasPlayed) {
          setState(() => _showGhostHints = true);
          // Mark as seen after showing
          _markGhostHintsSeen();
        }
      });
    } catch (e) {
      debugPrint('PlayerScreen: Error checking ghost hints preference: $e');
    }
  }

  /// Mark ghost hints as seen in SharedPreferences (Progressive Disclosure)
  Future<void> _markGhostHintsSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ghostHintsSeenKey, true);
      debugPrint('PlayerScreen: Ghost hints marked as seen');
    } catch (e) {
      debugPrint('PlayerScreen: Error saving ghost hints preference: $e');
    }
  }

  Widget _buildGhostHints(double scale) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // HOLD HINT (Pill pulsing)
            Positioned(
              bottom: 120 * scale,
              left: 0,
              right: 0,
              child: Center(
                child: _buildHintBubble('Hold middle to record voice reply', scale),
              ),
            ),
            
            // SWIPE HINT (Up arrow)
            Positioned(
              bottom: 180 * scale,
              left: 40 * scale,
              child: Column(
                children: [
                  Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 32 * scale),
                  SizedBox(height: 8 * scale),
                  Text(
                    'Swipe for Camera',
                    style: TextStyle(color: Colors.white, fontSize: 10 * scale, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHintBubble(String text, double scale) {
    return AnimatedOpacity(
      duration: const Duration(seconds: 1),
      opacity: _showGhostHints ? 0.8 : 0.0,
      child: GlassContainer(
        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
        borderRadius: 20 * scale,
        child: Text(
          text,
          style: TextStyle(color: Colors.white, fontSize: 12 * scale, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
  Widget _buildCyberpunkBackground(double scale) {
    return Container(
      color: AppColors.background,
      child: CustomPaint(
        painter: GridPainter(
          color: Colors.white.withOpacity(0.05),
          scale: scale,
        ),
      ),
    );
  }

  /// Confirm delete vibe dialog
  Future<void> _confirmDeleteVibe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Vibe?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will delete the vibe for both you and ${_vibe!.senderName}. This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.urgency),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _deleteVibe();
    }
  }
  
  /// Delete vibe for everyone
  Future<void> _deleteVibe() async {
    try {
      await ref.read(vibeServiceProvider).deleteVibeForEveryone(_vibe!.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vibe deleted'),
            backgroundColor: AppColors.success,
          ),
        );
        
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.home);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

/// Helper for reaction animations
class FloatingEmoji {
  final String emoji;
  final double x;
  double y;
  final double speed;
  double opacity;

  FloatingEmoji({
    required this.emoji,
    required this.x,
    required this.y,
    required this.speed,
    this.opacity = 1.0,
  });
}

/// A custom painter that draws a faint cyberpunk tech grid
class GridPainter extends CustomPainter {
  final Color color;
  final double scale;
  
  GridPainter({
    required this.color,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5 * scale;

    final double spacing = 40.0 * scale;

    // Draw vertical lines
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Draw horizontal lines
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
