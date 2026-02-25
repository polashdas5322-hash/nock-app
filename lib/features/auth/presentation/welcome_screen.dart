import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:nock/core/theme/app_icons.dart';
import 'package:nock/shared/widgets/app_icon.dart';

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/services/deep_link_service.dart';
import 'package:nock/shared/widgets/glass_container.dart';
// import 'package:video_player/video_player.dart'; // Ensure this package is available

/// THE HERO WELCOME (Step 1 of 4)
/// 
/// "The Front Door."
/// 
/// Merges Auth + Intro.
/// - High-quality background (Video/Animation)
/// - Strong Value Prop ("Real friends, real life.")
/// - Simple Auth buttons (Google/Apple)
/// 
/// 2025 REFACTOR: Simplified significantly to remove "Explainers".
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _isLoading = false;
  String? _statusText; // UI Feedback for clipboard operations
  // TODO: Add VideoPlayerController if we have a legitimate video asset. 
  // For now, we use a high-quality gradient animation.

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _statusText = "Connecting to inviter..."; // 1. Set Context
    });
    
    // 2. Artificial Delay (Crucial for psychology)
    // This gives the user time to read the text before the system alert pops up.
    await Future.delayed(const Duration(milliseconds: 1500));

    // 3. UX FIX: Check clipboard for deferred invite link
    // Now the user thinks: "Ah, it's pasting the invite code!"
    try {
      await ref.read(deepLinkServiceProvider).checkDeferredInvite()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ignore timeouts/errors - proceed to login
    }

    try {
      final user = await ref.read(authServiceProvider).signInWithGoogle();
      if (user != null && mounted) {
        // Navigation is handled by Router redirect logic
      }
    } catch (e) {
      debugPrint('Auth Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $e')), // Friendly error needed
        );
      }
    } finally {
      if (mounted) setState(() {
        _isLoading = false;
        _statusText = null;
      });
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() {
      _isLoading = true;
      _statusText = "Connecting to inviter...";
    });

    // Artificial Delay
    await Future.delayed(const Duration(milliseconds: 1500));

    // UX FIX: Check clipboard for deferred invite link
    try {
      await ref.read(deepLinkServiceProvider).checkDeferredInvite()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Ignore timeouts/errors
    }

    try {
      final user = await ref.read(authServiceProvider).signInWithApple();
      if (user != null && mounted) {
        // Navigation handled by Router
      }
    } catch (e) {
       debugPrint('Auth Error: $e');
    } finally {
      if (mounted) setState(() {
        _isLoading = false;
        _statusText = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark entry
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. DYNAMIC BACKGROUND
          // Placeholder for high-res video: "Life happening"
          // Falling back to an animated gradient mesh
          // _buildVideoBackground(), OR
          _buildAnimatedMeshBackground(),

          // 2. DARKENING OVERLAY (Gradient from bottom)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.0), // Clear top
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.8), // Dark bottom for buttons
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),

          // 3. CONTENT
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   const Spacer(),
                   
                   // Hero Text
                   Text(
                     'Real friends.\nReal life.',
                     style: AppTypography.displayLarge.copyWith(
                       color: Colors.white,
                       height: 1.1,
                       shadows: [
                         Shadow(
                           color: Colors.black.withOpacity(0.5),
                           offset: const Offset(0, 2),
                           blurRadius: 10,
                         ),
                       ],
                     ),
                   ),
                   
                   const SizedBox(height: 16),
                   
                   Text(
                     'No filters. No feed. Just your squad.',
                     style: AppTypography.bodyLarge.copyWith(
                       color: Colors.white.withOpacity(0.9),
                       fontSize: 18,
                     ),
                   ),
                   
                   const SizedBox(height: 48),

                   // AUTH BUTTONS
                   if (_isLoading)
                     Center(
                       child: Column(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                           const CircularProgressIndicator(color: Colors.white),
                           if (_statusText != null) ...[
                             const SizedBox(height: 16),
                             Text(
                               _statusText!,
                               style: AppTypography.bodyMedium.copyWith(
                                 color: Colors.white.withOpacity(0.8),
                                 fontSize: 14,
                                 fontWeight: FontWeight.w500,
                               ),
                             ),
                           ],
                         ],
                       ),
                     )
                   else ...[
                     _buildAuthButton(
                       label: 'Continue with Apple',
                       icon: AppIcons.apple,
                       backgroundColor: Colors.white,
                       textColor: Colors.black,
                       onPressed: _handleAppleSignIn,
                     ),
                     const SizedBox(height: 16),
                     _buildAuthButton(
                       label: 'Continue with Google',
                       icon: AppIcons.google, 
                       backgroundColor: Colors.white.withOpacity(0.15),
                       textColor: Colors.white,
                       onPressed: _handleGoogleSignIn,
                       isGlass: true,
                     ),
                   ],
                   
                   const SizedBox(height: 24),
                   
                   // Terms
                   Center(
                     child: Text(
                       'By continuing, you agree to our Terms & Privacy Policy.',
                       textAlign: TextAlign.center,
                       style: AppTypography.caption.copyWith(
                         color: Colors.white.withOpacity(0.5),
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

  Widget _buildAnimatedMeshBackground() {
    // A simplified placeholder for a "Mesmerizing" background
    // In production, this would be a looping video or Rive animation.
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
             Color(0xFF6B2CF5), // Purple
             Color(0xFF2C5CF5), // Blue
             Color(0xFF000000), // Black
          ],
        ),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
        child: Container(color: Colors.transparent),
      ),
    );
  }

  Widget _buildAuthButton({
    required String label, 
    required PhosphorIconData icon, 
    required Color backgroundColor, 
    required Color textColor, 
    required VoidCallback onPressed,
    bool isGlass = false,
  }) {
    // FIX: Use AppTypography.buttonText to ensure 'Inter' font is used
    final buttonStyle = AppTypography.buttonText.copyWith(
      color: textColor,
      // Ensure specific overrides for this screen if needed
      fontWeight: FontWeight.w600, 
    );

    final buttonChild = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppIcon(icon, color: textColor, size: 28),
        const SizedBox(width: 12),
        Text(
          label,
          style: buttonStyle, 
        ),
      ],
    );

    if (isGlass) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: GlassContainer(
           borderRadius: 16,
           backgroundColor: backgroundColor,
           onTap: onPressed,
           child: Center(child: buttonChild),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: onPressed,
        child: buttonChild,
      ),
    );
  }
}

