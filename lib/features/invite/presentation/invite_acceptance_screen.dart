import 'package:nock/core/theme/app_icons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nock/core/constants/app_routes.dart';
import 'package:nock/core/services/auth_service.dart'; // for authStateProvider
import 'package:nock/core/providers/deep_link_provider.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';

/// Invite Acceptance Screen
///
/// Handles deep links like: vibe.app/invite/username123
/// This screen is shown when a user clicks an invite link
class InviteAcceptanceScreen extends ConsumerStatefulWidget {
  final String inviterId;

  const InviteAcceptanceScreen({super.key, required this.inviterId});

  @override
  ConsumerState<InviteAcceptanceScreen> createState() =>
      _InviteAcceptanceScreenState();
}

class _InviteAcceptanceScreenState
    extends ConsumerState<InviteAcceptanceScreen> {
  bool _isLoading = true;
  bool _isAccepting = false;
  String? _inviterName;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInviterInfo();

    // CRITICAL: "Consume" the pending invite's mandatory redirect state on mount.
    // By calling dismiss(), we tell the Router that we have already seen this
    // invite in this session, so it won't force-redirect us back here if we
    // choose to navigate to Home or Settings later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(pendingInviteProvider.notifier).dismiss();
        debugPrint(
          'InviteAcceptanceScreen: Dismissed active redirect for this invite',
        );
      }
    });
  }

  Future<void> _loadInviterInfo() async {
    try {
      if (widget.inviterId.isEmpty) {
        setState(() {
          _error = 'Invalid invite link';
          _isLoading = false;
        });
        return;
      }

      // ACTUAL FIRESTORE IMPLEMENTATION: Fetch inviter info
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.inviterId)
          .get();

      if (!doc.exists) {
        setState(() {
          _error = 'User not found';
          _isLoading = false;
        });
        return;
      }

      final data = doc.data();
      setState(() {
        _inviterName = data?['displayName'] ?? 'Nock User';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load invite: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptInvite() async {
    setState(() => _isAccepting = true);

    try {
      // Check if user is logged in
      final authState = ref.read(authStateProvider);
      final currentUser = authState.valueOrNull;

      if (currentUser == null) {
        // Not logged in - go to auth first, then come back
        context.go(AppRoutes.welcome);
        return;
      }

      final currentUserId = currentUser.uid;
      final inviterId = widget.inviterId;

      // Validate inviter ID
      if (inviterId.isEmpty) {
        setState(() {
          _error = 'Invalid invite link';
          _isAccepting = false;
        });
        return;
      }

      if (inviterId == currentUserId) {
        setState(() {
          _error = 'You can\'t add yourself as a friend 😅';
          _isAccepting = false;
        });
        return;
      }

      // ACTUAL FIRESTORE IMPLEMENTATION: Connect both users as friends
      // This replaces the TODO placeholder that broke the viral loop
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();

      // 1. Add inviter to current user's friend list
      batch.update(firestore.collection('users').doc(currentUserId), {
        'friendIds': FieldValue.arrayUnion([inviterId]),
      });

      // 2. Add current user to inviter's friend list (bidirectional)
      batch.update(firestore.collection('users').doc(inviterId), {
        'friendIds': FieldValue.arrayUnion([currentUserId]),
      });

      // Execute both updates atomically
      await batch.commit();

      // CRITICAL: Only clear pending invite AFTER successful acceptance
      // This prevents losing the invite if there's a network error
      ref.read(pendingInviteProvider.notifier).clearPendingInvite();

      // Show success and go to home
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(AppIcons.checkCircle, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Text('You\'re now connected with $_inviterName!'),
              ],
            ),
            backgroundColor: AppColors.success,
          ),
        );
        context.go(AppRoutes.home);
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to accept invite: $e';
        _isAccepting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidNavy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00F0FF)),
                )
              : _error != null
              ? _buildErrorState()
              : _buildInviteContent(),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.error, color: AppColors.error, size: 64),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Something went wrong',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Go Home'),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteContent() {
    return Column(
      children: [
        const Spacer(),

        // Glowing avatar area
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppColors.primaryAction.withOpacity(0.3),
                AppColors.secondaryAction.withOpacity(0.3),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryAction.withOpacity(0.3),
                blurRadius: 50,
                spreadRadius: 20,
              ),
            ],
          ),
          child: Center(
            child: Text(
              _inviterName?.isNotEmpty == true
                  ? _inviterName![0].toUpperCase()
                  : '?',
              style: AppTypography.displayLarge.copyWith(
                fontSize: 64,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),

        Text(
          _inviterName ?? 'Someone',
          style: AppTypography.displaySmall.copyWith(
            color: AppColors.textPrimary,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'wants to exchange Vibes with you!',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textSecondary,
          ),
        ),

        const Spacer(),

        // Accept button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isAccepting ? null : _acceptInvite,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryAction,
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            child: _isAccepting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textInverse,
                    ),
                  )
                : Text(
                    'Accept Invite',
                    style: AppTypography.buttonText.copyWith(
                      color: AppColors.textInverse,
                      fontSize: 18,
                    ),
                  ),
          ),
        ),

        const SizedBox(height: 16),

        TextButton(
          onPressed: () {
            // CRITICAL FIX: Removed clearPendingInvite() to prevent losing the invite
            // if user just wants to browse first.
            context.go(AppRoutes.home);
          },
          child: Text(
            'Maybe later',
            style: AppTypography.buttonTextSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
