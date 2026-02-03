import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Storage Hygiene Service
///
/// Responsible for cleaning up orphaned temporary files, specifically
/// "ghost recordings" that were abandoned due to app termination or crashes.
class StorageHygieneService {
  static const String _ghostPrefix = 'ghost_rec_';
  static const Duration _maxFileAge = Duration(hours: 24);

  /// Scans the cache directory for abandoned recording files and deletes them.
  /// Should be called in main() before runApp() or during initialization.
  static Future<void> cleanOrphanedRecordings() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      
      if (!await dir.exists()) return;

      final now = DateTime.now();
      int deletedCount = 0;
      int reclaimedBytes = 0;
      
      await for (final entity in dir.list()) {
        if (entity is File) {
          final filename = p.basename(entity.path);
          
          // Match files created by the ghost recording logic
          // Checks for both ghost prefix AND standard mp4 extension
          if (filename.startsWith(_ghostPrefix) && filename.endsWith('.mp4')) {
            try {
              final stat = await entity.stat();
              
              // Delete if older than 24 hours (safety buffer for active sessions)
              if (now.difference(stat.modified) > _maxFileAge) {
                final size = stat.size;
                await entity.delete();
                deletedCount++;
                reclaimedBytes += size;
                debugPrint("StorageHygiene: Deleted orphan file $filename (${(size / 1024 / 1024).toStringAsFixed(2)} MB)");
              }
            } catch (e) {
              debugPrint("StorageHygiene: Failed to process $filename: $e");
            }
          }
        }
      }
      
      if (deletedCount > 0) {
        debugPrint("StorageHygiene: Cleanup complete. Removed $deletedCount files, reclaimed ${(reclaimedBytes / 1024 / 1024).toStringAsFixed(2)} MB.");
      }
    } catch (e) {
      debugPrint("StorageHygiene: Service error: $e");
    }
  }
}
