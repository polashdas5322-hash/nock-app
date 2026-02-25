import 'package:nock/core/theme/app_icons.dart';
import 'package:nock/shared/widgets/app_icon.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/models/user_model.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/features/squad/presentation/squad_screen.dart';

/// Features:
/// - Quick Send Row: Recent/active friends for instant single-tap sending
/// - Multi-Select List: Checkboxes for group broadcasting
///
/// UPDATE: Now implements "Spinner -> Checkmark" Industry Standard Feedback Loop
class SmartSendSheet extends ConsumerStatefulWidget {
  final bool isAudioOnly;
  final bool
  isPreSelectionMode; // True when accessed from Face Pile before capture
  final Set<String> initialSelectedIds; // Preserve previous selections
  final Future<String?> Function(String)? onSendToOne; // MUST return Task ID
  final Future<List<String?>> Function(List<String>)?
  onSendToMany; // For bulk send, returns list of Task IDs
  final Function(Set<String>)? onPreSelect; // Callback for pre-selection mode

  const SmartSendSheet({
    super.key,
    required this.isAudioOnly,
    this.isPreSelectionMode = false,
    this.initialSelectedIds = const {},
    this.onSendToOne,
    this.onSendToMany,
    this.onPreSelect,
  });

  @override
  ConsumerState<SmartSendSheet> createState() => _SmartSendSheetState();
}

class _SmartSendSheetState extends ConsumerState<SmartSendSheet> {
  late Set<String> _selectedIds;

  // UX State
  String?
  _loadingFriendId; // Which friend is currently being sent to (Quick Row)
  bool _isMainButtonLoading = false;
  bool _showCheckmark = false; // "Sent!" state

  @override
  void initState() {
    super.initState();
    // Initialize with any previous selections (preserves state across opens)
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
  }

