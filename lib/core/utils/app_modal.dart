import 'package:flutter/material.dart';
import 'package:nock/shared/widgets/vibe_bottom_sheet.dart';

class AppModal {
  AppModal._();

  /// Standard bottom sheet presentation with 2026 aesthetics
  /// - Solid AppColors.surface background
  /// - 24px top corner radius
  /// - Custom child wrapper in VibeBottomSheet for standardized handle
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool isScrollControlled = true,
    bool useRootNavigator = false,
    bool isDismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      backgroundColor: Colors.transparent, // Handled by VibeBottomSheet
      barrierColor: Colors.black54,
      elevation: 0,
      builder: (context) => VibeBottomSheet(child: child),
    );
  }
}
