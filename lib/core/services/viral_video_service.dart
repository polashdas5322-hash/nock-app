import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:appinio_social_share/appinio_social_share.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:gal/gal.dart'; // Gallery saver for Save button

/// Video export format type
///
/// - [raw]: 1:1 square ratio, simple loop, preserves original memory (for Save button)
/// - [viral]: 9:16 vertical ratio, blurred background, Instagram-ready (for Share button)
enum VideoExportType { raw, viral }

/// Viral Video Service - The "Share Your Aura" Engine
///
/// Generates TikTok/Instagram-ready MP4 videos from image + audio.
/// Uses FFmpeg to create a polished, 9:16 video with blurred background.
class ViralVideoService {
  final AppinioSocialShare _socialShare = AppinioSocialShare();

  /// Generate a viral-ready MP4 video
  Future<File?> generateViralVideo({
    required String imagePath,
    required String audioPath,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${dir.path}/vibe_viral_$timestamp.mp4';

      final file = File(outputPath);
      if (await file.exists()) await file.delete();

      onProgress?.call(0.1);

      final List<String> args = [
        '-y',
        '-hwaccel', 'auto',
        '-loop', '1',
        '-i', imagePath,
        '-hwaccel', 'auto',
        '-i', audioPath,

        // COMPLEX FILTERS: Blurred background + scaled foreground
        '-filter_complex',
        '[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=20[bg];'
            '[0:v]scale=1080:-1[fg];'
            '[bg][fg]overlay=(W-w)/2:(H-h)/2',

        // 1. FORCE FRAMERATE & KEYFRAMES (TikTok/IG stability)
        '-r', '30',
        '-g', '60',
        '-keyint_min', '60',
        '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart',

        // 2. HARDWARE ENCODING (LGPL Compliant)
        '-c:v', Platform.isIOS ? 'h264_videotoolbox' : 'h264_mediacodec',
      ];

      if (Platform.isIOS) {
        args.addAll(['-b:v', '4M', '-profile:v', 'high']);
      } else {
        // h264_mediacodec for Android
        args.addAll(['-b:v', '4M', '-profile:v', 'high']);
      }

      args.addAll(['-c:a', 'aac', '-b:a', '192k', '-shortest', outputPath]);

      debugPrint('ViralVideo: Generating video with args: $args');
      onProgress?.call(0.2);

      // Async execution to prevent UI thread blocking
      final session = await FFmpegKit.executeWithArgumentsAsync(args);
      final returnCode = await session.getReturnCode();

      onProgress?.call(0.9);

      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('ViralVideo: SUCCESS - Video saved to $outputPath');
        onProgress?.call(1.0);
        return File(outputPath);
      } else {
        final logs = await session.getOutput();
        debugPrint('ViralVideo: FFmpeg Error: $logs');
        return null;
      }
    } catch (e) {
      debugPrint('ViralVideo: Error generating video: $e');
      return null;
    }
  }

  /// Generate video from URLs (downloads files first)
  Future<File?> generateFromUrls({
    required String imageUrl,
    required String audioUrl,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();

      onProgress?.call(0.05);

      debugPrint('ViralVideo: Downloading image...');
      final imageResponse = await http.get(Uri.parse(imageUrl));
      if (imageResponse.statusCode != 200) {
        debugPrint('ViralVideo: Failed to download image');
        return null;
      }
      final imagePath =
          '${tempDir.path}/viral_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(imagePath).writeAsBytes(imageResponse.bodyBytes);

      onProgress?.call(0.2);

      debugPrint('ViralVideo: Downloading audio...');
      final audioResponse = await http.get(Uri.parse(audioUrl));
      if (audioResponse.statusCode != 200) {
        debugPrint('ViralVideo: Failed to download audio');
        return null;
      }
      final audioPath =
          '${tempDir.path}/viral_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await File(audioPath).writeAsBytes(audioResponse.bodyBytes);

      onProgress?.call(0.4);

      return await generateViralVideo(
        imagePath: imagePath,
        audioPath: audioPath,
        onProgress: (p) => onProgress?.call(0.4 + p * 0.6),
      );
    } catch (e) {
      debugPrint('ViralVideo: Error generating from URLs: $e');
      return null;
    }
  }

  // ============ UNIFIED VIDEO GENERATION (Single Source of Truth) ============

  /// Generate video with configurable export type
  ///
  /// This is the unified entry point for all video generation:
  /// - [raw]: 1:1 square, simple loop - for Save to Gallery
  /// - [viral]: 9:16 vertical, blurred background - for Social Sharing
  Future<File?> generateVideo({
    required String imagePath,
    required String audioPath,
    VideoExportType type = VideoExportType.raw,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${dir.path}/vibe_${type.name}_$timestamp.mp4';

      final file = File(outputPath);
      if (await file.exists()) await file.delete();

      onProgress?.call(0.1);

      final List<String> args = ['-y'];

      if (type == VideoExportType.viral) {
        // VIRAL FORMAT: 9:16 with blurred background (Instagram/TikTok ready)
        args.addAll([
          '-hwaccel',
          'auto',
          '-loop',
          '1',
          '-i',
          imagePath,
          '-hwaccel',
          'auto',
          '-i',
          audioPath,
          '-filter_complex',
          '[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=20[bg];'
              '[0:v]scale=1080:-1[fg];'
              '[bg][fg]overlay=(W-w)/2:(H-h)/2',
          '-r',
          '30',
          '-g',
          '60',
          '-keyint_min',
          '60',
          '-pix_fmt',
          'yuv420p',
          '-movflags',
          '+faststart',
          '-c:v',
          Platform.isIOS ? 'h264_videotoolbox' : 'h264_mediacodec',
        ]);
        if (Platform.isIOS) {
          args.addAll(['-b:v', '4M', '-profile:v', 'high']);
        } else {
          args.addAll(['-b:v', '4M', '-profile:v', 'high']);
        }
      } else {
        // RAW FORMAT: 1:1 square, center-cropped (for Gallery Save)
        // This creates a clean square video that fills gallery thumbnails
        //
        // IMPORTANT: Using HARDWARE ENCODERS (no GPL libx264)
        // -tune stillimage is libx264-specific, using -b:v instead
        final rawEncoder = Platform.isIOS
            ? 'h264_videotoolbox'
            : 'h264_mediacodec';

        args.addAll([
          '-loop', '1',
          '-i', imagePath,
          '-i', audioPath,
          // 1:1 Square Filter Chain:
          // 1. Scale to ensure shorter side is at least 1080
          // 2. Center-crop to 1080x1080 square
          '-filter_complex',
          '[0:v]scale=1080:1080:force_original_aspect_ratio=increase,crop=1080:1080[out]',
          '-map', '[out]',
          '-map', '1:a',
          // Hardware Encoder (fast, no GPL issues)
          '-c:v', rawEncoder,
          '-b:v', '2M', // 2 Mbps (good for static image video)
          '-pix_fmt', 'yuv420p',
        ]);
      }

      // Common audio settings
      args.addAll(['-c:a', 'aac', '-b:a', '192k', '-shortest', outputPath]);

      debugPrint('MediaEngine: Generating ${type.name} video...');
      debugPrint('MediaEngine: Command args: ${args.join(' ')}');
      onProgress?.call(0.2);

      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      onProgress?.call(0.9);

      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint(
          'MediaEngine: SUCCESS - ${type.name} video saved to $outputPath',
        );
        onProgress?.call(1.0);
        return File(outputPath);
      } else {
        final logs = await session.getOutput();
        debugPrint('MediaEngine: FFmpeg Error: $logs');

        // Fallback to software encoder if hardware fails
        if (type == VideoExportType.viral) {
          debugPrint('MediaEngine: Retrying with software encoder...');
          return await generateVideo(
            imagePath: imagePath,
            audioPath: audioPath,
            type: VideoExportType.raw, // Fallback to simpler format
            onProgress: onProgress,
          );
        }
        return null;
      }
    } catch (e) {
      debugPrint('MediaEngine: Error generating video: $e');
      return null;
    }
  }

  // ============ GALLERY SAVE (Single Source of Truth) ============

  /// Save media to device gallery
  ///
  /// Handles all media types from camera:
  /// - Photo only → saves directly as image
  /// - Video only → saves directly as video
  /// - Photo + Audio → merges to MP4 (1:1 raw format) then saves
  ///
  /// Returns true if save was successful
  Future<bool> saveToGallery({
    File? imageFile,
    File? videoFile,
    File? audioFile,
    String albumName = 'Vibe',
    void Function(double progress)? onProgress,
  }) async {
    try {
      onProgress?.call(0.1);

      // CASE 1: Photo + Audio → Merge to video first
      if (imageFile != null && audioFile != null) {
        debugPrint('MediaEngine: Photo + Audio → Merging to MP4...');
        final mergedVideo = await generateVideo(
          imagePath: imageFile.path,
          audioPath: audioFile.path,
          type: VideoExportType.raw, // 1:1 for gallery
          onProgress: (p) => onProgress?.call(0.1 + p * 0.7),
        );

        if (mergedVideo != null) {
          await Gal.putVideo(mergedVideo.path, album: albumName);
          debugPrint('MediaEngine: ✅ Merged video saved to gallery');
          onProgress?.call(1.0);
          return true;
        }
        return false;
      }

      // CASE 2: Photo only → Crop to 1:1 square then save
      if (imageFile != null) {
        debugPrint('MediaEngine: Photo → Cropping to 1:1 square...');

        // Crop image to 1:1 square using FFmpeg
        final croppedImage = await _cropImageToSquare(imageFile.path);

        if (croppedImage != null) {
          await Gal.putImage(croppedImage.path, album: albumName);
          onProgress?.call(1.0);
          debugPrint('MediaEngine: ✅ Square photo saved to gallery');
          return true;
        } else {
          // Fallback: save original if crop fails
          await Gal.putImage(imageFile.path, album: albumName);
          onProgress?.call(1.0);
          debugPrint(
            'MediaEngine: ✅ Original photo saved to gallery (crop failed)',
          );
          return true;
        }
      }

      // CASE 3: Video only → Crop to 1:1 square then save
      if (videoFile != null) {
        debugPrint('MediaEngine: Video → Cropping to 1:1 square...');

        // Crop video to 1:1 square using FFmpeg
        final croppedVideo = await _cropVideoToSquare(videoFile.path);

        if (croppedVideo != null) {
          await Gal.putVideo(croppedVideo.path, album: albumName);
          onProgress?.call(1.0);
          debugPrint('MediaEngine: ✅ Square video saved to gallery');
          return true;
        } else {
          // Fallback: save original if crop fails
          await Gal.putVideo(videoFile.path, album: albumName);
          onProgress?.call(1.0);
          debugPrint(
            'MediaEngine: ✅ Original video saved to gallery (crop failed)',
          );
          return true;
        }
      }

      debugPrint('MediaEngine: ⚠️ Nothing to save');
      return false;
    } catch (e) {
      debugPrint('MediaEngine: ❌ Save to gallery failed: $e');
      return false;
    }
  }

  /// Crop image to 1:1 square using FFmpeg
  ///
  /// Centers and crops to 1080x1080 for consistent gallery appearance
  Future<File?> _cropImageToSquare(String imagePath) async {
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${dir.path}/vibe_square_$timestamp.jpg';

      debugPrint('MediaEngine: Input image path: $imagePath');

      // Check if input file exists
      final inputFile = File(imagePath);
      if (!await inputFile.exists()) {
        debugPrint('MediaEngine: ❌ Input image file does not exist!');
        return null;
      }

      debugPrint(
        'MediaEngine: Input file exists, size: ${await inputFile.length()} bytes',
      );

      // FFmpeg filter: scale to ensure shorter side is 1080, then center-crop to 1080x1080
      final args = [
        '-y',
        '-i', imagePath,
        '-vf',
        'scale=1080:1080:force_original_aspect_ratio=increase,crop=1080:1080',
        '-q:v', '2', // High quality JPEG
        outputPath,
      ];

      debugPrint('MediaEngine: Cropping image to 1:1 square...');
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      debugPrint('MediaEngine: FFmpeg return code: $returnCode');

      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final size = await outputFile.length();
          debugPrint('MediaEngine: ✅ Image cropped to 1080x1080 ($size bytes)');
          return outputFile;
        } else {
          debugPrint('MediaEngine: ❌ Output image file not created');
        }
      } else {
        final logs = await session.getOutput();
        debugPrint('MediaEngine: ❌ Image crop failed with code: $returnCode');
        debugPrint('MediaEngine: FFmpeg logs: $logs');
      }

      return null;
    } catch (e, stack) {
      debugPrint('MediaEngine: Image crop exception: $e');
      debugPrint('MediaEngine: Stack trace: $stack');
      return null;
    }
  }

  /// Crop video to 1:1 square using FFmpeg
  ///
  /// Centers and crops to 1080x1080 for consistent gallery appearance
  /// Uses software encoding for maximum compatibility
  Future<File?> _cropVideoToSquare(String videoPath) async {
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${dir.path}/vibe_square_$timestamp.mp4';

      debugPrint('MediaEngine: Input video path: $videoPath');

      // Check if input file exists
      final inputFile = File(videoPath);
      if (!await inputFile.exists()) {
        debugPrint('MediaEngine: ❌ Input video file does not exist!');
        return null;
      }

      debugPrint(
        'MediaEngine: Input file exists, size: ${await inputFile.length()} bytes',
      );

      // FFmpeg filter: scale to minimum 1080 on shorter side, then center-crop to 1080x1080
      // Using filter_complex for robust square crop
      //
      // IMPORTANT: Using HARDWARE ENCODERS (The Locket Way)
      // - ffmpeg_kit_flutter_new_https does NOT include full libx264 (GPL licensing)
      // - Using h264_mediacodec (Android) / h264_videotoolbox (iOS) for fast hardware encoding
      // - No -preset/-crf flags (libx264-specific), using -b:v for bitrate control instead

      final encoder = Platform.isIOS ? 'h264_videotoolbox' : 'h264_mediacodec';

      final args = [
        '-y',
        '-i', videoPath,
        // Simple and robust filter: scale then crop
        // scale=1080:1080:force_original_aspect_ratio=increase ensures min dimension is 1080
        // crop=1080:1080 takes center 1080x1080
        '-filter_complex',
        '[0:v]scale=1080:1080:force_original_aspect_ratio=increase,crop=1080:1080[v]',
        '-map', '[v]',
        '-map', '0:a?', // Map audio if exists (? makes it optional)
        // Hardware Encoder (fast, no GPL issues)
        '-c:v', encoder,
        '-b:v', '4M', // 4 Mbps bitrate (good quality for 1080x1080)
        // Audio settings
        '-c:a', 'aac',
        '-b:a', '128k',
        // Compatibility
        '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart',
        outputPath,
      ];

      debugPrint('MediaEngine: Cropping video to 1:1 square...');
      debugPrint('MediaEngine: FFmpeg args: ${args.join(' ')}');

      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      debugPrint('MediaEngine: FFmpeg return code: $returnCode');

      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final size = await outputFile.length();
          debugPrint('MediaEngine: ✅ Video cropped to 1080x1080 ($size bytes)');
          return outputFile;
        } else {
          debugPrint('MediaEngine: ❌ Output file not created');
        }
      } else {
        final logs = await session.getOutput();
        debugPrint('MediaEngine: ❌ Video crop failed with code: $returnCode');
        debugPrint('MediaEngine: FFmpeg logs: $logs');
      }

      return null;
    } catch (e, stack) {
      debugPrint('MediaEngine: Video crop exception: $e');
      debugPrint('MediaEngine: Stack trace: $stack');
      return null;
    }
  }

  /// Download an existing video file for sharing
  Future<File?> downloadVideo(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      onProgress?.call(0.1);

      debugPrint('ViralVideo: Downloading existing video from $url');
      final response = await http.get(Uri.parse(url));
      onProgress?.call(0.8);

      if (response.statusCode != 200) {
        debugPrint(
          'ViralVideo: Failed to download video (${response.statusCode})',
        );
        return null;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${tempDir.path}/vibe_shared_video_$timestamp.mp4';
      final file = File(path);
      await file.writeAsBytes(response.bodyBytes);

      onProgress?.call(1.0);
      debugPrint('ViralVideo: Video downloaded to $path');
      return file;
    } catch (e) {
      debugPrint('ViralVideo: Error downloading video: $e');
      return null;
    }
  }

  /// Check if Instagram is installed
  Future<bool> isInstagramInstalled() async {
    try {
      final apps = await _socialShare.getInstalledApps();
      return apps['instagram'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Check if TikTok is installed
  Future<bool> isTikTokInstalled() async {
    try {
      final apps = await _socialShare.getInstalledApps();
      return apps['tiktok'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Get all installed sharing apps
  Future<Map<String, bool>> getInstalledApps() async {
    try {
      final result = await _socialShare.getInstalledApps();
      return Map<String, bool>.from(result);
    } catch (e) {
      return {};
    }
  }

  /// Check Android permissions based on SDK version
  Future<void> _checkAndroidPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        await Permission.photos.request();
        await Permission.videos.request();
      } else {
        await Permission.storage.request();
      }
    }
  }

  /// Share to Instagram Stories
  /// Android/iOS: shareToInstagramStory(String appId, {stickerImage, backgroundImage, backgroundVideo, ...})
  Future<String> shareToInstagramStories({
    required String videoPath,
    String? facebookAppId,
    String? attributionUrl,
  }) async {
    try {
      await _checkAndroidPermissions();

      String? result;
      final appId = facebookAppId ?? 'YOUR_FB_APP_ID';

      if (Platform.isAndroid) {
        // Android: shareToInstagramStory(appId, {stickerImage, backgroundImage, backgroundVideo, ...})
        result = await _socialShare.android.shareToInstagramStory(
          appId, // First positional arg: appId
          backgroundVideo: videoPath,
          backgroundTopColor: '#000000',
          backgroundBottomColor: '#000000',
          attributionURL: attributionUrl ?? 'https://getvibe.app',
        );
      } else if (Platform.isIOS) {
        // iOS: shareToInstagramStory(appId, {stickerImage, backgroundImage, backgroundVideo, ...})
        result = await _socialShare.iOS.shareToInstagramStory(
          appId, // First positional arg: appId
          backgroundVideo: videoPath,
          backgroundTopColor: '#000000',
          backgroundBottomColor: '#000000',
          attributionURL: attributionUrl ?? 'https://getvibe.app',
        );
      }

      debugPrint('ViralVideo: Instagram Stories share result: $result');
      return result ?? 'success';
    } catch (e) {
      debugPrint('ViralVideo: Error sharing to Instagram Stories: $e');
      return await shareToSystem(videoPath, 'Check out my Vibe! 🎤');
    }
  }

  /// Share to Instagram Feed/Reels
  /// Android: shareToInstagramFeed(message, filePath) - 2 positional args
  /// iOS: shareToInstagramReels(videoPath) - 1 positional arg
  Future<String> shareToInstagramReels(String videoPath) async {
    try {
      await _checkAndroidPermissions();

      String? result;
      if (Platform.isAndroid) {
        // Android: shareToInstagramFeed(String message, String? filePath)
        result = await _socialShare.android.shareToInstagramFeed('', videoPath);
      } else if (Platform.isIOS) {
        // iOS: shareToInstagramReels(String videoPath)
        result = await _socialShare.iOS.shareToInstagramReels(videoPath);
      }

      return result ?? 'success';
    } catch (e) {
      debugPrint('ViralVideo: Error sharing to Instagram Reels: $e');
      return await shareToSystem(videoPath, 'Check out my Vibe! 🎤');
    }
  }

  /// Share to TikTok
  /// Android: shareToTiktokStatus(List<String> filePaths)
  /// iOS: shareToTiktokPost(videoFile, redirectUrl, TiktokFileType) - requires TikTok SDK setup
  Future<String> shareToTikTok(String videoPath) async {
    try {
      if (Platform.isAndroid) {
        await _checkAndroidPermissions();

        // Android: shareToTiktokStatus(List<String> filePaths)
        final result = await _socialShare.android.shareToTiktokStatus([
          videoPath,
        ]);
        return result;
      } else {
        // iOS requires TikTok SDK setup - fallback to system share
        debugPrint(
          'ViralVideo: iOS TikTok requires SDK setup, using system share',
        );
        return await shareToSystem(videoPath, 'Check out my Vibe! 🎤 #vibeapp');
      }
    } catch (e) {
      debugPrint('ViralVideo: Error sharing to TikTok: $e');
      return await shareToSystem(videoPath, 'Check out my Vibe! 🎤 #vibeapp');
    }
  }

  /// Share to WhatsApp
  /// Android: shareToWhatsapp(message, filePath) - 2 positional args
  /// iOS: shareToWhatsapp(message) - only text supported
  Future<String> shareToWhatsApp(String videoPath, String message) async {
    try {
      String? result;
      if (Platform.isAndroid) {
        // Android: shareToWhatsapp(String message, String? filePath)
        result = await _socialShare.android.shareToWhatsapp(message, videoPath);
      } else if (Platform.isIOS) {
        // iOS only supports text - use system share for files
        return await shareToSystem(videoPath, message);
      }
      return result ?? 'success';
    } catch (e) {
      debugPrint('ViralVideo: Error sharing to WhatsApp: $e');
      return await shareToSystem(videoPath, message);
    }
  }

  /// Share to system share sheet (THE ULTIMATE FALLBACK)
  /// Uses share_plus which is rock-solid
  Future<String> shareToSystem(String videoPath, String message) async {
    try {
      final file = XFile(videoPath);
      await Share.shareXFiles([file], text: message, subject: 'My Vibe');
      return 'success';
    } catch (e) {
      debugPrint('ViralVideo: Error sharing to system: $e');
      return 'error: $e';
    }
  }
}

/// Provider for ViralVideoService
final viralVideoServiceProvider = Provider<ViralVideoService>((ref) {
  return ViralVideoService();
});

/// State for tracking video generation
class ViralVideoState {
  final bool isGenerating;
  final double progress;
  final File? outputFile;
  final String? error;

  const ViralVideoState({
    this.isGenerating = false,
    this.progress = 0.0,
    this.outputFile,
    this.error,
  });

  ViralVideoState copyWith({
    bool? isGenerating,
    double? progress,
    File? outputFile,
    String? error,
  }) {
    return ViralVideoState(
      isGenerating: isGenerating ?? this.isGenerating,
      progress: progress ?? this.progress,
      outputFile: outputFile ?? this.outputFile,
      error: error ?? this.error,
    );
  }
}

/// State notifier for viral video generation
class ViralVideoNotifier extends StateNotifier<ViralVideoState> {
  final ViralVideoService _service;

  ViralVideoNotifier(this._service) : super(const ViralVideoState());

  Future<File?> generateAndShare({
    required String imageUrl,
    required String audioUrl,
    String? platform,
    String? message,
  }) async {
    state = state.copyWith(isGenerating: true, progress: 0.0, error: null);

    try {
      final videoFile = await _service.generateFromUrls(
        imageUrl: imageUrl,
        audioUrl: audioUrl,
        onProgress: (p) => state = state.copyWith(progress: p * 0.8),
      );

      if (videoFile == null) {
        state = state.copyWith(
          isGenerating: false,
          error: 'Failed to generate video',
        );
        return null;
      }

      state = state.copyWith(progress: 0.9, outputFile: videoFile);

      if (platform != null) {
        switch (platform) {
          case 'instagram':
            await _service.shareToInstagramStories(videoPath: videoFile.path);
            break;
          case 'reels':
            await _service.shareToInstagramReels(videoFile.path);
            break;
          case 'tiktok':
            await _service.shareToTikTok(videoFile.path);
            break;
          case 'whatsapp':
            await _service.shareToWhatsApp(videoFile.path, message ?? '');
            break;
          default:
            await _service.shareToSystem(videoFile.path, message ?? '');
        }
      }

      state = state.copyWith(isGenerating: false, progress: 1.0);
      return videoFile;
    } catch (e) {
      state = state.copyWith(isGenerating: false, error: e.toString());
      return null;
    }
  }

  void reset() {
    state = const ViralVideoState();
  }
}

/// Provider for viral video state
final viralVideoStateProvider =
    StateNotifierProvider<ViralVideoNotifier, ViralVideoState>((ref) {
      final service = ref.watch(viralVideoServiceProvider);
      return ViralVideoNotifier(service);
    });
