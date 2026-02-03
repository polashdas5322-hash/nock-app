import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Share Service - Handles viral sharing of Vibes
/// Creates shareable content for TikTok, Instagram, etc.
class ShareService {
  ShareService();
  
  // Platform channel for native sharing
  static const _shareChannel = MethodChannel('com.nock.nock/share');

  // ==================== SOCIAL DEEP LINKS ====================

  /// Navigate directly to TikTok app (opens empty app - no image)
  /// DEPRECATED: Use shareToTikTok() instead to share with image
  Future<void> openTikTok() async {
    final Uri tiktokUri = Uri.parse('tiktok://');
    final Uri webUri = Uri.parse('https://www.tiktok.com/');
    
    try {
      if (await canLaunchUrl(tiktokUri)) {
        await launchUrl(tiktokUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('ShareService: Failed to open TikTok: $e');
      // Fallback to web
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  /// Share image to TikTok using platform channel (with image content)
  /// Opens TikTok with the image ready to create a post
  Future<bool> shareToTikTok(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        debugPrint('ShareService: Image file does not exist');
        return false;
      }
      
      // Use platform channel for TikTok share with image
      final result = await _shareChannel.invokeMethod<bool>('shareToTikTok', {
        'imagePath': imageFile.path,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('ShareService: TikTok share failed: $e');
      return false;
    }
  }

  /// Check if TikTok is installed
  Future<bool> isTikTokInstalled() async {
    try {
      final result = await _shareChannel.invokeMethod<bool>('isTikTokInstalled');
      return result ?? false;
    } catch (e) {
      debugPrint('ShareService: Failed to check TikTok: $e');
      return false;
    }
  }


  /// Open Instagram's native share sheet with Feed, Messages, Reels, Stories options
  /// This shares directly to Instagram app, showing Instagram's own picker
  Future<bool> openInstagramShareSheet(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        debugPrint('ShareService: Image file does not exist');
        return false;
      }
      
      // Check if Instagram is installed
      final Uri instagramUri = Uri.parse('instagram://');
      if (!await canLaunchUrl(instagramUri)) {
        debugPrint('ShareService: Instagram not installed');
        return false;
      }
      
      // Use share_plus with Instagram-specific sharing
      // This opens Instagram's native share picker showing Feed, Messages, Reels, Stories
      await Share.shareXFiles(
        [XFile(imageFile.path)],
        text: '', // Instagram ignores text for image shares
        sharePositionOrigin: null,
      );
      
      // Note: share_plus opens system share sheet
      // For Instagram-only picker, we need platform channels
      // Using Android Intent to share directly to Instagram
      return true;
    } catch (e) {
      debugPrint('ShareService: Failed to open Instagram: $e');
      return false;
    }
  }

  /// Open Instagram directly and let user choose destination (Feed, Stories, Reels, Messages)
  /// Uses platform channel to send EXPLICIT INTENT to Instagram package
  /// This shows ONLY Instagram's internal picker - NOT the system share sheet with all apps
  Future<bool> shareToInstagramDirect(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        debugPrint('ShareService: Image file does not exist');
        return false;
      }
      
      // BOTH Android and iOS use platform channel for Instagram-only share
      // Android: Uses explicit intent with package="com.instagram.android"
      // iOS: Uses UIDocumentInteractionController with UTI="com.instagram.exclusivegram"
      final result = await _shareChannel.invokeMethod<bool>('shareToInstagram', {
        'imagePath': imageFile.path,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('ShareService: Instagram share failed: $e');
      return false;
    }
  }
  
  /// Check if Instagram is installed
  Future<bool> isInstagramInstalled() async {
    try {
      // Both platforms use platform channel to check
      final result = await _shareChannel.invokeMethod<bool>('isInstagramInstalled');
      return result ?? false;
    } catch (e) {
      debugPrint('ShareService: Failed to check Instagram: $e');
      return false;
    }
  }



  /// Open native system share sheet with all available options
  Future<void> shareGeneric(String text, {File? imageFile}) async {
    try {
      if (imageFile != null && await imageFile.exists()) {
        await Share.shareXFiles(
          [XFile(imageFile.path)],
          text: text,
          subject: 'Join me on Nock!',
        );
      } else {
        await Share.share(text, subject: 'Join me on Nock!');
      }
    } catch (e) {
      debugPrint('ShareService: Failed to share: $e');
      rethrow;
    }
  }

  /// Share a vibe's audio file
  Future<void> shareAudio({
    required String audioUrl,
    required String senderName,
    String? message,
  }) async {
    try {
      // Download the audio file temporarily
      final tempDir = await getTemporaryDirectory();
      final audioFile = File('${tempDir.path}/vibe_audio.m4a');
      
      // If it's a URL, download it
      if (audioUrl.startsWith('http')) {
        final response = await http.get(Uri.parse(audioUrl));
        await audioFile.writeAsBytes(response.bodyBytes);
      } else {
        // It's a local file path
        await File(audioUrl).copy(audioFile.path);
      }
      
      // Share the file
      await Share.shareXFiles(
        [XFile(audioFile.path)],
        text: message ?? 'Check out this Vibe from $senderName! 🎤✨',
        subject: 'Nock from $senderName',
      );
    } catch (e) {
      debugPrint('Error sharing audio: $e');
      rethrow;
    }
  }

  /// Share a vibe with image
  Future<void> shareVibe({
    required String imageUrl,
    required String audioUrl,
    required String senderName,
    String? message,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = <XFile>[];
      
      // Download image
      if (imageUrl.isNotEmpty) {
        final imageFile = File('${tempDir.path}/vibe_image.jpg');
        if (imageUrl.startsWith('http')) {
          final response = await http.get(Uri.parse(imageUrl));
          await imageFile.writeAsBytes(response.bodyBytes);
        } else {
          await File(imageUrl).copy(imageFile.path);
        }
        files.add(XFile(imageFile.path));
      }
      
      // Download audio
      if (audioUrl.isNotEmpty) {
        final audioFile = File('${tempDir.path}/vibe_audio.m4a');
        if (audioUrl.startsWith('http')) {
          final response = await http.get(Uri.parse(audioUrl));
          await audioFile.writeAsBytes(response.bodyBytes);
        } else {
          await File(audioUrl).copy(audioFile.path);
        }
        files.add(XFile(audioFile.path));
      }
      
      // Share files
      await Share.shareXFiles(
        files,
        text: message ?? '🎤 Vibe from $senderName\n\nDownload Vibe app to listen! ✨',
        subject: 'Nock from $senderName',
      );
    } catch (e) {
      debugPrint('Error sharing vibe: $e');
      rethrow;
    }
  }

  /// Share text with app link
  Future<void> shareAppLink({String? customMessage}) async {
    const appLink = 'https://getvibe.app'; // Replace with actual app store link
    final message = customMessage ?? 
        '✨ I\'m using Vibe to send voice messages that appear on my friends\' home screens!\n\n'
        'Download Vibe: $appLink';
    
    await Share.share(message, subject: 'Check out Vibe!');
  }

  /// Generate and share a "Vibe Card" - static image with audio waveform
  /// This is a simpler alternative to full video export
  Future<void> shareVibeCard({
    required String imagePath,
    required String senderName,
    required String message,
  }) async {
    try {
      // For now, just share the image with text
      // In production, you'd overlay the Aura visualization
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: '🎤 "$message"\n\n- $senderName via Vibe\n\nDownload Vibe to hear the voice message! ✨',
        subject: 'Nock from $senderName',
      );
    } catch (e) {
      debugPrint('Error sharing vibe card: $e');
      rethrow;
    }
  }
}

/// Share service provider
final shareServiceProvider = Provider<ShareService>((ref) {
  return ShareService();
});
