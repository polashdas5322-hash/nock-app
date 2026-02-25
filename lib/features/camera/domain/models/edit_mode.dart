/// Edit mode types for the camera screen
enum EditMode {
  none,
  draw,
  sticker,
  text,
  audio, // Voice note recording mode
}

extension EditModeExtension on EditMode {
  bool get isEditing => this != EditMode.none;

  String get label {
    switch (this) {
      case EditMode.none:
        return 'None';
      case EditMode.draw:
        return 'Draw';
      case EditMode.sticker:
        return 'Sticker';
      case EditMode.text:
        return 'Text';
      case EditMode.audio:
        return 'Voice';
    }
  }
}
