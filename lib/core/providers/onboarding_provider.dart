import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for onboarding state
final onboardingStateProvider =
    StateNotifierProvider<OnboardingStateNotifier, AsyncValue<bool>>((ref) {
      return OnboardingStateNotifier();
    });

class OnboardingStateNotifier extends StateNotifier<AsyncValue<bool>> {
  OnboardingStateNotifier() : super(const AsyncValue.loading()) {
    _loadState();
  }

  static const String _onboardingCompletedKey = 'onboarding_completed';

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(_onboardingCompletedKey) ?? false;
      state = AsyncValue.data(completed);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> completeOnboarding() async {
    state = const AsyncValue.loading();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingCompletedKey, true);
      state = const AsyncValue.data(true);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> resetOnboarding() async {
    state = const AsyncValue.loading();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_onboardingCompletedKey);
      state = const AsyncValue.data(false);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