  /// 2026 UX: The "Trust Loop"
  /// Spinner -> 500ms -> Checkmark -> Close
  Future<void> _handleSendWithFeedback(
    List<String> recipients, {
    String? quickSendId,
  }) async {
    if (recipients.isEmpty) return;

    // In Pre-Selection mode, we don't send updates, just return
    if (widget.isPreSelectionMode) {
      widget.onPreSelect?.call(_selectedIds);
      Navigator.pop(context);
      return;
    }

    HapticFeedback.mediumImpact(); // Initial tap feedback

    setState(() {
      if (quickSendId != null) {
        _loadingFriendId = quickSendId;
      } else {
        _isMainButtonLoading = true;
      }
    });

    try {
      // 1. Trigger the send
      String? taskId;
      if (quickSendId != null && widget.onSendToOne != null) {
        // Expecting Future<String?> here now
        taskId = await widget.onSendToOne!(quickSendId);
      } else if (widget.onSendToMany != null) {
        // For group send, we also want to wait.
        final results = await widget.onSendToMany!(recipients);
        // Check if at least one succeeded
        if (results.any((id) => id != null)) {
          taskId = "batch_success";
        }
      }

      // 🛑 FIX: Check for failure (False Positive Prevention)
      if (taskId == null) {
        throw Exception("Upload initiation failed (network or file error)");
      }

      // 2. Artificial "Handoff" Delay (Psychological Trust)
      // Only do this if we are sending, not if just selecting
      await Future.delayed(const Duration(milliseconds: 600));

      // 3. Show Success State
      if (mounted) {
        HapticFeedback.lightImpact(); // Success haptic
        setState(() {
          _loadingFriendId = null;
          _isMainButtonLoading = false;
          _showCheckmark = true; // Shows the Big Green Checkmark
        });
      }

      // 4. Close automatically after letting user see checkmark
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      // Error State (Revert to normal)
      if (mounted) {
        setState(() {
          _loadingFriendId = null;
          _isMainButtonLoading = false;
          _showCheckmark = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                AppIcon(AppIcons.error, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _extractUserMessage(e),
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.urgency,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Extract user-friendly message from exception
  String _extractUserMessage(Object e) {
    final errorStr = e.toString().toLowerCase();

    if (errorStr.contains('no internet') ||
        errorStr.contains('socketexception') ||
        errorStr.contains('connection')) {
      return 'No internet connection';
    } else if (errorStr.contains('timeout')) {
      return 'Request timed out. Try again.';
    } else if (errorStr.contains('permission')) {
      return 'Permission denied';
    } else if (errorStr.contains('upload initiation failed')) {
      return 'Could not start upload';
    }

    return 'Failed to send. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    // 2026 UX: If showing checkmark, show ONLY the checkmark overlay
    // But inside a BottomSheet we might just want to overlay it or replace content.
    // Let's replace content for simplicity and clarity.

    final friendsAsync = ref.watch(friendsProvider);
    final isPreSelection = widget.isPreSelectionMode;

    return Column(
      children: [
        // 1. Handle & Header
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.cardBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  AppIcon(
                    isPreSelection
                        ? AppIcons
                              .friends // Pre-selection mode icon
                        : (widget.isAudioOnly ? AppIcons.mic : AppIcons.send),
                    color: AppColors.primaryAction,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isPreSelection
                        ? 'Select Recipients' // Pre-selection mode title
                        : (widget.isAudioOnly
                              ? 'Send Audio Vibe'
                              : 'Send Vibe'),
                    style: AppTypography.headlineSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // Action button changes based on mode
              if (_selectedIds.isNotEmpty)
                GestureDetector(
                  onTap: _isMainButtonLoading
                      ? null
                      : () {
                          if (isPreSelection) {
                            _handleSendWithFeedback(_selectedIds.toList());
                          } else {
                            _handleSendWithFeedback(_selectedIds.toList());
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryAction,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _isMainButtonLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textInverse,
                            ),
                          )
                        : _showCheckmark
                        ? AppIcon(
                            AppIcons.check,
                            color: AppColors.textInverse,
                            size: 20,
                          )
                        : Text(
                            isPreSelection
                                ? 'Done (${_selectedIds.length})' // Pre-selection mode
                                : 'Send (${_selectedIds.length})', // Send mode
                            style: AppTypography.buttonText.copyWith(
                              color: AppColors.textInverse,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
            ],
          ),
        ),

        // 2. Friend List
        Expanded(
          child: friendsAsync.when(
            data: (friends) {
              if (friends.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIcons.friends,
                        color: AppColors.textSecondary,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text('No friends yet', style: AppTypography.bodyMedium),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push('/add-friends');
                        },
                        icon: AppIcon(
                          AppIcons.addFriend,
                          color: AppColors.primaryAction,
                        ),
                        label: Text(
                          'Add Friends',
                          style: AppTypography.buttonText.copyWith(
                            color: AppColors.primaryAction,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              // SORTING: Active friends first ("Recents")
              final sortedFriends = List<UserModel>.from(friends)
                ..sort(
                  (a, b) => (b.lastActive ?? DateTime(0)).compareTo(
                    a.lastActive ?? DateTime(0),
                  ),
                );

              // Split: Top 4 are "Quick Send", rest are in the list
              final quickSendTargets = sortedFriends.take(4).toList();

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // A. Quick Send Row (The "Snapchat" Row) - Instant single-tap send
                  if (quickSendTargets.isNotEmpty) ...[
                    Text(
                      'RECENTS',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: quickSendTargets.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (context, index) {
                          final friend = quickSendTargets[index];
                          final isSelected = _selectedIds.contains(friend.id);
                          final isLoading = _loadingFriendId == friend.id;

                          return GestureDetector(
                            onTap: isLoading
                                ? null
                                : () {
                                    if (isPreSelection) {
                                      // PRE-SELECTION MODE: Toggle selection
                                      HapticFeedback.mediumImpact();
                                      setState(() {
                                        if (isSelected) {
                                          _selectedIds.remove(friend.id);
                                        } else {
                                          _selectedIds.add(friend.id);
                                        }
                                      });
                                    } else {
                                      // SEND MODE: Instant send with feedback
                                      _handleSendWithFeedback([
                                        friend.id,
                                      ], quickSendId: friend.id);
                                    }
                                  },
                            child: Column(
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: (isSelected || isLoading)
                                              ? AppColors
                                                    .primaryAction // Selected: bright border
                                              : AppColors.primaryAction
                                                    .withOpacity(0.3),
                                          width: (isSelected || isLoading)
                                              ? 3
                                              : 2,
                                        ),
                                      ),
                                      child: isLoading
                                          ? const Padding(
                                              padding: EdgeInsets.all(16.0),
                                              child: SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: AppColors
                                                          .primaryAction,
                                                    ),
                                              ),
                                            )
                                          : CircleAvatar(
                                              radius: 28,
                                              backgroundImage:
                                                  friend.avatarUrl != null
                                                  ? NetworkImage(
                                                      friend.avatarUrl!,
                                                    )
                                                  : null,
                                              backgroundColor:
                                                  AppColors.surfaceLight,
                                              child: friend.avatarUrl == null
                                                  ? Text(
                                                      friend.displayName[0]
                                                          .toUpperCase(),
                                                      style: AppTypography
                                                          .labelSmall
                                                          .copyWith(
                                                            color: AppColors
                                                                .textPrimary,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                    )
                                                  : null,
                                            ),
                                    ),
                                    // Selection checkmark badge
                                    if (isSelected && !isLoading)
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: const BoxDecoration(
                                            color: AppColors.primaryAction,
                                            shape: BoxShape.circle,
                                          ),
                                          child: AppIcon(
                                            AppIcons.check,
                                            size: 12,
                                            color: AppColors.textInverse,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  friend.displayName.trim().contains(' ')
                                      ? friend.displayName
                                            .trim()
                                            .split(' ')
                                            .first
                                      : friend.displayName
                                            .trim(), // Safer first name extraction
                                  style: AppTypography.bodySmall.copyWith(
                                    color: (isSelected || isLoading)
                                        ? AppColors.primaryAction
                                        : AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: (isSelected || isLoading)
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(color: AppColors.cardBorder, height: 32),
                  ],

                  // B. Multi-Select List (The "Broadcast" List) - Checkboxes for group send
                  Text(
                    'ALL FRIENDS',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...sortedFriends.map((friend) {
                    final isSelected = _selectedIds.contains(friend.id);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundImage: friend.avatarUrl != null
                            ? NetworkImage(friend.avatarUrl!)
                            : null,
                        backgroundColor: AppColors.surface,
                        child: friend.avatarUrl == null
                            ? Text(
                                friend.displayName[0].toUpperCase(),
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        friend.displayName,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: Checkbox(
                        value: isSelected,
                        activeColor: AppColors.primaryAction,
                        checkColor: AppColors.textInverse,
                        shape: const CircleBorder(),
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (val == true) {
                              _selectedIds.add(friend.id);
                            } else {
                              _selectedIds.remove(friend.id);
                            }
                          });
                        },
                      ),
                      onTap: () {
                        // Toggle selection on row tap
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (isSelected) {
                            _selectedIds.remove(friend.id);
                          } else {
                            _selectedIds.add(friend.id);
                          }
                        });
                      },
                    );
                  }),
                ],
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primaryAction),
            ),
            error: (err, _) => Center(
              child: Text(
                'Error: $err',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.urgency,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
