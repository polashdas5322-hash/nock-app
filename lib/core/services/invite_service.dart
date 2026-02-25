import 'package:nock/core/theme/app_icons.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:appinio_social_share/appinio_social_share.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Invite Service - The "Visual Invite" Engine
///
/// Based on competitor analysis (Locket, NoteIt, Widgetable):
/// - Visual invites (images/videos) outperform text links
/// - Story-ready 9:16 content gets higher engagement
/// - Deep links should be attached as stickers
///
/// Strategy:
/// 1. Generate a beautiful "Invite Card" with user's Aura
/// 2. Share to Instagram Stories, Snapchat, WhatsApp, SMS
/// 3. Include personalized deep link for tracking
class InviteService {
  final AppinioSocialShare _socialShare = AppinioSocialShare();

  // Your app's store URLs (replace with actual)
  static const String appStoreUrl =
      'https://apps.apple.com/app/nock/id0000000000';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.nock.nock';

  // --------------------------
  // INVITE LINK STRATEGY
  // --------------------------
  //
  // CURRENT (MVP): Using custom scheme nock://
  //   + Works if app is installed
  //   - NOT clickable on Instagram, TikTok, WhatsApp (shows as plain text)
  //   - Shows error if app not installed
  //
  // FOR PRODUCTION: Switch to HTTPS with Universal Links
  //   Option A: Use your own domain (e.g., https://getvibe.app/invite/)
  //     - Requires AASA file on server
  //     - Requires Associated Domains entitlement
  //
  //   Option B: Use Firebase Dynamic Links (deprecated) or Branch.io
  //     - Handles app-not-installed gracefully (redirects to store)
  //     - Links are clickable on all social platforms
  //     - Provides analytics
  //
  // TODO: For production, replace nock:// with https:// and set up
  // Universal Links (iOS) + App Links (Android)
  // DEFERRED LINK STRATEGY: Use a Universal Link (HTTPS) as the base.
  // This ensures links are clickable on Instagram/WhatsApp and provides
  // a bridge for users who don't have the app installed yet.
  static const String webInviteBaseUrl = 'https://getnock.app/i/';

  /// Generate a personalized invite link
  /// Format: nock://invite/USERID (matches document ID in Firestore)
  /// Generate a personalized invite link
  /// Format: https://getvibe.app/i/USERID
  /// ALSO: Copies to clipboard to support the "Clipboard Bridge" for new users!
  Future<String> generateInviteLink(String userId) async {
    final link = '$webInviteBaseUrl$userId';
    await copyInviteLink(link); // Force copy to clipboard for deferred linking
    return link;
  }

  /// Get the appropriate store URL for the current platform
  String getStoreUrl() {
    return Platform.isIOS ? appStoreUrl : playStoreUrl;
  }

  /// Generate the default invite message with CLICKABLE store link
  /// Note: nock:// links are NOT clickable in WhatsApp/SMS
  /// So we use the store URL which IS clickable
  String generateInviteMessage({
    required String senderName,
    String? customMessage,
    String? userId,
  }) {
    if (customMessage != null && customMessage.isNotEmpty) {
      return customMessage;
    }

    // Use store URL (clickable) instead of custom scheme (not clickable)
    final storeLink = getStoreUrl();

    return '''🎙️ $senderName invited you to Nock!

Nock lets you send voice messages right to your friends' home screen 💫

Download now: $storeLink''';
  }

  /// Share invite via Instagram Stories (most viral!)
  /// API: shareToInstagramStory(appId, {stickerImage, backgroundImage, ...})
  /// Returns true only if Instagram actually opened
  Future<bool> shareToInstagramStory({
    required String imagePath,
    String? senderName,
    String? facebookAppId,
  }) async {
    try {
      final appId = facebookAppId ?? 'YOUR_FB_APP_ID';
      String? result;

      if (Platform.isAndroid) {
        result = await _socialShare.android.shareToInstagramStory(
          appId,
          stickerImage: imagePath,
          backgroundTopColor: '#0A0A0A',
          backgroundBottomColor: '#1A1A2E',
          attributionURL: getStoreUrl(),
        );
      } else if (Platform.isIOS) {
        result = await _socialShare.iOS.shareToInstagramStory(
          appId,
          stickerImage: imagePath,
          backgroundTopColor: '#0A0A0A',
          backgroundBottomColor: '#1A1A2E',
          attributionURL: getStoreUrl(),
        );
      }

      // appinio_social_share returns non-empty string on success
      final success = result != null && result.isNotEmpty;
      debugPrint(
        'InviteService: Instagram Story result: $result, success: $success',
      );
      return success;
    } catch (e) {
      debugPrint('InviteService: Instagram Story share failed: $e');
      return false;
    }
  }

