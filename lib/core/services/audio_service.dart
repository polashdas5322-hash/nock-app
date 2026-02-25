import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nock/core/constants/app_constants.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:audio_session/audio_session.dart' as session;

/// Global "Hardware Manager" - The Source of Truth
/// Holds the ID of the content (vibeId) that currently claims the speakers.
final activeContentIdProvider = StateProvider<String?>((ref) => null);

/// Scoped Audio Player (One per widget/screen)
/// Automatically handles cleanup/stopping when a new piece of content takes over.
final scopedAudioPlayerProvider = Provider.autoDispose
    .family<AudioPlayer, String>((ref, contentId) {
      final player = AudioPlayer();

      // LOGIC: If the global active ID changes to something else, WE must stop.
      ref.listen(activeContentIdProvider, (previous, next) {
        if (next != contentId) {
          player.stop(); // Release resources immediately
        }
      });

      ref.onDispose(() {
        player.dispose();
      });

      return player;
    });

/// Audio Recording State
enum RecordingState { idle, recording, paused, stopped }

/// Audio Playback State
enum PlaybackState { idle, loading, playing, paused, completed }

/// Recording State Notifier
final recordingStateProvider =
    StateNotifierProvider<RecordingStateNotifier, RecordingState>((ref) {
      return RecordingStateNotifier(ref);
    });

/// Current recording duration
final recordingDurationProvider = StateProvider<int>((ref) => 0);

/// Waveform data during recording
final waveformDataProvider = StateProvider<List<double>>((ref) => []);

/// Audio Service Provider
final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();

  // Sync player state to Riverpod provider
  service.player.onPlayerStateChanged.listen((playerState) {
    PlaybackState newState;
    switch (playerState) {
      case PlayerState.playing:
        newState = PlaybackState.playing;
        break;
      case PlayerState.paused:
        newState = PlaybackState.paused;
        break;
      case PlayerState.completed:
        newState = PlaybackState.completed;
        break;
      default:
        newState = PlaybackState.idle;
    }
    ref.read(playbackStateProvider.notifier).state = newState;
  });

  ref.onDispose(service.dispose);
  return service;
});

/// Playback state provider
final playbackStateProvider = StateProvider<PlaybackState>(
  (ref) => PlaybackState.idle,
);

/// Current playback position
final playbackPositionProvider = StateProvider<Duration>(
  (ref) => Duration.zero,
);

/// Total audio duration
final totalDurationProvider = StateProvider<Duration>((ref) => Duration.zero);

class RecordingStateNotifier extends StateNotifier<RecordingState> {
  final Ref _ref;
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;
  Timer? _durationTimer;
  bool _isMonitoring = false; // FIX: Flag to stop amplitude monitor loop

  RecordingStateNotifier(this._ref) : super(RecordingState.idle);

  String? get currentPath => _currentPath;

