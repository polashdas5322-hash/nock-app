import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/constants/app_routes.dart';

/// Welcome Screen with Multi-Method Authentication
/// 
/// Supports authentication methods:
/// 1. Apple Sign-In (iOS) / Google Sign-In - Fastest, 1-tap
/// 2. Google Sign-In (Android/iOS) - Most common
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  
  // Progressive Disclosure: Show secondary auth options on Android
  bool _showMoreOptions = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.signInWithGoogle();
      
      if (result != null && mounted) {
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      if (mounted) {
        setState(() => _errorMessage = 'Google sign-in failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.signInWithApple();
      
      if (result != null && mounted) {
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Apple sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.vibeBackground,
      body: SafeArea(
        child: Stack(
          children: [
            // Animated background gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.5,
                    colors: [
                      AppColors.vibePrimary.withOpacity(0.15),
                      AppColors.vibeBackground,
                    ],
                  ),
                ),
              ),
            ),
            
            // Main content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  
                  // Logo and title (instant - no animation)
                  _buildHeader(),
                  
                  const Spacer(flex: 1),
                  
                  // Auth buttons (instant - no animation)
                  _buildAuthButtons(),
                  
                  const SizedBox(height: 24),
                  
                  // Error message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  const Spacer(flex: 1),
                  
                  // Terms and privacy
                  _buildFooter(),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
            
            // Loading overlay
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.vibePrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // App icon/logo
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.vibePrimary,
                AppColors.vibeSecondary,
              ],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.vibePrimary.withOpacity(0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(
            Icons.waves_rounded,
            size: 64,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 32),
        
        // App name (KEEP)
        const Text(
          'Nock',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
        // Tagline removed (KILL - visual noise per UX protocol)
      ],
    );
  }

  Widget _buildAuthButtons() {
    return Column(
      children: [
        // Apple Sign-In (iOS only, shown first on iOS - KEEP)
        if (Platform.isIOS) ...[
          _buildAuthButton(
            label: 'Continue with Apple',
            icon: Icons.apple,
            backgroundColor: Colors.white,
            textColor: Colors.black,
            onTap: _signInWithApple,
          ),
          const SizedBox(height: 12),
        ],
        
        // Google Sign-In (Primary on Android - KEEP)
        _buildAuthButton(
          label: 'Continue with Google',
          icon: null,
          customIcon: _buildGoogleIcon(),
          backgroundColor: Colors.white,
          textColor: Colors.black87,
          onTap: _signInWithGoogle,
        ),
        
        // Progressive Disclosure: "More options" on Android (HIDE secondary auth)
        if (Platform.isAndroid) ...[
          const SizedBox(height: 16),
          if (_showMoreOptions) ...[
            // Revealed: Apple button
            _buildAuthButton(
              label: 'Continue with Apple',
              icon: Icons.apple,
              backgroundColor: Colors.white,
              textColor: Colors.black,
              onTap: _signInWithApple,
            ),
          ] else ...[
            // "More options" text button
            GestureDetector(
              onTap: () => setState(() => _showMoreOptions = true),
              child: Text(
                'More sign-in options',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white.withOpacity(0.3),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildAuthButton({
    required String label,
    IconData? icon,
    Widget? customIcon,
    required Color backgroundColor,
    required Color textColor,
    Color? borderColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: borderColor != null ? Border.all(color: borderColor) : null,
          boxShadow: backgroundColor != Colors.transparent
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,  // Prevent overflow
          children: [
            if (customIcon != null) customIcon,
            if (icon != null) Icon(icon, color: textColor, size: 24),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleIcon() {
    // Simple Google "G" icon
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            foreground: Paint()
              ..shader = const LinearGradient(
                colors: [
                  Color(0xFF4285F4), // Blue
                  Color(0xFF34A853), // Green
                  Color(0xFFFBBC05), // Yellow
                  Color(0xFFEA4335), // Red
                ],
              ).createShader(const Rect.fromLTWH(0, 0, 24, 24)),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    // Progressive Disclosure: Minimized footer - info icon reveals Terms/Privacy
    return GestureDetector(
      onTap: _showLegalBottomSheet,
      child: Icon(
        Icons.info_outline,
        color: Colors.white.withOpacity(0.25),
        size: 20,
      ),
    );
  }

  void _showLegalBottomSheet() {
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
          children: [
            Text(
              'Legal',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.white54),
              title: const Text('Terms of Service', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white24),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navigate to Terms
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip, color: Colors.white54),
              title: const Text('Privacy Policy', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white24),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navigate to Privacy
              },
            ),
            const SizedBox(height: 16),
            Text(
              'By continuing, you agree to our Terms and Privacy Policy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