  /// Share invite via Instagram DM / Feed
  /// Android: shareToInstagramFeed(message, filePath)
  /// iOS: shareToInstagramFeed(imagePath) - only path
  /// Returns true only if Instagram opened, false triggers system share fallback
  Future<bool> shareToInstagramDm({
    required String imagePath,
    required String message,
  }) async {
    try {
      String? result;
      if (Platform.isAndroid) {
        result = await _socialShare.android.shareToInstagramFeed(
          message,
          imagePath,
        );
      } else if (Platform.isIOS) {
        result = await _socialShare.iOS.shareToInstagramFeed(imagePath);
      }

      final success = result != null && result.isNotEmpty;
      debugPrint(
        'InviteService: Instagram Feed result: $result, success: $success',
      );

      if (!success) {
        // Instagram not installed - use system share
        debugPrint(
          'InviteService: Instagram not available, using system share',
        );
        return await shareToSystem(imagePath: imagePath, message: message);
      }
      return true;
    } catch (e) {
      debugPrint('InviteService: Instagram share failed: $e');
      // Fallback to system share - tell caller it was a fallback
      return await shareToSystem(imagePath: imagePath, message: message);
    }
  }

  /// Share invite via Snapchat (uses system share - no direct API)
  Future<bool> shareToSnapchat({
    required String imagePath,
    String? message,
  }) async {
    try {
      await Share.shareXFiles([
        XFile(imagePath),
      ], text: message ?? 'Join me on Nock! 🎙️');
      return true;
    } catch (e) {
      debugPrint('InviteService: Snapchat share failed: $e');
      return false;
    }
  }

  /// Share invite via WhatsApp
  /// Android: shareToWhatsapp(message, filePath) - supports file
  /// iOS: shareImageToWhatsApp(imagePath) - image only
  /// Returns true only if WhatsApp opened
  Future<bool> shareToWhatsApp({
    required String imagePath,
    required String message,
  }) async {
    try {
      String? result;
      if (Platform.isAndroid) {
        // Android supports message + file
        result = await _socialShare.android.shareToWhatsapp(message, imagePath);
      } else {
        // iOS: Use shareImageToWhatsApp for image sharing
        result = await _socialShare.iOS.shareImageToWhatsApp(imagePath);
      }

      final success = result.isNotEmpty;
      debugPrint('InviteService: WhatsApp result: $result, success: $success');

      if (!success) {
        debugPrint('InviteService: WhatsApp not available, using system share');
        return await shareToSystem(imagePath: imagePath, message: message);
      }
      return true;
    } catch (e) {
      debugPrint('InviteService: WhatsApp share failed: $e');
      // Fallback to system share
      return await shareToSystem(imagePath: imagePath, message: message);
    }
  }

  /// Share invite via SMS/Messages
  /// If recipientPhone is provided, opens SMS directly to that contact
  Future<bool> shareToMessages({
    required String message,
    String? imagePath,
    String? recipientPhone,
  }) async {
    try {
      // If we have a specific recipient, open SMS directly
      if (recipientPhone != null && recipientPhone.isNotEmpty) {
        final encodedMessage = Uri.encodeComponent(message);
        final cleanPhone = recipientPhone.replaceAll(RegExp(r'[^\d+]'), '');

        // Use sms: URI scheme - works on both iOS and Android
        // Format: sms:+1234567890?body=Hello%20World
        final smsUri = Uri.parse('sms:$cleanPhone?body=$encodedMessage');

        // Use platform's default SMS app
        if (Platform.isIOS) {
          // iOS requires & instead of ? for additional params
          final iosSmsUri = Uri.parse('sms:$cleanPhone&body=$encodedMessage');
          await Share.share(
            message,
          ); // Fallback - iOS doesn't always support body in sms:
          debugPrint('InviteService: SMS to $cleanPhone opened via share');
        } else {
          // Android handles sms: URI well
          await Share.share(message);
        }
        return true;
      }

      // Generic share (no specific recipient)
      if (imagePath != null) {
        await Share.shareXFiles([XFile(imagePath)], text: message);
      } else {
        await Share.share(message);
      }
      return true;
    } catch (e) {
      debugPrint('InviteService: Messages share failed: $e');
      return false;
    }
  }

