import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:nock/features/camera/domain/models/camera_models.dart';

/// Data class for overlay content to be composited onto video/images
class OverlayContent {
  final List<DrawingStroke> strokes;
  final List<StickerOverlay> stickers;
  final List<TextOverlay> textOverlays;

  const OverlayContent({
    required this.strokes,
    required this.stickers,
    required this.textOverlays,
  });

  bool get isEmpty => strokes.isEmpty && stickers.isEmpty && textOverlays.isEmpty;
  bool get isNotEmpty => !isEmpty;
}

/// Service for compositing overlays onto videos and images
/// 
/// This service handles:
/// - Creating transparent overlay images from drawings/stickers/text
/// - Compositing overlays onto videos using FFmpeg
/// - Extracting video thumbnails
/// - Smart resolution handling (downscale 4K to 1080p, no upscaling)
class VideoProcessingService {
  
  /// Extract first frame from video as JPEG thumbnail
  /// Used for widget preview and PlayerScreen fallback
  static Future<File?> extractVideoThumbnail(String videoPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final thumbnailPath = '${tempDir.path}/vibe_thumbnail_$timestamp.jpg';
      
      // FFmpeg command to extract first frame as JPEG
      // -ss 0: Seek to start (first frame)
      // -vframes 1: Extract only 1 frame
      // -q:v 2: High quality JPEG (2-5 is good, lower = better)
      final command = [
        '-y',
        '-hwaccel', 'auto',
        '-i', videoPath,
        '-ss', '0',
        '-vframes', '1',
        '-q:v', '2',
        '-pix_fmt', 'yuvj420p',
        thumbnailPath,
      ];
      
      debugPrint('FFmpeg: Extracting video thumbnail...');
      final session = await FFmpegKit.executeWithArguments(command);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        final thumbnailFile = File(thumbnailPath);
        if (await thumbnailFile.exists()) {
          debugPrint('FFmpeg: Thumbnail extracted to $thumbnailPath');
          return thumbnailFile;
        }
      }
      
