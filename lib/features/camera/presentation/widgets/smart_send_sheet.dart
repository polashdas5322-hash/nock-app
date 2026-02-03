import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/models/user_model.dart';
import 'package:nock/features/squad/presentation/squad_screen.dart';

/// Features:
/// - Quick Send Row: Recent/active friends for instant single-tap sending
/// - Multi-Select List: Checkboxes for group broadcasting
/// 
/// UPDATE: Now implements "Spinner -> Checkmark" Industry Standard Feedback Loop
class SmartSendSheet extends ConsumerStatefulWidget {
  final bool isAudioOnly;
  final bool isPreSelectionMode; // True when accessed from Face Pile before capture
  final Set<String> initialSelectedIds; // Preserve previous selections
  final Future<String?> Function(String)? onSendToOne; // MUST return Task ID
  final Future<List<String?>> Function(List<String>)? onSendToMany; // For bulk send, returns list of Task IDs
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
  String? _loadingFriendId; // Which friend is currently being sent to (Quick Row)
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
  Future<void> _handleSendWithFeedback(List<String> recipients, {String? quickSendId}) async {
    if (recipients.isEmpty) return;
    
    // In Pre-Selection mode, we don't send updates, just return
    if (widget.isPreSelectionMode) {
      widget.onPreSelect?.call(_selectedIds);
      Navigator.pop(context);
      return;
    }

    HapticFeedback.heavyImpact(); // Initial tap feedback

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
        HapticFeedback.mediumImpact(); // Success haptic
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to send: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 2026 UX: If showing checkmark, show ONLY the checkmark overlay
    // But inside a BottomSheet we might just want to overlay it or replace content.
    // Let's replace content for simplicity and clarity.
    if (_showCheckmark) {
      return Container(
        height: 300,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.check_circle_rounded, color: AppColors.primaryAction, size: 80),
            SizedBox(height: 16),
            Text(
              'Sent!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      );
    }
  
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
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                   Icon(
                    isPreSelection 
                        ? Icons.people_rounded  // Pre-selection mode icon
                        : (widget.isAudioOnly ? Icons.mic : Icons.send_rounded),
                    color: AppColors.primaryAction,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isPreSelection 
                        ? 'Select Recipients'  // Pre-selection mode title
                        : (widget.isAudioOnly ? 'Send Audio Vibe' : 'Send Vibe'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // Action button changes based on mode
              if (_selectedIds.isNotEmpty)
                GestureDetector(
                  onTap: _isMainButtonLoading ? null : () {
                    if (isPreSelection) {
                      _handleSendWithFeedback(_selectedIds.toList());
                    } else {
                      _handleSendWithFeedback(_selectedIds.toList());
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryAction,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _isMainButtonLoading
                     ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) 
                     : Text(
                      isPreSelection 
                          ? 'Done (${_selectedIds.length})'  // Pre-selection mode
                          : 'Send (${_selectedIds.length})',  // Send mode
                      style: const TextStyle(
                        color: Colors.black,
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
                      const Icon(Icons.people_outline, color: Colors.grey, size: 48),
                      const SizedBox(height: 16),
                      const Text('No friends yet', style: TextStyle(color: Colors.white54)),
                      const SizedBox(height: 12),
                       TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push('/add-friends');
                        },
                        icon: const Icon(Icons.person_add, color: AppColors.primaryAction),
                        label: const Text('Add Friends', style: TextStyle(color: AppColors.primaryAction)),
                      ),
                    ],
                  ),
                );
              }

              // SORTING: Active friends first ("Recents")
              final sortedFriends = List<UserModel>.from(friends)
                ..sort((a, b) => (b.lastActive ?? DateTime(0)).compareTo(a.lastActive ?? DateTime(0)));

              // Split: Top 4 are "Quick Send", rest are in the list
              final quickSendTargets = sortedFriends.take(4).toList();

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // A. Quick Send Row (The "Snapchat" Row) - Instant single-tap send
                  if (quickSendTargets.isNotEmpty) ...[
                    const Text(
                      'RECENTS',
                      style: TextStyle(
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
                            onTap: isLoading ? null : () {
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
                                _handleSendWithFeedback([friend.id], quickSendId: friend.id);
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
                                              ? AppColors.primaryAction  // Selected: bright border
                                              : AppColors.primaryAction.withOpacity(0.3),
                                          width: (isSelected || isLoading) ? 3 : 2,
                                        ),
                                      ),
                                      child: isLoading
                                       ? const Padding(
                                           padding: EdgeInsets.all(16.0),
                                            child: SizedBox(
                                              width: 24, height: 24,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryAction)
                                            ),
                                         )
                                       : CircleAvatar(
                                        radius: 28,
                                        backgroundImage: friend.avatarUrl != null
                                            ? NetworkImage(friend.avatarUrl!)
                                            : null,
                                        backgroundColor: Colors.grey[800],
                                        child: friend.avatarUrl == null
                                            ? Text(
                                                friend.displayName[0].toUpperCase(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
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
                                          child: const Icon(
                                            Icons.check,
                                            size: 12,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  friend.displayName.trim().contains(' ') 
                                      ? friend.displayName.trim().split(' ').first 
                                      : friend.displayName.trim(), // Safer first name extraction
                                  style: TextStyle(
                                    color: (isSelected || isLoading) ? AppColors.primaryAction : Colors.white,
                                    fontSize: 12,
                                    fontWeight: (isSelected || isLoading) ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 32),
                  ],

                  // B. Multi-Select List (The "Broadcast" List) - Checkboxes for group send
                  const Text(
                    'ALL FRIENDS',
                    style: TextStyle(
                      color: Colors.white54,
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
                        backgroundColor: Colors.grey[800],
                        child: friend.avatarUrl == null
                            ? Text(
                                friend.displayName[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              )
                            : null,
                      ),
                      title: Text(
                        friend.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      trailing: Checkbox(
                        value: isSelected,
                        activeColor: AppColors.primaryAction,
                        checkColor: Colors.black,
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
              child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
            ),
          ),
        ),
      ],
    );
  }
}