  /// Share invite via Messenger
  /// IMPORTANT: shareToMessenger only takes (String message) - no file support!
  /// We use system share for file + message - opens native share sheet
  Future<bool> shareToMessenger({
    required String imagePath,
    required String message,
  }) async {
    try {
      // Messenger API only supports text, use system share for image
      // This opens the native share sheet where user can select Messenger
      return await shareToSystem(imagePath: imagePath, message: message);
    } catch (e) {
      debugPrint('InviteService: Messenger share failed: $e');
      return false;
    }
  }

  /// Share invite via Telegram
  /// Android: shareToTelegram(message, filePath) - supports file
  /// iOS: Uses system share (Telegram API only supports text on iOS)
  Future<bool> shareToTelegram({
    required String imagePath,
    required String message,
  }) async {
    try {
      if (Platform.isAndroid) {
        // Android supports message + file
        final result = await _socialShare.android.shareToTelegram(
          message,
          imagePath,
        );
        final success = result.isNotEmpty;
        debugPrint(
          'InviteService: Telegram result: $result, success: $success',
        );

        if (!success) {
          debugPrint(
            'InviteService: Telegram not available, using system share',
          );
          return await shareToSystem(imagePath: imagePath, message: message);
        }
        return true;
      } else {
        // iOS only supports text - use system share for files
        return await shareToSystem(imagePath: imagePath, message: message);
      }
    } catch (e) {
      debugPrint('InviteService: Telegram share failed: $e');
      return await shareToSystem(imagePath: imagePath, message: message);
    }
  }

  /// System share sheet (ultimate fallback - uses share_plus)
  Future<bool> shareToSystem({
    String? imagePath,
    required String message,
  }) async {
    try {
      if (imagePath != null) {
        await Share.shareXFiles(
          [XFile(imagePath)],
          text: message,
          subject: 'Join me on Nock!',
        );
      } else {
        await Share.share(message, subject: 'Join me on Nock!');
      }
      return true;
    } catch (e) {
      debugPrint('InviteService: System share failed: $e');
      return false;
    }
  }

  /// Copy invite link to clipboard
  /// This is CRITICAL for the "Clipboard Bridge" deferred deep link strategy.
  /// When a new user installs the app, we check the clipboard for this link.
  Future<void> copyInviteLink(String link) async {
    try {
      await Clipboard.setData(ClipboardData(text: link));
      debugPrint('InviteService: Link copied to clipboard for bridge: $link');
    } catch (e) {
      debugPrint('InviteService: Failed to copy link: $e');
    }
  }
}

/// Visual Invite Card Generator
///
/// Creates beautiful 9:16 story-ready images for sharing.
/// Based on competitor analysis: Visual invites >> Text links
class InviteCardGenerator {
  /// Generate an invite card widget (to be captured as image)
  static Widget buildInviteCard({
    required String senderName,
    required String username,
    String? avatarUrl,
    Color primaryColor = AppColors.bioLime,
    Color secondaryColor = AppColors.digitalLavender,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // RESPONSIVE FIX: Use scale factor instead of hardcoded 1080x1920
        // Baseline width is 360 (standard mobile logical width)
        final scale = constraints.maxWidth / 360;

        return AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.background,
                  AppColors.surfaceLight,
                  AppColors.backgroundAlt,
                ],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background effects
                _buildBackgroundEffects(primaryColor, secondaryColor, scale),

                // Main content
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),

