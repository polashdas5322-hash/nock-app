import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart'; // For PlayerState enum
import 'package:path_provider/path_provider.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/vibe_service.dart';
import 'package:nock/core/services/audio_service.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/shared/widgets/aura_visualization.dart';
import 'package:nock/features/squad/presentation/squad_screen.dart';  // for friendsProvider
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/providers/vibe_upload_provider.dart';

/// Preview Screen - Review photo/video + audio before sending
class PreviewScreen extends ConsumerStatefulWidget {
  final String imagePath;
  final String audioPath;
  final String? videoPath;
  final bool isVideo;
  final bool isAudioOnly;  // Audio-only mode with blurred profile background
  final String? senderAvatarUrl;  // For audio-only blurred background
  final bool isFromGallery;
  final DateTime? originalPhotoDate;
  final int? audioDuration; // Actual audio/video duration in seconds

  const PreviewScreen({
    super.key,
    required this.imagePath,
    required this.audioPath,
    this.videoPath,
    this.isVideo = false,
    this.isAudioOnly = false,
    this.senderAvatarUrl,
    required this.isFromGallery,
    this.originalPhotoDate,
    this.audioDuration,
  });

  @override
  ConsumerState<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends ConsumerState<PreviewScreen> with WidgetsBindingObserver {
  bool _isSending = false;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  
  // Key for capturing audio-only background as image
  final GlobalKey _backgroundKey = GlobalKey();
  
  // Audio playback state for Aura visualization
  bool _isAudioPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // FIX: Stop any "zombie" audio from previous screens immediately
    ref.read(audioServiceProvider).stop();
    
    if (widget.isVideo && widget.videoPath != null) {
      _initializeVideoPlayer();
    }
    
    // Listen to audio playback state for Aura visualization
    if (widget.isAudioOnly || (!widget.isVideo && widget.audioPath.isNotEmpty)) {
      _setupAudioStateListener();
      
      // FIX #7: Auto-play audio for photo+audio mode (consistent with video auto-play)
      // Delay slightly to let the UI settle
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && widget.audioPath.isNotEmpty) {
          ref.read(audioServiceProvider).playFromFile(widget.audioPath);
        }
      });
    }
  }
  
  void _setupAudioStateListener() {
    final audioService = ref.read(audioServiceProvider);
    audioService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isAudioPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  Future<void> _initializeVideoPlayer() async {
    final controller = VideoPlayerController.file(File(widget.videoPath!));
    
    // Release old controller if it exists to prevent leaks
    final oldController = _videoController;
    if (oldController != null) {
      await oldController.dispose();
    }
    
    // Assign early so dispose() can clean it up if user exits NOW
    _videoController = controller;

  try {
    await controller.initialize();
    
    // CRITICAL RACE FIX:
    if (!mounted) {
      // No need to dispose here as dispose() method already handled _videoController
      // effectively (or will when it runs, if it hasn't already).
      // Actually, if dispose() ran, _videoController might be null or disposed.
      return; 
    }
    
    // Safety check: ensure the controller we just inited is still the active one
    // and hasn't been disposed/replaced by another call.
    if (_videoController != controller) return;

    await controller.setLooping(true);
    await controller.play();
    
    if (mounted) {
      setState(() => _isVideoInitialized = true);
    }
  } catch (e) {
    debugPrint('Error initializing video: $e');
  }
}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // FIX: Stop audio and pause video when app goes to background
      ref.read(audioServiceProvider).stop();
      if (_videoController != null && _videoController!.value.isPlaying) {
        _videoController!.pause();
        if (mounted) setState(() {});
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.dispose();
    // FIX: Stop audio playback to prevent "Zombie Audio" leak
    // Without this, audio continues playing after leaving screen
    ref.read(audioServiceProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidNavy,
      body: Stack(
        children: [
          // Preview content (image, video, or audio-only background)
          Positioned.fill(
            child: RepaintBoundary(
              key: _backgroundKey,
              child: _buildPreviewContent(),
            ),
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  Row(
                    children: [
                      if (widget.isVideo)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryAction.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.videocam, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'VIDEO',
                                style: AppTypography.labelSmall.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.isFromGallery && widget.originalPhotoDate != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                            child: Text(
                            '📅 ${_formatDate(widget.originalPhotoDate!)}',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.vibeAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Video playback controls (if video)
          if (widget.isVideo && _isVideoInitialized && _videoController != null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 200,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_videoController!.value.isPlaying) {
                        _videoController!.pause();
                      } else {
                        _videoController!.play();
                      }
                    });
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _videoController!.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).padding.bottom + 24,
                top: 24,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.9),
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Audio preview indicator (only for photo mode)
                  if (!widget.isVideo && widget.audioPath.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.mic,
                            color: AppColors.error, // âœ¨ Thermal Orange (Voice/Record standard)
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Voice note attached',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              ref.read(audioServiceProvider).playFromFile(
                                widget.audioPath,
                              );
                            },
                            icon: const Icon(
                              Icons.play_arrow,
                              color: AppColors.primaryAction,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Video info (for video mode)
                  if (widget.isVideo && _videoController != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.videocam,
                            color: AppColors.secondaryAction,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Video with audio ${_isVideoInitialized ? "(${_formatDuration(_videoController!.value.duration)})" : ""}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Send button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? null : _sendVibe,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryAction,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.black),
                      label: Text(
                        _isSending ? 'Sending...' : 'Send Vibe',
                        style: AppTypography.buttonText.copyWith(color: Colors.black),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build the main preview content based on mode
  Widget _buildPreviewContent() {
    // Audio-only mode: Show blurred profile picture or gradient
    // Use 1:1 aspect ratio to match the camera portal design
    if (widget.isAudioOnly) {
      return Center(
        child: AspectRatio(
          aspectRatio: 1.0, // Match camera portal's 1:1 square
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: _buildAudioOnlyBackground(),
          ),
        ),
      );
    }
    
    // Video mode
    if (widget.isVideo && widget.videoPath != null) {
      return _buildVideoPlayer();
    }
    
    // Photo mode (default)
    if (widget.imagePath.isNotEmpty && File(widget.imagePath).existsSync()) {
      return Image.file(
        File(widget.imagePath),
        fit: BoxFit.cover,
      );
    }
    
    // Fallback: gradient background
    return _buildAudioOnlyBackground();
  }
  
  /// Build beautiful background for audio-only vibes
  /// Uses blurred profile picture if available, otherwise animated gradient
  Widget _buildAudioOnlyBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1: Profile image or gradient base
        if (widget.senderAvatarUrl != null && widget.senderAvatarUrl!.isNotEmpty)
          Image.network(
            widget.senderAvatarUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildGradientFallback(),
          )
        else
          _buildGradientFallback(),
        
        // Layer 2: Heavy blur effect
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(color: Colors.transparent),
        ),
        
        // Layer 3: Dark overlay for contrast
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.3),
                Colors.black.withOpacity(0.5),
                Colors.black.withOpacity(0.7),
              ],
            ),
          ),
        ),
        
        // Layer 4: Animated Aura visualization
        // Connected to actual audio playback state
        Positioned.fill(
          child: Opacity(
            opacity: 0.4,
            child: AuraVisualization(isPlaying: _isAudioPlaying),
          ),
        ),
        
        // Layer 5: Audio mode indicator in center
        // FIX: Removed redundant static mic icon - AuraVisualization IS the indicator
        // Keeping just the text labels for context
        Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated play button that pulses with audio
                GestureDetector(
                  onTap: () {
                    if (_isAudioPlaying) {
                      ref.read(audioServiceProvider).stop();
                    } else {
                      ref.read(audioServiceProvider).playFromFile(widget.audioPath);
                    }
                  },
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryAction.withOpacity(0.3),
                          AppColors.primaryAction.withOpacity(0.1),
                        ],
                      ),
                      border: Border.all(
                        color: AppColors.primaryAction.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _isAudioPlaying ? Icons.pause : Icons.play_arrow,
                      size: 42,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Audio Vibe',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.audioDuration ?? 0}s',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  /// Gradient fallback when no profile picture available
  Widget _buildGradientFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.voidNavy,
            AppColors.surface,
          ],
        ),
      ),
    );
  }
  
  /// Capture the background as an image file for widget compatibility
  /// 
  /// SAFETY FIX: Implements dynamic downscaling to prevent GPU Texture OOM crashes.
  /// Standard mobile GPUs have a Max Texture Size limit (often 4096px or 8192px).
  /// Capturing at full device pixel ratio on a large tablet can exceed this limit.
  Future<File?> _captureBackgroundAsImage() async {
    try {
      final boundary = _backgroundKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      
      // 1. Calculate a safe pixel ratio
      // logicalSize * pixelRatio = physicalPixels
      final ui.Size logicalSize = boundary.size;
      
      // CRITICAL OOM FIX: Lowered from 2048px to 1080px (Final Safety Adjustment).
      // 2048x2048px = 16MB (Safe-ish).
      // 1080x1920px = 8MB (Ideal high-quality limit).
      // 1024x1024px = 4MB (Bulletproof).
      const double maxSafeDimension = 1080.0; 
      
      final double maxSide = math.max(logicalSize.width, logicalSize.height);
      
      // If the widget is already larger than 1080px, the ratio will be < 1.0
      double safePixelRatio = 1.0;
      if (maxSide > maxSafeDimension) {
        safePixelRatio = maxSafeDimension / maxSide;
      }
      
      // 2. Capture the image with the calculated safe ratio
      final image = await boundary.toImage(pixelRatio: safePixelRatio);
      
      // CRITICAL PERFORMANCE FIX: "Extract on Main, Encode on Worker" Pattern
      // 1. Extract raw RGBA bytes on the UI thread (very fast, no encoding).
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final int width = image.width;
      final int height = image.height;
      
      // CRITICAL: Explicitly dispose the GPU handle immediately as we now have the CPU bytes.
      image.dispose();
      
      if (byteData == null) return null;

      // 2. Offload heavy PNG compression to a background isolate using the 'image' package.
      // This avoids the ArgumentError because we are passing raw bytes (Uint8List), not a GPU handle.
      final Uint8List pngBytes = await Isolate.run(() {
        final rawBytes = byteData.buffer.asUint8List();
        
        // Convert raw bytes to an 'image' package object
        final imgImage = img.Image.fromBytes(
          width: width,
          height: height,
          bytes: rawBytes.buffer,
          numChannels: 4,
          format: img.Format.uint8,
          order: img.ChannelOrder.rgba,
        );
        
        // Perform the CPU-intensive PNG encoding
        return img.encodePng(imgImage);
      });
      
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/audio_vibe_bg_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);
      
      return file;
    } catch (e) {
      debugPrint('Error capturing background: $e');
      return null;
    }
  }

  Widget _buildVideoPlayer() {
    if (!_isVideoInitialized || _videoController == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF00F0FF),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          if (_videoController!.value.isPlaying) {
            _videoController!.pause();
          } else {
            _videoController!.play();
          }
        });
      },
      // PORTAL PARADOX FIX: Use AspectRatio instead of BoxFit.cover
      // This preserves the 1:1 square framing the user saw during recording
      // PORTAL PARADOX FIX (Option A): Force 1:1 Aspect Ratio + BoxFit.cover
      // This crops the 9:16 video to a square, matching exactly what the user framed.
      child: Center(
        child: AspectRatio(
          aspectRatio: 1.0, // Force Square
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: FittedBox(
              fit: BoxFit.cover, // Zoom-to-cover (Crop top/bottom)
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _formatDate(DateTime date) {
    final months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  Future<void> _sendVibe() async {
    _showFriendPicker();
  }

  void _showFriendPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final friendsAsync = ref.watch(friendsProvider);
          
          return Container(
            padding: const EdgeInsets.all(24),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Send to...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
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
                                  Navigator.pop(context); // Close picker
                                  context.push(AppRoutes.addFriends);
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
                                color: AppColors.primaryAction,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.send, color: Colors.black, size: 20),
                            ),
                            onTap: () => _performSend(friend.id),
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.primaryAction),
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

  Future<void> _performSend(String receiverId) async {
    Navigator.pop(context); // Close picker
    
    if (_isSending) return;
    
    // FIX: stop audio immediately when send starts to prevent "Zombie Audio" 
    ref.read(audioServiceProvider).stop();
    
    // We need to capture the background image BEFORE navigating
    // because after navigation the context is gone
    File? imageFile;
    if (widget.isAudioOnly) {
      // Show a temporary loading if needed, but since capture is fast, we just do it
      // AUDIO-ONLY: Capture the blurred background as image for widget
      imageFile = await _captureBackgroundAsImage();
      if (imageFile == null) {
        debugPrint('Warning: Could not capture background, sending without image');
      }
    } else if (!widget.isVideo && widget.imagePath.isNotEmpty) {
      // PHOTO: Use the actual photo
      imageFile = File(widget.imagePath);
    }

    // Capture duration and other metadata
    int duration = widget.audioDuration ?? 5;
    if (widget.isVideo && _isVideoInitialized && _videoController != null) {
      duration = _videoController!.value.duration.inSeconds;
      if (duration <= 0) duration = widget.audioDuration ?? 5;
    }
    
    // Mock waveform for now (should be passed from camera but PreviewScreen doesn't have it yet)
    final waveform = List.generate(20, (_) => 0.5);

    // Trigger background upload
    debugPrint('📤 [PreviewScreen] Triggering background upload');
    // Trigger blocking upload (User Request: Wait until full success)
    debugPrint('📤 [PreviewScreen] Triggering BLOCKING upload');
    
    // 1. Show Blocking Dialog
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissal
      builder: (context) => PopScope( // Prevent back button
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                const CircularProgressIndicator(
                  color: AppColors.primaryAction,
                ),
                const SizedBox(height: 24),
                Text(
                  'Sending Vibe...',
                  style: AppTypography.bodyMedium.copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait until upload completes',
                  style: AppTypography.labelSmall.copyWith(color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // 2. Await full upload
      await ref.read(vibeUploadProvider.notifier).addUploadBlocking(
        receiverId: receiverId,
        audioPath: widget.audioPath.isNotEmpty ? widget.audioPath : null,
        audioDuration: duration,
        waveformData: waveform, // Corrected from waveformData to waveform
        imagePath: imageFile?.path,
        videoPath: widget.isVideo && widget.videoPath != null ? widget.videoPath : null,
        isVideo: widget.isVideo,
        isAudioOnly: widget.isAudioOnly,
        isFromGallery: widget.isFromGallery,
        originalPhotoDate: widget.originalPhotoDate,
      );
      
      // 3. Success! Dismiss Dialog + Navigate Home
      if (mounted) {
        Navigator.pop(context); // Dismiss Dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Vibe sent successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        context.go(AppRoutes.home);
      }
    } catch (e) {
      // 4. Error! Dismiss Dialog + Show Error
      if (mounted) {
        Navigator.pop(context); // Dismiss Dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Send failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}
