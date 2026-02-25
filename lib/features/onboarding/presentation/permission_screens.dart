import 'package:nock/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nock/core/services/contacts_sync_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/shared/widgets/glass_container.dart';
import 'package:nock/shared/widgets/aura_visualization.dart';

/// Permission flow screens - "Hard Gate" onboarding
/// Forces users to grant all permissions before entering the app

/// Base Permission Screen
class PermissionScreen extends ConsumerStatefulWidget {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Permission permission;
  final String nextRoute;
  final AuraMood mood;

  const PermissionScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.permission,
    required this.nextRoute,
    this.mood = AuraMood.neutral,
  });

  @override
  ConsumerState<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends ConsumerState<PermissionScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    // FIX: Register as observer to detect when user returns from Settings
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _checkExistingPermission();
  }

  Future<void> _checkExistingPermission() async {
    final status = await widget.permission.status;
    if (status.isGranted && mounted) {
      context.go(widget.nextRoute);
    }
  }

  @override
  void dispose() {
    // FIX: Remove observer on dispose
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  // FIX: Auto-check permission when user returns from Settings
  // Without this, users get trapped on the permission screen
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // User returned from Settings, re-check permission status
      _checkExistingPermission();
    }
  }

  Future<void> _requestPermission() async {
    if (_isRequesting) return;

    setState(() => _isRequesting = true);

    final status = await widget.permission.request();

    setState(() => _isRequesting = false);

    if (status.isGranted && mounted) {
      context.go(widget.nextRoute);
    } else if (status.isPermanentlyDenied && mounted) {
      _showSettingsDialog();
    } else if (status.isDenied && mounted) {
      // FIX: Handle simple denial - show message and allow retry or skip
      _showDeniedDialog();
    }
  }

  void _showDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Permission Needed', style: AppTypography.headlineMedium),
        content: Text(
          '${widget.title} permission is required for the best Vibe experience. Would you like to try again?',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Allow skip - proceed anyway (limited functionality)
              context.go(widget.nextRoute);
            },
            child: const Text('Skip for now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestPermission();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryAction,
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Permission Required', style: AppTypography.headlineMedium),
        content: Text(
          '${widget.title} permission was permanently denied. Please enable it in Settings to continue, or skip to use limited functionality.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          // FIX: Add "Skip for now" to prevent death loop
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // Allow user to skip if they really refuse
              context.go(widget.nextRoute);
            },
            child: const Text('Skip for now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryAction,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Animated Aura with icon
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.9 + (_pulseController.value * 0.1),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AuraVisualization(size: 200, mood: widget.mood),
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.background.withOpacity(0.8),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.icon,
                            size: 40,
                            color: AppColors.primaryAction,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 48),

              // Title
              Text(
                widget.title,
                style: AppTypography.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Subtitle
              Text(
                widget.subtitle,
                style: AppTypography.headlineSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Description
              GlassContainer(
                padding: const EdgeInsets.all(20),
                child: Text(
                  widget.description,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const Spacer(),

              // Grant Permission Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isRequesting ? null : _requestPermission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryAction,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: _isRequesting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: AppColors.background,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(widget.title, style: AppTypography.buttonText),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// THE SQUAD SCREEN (Step 2 of 4)
///
/// "Build your inner circle."
///
/// This screen replaces the generic "Contacts Permission" screen.
/// Ideally, it should show a preview of friends already on Nock (if we had the graph).
/// Since we don't have permissions yet, we use social proof copy.
class ContactsPermissionScreen extends ConsumerStatefulWidget {
  const ContactsPermissionScreen({super.key});

  @override
  ConsumerState<ContactsPermissionScreen> createState() =>
      _ContactsPermissionScreenState();
}

class _ContactsPermissionScreenState
    extends ConsumerState<ContactsPermissionScreen> {
  bool _isLoading = false;

  Future<void> _requestPermission() async {
    setState(() => _isLoading = true);

    // 1. Request Permission
    // "Find Friends" -> Triggers system dialog
    final status = await Permission.contacts.request();

    if (status.isGranted) {
      // 2. Sync Contacts (Background)
      // We don't block navigation on this, but we kick it off.
      // The Next screen (Widget) or Home will eventually show the results.
      ref.read(contactsSyncServiceProvider).syncContacts();

      if (mounted) {
        // 3. Navigate to Step 3: Magic (Widget)
        context.go(AppRoutes.widgetSetup);
      }
    } else {
      // Permission denied
      // We still let them proceed, but maybe show a dialog or just move on.
      // Progressive Disclosure means we don't block them forever.
      if (mounted) {
        setState(() => _isLoading = false);
        // Optional: Show "You can add friends later" snackbar?
        // For now, simple progression.
        context.go(AppRoutes.widgetSetup);
      }
    }
  }

  void _skip() {
    // skip logic
    context.go(AppRoutes.widgetSetup);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Ambient Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.vibePrimary.withOpacity(0.1),
                    AppColors.background,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 1),

                  // Hero Image / Icon
                  // Using a large, friendly icon or illustration
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadow,
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(
                      AppIcons.peopleAlt,
                      size: 64,
                      color: AppColors.vibePrimary,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Headline
                  Text(
                    'Your Squad',
                    style: AppTypography.displaySmall.copyWith(
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Body Copy
                  Text(
                    'See which of your friends are already here. Nock is better together.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLarge.copyWith(
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Primary Action
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _requestPermission,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.vibePrimary,
                        foregroundColor: AppColors.textInverse,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: AppColors.textInverse,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Find My Friends',
                              style: AppTypography.buttonText.copyWith(
                                fontSize: 18,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Secondary Action (Skip)
                  TextButton(
                    onPressed: _skip,
                    child: Text(
                      'Skip for now',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const Spacer(flex: 1),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 🗑️ DEPRECATED SCREENS REMOVED:
// - MicrophonePermissionScreen (Now contextual in CameraScreenNew)
// - CameraPermissionScreen (Now contextual in CameraScreenNew)
// - NotificationPermissionScreen (Now contextual in PreviewScreen)
