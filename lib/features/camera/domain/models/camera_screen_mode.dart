/// High-level modes the camera screen can be in.
///
/// This enum encodes the **primary interaction state** of the camera screen.
/// It is derived from the underlying boolean flags and is used to simplify
/// complex conditional UI logic. The enum values are mutually exclusive —
/// the screen can only be in one mode at a time.
///
/// Usage: Access via `_screenMode` getter in `_CameraScreenNewState`.
enum CameraScreenMode {
  /// Live camera preview, ready to capture photo (tap) or video (hold).
  cameraIdle,

  /// Actively recording video (hold-to-record).
  recordingVideo,

  /// Audio-only mode, idle, waiting for user to start recording.
  audioIdle,

  /// Audio-only mode, actively recording.
  audioRecording,

  /// Reviewing a captured photo or video (pre-send).
  reviewingCapture,

  /// Editing captured media (draw, sticker, text, voiceover).
  editing,

  /// Full-screen text input overlay is active.
  editingText,
}

extension CameraScreenModeExtension on CameraScreenMode {
  /// True when the user is reviewing or editing captured content.
  bool get isPostCapture =>
      this == CameraScreenMode.reviewingCapture ||
      this == CameraScreenMode.editing ||
      this == CameraScreenMode.editingText;

  /// True when any kind of recording is active.
  bool get isRecording =>
      this == CameraScreenMode.recordingVideo ||
      this == CameraScreenMode.audioRecording;

  /// True when UI controls should be hidden for focus.
  bool get shouldHideControls =>
      isRecording || this == CameraScreenMode.editingText;

  /// True when the screen is in any audio-only state.
  bool get isAudioMode =>
      this == CameraScreenMode.audioIdle ||
      this == CameraScreenMode.audioRecording;
}
