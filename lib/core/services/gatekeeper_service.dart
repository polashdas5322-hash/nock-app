import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vad/vad.dart';
import 'package:flutter/foundation.dart';

/// Gatekeeper Service - Local Voice Activity Detection (VAD)
///
/// POLICY: FAIL-CLOSED
/// If audio is corrupt, silent, or fails processing, this service returns NULL.
/// We do NOT upload garbage to the server. This protects:
/// 1. Backend stability (no corrupt files)
/// 2. OpenAI costs (no empty transcription requests)
/// 3. Data integrity (consistent format across all uploads)
class GatekeeperService {
  static final GatekeeperService instance = GatekeeperService._();
  GatekeeperService._();

  /// 🛡️ The Bouncer: Fail-Closed Voice Detection
  ///
  /// Returns [File] (WAV) if human speech is detected.
  /// Returns [null] if silent, noisy, or verification fails.
  ///
  /// Technical fixes applied:
  /// - FIX 1: `-c:a pcm_s16le` forces 16-bit Integer codec (prevents "Robot Noise" on iOS/Android)
  /// - FIX 2: `frameSamples: 512` syncs with our 1024-byte chunks (prevents "Skipped Frame" bug)
  /// - FIX 3: `executeAsync` prevents UI jank during compression
  Future<File?> hasSpeech(File mediaFile, {bool isVideo = false}) async {
    final tempDir = await getTemporaryDirectory();
    final String sessionKey = DateTime.now().millisecondsSinceEpoch.toString();
    final File wavFile = File('${tempDir.path}/gatekeeper_$sessionKey.wav');

    // Resource Management: Create handler here for safe disposal in finally block
    final VadHandler vadHandler = VadHandler.create(isDebug: kDebugMode);
    StreamSubscription? vadSubscription;

    try {
      // ---------------------------------------------------------
      // STEP 1: Robust Normalization (FFmpeg)
      // ---------------------------------------------------------
      // -vn          : Disable video (extract audio only)
      // -ar 16000    : Resample to 16kHz (REQUIRED by Silero VAD)
      // -ac 1        : Downmix to Mono (REQUIRED by Silero VAD)
      // -c:a pcm_s16le : FORCE 16-bit Signed Integer Little Endian
      //                  (CRITICAL: Prevents 32-bit float output on iOS)
      // -y           : Overwrite output file if exists
      // ---------------------------------------------------------
      final command =
          '-y -hwaccel auto -i "${mediaFile.path}" -vn -ar 16000 -ac 1 -c:a pcm_s16le "${wavFile.path}"';

      // FIX: Use executeAsync to prevent UI thread blocking on heavy files
      final ffmpegCompleter = Completer<bool>();

      await FFmpegKit.executeAsync(command, (session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          ffmpegCompleter.complete(true);
        } else {
          final logs = await session.getLogs();
          final lastLog = logs.isNotEmpty ? logs.last.getMessage() : 'No logs';
          debugPrint(
            'Gatekeeper: FFmpeg failed. Code: $returnCode, Last log: $lastLog',
          );
          ffmpegCompleter.complete(false);
        }
      });

      // FAIL-CLOSED: If FFmpeg fails, reject the file to protect backend
      if (!await ffmpegCompleter.future) {
        debugPrint(
          'Gatekeeper: Normalization failed. Rejecting upload (Fail-Closed).',
        );
        return null;
      }

      // ---------------------------------------------------------
      // STEP 2: Binary Validation (Isolate-offloaded)
      // ---------------------------------------------------------
      if (!await wavFile.exists()) return null;

      // FIX: Offload heavy file reading and sublisting to background isolate
      // This prevents the main thread from stalling on massive audio buffers
      final List<Uint8List> chunks = await compute(
        _chunkFileIsolate,
        wavFile.path,
      );

      if (chunks.isEmpty) {
        debugPrint('Gatekeeper: WAV file empty or too small.');
        try {
          await wavFile.delete();
        } catch (_) {}
        return null;
      }

      // ---------------------------------------------------------
      // STEP 3: VAD Analysis (Synchronized Frame Processing)
      // ---------------------------------------------------------
      final detectionCompleter = Completer<bool>();
      bool hasSpeech = false;

      // OPTIMIZATION: Early exit - stop immediately upon first speech detection
      vadSubscription = vadHandler.onSpeechStart.listen((_) {
        if (!hasSpeech) {
          hasSpeech = true;
          debugPrint('Gatekeeper: Speech detected! Early exit.');
          if (!detectionCompleter.isCompleted) {
            detectionCompleter.complete(true);
          }
        }
      });

      // Chunk size: 1024 bytes = 512 samples (16-bit = 2 bytes/sample)
      // This matches Silero VAD v5 requirements for 16kHz audio
      final audioStream = Stream<Uint8List>.fromIterable(chunks);

      await vadHandler.startListening(
        audioStream: audioStream,
        // CRITICAL FIX: Explicitly tell VAD we are sending 512 samples/chunk
        // Default is often 1536 (legacy), which would BREAK this stream
        frameSamples: 512,
        recordConfig: const RecordConfig(
          sampleRate: 16000,
          numChannels: 1,
          encoder: AudioEncoder.pcm16bits,
        ),
      );

      // TIMEOUT: 2x Duration Safety Buffer
      // Prevents hanging on slow devices or edge cases
      // Logic: Duration(ms) = (Bytes / 32) * 2 (Safety Factor) + 500ms buffer
      final totalBytes = chunks.fold<int>(
        0,
        (sum, chunk) => sum + chunk.length,
      );
      final processingTimeout = Duration(
        milliseconds: (totalBytes / 16).ceil() + 500,
      );

      try {
        await Future.any([
          detectionCompleter.future,
          Future.delayed(processingTimeout, () => false),
        ]);
      } catch (e) {
        debugPrint('Gatekeeper: VAD timeout or error: $e');
      }

      await vadHandler.stopListening();

      debugPrint('Gatekeeper: Speech detected = $hasSpeech');

      if (hasSpeech) {
        return wavFile; // ✅ Verified Speech - caller owns this file now
      } else {
        // Cleanup silent/rejected file to save storage
        try {
          await wavFile.delete();
        } catch (_) {}
        return null; // 🛑 Fail-Closed: No speech detected
      }
    } catch (e) {
      debugPrint('Gatekeeper: Critical Error: $e');
      // Ensure temp file is cleaned up on crash
      try {
        if (await wavFile.exists()) await wavFile.delete();
      } catch (_) {}
      return null; // 🛑 Fail-Closed on Exception
    } finally {
      // Resource Safety: Always dispose native resources
      await vadSubscription?.cancel();
      vadHandler.dispose();
    }
  }
}

/// FIX: Global static helper for 'compute' compatibility
/// Offloads binary I/O to background isolate
List<Uint8List> _chunkFileIsolate(String path) {
  try {
    final file = File(path);
    final bytes = file.readAsBytesSync();

    // Validate standard WAV header (44 bytes)
    if (bytes.length <= 44 + 3200) {
      // 44 header + 0.1s data
      return [];
    }

    // Extract Raw PCM Data (Skip WAV Header)
    final Uint8List audioBytes = bytes.sublist(44);

    // Chunk size: 1024 bytes = 512 samples
    final List<Uint8List> chunks = [];
    const int chunkSize = 1024;

    for (int i = 0; i < audioBytes.length; i += chunkSize) {
      int end = (i + chunkSize < audioBytes.length)
          ? i + chunkSize
          : audioBytes.length;
      chunks.add(audioBytes.sublist(i, end));
    }

    return chunks;
  } catch (e) {
    debugPrint('Gatekeeper: Isolate I/O error: $e');
    return [];
  }
}
