import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/shared/widgets/glass_container.dart';
import 'package:nock/core/constants/app_constants.dart';
import '../../../core/services/subscription_service.dart';

/// Subscription Screen - Premium upgrade paywall
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _isLoading = false;
  String _selectedProductId = AppConstants.subscriptionMonthlyId;

  Future<void> _handleRestore() async {
    setState(() => _isLoading = true);
    try {
      final isPremium = await ref.read(subscriptionServiceProvider).restorePurchases();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPremium 
              ? 'Purchases restored successfully! Access granted.' 
              : 'No active subscriptions found to restore.'),
          ),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error restoring purchases: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSubscribe() async {
    setState(() => _isLoading = true);
    try {
      final isPremium = await ref.read(subscriptionServiceProvider).purchasePackage(_selectedProductId);
      if (isPremium && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Welcome to VIBE+! Your memories are now safe.')),
        );
        context.pop();
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidNavy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
        leading: TextButton(
          onPressed: _isLoading ? null : _handleRestore,
          child: const Text(
            'Restore Purchases',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        leadingWidth: 120,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(),
                      
                      // Logo
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [AppColors.primaryAction, AppColors.secondaryAction],
                        ).createShader(bounds),
                        child: Text(
                          'VIBE+',
                          style: AppTypography.displayLarge.copyWith(height: 1.0),
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Features - Loss Aversion Messaging
                      _buildFeature(Icons.history, 'Don\'t let your history fade'),
                      _buildFeature(Icons.all_inclusive, 'Unlock all memories in the vault'),
                      _buildFeature(Icons.verified_user, 'Preserve your moments forever'),
                      _buildFeature(Icons.auto_awesome, 'Coming Soon: Retro Rewinds'),
                      
                      const Spacer(),
                      
                      // Tier Selection
                      Row(
                        children: [
                          _buildTierCard(
                            id: AppConstants.subscriptionWeeklyId,
                            title: 'Weekly',
                            price: '\$0.99',
                            subtitle: 'Impulse Pass',
                          ),
                          const SizedBox(width: 12),
                          _buildTierCard(
                            id: AppConstants.subscriptionMonthlyId,
                            title: 'Monthly',
                            price: '\$4.99',
                            subtitle: 'Popular',
                            isPopular: true,
                          ),
                          const SizedBox(width: 12),
                          _buildTierCard(
                            id: AppConstants.subscriptionAnnualId,
                            title: 'Annual',
                            price: '\$29.99',
                            subtitle: 'Best Value',
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      Text(
                        'Preserve your history. One tap to unlock.',
                        style: AppTypography.bodySmall.copyWith(color: Colors.white70),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Subscribe button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleSubscribe,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondaryAction,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 8,
                            shadowColor: AppColors.secondaryAction.withValues(alpha: 0.5),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _selectedProductId == AppConstants.subscriptionAnnualId 
                                      ? 'Secure My Memories' 
                                      : 'Unlock Memory Vault',
                                  style: AppTypography.headlineMedium.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Legal Links - Required by App Store
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _isLoading ? null : _handleRestore,
                            child: const Text(
                              'Restore Purchases',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          GestureDetector(
                            onTap: () {
                              // TODO: Open Terms
                            },
                            child: const Text(
                              'Terms of Service',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          GestureDetector(
                            onTap: () {
                              // TODO: Open Privacy
                            },
                            child: const Text(
                              'Privacy Policy',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryAction.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primaryAction, size: 24),
          ),
          const SizedBox(width: 16),
          Text(
            text,
            style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCard({
    required String id,
    required String title,
    required String price,
    required String subtitle,
    bool isPopular = false,
  }) {
    final isSelected = _selectedProductId == id;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedProductId = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected 
              ? AppColors.primaryAction.withOpacity(0.1) 
              : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected 
                ? AppColors.primaryAction 
                : Colors.white.withOpacity(0.1),
              width: 2,
            ),
          ),
          child: Column(
            children: [
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryAction,
                    borderRadius: BorderRadius.circular(4),
                  ),
                    child: const Text(
                      'POPULAR',
                      style: TextStyle(
                        color: AppColors.voidNavy, // âœ¨ Consistency
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ),
              Text(
                title,
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                price,
                style: AppTypography.headlineSmall.copyWith(
                  fontWeight: FontWeight.w900,
                  color: isSelected ? AppColors.primaryAction : Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
