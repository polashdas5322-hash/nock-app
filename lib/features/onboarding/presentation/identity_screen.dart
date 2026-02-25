import 'package:nock/core/theme/app_icons.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/shared/widgets/glass_container.dart';

/// Identity Screen (Stage 2)
///
/// Allows users to customize their profile before entering the Squad stage.
/// Triggers the "Endowment Effect" - users feel ownership of their identity.
///
/// Uses existing AuthService APIs:
/// - `updateAvatar(File)` - propagates to vibes and friend widgets
/// - `createOrUpdateUserDocument(..., isProfileUpdate: true)` - updates displayName
class IdentityScreen extends ConsumerStatefulWidget {
  const IdentityScreen({super.key});

  @override
  ConsumerState<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends ConsumerState<IdentityScreen> {
  final _nameController = TextEditingController();
  bool _isLoading = false;
  bool _isUpdatingAvatar = false;
  File? _selectedImage;
  String? _currentAvatarUrl;

  // Reactive state flag to prevent overwriting user edits
  bool _hasInitialized = false;

  // REMOVED: initState pre-fill logic (Race Condition Fix)

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint('IdentityScreen: Error picking image: $e');
    }
  }

  Future<void> _saveAndContinue() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter your name')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);
      final userId = authService.currentUserId;

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // 1. Upload avatar if selected (uses existing propagation logic)
      if (_selectedImage != null) {
        setState(() => _isUpdatingAvatar = true);
        await authService.updateAvatar(_selectedImage!);
        setState(() => _isUpdatingAvatar = false);
      }

      // 2. Update display name (uses existing protection logic)
      await authService.createOrUpdateUserDocument(
        userId: userId,
        displayName: name,
        isProfileUpdate: true,
      );

      if (mounted) {
        HapticFeedback.mediumImpact();
        // Navigate to Widget Setup (Skip Contacts as per request)
        context.go(AppRoutes.widgetSetup);
      }
    } catch (e) {
      debugPrint('IdentityScreen: Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // RACE CONDITION FIX: Watch the stream instead of reading once
    final userAsync = ref.watch(currentUserProvider);

    return userAsync.when(
      // Block UI until data is ready to prevent "Empty Profile" glitch
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.bioLime),
        ),
      ),
      error: (err, stack) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text(
            'Error loading profile',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
      data: (user) {
        // Reactive Pre-fill: Only run once when data first arrives
        if (!_hasInitialized && user != null) {
          // Use microtask to avoid "setState during build" if strict
          // But effectively safe here as we are building the widget tree
          if (_nameController.text.isEmpty) {
            _nameController.text = user.displayName ?? '';
          }
          _currentAvatarUrl ??= user.avatarUrl;
          _hasInitialized = true;
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              // Ambient Background - Radial gradient

              // Content
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 48),

                              // Header
                              Text(
                                'Claim Your Aura',
                                style: AppTypography.headlineLarge.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your identity. Your vibe.',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const Spacer(),

                              // Avatar Picker
                              Center(
                                child: GestureDetector(
                                  onTap: _isLoading ? null : _pickAvatar,
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 140,
                                        height: 140,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.bioLime,
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.bioLime
                                                  .withOpacity(0.3),
                                              blurRadius: 20,
                                              spreadRadius: 5,
                                            ),
                                          ],
                                        ),
                                        child: ClipOval(
                                          child: _selectedImage != null
                                              ? Image.file(
                                                  _selectedImage!,
                                                  fit: BoxFit.cover,
                                                )
                                              : _currentAvatarUrl != null &&
                                                    _currentAvatarUrl!
                                                        .isNotEmpty
                                              ? Image.network(
                                                  _currentAvatarUrl!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      _buildPlaceholder(),
                                                )
                                              : _buildPlaceholder(),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppColors.bioLime,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.3,
                                                ),
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            _isUpdatingAvatar
                                                ? AppIcons.hourglass
                                                : AppIcons.camera,
                                            color: AppColors.voidNavy,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Tap to change',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 40),

                              // Name Input
                              GlassContainer(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                useLuminousBorder: true,
                                child: TextField(
                                  controller: _nameController,
                                  style: AppTypography.bodyLarge.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Your name',
                                    hintStyle: AppTypography.bodyLarge.copyWith(
                                      color: AppColors.textTertiary,
                                    ),
                                    border: InputBorder.none,
                                    prefixIcon: Icon(
                                      AppIcons.profile,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  textCapitalization: TextCapitalization.words,
                                  enabled: !_isLoading,
                                ),
                              ),

                              const Spacer(),

                              // Continue Button
                              SizedBox(
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: _isLoading
                                      ? null
                                      : _saveAndContinue,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.bioLime,
                                    foregroundColor: AppColors.voidNavy,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.voidNavy,
                                          ),
                                        )
                                      : Text(
                                          'Continue',
                                          style: AppTypography.labelLarge
                                              .copyWith(
                                                color: AppColors.voidNavy,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.surfaceLight,
      child: Icon(AppIcons.profile, size: 64, color: AppColors.textTertiary),
    );
  }
}