  /// Start recording
  Future<bool> startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        return false;
      }

      // CRITICAL: Clear previous recording data before starting new one
      _ref.read(recordingDurationProvider.notifier).state = 0;
      _ref.read(waveformDataProvider.notifier).state = [];

      // Get temp directory for recording
      final tempDir = await getTemporaryDirectory();
      _currentPath = path.join(
        tempDir.path,
        'vibe_recording_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );

      // Configure recording
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentPath!,
      );

      state = RecordingState.recording;
      _startDurationTimer();
      _startAmplitudeMonitor();

      return true;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      return false;
    }
  }

  /// Stop recording
  Future<String?> stopRecording() async {
    // 🛡️ STABILITY FIX: Only stop if we are actually recording or paused
    // Prevents "Stop() called but track is not started" native warnings
    if (state != RecordingState.recording && state != RecordingState.paused) {
      debugPrint(
        'RecordingStateNotifier: stopRecording called while not active. Skipping.',
      );
      return null;
    }

    try {
      // FIX: Cancel timer BEFORE stopping to prevent state updates on disposed widget
      _durationTimer?.cancel();
      _durationTimer = null;
      _isMonitoring = false; // Stop amplitude loop

      final path = await _recorder.stop();
      state = RecordingState.stopped;
      // NOTE: We no longer clear duration/waveform here
      // so the UI can send the data!
      return path;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      return null;
    }
  }

  /// Cancel recording
  Future<void> cancelRecording() async {
    try {
      await _recorder.stop();
      // Delete the file
      if (_currentPath != null) {
        final file = File(_currentPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      state = RecordingState.idle;
      _ref.read(recordingDurationProvider.notifier).state = 0;
      _ref.read(waveformDataProvider.notifier).state = [];
    } catch (e) {
      debugPrint('Error canceling recording: $e');
    }
  }

  void _startDurationTimer() {
    // CRITICAL FIX: Use Timer.periodic instead of while loop with Future.delayed
    // Future.delayed is "at least" 1 second, causing drift over time.
    // Timer.periodic ticks at consistent intervals for accurate UI sync.
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state != RecordingState.recording) {
        timer.cancel();
        return;
      }

      _ref.read(recordingDurationProvider.notifier).state++;

      // Auto-stop at max duration
      if (_ref.read(recordingDurationProvider) >=
          AppConstants.maxVoiceNoteDuration) {
        timer.cancel();
        stopRecording();
      }
    });
  }

  void _startAmplitudeMonitor() async {
    _isMonitoring = true;
    while (_isMonitoring && state == RecordingState.recording) {
      try {
        // FIX: Check flag before each state update to prevent defunct element errors
        if (!_isMonitoring) return;

        final amplitude = await _recorder.getAmplitude();
        final normalized = ((amplitude.current + 60) / 60).clamp(0.0, 1.0);

        // FIX: Double-check before state update
        if (!_isMonitoring) return;

        final currentWaveform = [..._ref.read(waveformDataProvider)];
        currentWaveform.add(normalized);

        // Keep ALL samples for accurate visualization and storage
        // UI components will downsample as needed

        // FIX: Triple-check before state update
        if (!_isMonitoring) return;
        _ref.read(waveformDataProvider.notifier).state = currentWaveform;
      } catch (e) {
        // Ignore amplitude errors
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _isMonitoring = false; // Stop amplitude loop on dispose
    _recorder.dispose();
    super.dispose();
  }
}

/// Audio playback service
class AudioService {
  final AudioPlayer _player = AudioPlayer();

  AudioPlayer get player => _player;

  /// Play audio from URL
  Future<void> playFromUrl(String url) async {
    try {
      await _player.play(UrlSource(url));
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  /// Play audio from file
  Future<void> playFromFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await _player.play(DeviceFileSource(path));
      } else {
        debugPrint('AudioService: File not found: $path');
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  /// Pause playback
  Future<void> pause() async {
    await _player.pause();
  }

  /// Resume playback
  Future<void> resume() async {
    await _player.resume();
  }

  /// Stop playback
  Future<void> stop() async {
    await _player.stop();
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Get current position stream
  Stream<Duration> get positionStream => _player.onPositionChanged;

  /// Get duration stream
  Stream<Duration> get durationStream => _player.onDurationChanged;

  /// Get player state stream
  Stream<PlayerState> get stateStream => _player.onPlayerStateChanged;

  void dispose() {
    _player.dispose();
  }

  /// Initialize Global Audio Session (Best Practice)
  /// Handles interruptions (Phone calls, Siri, Alarms) robustly.
  static Future<void> initSession() async {
    final sessionInstance = await session.AudioSession.instance;
    await sessionInstance.configure(
      session.AudioSessionConfiguration(
        // [FIX] PRE-WARM READY: Remove 'const' to allow option combination if supported,
        // or simply rely on runtime configuration.
        avAudioSessionCategory: session.AVAudioSessionCategory.playAndRecord,
        // FIX: Added defaultToSpeaker to prevent audio routing to earpiece on iOS
        avAudioSessionCategoryOptions:
            session.AVAudioSessionCategoryOptions.mixWithOthers |
            session.AVAudioSessionCategoryOptions.defaultToSpeaker,
        androidAudioAttributes: const session.AndroidAudioAttributes(
          contentType: session.AndroidAudioContentType.speech,
          usage: session.AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType:
            session.AndroidAudioFocusGainType.gainTransientMayDuck,
      ),
    );

    // Handle global interruptions (e.g. Phone Call)
    sessionInstance.interruptionEventStream.listen((event) {
      if (event.begin) {
        // Interruption started
        switch (event.type) {
          case session.AudioInterruptionType.pause:
          case session.AudioInterruptionType.unknown:
            // Phone call or alarm -> PAUSE
            debugPrint('AudioSession: Interruption started (${event.type})');
            break;
          default:
            break;
        }
      } else {
        // Interruption ended
        // We generally DO NOT resume automatically for calls, as per Apple Guidelines.
        // User should explicitly tap play.
        debugPrint('AudioSession: Interruption ended (${event.type})');
      }
    });
  }
}

/// Audio Lifecycle Manager
///
/// Listens for app lifecycle changes and ensures the iOS audio session
/// is deactivated when the app is backgrounded to prevent the "Red Bar".
class AudioLifecycleManager extends ConsumerStatefulWidget {
  final Widget child;
  const AudioLifecycleManager({super.key, required this.child});

  @override
  ConsumerState<AudioLifecycleManager> createState() =>
      _AudioLifecycleManagerState();
}

class _AudioLifecycleManagerState extends ConsumerState<AudioLifecycleManager>
    with WidgetsBindingObserver {
  static const _platform = MethodChannel('com.vive.app/audio');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App is going to background -> Kill the Red Bar
      _deactivateAudioSession();
    }
  }

  Future<void> _deactivateAudioSession() async {
    if (Platform.isIOS) {
      try {
        // STEP 1: Stop any active recording/playback before deactivating native session
        // This ensures the hardware is released and prevents "IsBusy" errors (0x62757379)
        await ref.read(recordingStateProvider.notifier).stopRecording();
        await ref.read(audioServiceProvider).stop();

        // STEP 2: Slight delay to allow AVAudioSession to enter a non-busy state
        // Higher-level players (Audioplayers/Record) may take a few ms to release the sink
        await Future.delayed(const Duration(milliseconds: 200));

        await _platform.invokeMethod('deactivateSession');
        debugPrint(
          '🔗 AudioLifecycle: iOS session deactivated to prevent Red Bar',
        );
      } on PlatformException catch (e) {
        debugPrint(
          '🔗 AudioLifecycle: Failed to deactivate session: ${e.message}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
