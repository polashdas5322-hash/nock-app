import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Background Upload Service
/// 
/// Provides a "Short-lived" native bridge to ensure uploads finish
/// even if the app is swiped away or backgrounded.
/// 
/// Uses:
/// - Android: Expedited Jobs (WorkManager) / User-Initiated Data Transfer
/// - iOS: BGContinuedProcessingTask (iOS 19+) + URLSession background
class BackgroundUploadService {
  static const MethodChannel _channel = MethodChannel('com.nock.nock/background_upload');

  /// Start a "Short-lived" background task
  /// This tells the OS to give the app ~3-5 minutes of survival time.
  static Future<String?> startTask({
    required String title,
    required String subtitle,
  }) async {
    try {
      final String? taskId = await _channel.invokeMethod('startBackgroundTask', {
        'title': title,
        'subtitle': subtitle,
      });
      debugPrint('🛡️ BackgroundUpload: Task started - $taskId');
      return taskId;
    } catch (e) {
      debugPrint('⚠️ BackgroundUpload: Failed to start task: $e');
      return null;
    }
  }

  /// Update the progress of the background task (Visible in Live Activities/Notifications)
  static Future<void> updateProgress(String taskId, double fraction, String subtitle) async {
    try {
      await _channel.invokeMethod('updateTaskProgress', {
        'taskId': taskId,
        'fraction': fraction,
        'subtitle': subtitle,
      });
    } catch (e) {
       debugPrint('⚠️ BackgroundUpload: Failed to update progress: $e');
    }
  }

  /// End the background task
  /// MUST be called once the upload finishes or fails.
  static Future<void> stopTask(String? taskId) async {
    if (taskId == null) return;
    try {
      await _channel.invokeMethod('stopBackgroundTask', {
        'taskId': taskId,
      });
      debugPrint('🛡️ BackgroundUpload: Task stopped - $taskId');
    } catch (e) {
      debugPrint('⚠️ BackgroundUpload: Failed to stop task: $e');
    }
  }
}
