import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Helper to communicate with native platform services
class NativeServiceHelper {
  static const _platform = MethodChannel('com.nock.nock/audio_control');

  /// Stops the NockAudioService on Android to free up hardware resources (Mic).
  /// This is crucial before initializing the Camera to prevent hangs.
  static Future<void> stopBackgroundService() async {
    if (Platform.isAndroid) {
      try {
        debugPrint('🔑 Requesting native service stop to free resources...');
        await _platform.invokeMethod('stopNockAudioService');
      } on PlatformException catch (e) {
        debugPrint('❌ Error stopping native service: ${e.message}');
      }
    }
  }
}