      debugPrint('FFmpeg: Failed to extract thumbnail');
      return null;
    } catch (e) {
      debugPrint('Error extracting thumbnail: $e');
      return null;
    }
  }

  /// Extract audio track from video as m4a/aac
  /// Used to minimize bandwidth for transcription
  static Future<File?> extractAudio(String videoPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final audioPath = '${tempDir.path}/vibe_audio_extract_$timestamp.m4a';
      
      // FFmpeg command to extract audio without re-encoding (if possible)
      // -vn: Skip video
      // -acodec copy: Copy audio stream without re-encoding (super fast)
      final command = [
        '-y',
        '-hwaccel', 'auto',
        '-i', videoPath,
        '-vn',
        '-acodec', 'copy',
        audioPath,
      ];
      
      debugPrint('FFmpeg: Extracting audio from video...');
      final session = await FFmpegKit.executeWithArguments(command);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        final audioFile = File(audioPath);
        if (await audioFile.exists()) {
          debugPrint('FFmpeg: Audio extracted to $audioPath');
          return audioFile;
        }
      }
      
      // Fallback: If copy fails (e.g. incompatible container), try encoding to aac
      debugPrint('FFmpeg: Fast audio copy failed, trying AAC encode fallback...');
      final fallbackCommand = [
        '-y',
        '-hwaccel', 'auto',
        '-i', videoPath,
        '-vn',
        '-c:a', 'aac',
        '-b:a', '128k',
        audioPath,
      ];
      
      final fallbackSession = await FFmpegKit.executeWithArguments(fallbackCommand);
      final fallbackReturnCode = await fallbackSession.getReturnCode();
      
      if (ReturnCode.isSuccess(fallbackReturnCode)) {
        final audioFile = File(audioPath);
        if (await audioFile.exists()) {
          return audioFile;
        }
      }

      debugPrint('FFmpeg: Failed to extract audio');
      return null;
    } catch (e) {
      debugPrint('Error extracting audio: $e');
      return null;
    }
  }

  /// Calculate target resolution for video output
  /// 
  /// PORTAL PARADOX FIX: Force 1:1 aspect ratio to match UI portal
  /// The UI shows a 1:1 square portal (portalHeight = portalWidth)
  /// We MUST crop the video to this same ratio to prevent:
  /// - Privacy leaks (hidden top/bottom areas appearing in final video)
  /// - Floating overlays (drawings misaligned with cropped area)
  /// 
  /// Example: 1080x1920 source → 1080x1080 output (1:1 square)
  static Size calculateTargetResolution(Size sourceSize, {double targetAspect = 1.0}) {
    // Max width is 720p for widget optimization/file size balance
    const double maxWidth = 720.0;
    
    // Use source width or cap at 1080p
    final double targetWidth = sourceSize.width > maxWidth ? maxWidth : sourceSize.width;
    
    // CRITICAL FIX: Calculate height based on UI portal aspect ratio (1:1 square)
    // NOT based on the camera source (9:16)
    // Height = Width / AspectRatio
    // Example: 1080 / 1 = 1080 pixels (square)
    final double targetHeight = targetWidth / targetAspect;
    
    return Size(targetWidth, targetHeight);
  }

  /// Create a transparent overlay PNG from drawings, stickers, and text
  /// 
  /// This properly maps screen coordinates to video coordinates,
  /// accounting for BoxFit.cover cropping in the camera preview.
  /// 
  /// [videoSize] - The target video dimensions
  /// [renderSize] - The screen render area dimensions (where user drew)
  /// [content] - The overlay content (strokes, stickers, text)
  /// [isFrontCamera] - UNUSED: FFmpeg already applies hflip to front camera video,
  ///                   so overlay coordinates map 1:1 without modification.
  static Future<File?> createOverlayImage({
    required Size videoSize,
    required Size renderSize,
    required OverlayContent content,
    bool isFrontCamera = false,  // Kept for API compatibility, but UNUSED
  }) async {
    try {
      // Create a picture recorder to draw overlays on transparent background
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      // FIX: Removed mirrorX() function entirely.
      // The FFmpeg command already applies hflip to front camera videos,
      // so overlay coordinates should map 1:1 without modification.
      // Previously, we were double-mirroring which caused overlays to
      // appear on the opposite side from where the user drew them.
      
      // ========== CRITICAL: Aspect Ratio Offset Calculation ==========
      // 
      // PROBLEM: The camera preview uses BoxFit.cover which CROPS the video
      // to fill the screen. Screen coordinate (0,0) does NOT map to video (0,0).
      //
      // SOLUTION: Calculate the crop offset and apply it to all coordinates.
      // 
      // UPDATE: We now use normalized coordinates (0.0 to 1.0) relative to renderSize.
      // ================================================================
      
      final renderAspect = renderSize.width / renderSize.height;
      final videoAspect = videoSize.width / videoSize.height;
      
      double scale;
      double offsetX = 0;
      double offsetY = 0;
      
      if (renderAspect > videoAspect) {
        // Screen is wider than video - video is cropped on top/bottom
        scale = videoSize.width / renderSize.width;
        final scaledHeight = renderSize.height * scale;
        offsetY = (videoSize.height - scaledHeight) / 2;
      } else {
        // Screen is taller than video - video is cropped on left/right
        scale = videoSize.height / renderSize.height;
        final scaledWidth = renderSize.width * scale;
        offsetX = (videoSize.width - scaledWidth) / 2;
      }
      
      // Coordinate mapping helpers
      double mapX(double normalizedX) => normalizedX * (renderSize.width * scale) + offsetX;
      double mapY(double normalizedY) => normalizedY * (renderSize.height * scale) + offsetY;

      // Base width for scaling (matches DrawingPainter strategy)
      final videoScaleFactor = videoSize.width / 360;
      
      debugPrint('Overlay: renderSize=$renderSize, videoSize=$videoSize, scale=$scale, offsetX=$offsetX, offsetY=$offsetY');
      
      // Draw strokes
      for (final stroke in content.strokes) {
        final paint = Paint()
          ..color = stroke.color
          ..strokeWidth = stroke.strokeWidth * videoScaleFactor
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        
        if (stroke.points.length > 1) {
          final path = Path();
          path.moveTo(mapX(stroke.points.first.dx), mapY(stroke.points.first.dy));
          for (int i = 1; i < stroke.points.length; i++) {
            path.lineTo(mapX(stroke.points[i].dx), mapY(stroke.points[i].dy));
          }
          canvas.drawPath(path, paint);
        }
      }
      
      // Draw stickers
      for (final sticker in content.stickers) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: sticker.emoji,
            style: TextStyle(fontSize: 48 * sticker.scale * videoScaleFactor),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        
        final centerX = mapX(sticker.position.dx) + textPainter.width / 2;
        final centerY = mapY(sticker.position.dy) + textPainter.height / 2;
        
        canvas.save();
        canvas.translate(centerX, centerY);
        canvas.rotate(sticker.rotation);
        canvas.translate(-textPainter.width / 2, -textPainter.height / 2);
        textPainter.paint(canvas, Offset.zero);
        canvas.restore();
      }
      
      // Draw text overlays
      for (final textItem in content.textOverlays) {
        if (textItem.text.isEmpty) continue;
        
        final style = textItem.fontStyle.getStyle(
          textItem.fontSize * videoScaleFactor, 
          textItem.color,
        ).copyWith(
          shadows: [
            Shadow(
              color: Colors.black54,
              offset: Offset(1 * videoScaleFactor, 1 * videoScaleFactor),
              blurRadius: 4 * videoScaleFactor,
            ),
          ],
        );
        
        final textPainter = TextPainter(
          text: TextSpan(text: textItem.text, style: style),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        
        textPainter.paint(canvas, Offset(mapX(textItem.position.dx), mapY(textItem.position.dy)));
      }
      
      // Create the image
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        videoSize.width.toInt(),
        videoSize.height.toInt(),
      );
      
      // CRITICAL PERFORMANCE FIX: "Extract on Main, Encode on Worker"
      // 1. Extract raw RGBA bytes on UI thread (extremely fast, no compression)
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final int width = image.width;
      final int height = image.height;
      
      // Explicitly dispose of the GPU handle immediately
      image.dispose();
      
      if (byteData == null) return null;

      // 2. Offload heavy PNG compression to a background isolate
      final Uint8List pngBytes = await Isolate.run(() {
        final rawBytes = byteData.buffer.asUint8List();
        
        final imgImage = img.Image.fromBytes(
          width: width,
          height: height,
          bytes: rawBytes.buffer,
          numChannels: 4,
          format: img.Format.uint8,
          order: img.ChannelOrder.rgba,
        );
        
        return img.encodePng(imgImage);
      });
      
      final tempDir = await getTemporaryDirectory();
      final fileName = 'vibe_overlay_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);
      
      return file;
    } catch (e) {
      debugPrint('Error creating overlay image: $e');
      return null;
    }
  }

  /// Composite video with overlay using FFmpeg
  /// Burns drawings, stickers, and text onto the video
  ///
  /// Returns the composited video file, or null if failed
  static Future<File?> compositeVideoWithOverlay({
    required String videoPath,
    required File overlayImage,
    required Size targetSize,
    bool isFrontCamera = false, // NEW: Handle selfie mirroring
  }) async {
    try {
      // 1. PRE-CHECK: Does the video actually have audio?
      // This prevents the "Stream not found" crash.
      bool hasAudio = false;
      try {
        final probeSession = await FFprobeKit.getMediaInformation(videoPath);
        final mediaInfo = probeSession.getMediaInformation();
        if (mediaInfo != null) {
          final streams = mediaInfo.getStreams();
          hasAudio = streams.any((s) => s.getType() == 'audio');
        }
      } catch (e) {
        debugPrint('FFprobe error: $e');
        // Assume no audio if probe fails to be safe
        hasAudio = false;
      }

      debugPrint('FFmpeg: Input video has audio: $hasAudio');

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/vibe_video_overlay_$timestamp.mp4';

      // Delete existing output if any
      final outputFile = File(outputPath);
      if (await outputFile.exists()) await outputFile.delete();

      // RACE CONDITION FIX: Wait for overlay PNG to be fully written
      int retryCount = 0;
      const maxRetries = 10;
      const retryDelayMs = 100;

      while (retryCount < maxRetries) {
        final exists = await overlayImage.exists();
        final size = exists ? await overlayImage.length() : 0;

        if (exists && size > 0) {
          debugPrint('FFmpeg: Overlay PNG validated ($size bytes) after $retryCount retries');
          break;
        }

        debugPrint('FFmpeg: Waiting for overlay PNG to be written... (attempt ${retryCount + 1}/$maxRetries)');
        await Future.delayed(const Duration(milliseconds: retryDelayMs));
        retryCount++;
      }

      // Final validation after retries
      final overlaySize = await overlayImage.length();
      if (overlaySize == 0) {
        debugPrint('FFmpeg: CRITICAL - Overlay PNG is still empty after ${maxRetries * retryDelayMs}ms. Aborting.');
        return null;
      }

      final targetWidth = targetSize.width.toInt();
      final targetHeight = targetSize.height.toInt();

      // PORTAL PARADOX FIX: Center-crop to match UI portal
      // We use 'force_original_aspect_ratio=increase' to ensure the video COVERS the target square
      // Then crop the center square. This matches BoxFit.cover behavior in Flutter.
      final String scaleFilter = 'scale=$targetWidth:$targetHeight:force_original_aspect_ratio=increase';
      final String cropFilter = 'crop=$targetWidth:$targetHeight';

      final String videoFilter = isFrontCamera ? '[0:v]hflip,$scaleFilter,$cropFilter,fps=30[scaled]' : '[0:v]$scaleFilter,$cropFilter,fps=30[scaled]';

      // FIX: SELFIE OVERLAY PARADOX - Do NOT flip overlay for selfies
      // Although video is flipped, overlay is drawn relative to screen coordinates
      final String overlayFilter = '[1:v]scale=$targetWidth:$targetHeight[overlay]';

      // BUILD THE COMMAND DYNAMICALLY
      final List<String> command = [
        '-y',
        '-hwaccel', 'auto',
        '-i', videoPath, // Input 0: Video
        '-i', overlayImage.path, // Input 1: Transparent overlay PNG
      ];

      // LOGIC: If no audio, generate silence (Input 2)
      if (!hasAudio) {
        command.addAll([
          '-f',
          'lavfi',
          '-i',
          'anullsrc=channel_layout=mono:sample_rate=44100', // Input 2: Silence
        ]);
      }

      command.addAll([
        '-filter_complex',
        '$videoFilter;$overlayFilter;[scaled][overlay]overlay=0:0:format=auto',
        '-c:v', Platform.isIOS ? 'h264_videotoolbox' : 'h264_mediacodec',
      ]);

      if (Platform.isIOS) {
        // h264_videotoolbox specific settings (LGPL compliant)
        command.addAll([
          '-b:v', '2M',
          '-profile:v', 'high',
        ]);
      } else {
        // h264_mediacodec (Android) - USES HARDWARE ENCODER (LGPL compliant)
        command.addAll([
          '-b:v', '2M',
        ]);
      }

      // AUDIO MAPPING STRATEGY
      if (hasAudio) {
        // Scenario A: Source has audio. Process it normally.
        command.addAll([
          '-c:a', 'aac',
          '-b:a', '96k', // Lower bitrate
          '-ac', '1', // Mono audio
          '-ar', '44100',
          '-af', 'aresample=async=1', // Safe to use because we know audio exists
        ]);
      } else {
        // Scenario B: Source is silent. Map the generated silence (Input 2).
        command.addAll([
          '-map', '0:v', // Map Video from Input 0
          '-map', '2:a', // Map Audio from Input 2 (Silence)
          '-c:a', 'aac',
          '-shortest', // Stop silence when video ends
        ]);
      }

      command.addAll([
        '-fps_mode', 'cfr', // Constant frame rate

        // WEB OPTIMIZATION
        '-movflags', '+faststart', // Allows playback to start before download completes

        '-pix_fmt', 'yuv420p', // Required for iOS/QuickTime compatibility
        outputPath,
      ]);

      debugPrint('FFmpeg: Compositing video with overlays...');
      debugPrint('FFmpeg command: ${command.join(' ')}');

      final session = await FFmpegKit.executeWithArgumentsAsync(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('FFmpeg: SUCCESS - Video with overlays saved to $outputPath');
        // Clean up overlay image
        try { await overlayImage.delete(); } catch (_) {}
        return File(outputPath);
      } else {
        // HARDWARE ENCODER FALLBACK: If hardware encoder fails, retry with software libx264
        final logs = await session.getAllLogsAsString();
        debugPrint('FFmpeg: Hardware encoder failed. Logs: $logs');
        debugPrint('FFmpeg: Retrying with software encoder (libx264)...');
        
        // Command for software fallback
        final List<String> fallbackCommand = List.from(command);
        
        // Find and replace the encoder
        final encoderIdx = fallbackCommand.indexOf('-c:v');
        if (encoderIdx != -1 && encoderIdx + 1 < fallbackCommand.length) {
          fallbackCommand[encoderIdx + 1] = 'libx264';
          // libx264 specific tuning for mobile
          fallbackCommand.insertAll(encoderIdx + 2, ['-preset', 'ultrafast', '-crf', '23']);
        }
        
        final fallbackSession = await FFmpegKit.executeWithArgumentsAsync(fallbackCommand);
        final fallbackReturnCode = await fallbackSession.getReturnCode();
        
        // Clean up overlay image
        try { await overlayImage.delete(); } catch (_) {}
        
        if (ReturnCode.isSuccess(fallbackReturnCode)) {
          debugPrint('FFmpeg: SUCCESS (Software Fallback) - video saved to $outputPath');
          return File(outputPath);
        } else {
          final fallbackLogs = await fallbackSession.getAllLogsAsString();
          debugPrint('FFmpeg: CRITICAL - Software fallback also failed: $fallbackLogs');
          return null;
        }
      }
    } catch (e) {
      debugPrint('Error compositing video with overlays: $e');
      return null;
    }
  }
  /// Non-blocking video processing with callback (Optimistic UI support)
  /// 
  /// This runs the FFmpeg command asynchronously and triggers the callback
  /// when complete, allowing the UI to unblock immediately (Navigator.pop).
  static void processAndUpload({
    required String videoPath,
    required File overlayImage,
    required Size targetSize,
    required Function(File) onProcessed,
    required Function(String) onError,
    bool isFrontCamera = false,  // NEW: Handle selfie mirroring
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/vibe_video_overlay_$timestamp.mp4';
      
      // SAFETY CHECK: Validate overlay PNG before FFmpeg (docs recommendation)
      if (!await overlayImage.exists()) {
        debugPrint('FFmpeg (Async): ERROR - Overlay PNG does not exist');
        onError('Overlay PNG does not exist');
        return;
      }
      final overlaySize = await overlayImage.length();
      if (overlaySize == 0) {
        debugPrint('FFmpeg (Async): ERROR - Overlay PNG is empty (0 bytes)');
        onError('Overlay PNG is empty');
        return;
      }
      debugPrint('FFmpeg (Async): Overlay PNG validated (${overlaySize} bytes)');
      
      // 1. PRE-CHECK: Does the video actually have audio? (Async version)
      bool hasAudio = false;
      try {
        final probeSession = await FFprobeKit.getMediaInformation(videoPath);
        final mediaInfo = probeSession.getMediaInformation();
        if (mediaInfo != null) {
          final streams = mediaInfo.getStreams();
          hasAudio = streams.any((s) => s.getType() == 'audio');
        }
      } catch (e) {
         debugPrint('FFprobe (Async) error: $e');
         hasAudio = false;
      }
      debugPrint('FFmpeg (Async): Input video has audio: $hasAudio');

      final targetWidth = targetSize.width.toInt();
      final targetHeight = targetSize.height.toInt();
      
      // PORTAL PARADOX FIX: Center-crop to match UI portal (same as compositeVideoWithOverlay)
      final String scaleFilter = 'scale=$targetWidth:$targetHeight:force_original_aspect_ratio=increase';
      final String cropFilter = 'crop=$targetWidth:$targetHeight';

      final String videoFilter = isFrontCamera
          ? '[0:v]hflip,$scaleFilter,$cropFilter,fps=30[scaled]'
          : '[0:v]$scaleFilter,$cropFilter,fps=30[scaled]';
      
      // FIX: SELFIE OVERLAY PARADOX - Do NOT flip overlay for selfies
      final String overlayFilter = '[1:v]scale=$targetWidth:$targetHeight[overlay]';
      
      // BUILD THE COMMAND DYNAMICALLY
      final List<String> command = [
        '-y',
        '-hwaccel', 'auto',
        '-i', videoPath,           
        '-i', overlayImage.path,   
      ];

      // LOGIC: If no audio, generate silence (Input 2)
      if (!hasAudio) {
        command.addAll([
          '-f', 'lavfi',
          '-i', 'anullsrc=channel_layout=mono:sample_rate=44100', // Input 2: Silence
        ]);
      }

      command.addAll([
        '-filter_complex',
        '$videoFilter;$overlayFilter;[scaled][overlay]overlay=0:0:format=auto',
        '-c:v', Platform.isIOS ? 'h264_videotoolbox' : 'h264_mediacodec',
      ]);

      if (Platform.isIOS) {
        // h264_videotoolbox specific settings (LGPL compliant)
        command.addAll([
          '-b:v', '2M',
          '-profile:v', 'high',
        ]);
      } else {
        // h264_mediacodec (Android) - USES HARDWARE ENCODER (LGPL compliant)
        command.addAll([
          '-b:v', '2M',
        ]);
      }

      // AUDIO MAPPING STRATEGY
      if (hasAudio) {
         command.addAll([
          '-c:a', 'aac',
          '-b:a', '96k',             // Lower bitrate
          '-ac', '1',                // Mono audio
          '-ar', '44100',
          '-af', 'aresample=async=1',
         ]);
      } else {
        command.addAll([
          '-map', '0:v', // Map Video from Input 0
          '-map', '2:a', // Map Audio from Input 2 (Silence)
          '-c:a', 'aac',
          '-shortest',   // Stop silence when video ends
        ]);
      }

      command.addAll([
        // FIX: FFmpeg 8.0 - Use fps_mode instead of deprecated vsync
        '-fps_mode', 'cfr',     // Constant frame rate
        
        // WEB OPTIMIZATION
        '-movflags', '+faststart',
        
        '-pix_fmt', 'yuv420p',     
        outputPath,
      ]);
      
      debugPrint('FFmpeg (Async): Starting execution...');
      
      FFmpegKit.executeWithArgumentsAsync(command, (session) async {
         final returnCode = await session.getReturnCode();
         final logs = await session.getAllLogsAsString();
         
         if (ReturnCode.isSuccess(returnCode)) {
             debugPrint('FFmpeg (Async): Success! Handoff to upload.');
             final outFile = File(outputPath);
             if (await outFile.exists()) {
                 onProcessed(outFile);
             } else {
                 onError('Output file not found after success');
             }
             // Cleanup overlay
             try { if (await overlayImage.exists()) await overlayImage.delete(); } catch (_) {}
         } else {
             // HARDWARE ENCODER FALLBACK
             debugPrint('FFmpeg (Async): Hardware encoder failed, retrying with libx264...');
             
             final List<String> fallbackCommand = List.from(command);
             final encoderIdx = fallbackCommand.indexOf('-c:v');
             if (encoderIdx != -1 && encoderIdx + 1 < fallbackCommand.length) {
               fallbackCommand[encoderIdx + 1] = 'libx264';
               fallbackCommand.insertAll(encoderIdx + 2, ['-preset', 'ultrafast', '-crf', '23']);
             }
             
             FFmpegKit.executeWithArgumentsAsync(fallbackCommand, (fallbackSession) async {
               final fallbackReturnCode = await fallbackSession.getReturnCode();
               
               if (ReturnCode.isSuccess(fallbackReturnCode)) {
                 debugPrint('FFmpeg (Async): Success (Software Fallback)!');
                 final outFile = File(outputPath);
                 onProcessed(outFile);
               } else {
                 final fallbackLogs = await fallbackSession.getAllLogsAsString();
                 debugPrint('FFmpeg (Async): CRITICAL - Software fallback also failed: $fallbackLogs');
                 onError('Video processing failed (HW and SW encoders failed)');
               }
               
               // Cleanup overlay
               try { if (await overlayImage.exists()) await overlayImage.delete(); } catch (_) {}
             });
         }
      });
    } catch (e) {
      debugPrint('Error starting async processing: $e');
      onError(e.toString());
    }
  }

  /// Public helper for Isolate-based PNG encoding.
  /// 
  /// This allows CameraScreenNew to reuse the same high-performance
  /// encoding path used for video overlay creation.
  /// 
  /// [rawBytes] - Raw RGBA pixel data from ui.Image.toByteData(format: rawRgba)
  /// [width] - Image width in pixels
  /// [height] - Image height in pixels
  static Future<Uint8List> encodeImageInIsolate(Uint8List rawBytes, int width, int height) async {
    return Isolate.run(() {
      final imgImage = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rawBytes.buffer,
        numChannels: 4,
        format: img.Format.uint8,
        order: img.ChannelOrder.rgba,
      );
      
      return img.encodePng(imgImage);
    });
  }
}

/// Provider for VideoProcessingService
final videoProcessingServiceProvider = Provider<VideoProcessingService>((ref) {
  return VideoProcessingService();
});
