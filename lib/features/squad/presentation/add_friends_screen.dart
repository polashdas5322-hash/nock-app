import 'package:nock/core/theme/app_icons.dart';
import 'package:nock/shared/widgets/app_icon.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:nock/core/utils/app_modal.dart';
import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nock/core/services/invite_service.dart';
import 'package:nock/core/services/auth_service.dart';
import 'package:nock/core/services/share_service.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/constants/app_constants.dart';
import 'package:nock/core/models/user_model.dart';
import 'package:nock/core/services/contacts_sync_service.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/shared/widgets/qr_invite_card.dart';
import 'package:nock/core/theme/app_dimens.dart';

/// Unified Add Friends Screen
///
/// Combines:
/// 1. Visual invite cards (invite new users)
/// 2. Social sharing (viral growth)
/// 3. Contact syncing (find friends)
///
/// Layout:
/// - QR Code at top
/// - Quick share icons (Messenger, Instagram, Messages, etc.)
/// - Contact Sync section
/// - Full invite options list
class AddFriendsScreen extends ConsumerStatefulWidget {
  const AddFriendsScreen({super.key});

  @override
  ConsumerState<AddFriendsScreen> createState() => _AddFriendsScreenState();
}

class _AddFriendsScreenState extends ConsumerState<AddFriendsScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey _inviteCardKey = GlobalKey();
  bool _isGeneratingCard = false;
  bool _isSharing = false; // LAZY LOAD FIX: Prevents double-clicks during share
  File? _generatedCardFile;
  List<SyncedContact> _syncedContacts = []; // All contacts with match status
  bool _isSyncingContacts = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _addFriend(UserModel friend) async {
    final authService = ref.read(authServiceProvider);
    final currentUserId = authService.currentUserId;
    if (currentUserId == null) return;

    // Check if already friends
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.friendIds.contains(friend.id) ?? false) {
      _showError('${friend.displayName} is already in your squad!');
      return;
    }

    try {
      // Add to both users' friend lists
      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(currentUserId)
          .update({
            'friendIds': FieldValue.arrayUnion([friend.id]),
          });

      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(friend.id)
          .update({
            'friendIds': FieldValue.arrayUnion([currentUserId]),
          });

      if (mounted) {
        HapticFeedback.mediumImpact();
        _showSuccess('Added ${friend.displayName} to your squad!');
      }
    } catch (e) {
      _showError('Failed to add friend. Please try again.');
    }
  }

  // ==================== INVITE CARD FUNCTIONALITY ====================

  Future<File?> _generateInviteCard() async {
    if (_isGeneratingCard) return null;

    setState(() => _isGeneratingCard = true);

    final completer = Completer<File?>();

    // Wait for a short moment to ensure UI shows loading state
    await Future.delayed(const Duration(milliseconds: 100));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        completer.complete(null);
        return;
      }

      try {
        // MEMORY FIX: Use dynamic pixel ratio capped at 2.0
        final deviceRatio = MediaQuery.of(context).devicePixelRatio;
        final safeRatio = deviceRatio > 2.0 ? 2.0 : deviceRatio;

        // Try widget-based capture first
        var file = await InviteCardGenerator.captureInviteCard(
          cardKey: _inviteCardKey,
          pixelRatio: safeRatio,
        );

        // If widget capture failed, use offscreen rendering
        if (file == null) {
          debugPrint(
            'AddFriendsScreen: Widget capture failed, trying offscreen render...',
          );

          final userModel = ref.read(currentUserProvider).valueOrNull;
          final firebaseUser = ref.read(authStateProvider).valueOrNull;

          final displayName = userModel?.displayName.isNotEmpty == true
              ? userModel!.displayName
              : (firebaseUser?.displayName ?? 'Nock User');
          final username =
              userModel?.username ??
              (firebaseUser?.uid.substring(0, 8) ?? 'viber');

          file = await InviteCardGenerator.renderInviteCardOffscreen(
            senderName: displayName,
            username: username,
            pixelRatio: safeRatio,
          );
        }

        if (mounted) {
          setState(() {
            _generatedCardFile = file;
            _isGeneratingCard = false;
          });
        }
        completer.complete(file);
      } catch (e) {
        debugPrint('AddFriendsScreen: Error generating card: $e');
        if (mounted) {
          setState(() => _isGeneratingCard = false);
        }
        completer.complete(null);
      }
    });

    return completer.future;
  }

  Future<void> _shareToTarget(InviteTarget target) async {
    // Try to get user from Firestore first
    final userModel = ref.read(currentUserProvider).valueOrNull;

    // Fallback to Firebase Auth if Firestore user not available
    // (This can happen if Firestore API is disabled or user just signed up)
    final firebaseUser = ref.read(authStateProvider).valueOrNull;

    if (userModel == null && firebaseUser == null) {
      _showError('Please sign in to invite friends');
      return;
    }

    // Use Firestore user data if available, otherwise fallback to Firebase Auth
    final userId = userModel?.id ?? firebaseUser!.uid;
    final displayName = userModel?.displayName.isNotEmpty == true
        ? userModel!.displayName
        : (firebaseUser?.displayName ?? 'Nock User');

    HapticFeedback.mediumImpact();

    if (_generatedCardFile == null) {
      final file = await _generateInviteCard();
      if (file == null) {
        _showError('Failed to generate invite card');
        return;
      }
    }

    final inviteService = ref.read(inviteServiceProvider);
    final message = inviteService.generateInviteMessage(
      senderName: displayName,
    );
    // Use Firebase UID for the invite link
    final link = inviteService.generateInviteLink(userId);
    final fullMessage = '$message\n$link';

    bool success = false;

    switch (target) {
      case InviteTarget.instagramStory:
        success = await inviteService.shareToInstagramStory(
          imagePath: _generatedCardFile!.path,
          senderName: displayName,
        );
        break;
      case InviteTarget.instagramDm:
        success = await inviteService.shareToInstagramDm(
          imagePath: _generatedCardFile!.path,
          message: fullMessage,
        );
        break;
      case InviteTarget.snapchat:
        success = await inviteService.shareToSnapchat(
          imagePath: _generatedCardFile!.path,
          message: fullMessage,
        );
        break;
      case InviteTarget.whatsapp:
        success = await inviteService.shareToWhatsApp(
          imagePath: _generatedCardFile!.path,
          message: fullMessage,
        );
        break;
      case InviteTarget.messenger:
        success = await inviteService.shareToMessenger(
          imagePath: _generatedCardFile!.path,
          message: fullMessage,
        );
        break;
      case InviteTarget.telegram:
        success = await inviteService.shareToTelegram(
          imagePath: _generatedCardFile!.path,
          message: fullMessage,
        );
        break;
      case InviteTarget.messages:
        success = await inviteService.shareToMessages(
          message: fullMessage,
          imagePath: _generatedCardFile!.path,
        );
        break;
      case InviteTarget.other:
        success = await inviteService.shareToSystem(
          imagePath: _generatedCardFile!.path,
          message: fullMessage,
        );
        break;
    }

    if (!mounted) return;

    if (success) {
      // Show success - note: for system share (Messenger, Snapchat, Messages, Other)
      // success means the share sheet opened, not that user actually shared
      if (target == InviteTarget.other ||
          target == InviteTarget.messenger ||
          target == InviteTarget.snapchat ||
          target == InviteTarget.messages) {
        // For system share, don't claim "sent" - just opened share sheet
        _showSuccess('Share sheet opened!');
      } else {
        _showSuccess('Opened ${target.displayName}!');
      }
    } else {
      // Only show error for direct share apps that completely failed
      if (target == InviteTarget.instagramStory) {
        _showError('Instagram not installed. Try another option!');
      }
      // For other failures, they already fell back to system share
    }
  }

  // ==================== UI HELPERS ====================

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error, // High contrast for dark mode
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(AppIcons.check, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.r12),
        ),
      ),
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.vibeBackground,
      body: Stack(
        children: [
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: CustomScrollView(
                slivers: [
                  // Header
                  SliverToBoxAdapter(
                    child: userAsync.when(
                      data: (user) => _buildHeader(user?.friendIds.length ?? 0),
                      loading: () => _buildHeader(0),
                      error: (_, __) => _buildHeader(0),
                    ),
                  ),

                  // QR Code Invite Card (replaces search bar)
                  SliverToBoxAdapter(
                    child: userAsync.when(
                      data: (user) => QRInviteCard(
                        username:
                            user?.username ??
                            user?.id.substring(0, 8) ??
                            'user',
                        userId: user?.id,
                        displayName: user?.displayName,
                      ),
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppDimens.p40),
                          child: CircularProgressIndicator(
                            color: AppColors.vibePrimary,
                          ),
                        ),
                      ),
                      error: (_, __) => QRInviteCard(
                        username: 'user',
                        userId: null,
                        displayName: null,
                      ),
                    ),
                  ),

                  // 3-button social share row + Sync Contacts
                  SliverToBoxAdapter(child: _buildFindFriendsSection()),

                  const SliverToBoxAdapter(
                    child: SizedBox(
                      height: AppDimens.p64 + AppDimens.p32 + AppDimens.p4,
                    ), // 100 approx
                  ),
                ],
              ),
            ),
          ),

          // Hidden invite card for capture
          // FIX: Use Opacity(0.0) instead of left: -2000
          // Some Android OEMs (Samsung/Xiaomi) cull widgets positioned completely
          // off-screen, causing RepaintBoundary.toImage() to capture a blank image.
          // The Opacity approach keeps the widget rendered but invisible.
          Positioned(
            left: 0,
            top: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.0,
                child: RepaintBoundary(
                  key: _inviteCardKey,
                  child: Builder(
                    builder: (context) {
                      final screenWidth = MediaQuery.sizeOf(context).width;
                      final captureWidth = screenWidth > 500
                          ? 500.0
                          : screenWidth;

                      return SizedBox(
                        width: captureWidth,
                        height: captureWidth * 16 / 9,
                        child: userAsync.when(
                          data: (user) => InviteCardGenerator.buildInviteCard(
                            senderName: user?.displayName ?? 'Nock User',
                            username:
                                user?.username ??
                                user?.id.substring(0, 8) ??
                                'user',
                            primaryColor: AppColors.vibePrimary,
                            secondaryColor: AppColors.vibeSecondary,
                          ),
                          loading: () => InviteCardGenerator.buildInviteCard(
                            senderName: 'Loading...',
                            username: 'user',
                            primaryColor: AppColors.vibePrimary,
                            secondaryColor: AppColors.vibeSecondary,
                          ),
                          error: (_, __) => InviteCardGenerator.buildInviteCard(
                            senderName: 'Nock User',
                            username: 'user',
                            primaryColor: AppColors.vibePrimary,
                            secondaryColor: AppColors.vibeSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // Loading overlay
          if (_isGeneratingCard)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.vibePrimary),
                    SizedBox(height: AppDimens.p16),
                    Text(
                      'Creating your invite...',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
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

  Widget _buildHeader(int friendCount) {
    return Padding(
      padding: const EdgeInsets.all(AppDimens.p20),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(AppIcons.arrowLeft, color: AppColors.textPrimary),
              ),
              const SizedBox(width: AppDimens.p8),
              Text(
                'Invite Friends',
                style: AppTypography.headlineMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.p8),
          Text(
            'Share your QR code or invite via social media',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSyncContacts() async {
    if (_isSyncingContacts) return;

    setState(() => _isSyncingContacts = true);
    HapticFeedback.mediumImpact();

    try {
      final contactsService = ref.read(contactsSyncServiceProvider);
      final allContacts = await contactsService.syncContacts();

      if (!mounted) return;

      // Filter out users who are already friends
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      final friendIds = currentUser?.friendIds ?? [];

      // Remove contacts where the matched user is already a friend
      final filteredContacts = allContacts.where((c) {
        if (c.isOnNock && friendIds.contains(c.matchedUser!.id)) {
          return false; // Already friends
        }
        return true;
      }).toList();

      setState(() {
        _syncedContacts = filteredContacts;
        _isSyncingContacts = false;
      });

      final matchCount = filteredContacts.where((c) => c.isOnNock).length;
      final inviteCount = filteredContacts.where((c) => !c.isOnNock).length;

      if (matchCount > 0) {
        _showSuccess(
          'Found $matchCount friends on Nock! $inviteCount to invite.',
        );
      } else {
        _showSuccess('$inviteCount contacts ready to invite!');
      }
    } catch (e) {
      setState(() => _isSyncingContacts = false);
      _showError('Failed to sync contacts: $e');
      debugPrint('ContactSync error: $e');
    }
  }

  Widget _buildSyncedContactsSection() {
    final matchCount = _syncedContacts.where((c) => c.isOnNock).length;
    final inviteCount = _syncedContacts.where((c) => !c.isOnNock).length;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.p20,
        vertical: AppDimens.p12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(
                AppIcons.contacts,
                color: AppColors.primaryAction,
                size: 18,
              ),
              const SizedBox(width: AppDimens.p8),
              Text(
                'Your Contacts',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.primaryAction,
                ),
              ),
              const Spacer(),
              if (matchCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryAction.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(
                      AppDimens.p12 - AppDimens.p2,
                    ),
                  ),
                  child: Text(
                    '$matchCount on Nock',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.primaryAction,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                '$inviteCount to invite',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 350), // Limit height
            decoration: BoxDecoration(
              color: AppColors.surfaceGlassLow,
              borderRadius: BorderRadius.circular(AppDimens.r12),
              border: Border.all(color: AppColors.surfaceGlassDim),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _syncedContacts.length,
              itemBuilder: (context, index) {
                final contact = _syncedContacts[index];
                return _buildContactItem(contact);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(SyncedContact contact) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.p16,
        vertical: AppDimens.p12,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceGlassLow)),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 22,
            backgroundColor: contact.isOnNock
                ? AppColors.vibePrimary
                : Colors.grey.shade700,
            backgroundImage: contact.matchedUser?.avatarUrl != null
                ? NetworkImage(contact.matchedUser!.avatarUrl!)
                : null,
            child: contact.matchedUser?.avatarUrl == null
                ? Text(
                    contact.displayName.isNotEmpty
                        ? contact.displayName[0].toUpperCase()
                        : '?',
                    style: AppTypography.headlineSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: AppDimens.p12),

          // Contact info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.displayName,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  contact.phoneNumber,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Action button
          if (contact.isOnNock)
            ElevatedButton(
              onPressed: () => _addFriend(contact.matchedUser!),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.vibePrimary,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.p20),
                ),
              ),
              child: Text('Add', style: AppTypography.buttonTextSmall),
            )
          else
            OutlinedButton(
              onPressed: () => _inviteViaSms(contact),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(color: AppColors.surfaceGlassHigh),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.p20),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.send, size: 14),
                  SizedBox(width: 4),
                  Text('Invite', style: AppTypography.buttonTextSmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _inviteViaSms(SyncedContact contact) async {
    HapticFeedback.lightImpact();

    // Get current user for invite link
    final userModel = ref.read(currentUserProvider).valueOrNull;
    final userId = userModel?.id ?? '';

    final inviteService = ref.read(inviteServiceProvider);
    final message = inviteService.generateInviteMessage(
      senderName: userModel?.displayName ?? 'A friend',
    );
    final link = inviteService.generateInviteLink(userId);
    final fullMessage = '$message\n$link';

    // Clean phone number (keep only digits and +)
    final cleanPhone = contact.phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    // Build SMS URI using proper Uri constructor
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: cleanPhone,
      queryParameters: <String, String>{'body': fullMessage},
    );

    try {
      if (await canLaunchUrl(smsUri)) {
        if (!mounted) return;
        await launchUrl(smsUri);
        if (!mounted) return;
        _showSuccess('Opening SMS to ${contact.displayName}...');
      } else {
        if (!mounted) return;
        _showError('Could not open SMS app');
      }
    } catch (e) {
      debugPrint('SMS launch error: $e');
      _showError('Failed to open SMS: $e');
    }
  }

  Widget _buildFindFriendsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.p20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            children: [
              AppIcon(AppIcons.share, color: AppColors.textSecondary, size: 18),
              const SizedBox(width: AppDimens.p8),
              Text(
                'Share with friends',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.p20),

          // ================================
          // 3-BUTTON SOCIAL SHARE ROW
          // ================================
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. INSTAGRAM BUTTON
              _buildSocialShareButton(
                icon: AppIcons.switchCamera,
                label: 'Instagram',
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFF58529),
                    Color(0xFFDD2A7B),
                    Color(0xFF8134AF),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                onTap: () => _handleInstagramShare(),
              ),

              const SizedBox(width: AppDimens.p24 + AppDimens.p4), // 28
              // 2. TIKTOK BUTTON
              _buildSocialShareButton(
                icon: AppIcons.music,
                label: 'TikTok',
                color: Colors.black,
                borderColor: Colors.white.withOpacity(0.3),
                onTap: () => _handleTikTokTap(),
              ),

              const SizedBox(width: AppDimens.p24 + AppDimens.p4), // 28
              // 3. SHARE BUTTON
              _buildSocialShareButton(
                icon: AppIcons.share,
                label: 'Share',
                color: AppColors.textPrimary,
                iconColor: Colors.black,
                onTap: () => _handleGenericShare(),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ================================
          // SYNC CONTACTS BUTTON (Opens Bottom Sheet)
          // ================================
          GestureDetector(
            onTap: () => _showContactsBottomSheet(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surfaceGlassLow,
                borderRadius: BorderRadius.circular(AppDimens.r16),
                border: Border.all(color: AppColors.surfaceGlassMedium),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryAction.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: AppIcon(
                      AppIcons.contacts,
                      color: AppColors.primaryAction,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sync Contacts',
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Find friends already on Nock',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceGlassMedium,
                      shape: BoxShape.circle,
                    ),
                    child: AppIcon(
                      AppIcons.caretRight,
                      color: AppColors.textSecondary,
                      size: 14,
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

  // ================================
  // SOCIAL SHARE BUTTON WIDGET
  // ================================
  Widget _buildSocialShareButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Gradient? gradient,
    Color? color,
    Color? borderColor,
    Color iconColor = AppColors.textPrimary,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
              color: color,
              border: borderColor != null
                  ? Border.all(color: borderColor, width: 2)
                  : null,
              boxShadow: [
                BoxShadow(
                  color:
                      (gradient != null
                              ? const Color(0xFFDD2A7B)
                              : (color ?? AppColors.textPrimary))
                          .withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ================================
  // SHARE HANDLERS
  // ================================

  Future<void> _handleInstagramShare() async {
    // LAZY LOAD FIX: Prevent double-clicks during share
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      // Generate invite card first
      if (_generatedCardFile == null) {
        final file = await _generateInviteCard();
        if (file == null) {
          _showError('Failed to generate invite card');
          return;
        }
      }

      final shareService = ref.read(shareServiceProvider);

      // Check if Instagram is installed first
      final isInstalled = await shareService.isInstagramInstalled();
      if (!isInstalled) {
        _showError('Instagram is not installed');
        return;
      }

      // Open Instagram directly with explicit intent
      // This shows ONLY Instagram's picker (Feed, Messages, Reels, Stories) - NOT all apps!
      final success = await shareService.shareToInstagramDirect(
        _generatedCardFile!,
      );

      if (!mounted) return;

      if (success) {
        _showSuccess('Opening Instagram...');
      } else {
        // Instagram not installed or failed to open
        _showError('Failed to open Instagram. Try the Share button instead!');
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _handleTikTokTap() async {
    // LAZY LOAD FIX: Prevent double-clicks during share
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      // Generate invite card first (same as Instagram)
      if (_generatedCardFile == null) {
        final file = await _generateInviteCard();
        if (file == null) {
          _showError('Failed to generate invite card');
          return;
        }
      }

      final shareService = ref.read(shareServiceProvider);

      // Check if TikTok is installed
      final isInstalled = await shareService.isTikTokInstalled();
      if (!isInstalled) {
        _showError('TikTok is not installed');
        return;
      }

      // Share image to TikTok directly (bypasses system share sheet)
      final success = await shareService.shareToTikTok(_generatedCardFile!);

      if (!mounted) return;

      if (success) {
        _showSuccess('Opening TikTok...');
      } else {
        _showError('Failed to open TikTok. Try the Share button instead!');
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _handleGenericShare() async {
    // LAZY LOAD FIX: Prevent double-clicks during share
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      // Generate invite card first
      if (_generatedCardFile == null) {
        await _generateInviteCard();
      }

      final userModel = ref.read(currentUserProvider).valueOrNull;
      final displayName = userModel?.displayName ?? 'A friend';
      final inviteService = ref.read(inviteServiceProvider);
      final message = inviteService.generateInviteMessage(
        senderName: displayName,
      );

      // Open native share sheet with all options
      await Share.shareXFiles(
        _generatedCardFile != null ? [XFile(_generatedCardFile!.path)] : [],
        text: message,
        subject: 'Join me on Nock!',
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // ================================
  // CONTACTS BOTTOM SHEET
  // ================================

  void _showContactsBottomSheet() {
    HapticFeedback.mediumImpact();

    AppModal.show(
      context: context,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Contacts on Nock',
                    style: AppTypography.headlineMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Done',
                      style: AppTypography.buttonText.copyWith(
                        color: AppColors.vibePrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Divider(color: AppColors.surfaceGlassDim, height: 24),

            // Sync button if contacts not loaded yet
            if (_syncedContacts.isEmpty && !_isSyncingContacts)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: GestureDetector(
                  onTap: () async {
                    final proceed = await _showContactDisclosure();
                    if (proceed == true) {
                      await _handleSyncContacts();
                      setState(() {}); // Refresh bottom sheet
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.vibePrimary,
                          AppColors.vibeSecondary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(AppIcons.sync, color: AppColors.textPrimary),
                        SizedBox(width: 8),
                        Text(
                          'Sync Contacts Now',
                          style: AppTypography.buttonText.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Loading state
            if (_isSyncingContacts)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.vibePrimary),
                      SizedBox(height: 16),
                      Text(
                        'Syncing your contacts...',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Contacts list
            if (_syncedContacts.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _syncedContacts.length,
                  itemBuilder: (context, index) {
                    final contact = _syncedContacts[index];
                    return _buildContactItem(contact);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
  // ================================
  // CONTACT DISCLOSURE (2025 COMPLIANCE)
  // ================================

  Future<bool?> _showContactDisclosure() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDialog,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(AppIcons.privacy, color: AppColors.vibePrimary),
            SizedBox(width: 12),
            Text(
              'Your Privacy',
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nock uploads your contacts to our servers to help you find friends already on the app.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Your data is encrypted and never shared with 3rd parties. You can disconnect at any time in Settings.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Not Now',
              style: AppTypography.buttonText.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.vibePrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(
              'Agree & Sync',
              style: AppTypography.buttonText.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickShareButton(
    String label,
    PhosphorIconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: AppIcon(icon, color: AppColors.textPrimary, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteSection() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.send, color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 8),
              Text(
                'All invite options',
                style: AppTypography.labelSmall.copyWith(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildInviteOption(InviteTarget.instagramStory),
          _buildInviteOption(InviteTarget.instagramDm),
          _buildInviteOption(InviteTarget.messenger),
          _buildInviteOption(InviteTarget.whatsapp),
          _buildInviteOption(InviteTarget.snapchat),
          _buildInviteOption(InviteTarget.telegram),
          _buildInviteOption(InviteTarget.messages),
          _buildInviteOption(InviteTarget.other),
        ],
      ),
    );
  }

  Widget _buildInviteOption(InviteTarget target) {
    return GestureDetector(
      onTap: () => _shareToTarget(target),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceGlassLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: target.color,
                shape: BoxShape.circle,
              ),
              child: Icon(target.icon, color: AppColors.textPrimary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.displayName,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    _getInviteDescription(target),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            AppIcon(AppIcons.chevronRight, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  String _getInviteDescription(InviteTarget target) {
    switch (target) {
      case InviteTarget.instagramStory:
        return 'Share to your Story';
      case InviteTarget.instagramDm:
        return 'Send via Direct Message';
      case InviteTarget.messenger:
        return 'Send via Facebook Messenger';
      case InviteTarget.whatsapp:
        return 'Send via WhatsApp chat';
      case InviteTarget.snapchat:
        return 'Share as a Snap';
      case InviteTarget.telegram:
        return 'Send via Telegram';
      case InviteTarget.messages:
        return 'Send as iMessage or SMS';
      case InviteTarget.other:
        return 'Use system share sheet';
    }
  }
}