                    // "Aura" glow effect + Avatar
                    Container(
                      width: 100 * scale,
                      height: 100 * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.3),
                            blurRadius: 30 * scale,
                            spreadRadius: 15 * scale,
                          ),
                          BoxShadow(
                            color: secondaryColor.withOpacity(0.2),
                            blurRadius: 50 * scale,
                            spreadRadius: 10 * scale,
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              primaryColor.withOpacity(0.2),
                              secondaryColor.withOpacity(0.2),
                            ],
                          ),
                          border: Border.all(
                            color: primaryColor.withOpacity(0.5),
                            width: 1 * scale,
                          ),
                        ),
                        child: ClipOval(
                          child: avatarUrl != null && avatarUrl.isNotEmpty
                              ? Image.network(
                                  avatarUrl,
                                  fit: BoxFit.cover,
                                  width: 98 * scale,
                                  height: 98 * scale,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Center(
                                      child: Text(
                                        senderName.isNotEmpty
                                            ? senderName[0].toUpperCase()
                                            : 'V',
                                        style: AppTypography.displayMedium
                                            .copyWith(
                                              fontSize: 40 * scale,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              shadows: [
                                                Shadow(
                                                  color: primaryColor,
                                                  blurRadius: 10 * scale,
                                                ),
                                              ],
                                            ),
                                      ),
                                    );
                                  },
                                )
                              : Center(
                                  child: Text(
                                    senderName.isNotEmpty
                                        ? senderName[0].toUpperCase()
                                        : 'V',
                                    style: AppTypography.displayMedium.copyWith(
                                      fontSize: 40 * scale,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: primaryColor,
                                          blurRadius: 10 * scale,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),

                    SizedBox(height: 12 * scale),

                    // Sender name
                    Text(
                      senderName,
                      style: AppTypography.bodyLarge.copyWith(
                        fontSize: 16 * scale,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3 * scale,
                      ),
                    ),

                    SizedBox(height: 4 * scale),

                    // Invite text
                    Text(
                      'wants to send you Vibes',
                      style: AppTypography.labelSmall.copyWith(
                        fontSize: 9 * scale,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),

                    const Spacer(flex: 1),

                    // Call to action
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14 * scale,
                        vertical: 6 * scale,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primaryColor, secondaryColor],
                        ),
                        borderRadius: BorderRadius.circular(16 * scale),
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.5),
                            blurRadius: 10 * scale,
                            spreadRadius: 2 * scale,
                          ),
                        ],
                      ),
                      child: Text(
                        'Download Vibe',
                        style: AppTypography.labelSmall.copyWith(
                          fontSize: 11 * scale,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    SizedBox(height: 8 * scale),

                    // Username/link indicator
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8 * scale,
                        vertical: 4 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6 * scale),
                      ),
                      child: Text(
                        'nock://invite/${username.length > 12 ? username.substring(0, 12) : username}...',
                        style: AppTypography.labelSmall.copyWith(
                          fontSize: 7 * scale,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),

                    const Spacer(flex: 2),

                    // Bottom branding
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '🎤',
                          style: AppTypography.bodyLarge.copyWith(
                            fontSize: 11 * scale,
                          ),
                        ),
                        SizedBox(width: 4 * scale),
                        Text(
                          'NOCK',
                          style: AppTypography.labelSmall.copyWith(
                            fontSize: 8 * scale,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                            letterSpacing: 2 * scale,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 20 * scale),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _buildBackgroundEffects(
    Color primary,
    Color secondary,
    double scale,
  ) {
    return Stack(
      children: [
        // Top-left glow
        Positioned(
          top: -30 * scale,
          left: -30 * scale,
          child: Container(
            width: 130 * scale,
            height: 130 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [primary.withOpacity(0.3), primary.withOpacity(0.0)],
              ),
            ),
          ),
        ),
        // Bottom-right glow
        Positioned(
          bottom: -30 * scale,
          right: -30 * scale,
          child: Container(
            width: 170 * scale,
            height: 170 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  secondary.withOpacity(0.2),
                  secondary.withOpacity(0.0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Capture the invite card as an image using the widget tree
  /// Falls back to offscreen rendering if widget is not painted
  static Future<File?> captureInviteCard({
    required GlobalKey cardKey,
    double pixelRatio = 2.0,
  }) async {
    try {
      // Wait for multiple frames to ensure painting is complete
      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        await _waitForNextFrame();
      }

      final context = cardKey.currentContext;
      if (context == null) {
        debugPrint('InviteCardGenerator: Card context is null');
        return null;
      }

      RenderRepaintBoundary? boundary;
      try {
        boundary = context.findRenderObject() as RenderRepaintBoundary?;
      } catch (e) {
        debugPrint(
          'InviteCardGenerator: Cannot find RenderRepaintBoundary: $e',
        );
        return null;
      }

      if (boundary == null) {
        debugPrint('InviteCardGenerator: Boundary is null');
        return null;
      }

      // If still needs paint after waiting, try forcing layout
      if (boundary.debugNeedsPaint) {
        debugPrint('InviteCardGenerator: Forcing layout...');

        // Force a layout pass
        (context as Element).markNeedsBuild();
        await _waitForNextFrame();
        await Future.delayed(const Duration(milliseconds: 300));
        await _waitForNextFrame();
      }

      // Final attempt - capture anyway (may work in release mode)
      // debugNeedsPaint only fires in debug mode
      try {
        ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          debugPrint('InviteCardGenerator: byteData is null');
          return null;
        }
        final pngBytes = byteData.buffer.asUint8List();

        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${tempDir.path}/vibe_invite_$timestamp.png');
        await file.writeAsBytes(pngBytes);

        debugPrint('InviteCardGenerator: Card captured successfully');
        return file;
      } catch (e) {
        debugPrint('InviteCardGenerator: Capture failed: $e');
        // This is expected in debug mode if widget is still painting
        // In release mode, this typically works
        return null;
      }
    } catch (e) {
      debugPrint('InviteCardGenerator: Failed to capture card: $e');
      return null;
    }
  }

  /// Helper to wait for next frame
  static Future<void> _waitForNextFrame() async {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    return completer.future;
  }

  /// Render invite card offscreen using Canvas (doesn't require widget tree)
  /// This is a fallback when widget-based capture fails
  static Future<File?> renderInviteCardOffscreen({
    required String senderName,
    required String username,
    String? avatarUrl,
    Color primaryColor = AppColors.bioLime,
    Color secondaryColor = AppColors.digitalLavender,
    double pixelRatio = 2.0,
    double width = 1080,
    double height = 1920,
  }) async {
    try {
      debugPrint('InviteCardGenerator: Using canvas-based rendering...');

      final scale = width / 1080; // Baseline width for scaling

      // Create a picture recorder and canvas
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

      // Draw background gradient
      final backgroundPaint = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(width, height),
          [
            AppColors.background,
            AppColors.surfaceLight,
            AppColors.backgroundAlt,
          ],
          [0.0, 0.5, 1.0],
        );
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height), backgroundPaint);

      // Draw glow effect circles
      final glowPaint1 = Paint()
        ..color = primaryColor.withOpacity(0.15)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 100 * scale);
      canvas.drawCircle(
        Offset(width * 0.2, height * 0.3),
        250 * scale,
        glowPaint1,
      );

      final glowPaint2 = Paint()
        ..color = secondaryColor.withOpacity(0.1)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 80 * scale);
      canvas.drawCircle(
        Offset(width * 0.8, height * 0.7),
        200 * scale,
        glowPaint2,
      );

      // Draw center circle (avatar placeholder)
      final circlePaint = Paint()
        ..shader = ui.Gradient.radial(
          Offset(width / 2, height * 0.4),
          150 * scale,
          [primaryColor.withOpacity(0.3), primaryColor.withOpacity(0.05)],
        );
      canvas.drawCircle(
        Offset(width / 2, height * 0.4),
        150 * scale,
        circlePaint,
      );

      // Draw first letter of name in circle
      final letterStyle = ui.TextStyle(
        color: Colors.white,
        fontSize: 120 * scale,
        fontWeight: FontWeight.bold,
      );
      final letterBuilder =
          ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
            ..pushStyle(letterStyle)
            ..addText(
              senderName.isNotEmpty ? senderName[0].toUpperCase() : 'V',
            );
      final letterParagraph = letterBuilder.build()
        ..layout(ui.ParagraphConstraints(width: 200 * scale));
      canvas.drawParagraph(
        letterParagraph,
        Offset(width / 2 - (100 * scale), height * 0.4 - (60 * scale)),
      );

      // Draw sender name
      final nameStyle = ui.TextStyle(
        color: Colors.white,
        fontSize: 64 * scale,
        fontWeight: FontWeight.bold,
      );
      final nameBuilder =
          ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
            ..pushStyle(nameStyle)
            ..addText(senderName);
      final nameParagraph = nameBuilder.build()
        ..layout(ui.ParagraphConstraints(width: width - (100 * scale)));
      canvas.drawParagraph(nameParagraph, Offset(50 * scale, height * 0.55));

      // Draw "invited you to Vibe" text
      final inviteStyle = ui.TextStyle(
        color: Colors.white.withOpacity(0.8),
        fontSize: 40 * scale,
      );
      final inviteBuilder =
          ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
            ..pushStyle(inviteStyle)
            ..addText('invited you to Nock');
      final inviteParagraph = inviteBuilder.build()
        ..layout(ui.ParagraphConstraints(width: width - (100 * scale)));
      canvas.drawParagraph(inviteParagraph, Offset(50 * scale, height * 0.62));

      // Draw "Join my squad!" text
      final joinStyle = ui.TextStyle(
        color: primaryColor,
        fontSize: 48 * scale,
        fontWeight: FontWeight.w600,
      );
      final joinBuilder =
          ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
            ..pushStyle(joinStyle)
            ..addText('Join my squad!');
      final joinParagraph = joinBuilder.build()
        ..layout(ui.ParagraphConstraints(width: width - (100 * scale)));
      canvas.drawParagraph(joinParagraph, Offset(50 * scale, height * 0.72));

      // Draw VIBE logo text at bottom
      final logoStyle = ui.TextStyle(
        color: Colors.white.withOpacity(0.5),
        fontSize: 36 * scale,
        fontWeight: FontWeight.bold,
        // Use Mono for Logo as per Typography class
      );
      final logoBuilder =
          ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
            ..pushStyle(logoStyle)
            ..addText('NOCK');
      final logoParagraph = logoBuilder.build()
        ..layout(ui.ParagraphConstraints(width: width - (100 * scale)));
      canvas.drawParagraph(logoParagraph, Offset(50 * scale, height * 0.92));

      // Convert to image
      final picture = recorder.endRecording();
      final image = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        debugPrint('InviteCardGenerator: Canvas byteData is null');
        return null;
      }

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/vibe_invite_$timestamp.png');
      await file.writeAsBytes(pngBytes);

      debugPrint('InviteCardGenerator: Canvas render successful');
      return file;
    } catch (e) {
      debugPrint('InviteCardGenerator: Canvas render failed: $e');
      return null;
    }
  }
}

