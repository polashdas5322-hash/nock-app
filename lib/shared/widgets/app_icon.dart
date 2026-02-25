import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// A strict icon wrapper that enforces the use of Phosphor Icons.
///
/// This widget should be used instead of the standard [Icon] widget
/// to ensure consistent techy/thin iconography across the app.
class AppIcon extends StatelessWidget {
  /// The icon data to display. Use [AppIcons] to provide this.
  final PhosphorIconData icon;

  /// The size of the icon.
  final double? size;

  /// The color of the icon.
  final Color? color;

  const AppIcon(this.icon, {super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    return PhosphorIcon(icon, size: size, color: color);
  }
}
