import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/friends_provider.dart';
import '../../../core/services/widget_update_service.dart';
import '../../../shared/widgets/glass_container.dart';

/// Modern BFF Widget Configuration Screen
/// 
/// Replaces the legacy BFFConfigActivity.kt with a fluid, visually rich 
/// interface that follows the 2025 "Liquid Glass" and "Aura" design trends.
class BFFConfigScreen extends ConsumerStatefulWidget {
  final int appWidgetId;

  const BFFConfigScreen({
    super.key,
    required this.appWidgetId,
  });

  @override
  ConsumerState<BFFConfigScreen> createState() => _BFFConfigScreenState();
}

class _BFFConfigScreenState extends ConsumerState<BFFConfigScreen> {
  String _searchQuery = '';
  String? _selectedFriendId;

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.background,
      appBar: _buildLiquidAppBar(),
      body: Stack(
        children: [
          // Aura Background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: AppColors.darkGradient,
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                _buildSearchBar(),
                const SizedBox(height: 16),
                Expanded(
                  child: friendsAsync.when(
                    data: (friends) {
                      // Hick's Law: Filter and Sort
                      final filtered = friends
                          .where((f) => f.displayName
                              .toLowerCase()
                              .contains(_searchQuery.toLowerCase()))
                          .toList();

                      // Sort by activity mapping (if friendship data was available)
                      // For now, we just show the alphabetic or default order from DB

                      if (filtered.isEmpty) {
                        return _buildEmptyState();
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          return _buildFriendCard(filtered[index]);
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.primaryAction),
                    ),
                    error: (e, _) => Center(
                      child: Text('Error: $e', style: AppTypography.bodyMedium),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildLiquidAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: Text(
        "Pick your BFF",
        style: AppTypography.headlineMedium.copyWith(
          fontFamily: 'Outfit', // Using Outfit as requested for modern feel
          letterSpacing: -0.5,
        ),
      ),
      centerTitle: true,
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: AppColors.background.withOpacity(0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: TextField(
        style: const TextStyle(color: Colors.white),
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: "Search your squad...",
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
        ),
      ),
    );
  }

  Widget _buildFriendCard(UserModel friend) {
    final isSelected = _selectedFriendId == friend.id;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutQuint,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryAction.withOpacity(0.1) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? AppColors.primaryAction.withOpacity(0.5) : Colors.white.withOpacity(0.05),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () async {
              HapticFeedback.selectionClick();
              setState(() => _selectedFriendId = friend.id);
              
              // Save to Native Widget via HomeWidget
              await _saveFriendToWidget(friend);
              
              // Delay slightly for animation
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) {
                   Navigator.of(context).pop();
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: friend.avatarUrl != null
                          ? DecorationImage(
                              image: NetworkImage(friend.avatarUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                      gradient: friend.avatarUrl == null ? AppColors.primaryGradient : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friend.displayName,
                          style: AppTypography.labelLarge.copyWith(
                            color: isSelected ? AppColors.primaryAction : Colors.white,
                          ),
                        ),
                        if (friend.username != null)
                          Text(
                            "@${friend.username}",
                            style: AppTypography.caption,
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected ? AppColors.primaryAction : Colors.white.withOpacity(0.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            "No friends found",
            style: AppTypography.headlineSmall.copyWith(color: Colors.white.withOpacity(0.5)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveFriendToWidget(UserModel friend) async {
    // Ported from BFFConfigActivity.kt logic
    final keyPrefix = "widget_${widget.appWidgetId}";
    
    await Future.wait([
      HomeWidget.saveWidgetData<String>('${keyPrefix}_friendId', friend.id),
      HomeWidget.saveWidgetData<String>('${keyPrefix}_name', friend.displayName),
      HomeWidget.saveWidgetData<String>('${keyPrefix}_avatar', friend.avatarUrl ?? ''),
    ]);

    // Update the widget
    await HomeWidget.updateWidget(
      name: 'BFFWidgetProvider',
    );

    // Communicate back to native to finish configuration
    const widgetChannel = MethodChannel('com.nock.nock/widget');
    await widgetChannel.invokeMethod('finishConfig', {
      'appWidgetId': widget.appWidgetId,
    });
  }
}
