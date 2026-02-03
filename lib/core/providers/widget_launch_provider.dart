import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter/foundation.dart';

final widgetLaunchProvider = FutureProvider<Uri?>((ref) async {
  try {
    return await HomeWidget.initiallyLaunchedFromHomeWidget();
  } catch (e) {
    debugPrint('Error checking widget launch: $e');
    return null;
  }
});
