import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache Cleanup Service
/// 
/// Prevents storage bloat by automatically cleaning up old cached files.
/// Audio/image files downloaded for widget previews are cleaned after 24 hours.
class CacheCleanupService {
  static const String _lastCleanupKey = 'last_cache_cleanup';
  static const Duration _cleanupInterval = Duration(hours: 12);
  static const Duration _fileExpiry = Duration(hours: 48); // Extended from 24h
  static const int _maxCacheSize = 500 * 1024 * 1024; // 500MB limit
  
  /// Initialize and run cleanup if needed
  Future<void> initialize() async {
    await _runCleanupIfNeeded();
  }

  /// Run cleanup if it hasn't been done recently
  Future<void> _runCleanupIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCleanup = prefs.getInt(_lastCleanupKey) ?? 0;
    final lastCleanupTime = DateTime.fromMillisecondsSinceEpoch(lastCleanup);
    
    if (DateTime.now().difference(lastCleanupTime) > _cleanupInterval) {
      await cleanupCache();
      await prefs.setInt(_lastCleanupKey, DateTime.now().millisecondsSinceEpoch);
    }
  }

  /// Clean up old cached files
  Future<CleanupResult> cleanupCache() async {
    int filesDeleted = 0;
    int bytesFreed = 0;
    
    try {
      final tempDir = await getTemporaryDirectory();
      
      // Clean up share/export files
      // CRITICAL: Include ALL temp file patterns to prevent storage bloat
      filesDeleted += await _cleanupDirectory(
        Directory('${tempDir.path}'),
        patterns: [
          'vibe_share_', 
          'vibe_audio_', 
          'share_image_', 
          'share_audio_', 
          'temp_',
          'vibe_recording_',  // Voice note recordings (sent or cancelled)
          'vibe_invite_',     // Invite card images
          'vibe_viral_',      // FFmpeg generated videos (Heavy!)
          'vibe_shared_video_', // Downloaded shared videos
          'viral_image_',     // Asset downloads for generation
          'viral_audio_',     // Asset downloads for generation
          'vibe_thumbnail_',  // Video thumbnails
          'vibe_overlay_',    // Transparent overlay PNGs
          'vibe_video_overlay_', // Composited video files
          'flutter_sound',    // Raw recording buffers from flutter_sound
          'gatekeeper_',      // Temporary VAD files
        ],
        expiry: _fileExpiry,
        onDelete: (size) => bytesFreed += size,
      );
      
      // Clean up app cache
      try {
        final cacheDir = await getApplicationCacheDirectory();
        filesDeleted += await _cleanupDirectory(
          cacheDir,
          patterns: [
            'vibe_', 
            'temp_', 
            'share_',
            'libCachedImageData', // cached_network_image storage
            'flutter_sound',
          ],
          expiry: _fileExpiry,
          onDelete: (size) => bytesFreed += size,
        );
      } catch (e) {
        debugPrint('CacheCleanup: Cache directory cleanup failed: $e');
      }
      
      debugPrint('CacheCleanup: Deleted $filesDeleted files, freed ${_formatBytes(bytesFreed)}');
      
      return CleanupResult(
        success: true,
        filesDeleted: filesDeleted,
        bytesFreed: bytesFreed,
      );
    } catch (e) {
      debugPrint('CacheCleanup: Error during cleanup: $e');
      return CleanupResult(
        success: false,
        filesDeleted: filesDeleted,
        bytesFreed: bytesFreed,
        error: e.toString(),
      );
    }
  }

  /// Clean up files in a directory using LRU strategy
  Future<int> _cleanupDirectory(
    Directory directory, {
    List<String> patterns = const [],
    required Duration expiry,
    void Function(int size)? onDelete,
  }) async {
    int count = 0;
    
    if (!await directory.exists()) return 0;
    
    final now = DateTime.now();
    List<FileStatWithName> fileStats = [];
    
    // 1. Collect all matching files and their stats (Recursive scan!)
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        try {
          final fileName = entity.path.split('/').last;
          bool matchesPattern = patterns.isEmpty || 
              patterns.any((p) => fileName.contains(p));
          
          if (!matchesPattern) continue;
          
          final stat = await entity.stat();
          fileStats.add(FileStatWithName(
            path: entity.path,
            stat: stat,
          ));
        } catch (e) {
          debugPrint('CacheCleanup: Error stating ${entity.path}: $e');
        }
      }
    }

    // 2. Initial Cleanup: Delete expired files (older than _fileExpiry)
    for (var i = fileStats.length - 1; i >= 0; i--) {
      final f = fileStats[i];
      if (now.difference(f.stat.modified) > expiry) {
        try {
          final file = File(f.path);
          final size = f.stat.size;
          await file.delete();
          count++;
          onDelete?.call(size);
          fileStats.removeAt(i);
          debugPrint('CacheCleanup: Expired ${f.path}');
        } catch (_) {}
      }
    }

    // 3. LRU Cleanup: Sort by modification time (oldest first)
    fileStats.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    
    // 4. Size-based Eviction: Ensure total size < _maxCacheSize
    int currentTotalSize = fileStats.fold(0, (sum, f) => sum + f.stat.size);
    
    while (currentTotalSize > _maxCacheSize && fileStats.isNotEmpty) {
      final oldest = fileStats.removeAt(0);
      try {
        final file = File(oldest.path);
        final size = oldest.stat.size;
        await file.delete();
        count++;
        currentTotalSize -= size;
        onDelete?.call(size);
        debugPrint('CacheCleanup: LRU Evicted ${oldest.path} (${_formatBytes(size)})');
      } catch (e) {
        debugPrint('CacheCleanup: Failed to evict ${oldest.path}: $e');
      }
    }
    
    return count;
  }

  /// Force immediate cleanup (for settings or manual trigger)
  Future<CleanupResult> forceCleanup() async {
    final result = await cleanupCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCleanupKey, DateTime.now().millisecondsSinceEpoch);
    return result;
  }

  /// 🧹 FORCE WIPE: Completely delete ALL temporary and cached files.
  /// Used for forensic scrubbing during account deletion.
  Future<CleanupResult> forceWipe() async {
    int filesDeleted = 0;
    int bytesFreed = 0;
    
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = await getApplicationCacheDirectory();
      
      // Wipe everything in temp
      await for (final entity in tempDir.list(recursive: true)) {
        if (entity is File) {
          try {
            final size = (await entity.stat()).size;
            await entity.delete();
            filesDeleted++;
            bytesFreed += size;
          } catch (_) {}
        }
      }
      
      // Wipe everything in cache
      if (await cacheDir.exists()) {
        await for (final entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            try {
              final size = (await entity.stat()).size;
              await entity.delete();
              filesDeleted++;
              bytesFreed += size;
            } catch (_) {}
          }
        }
      }
      
      debugPrint('CacheCleanup: FORCE WIPE COMPLETE. Deleted $filesDeleted files.');
      
      return CleanupResult(
        success: true,
        filesDeleted: filesDeleted,
        bytesFreed: bytesFreed,
      );
    } catch (e) {
      debugPrint('CacheCleanup: Force wipe failed: $e');
      return CleanupResult(
        success: false,
        filesDeleted: filesDeleted,
        bytesFreed: bytesFreed,
        error: e.toString(),
      );
    }
  }

  /// Get current cache size
  Future<CacheInfo> getCacheInfo() async {
    int totalSize = 0;
    int fileCount = 0;
    
    try {
      final tempDir = await getTemporaryDirectory();
      final result = await _getDirectorySize(tempDir);
      totalSize += result.size;
      fileCount += result.count;
      
      try {
        final cacheDir = await getApplicationCacheDirectory();
        final cacheResult = await _getDirectorySize(cacheDir);
        totalSize += cacheResult.size;
        fileCount += cacheResult.count;
      } catch (e) {
        // Cache directory might not exist
      }
    } catch (e) {
      debugPrint('CacheCleanup: Error getting cache info: $e');
    }
    
    return CacheInfo(
      totalSize: totalSize,
      fileCount: fileCount,
      formattedSize: _formatBytes(totalSize),
    );
  }

  Future<({int size, int count})> _getDirectorySize(Directory dir) async {
    int size = 0;
    int count = 0;
    
    if (!await dir.exists()) return (size: 0, count: 0);
    
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        try {
          final stat = await entity.stat();
          size += stat.size;
          count++;
        } catch (e) {
          // Skip inaccessible files
        }
      }
    }
    
    return (size: size, count: count);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Helper class for file stats
class FileStatWithName {
  final String path;
  final FileStat stat;
  
  FileStatWithName({required this.path, required this.stat});
}

/// Result of a cache cleanup operation
class CleanupResult {
  final bool success;
  final int filesDeleted;
  final int bytesFreed;
  final String? error;

  CleanupResult({
    required this.success,
    required this.filesDeleted,
    required this.bytesFreed,
    this.error,
  });

  String get formattedBytesFreed {
    if (bytesFreed < 1024) return '$bytesFreed B';
    if (bytesFreed < 1024 * 1024) return '${(bytesFreed / 1024).toStringAsFixed(1)} KB';
    if (bytesFreed < 1024 * 1024 * 1024) return '${(bytesFreed / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytesFreed / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Information about current cache state
class CacheInfo {
  final int totalSize;
  final int fileCount;
  final String formattedSize;

  CacheInfo({
    required this.totalSize,
    required this.fileCount,
    required this.formattedSize,
  });
}

/// Cache cleanup service provider
final cacheCleanupServiceProvider = Provider<CacheCleanupService>((ref) {
  return CacheCleanupService();
});