/// Provider for InviteService
final inviteServiceProvider = Provider<InviteService>((ref) {
  return InviteService();
});

/// Enum for invite share targets
enum InviteTarget {
  instagramStory,
  instagramDm,
  snapchat,
  whatsapp,
  messenger,
  telegram,
  messages,
  other,
}

extension InviteTargetExtension on InviteTarget {
  String get displayName {
    switch (this) {
      case InviteTarget.instagramStory:
        return 'Instagram Story';
      case InviteTarget.instagramDm:
        return 'Instagram DM';
      case InviteTarget.snapchat:
        return 'Snapchat';
      case InviteTarget.whatsapp:
        return 'WhatsApp';
      case InviteTarget.messenger:
        return 'Messenger';
      case InviteTarget.telegram:
        return 'Telegram';
      case InviteTarget.messages:
        return 'Messages';
      case InviteTarget.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case InviteTarget.instagramStory:
        return AppIcons.camera;
      case InviteTarget.instagramDm:
        return AppIcons.send;
      case InviteTarget.snapchat:
        return AppIcons.snapchat;
      case InviteTarget.whatsapp:
        return AppIcons.chat;
      case InviteTarget.messenger:
        return AppIcons.messenger;
      case InviteTarget.telegram:
        return AppIcons.telegram;
      case InviteTarget.messages:
        return AppIcons.sms;
      case InviteTarget.other:
        return AppIcons.share;
    }
  }

  Color get color {
    switch (this) {
      case InviteTarget.instagramStory:
      case InviteTarget.instagramDm:
        return const Color(0xFFE1306C);
      case InviteTarget.snapchat:
        return const Color(0xFFFFFC00);
      case InviteTarget.whatsapp:
        return const Color(0xFF25D366);
      case InviteTarget.messenger:
        return const Color(0xFF0084FF);
      case InviteTarget.telegram:
        return const Color(0xFF0088CC);
      case InviteTarget.messages:
        return const Color(0xFF34C759);
      case InviteTarget.other:
        return AppColors.bioLime;
    }
  }
}
