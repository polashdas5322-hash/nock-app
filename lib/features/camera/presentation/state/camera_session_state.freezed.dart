// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'camera_session_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CameraSessionState {

// Capture State
 File? get capturedImage; File? get capturedVideo; File? get recordedAudioFile; bool get isRecordingVideo; bool get isRecordingAudio; int get audioDuration;// Edit State
 EditMode get currentEditMode; Color get currentDrawColor; double get currentStrokeWidth; TextFontStyle get currentFontStyle; double get currentTextSize;// UI/Preview State
 bool get isAudioOnlyMode; bool get isProcessingCapture; bool get showCurtain; bool get wasFrontCamera;// HUD State
 bool get showFocusReticle; Offset? get focusPoint;// Selection state for stickers/text
 int? get selectedStickerIndex; int? get selectedTextIndex;
/// Create a copy of CameraSessionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CameraSessionStateCopyWith<CameraSessionState> get copyWith => _$CameraSessionStateCopyWithImpl<CameraSessionState>(this as CameraSessionState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CameraSessionState&&(identical(other.capturedImage, capturedImage) || other.capturedImage == capturedImage)&&(identical(other.capturedVideo, capturedVideo) || other.capturedVideo == capturedVideo)&&(identical(other.recordedAudioFile, recordedAudioFile) || other.recordedAudioFile == recordedAudioFile)&&(identical(other.isRecordingVideo, isRecordingVideo) || other.isRecordingVideo == isRecordingVideo)&&(identical(other.isRecordingAudio, isRecordingAudio) || other.isRecordingAudio == isRecordingAudio)&&(identical(other.audioDuration, audioDuration) || other.audioDuration == audioDuration)&&(identical(other.currentEditMode, currentEditMode) || other.currentEditMode == currentEditMode)&&(identical(other.currentDrawColor, currentDrawColor) || other.currentDrawColor == currentDrawColor)&&(identical(other.currentStrokeWidth, currentStrokeWidth) || other.currentStrokeWidth == currentStrokeWidth)&&(identical(other.currentFontStyle, currentFontStyle) || other.currentFontStyle == currentFontStyle)&&(identical(other.currentTextSize, currentTextSize) || other.currentTextSize == currentTextSize)&&(identical(other.isAudioOnlyMode, isAudioOnlyMode) || other.isAudioOnlyMode == isAudioOnlyMode)&&(identical(other.isProcessingCapture, isProcessingCapture) || other.isProcessingCapture == isProcessingCapture)&&(identical(other.showCurtain, showCurtain) || other.showCurtain == showCurtain)&&(identical(other.wasFrontCamera, wasFrontCamera) || other.wasFrontCamera == wasFrontCamera)&&(identical(other.showFocusReticle, showFocusReticle) || other.showFocusReticle == showFocusReticle)&&(identical(other.focusPoint, focusPoint) || other.focusPoint == focusPoint)&&(identical(other.selectedStickerIndex, selectedStickerIndex) || other.selectedStickerIndex == selectedStickerIndex)&&(identical(other.selectedTextIndex, selectedTextIndex) || other.selectedTextIndex == selectedTextIndex));
}


@override
int get hashCode => Object.hashAll([runtimeType,capturedImage,capturedVideo,recordedAudioFile,isRecordingVideo,isRecordingAudio,audioDuration,currentEditMode,currentDrawColor,currentStrokeWidth,currentFontStyle,currentTextSize,isAudioOnlyMode,isProcessingCapture,showCurtain,wasFrontCamera,showFocusReticle,focusPoint,selectedStickerIndex,selectedTextIndex]);

@override
String toString() {
  return 'CameraSessionState(capturedImage: $capturedImage, capturedVideo: $capturedVideo, recordedAudioFile: $recordedAudioFile, isRecordingVideo: $isRecordingVideo, isRecordingAudio: $isRecordingAudio, audioDuration: $audioDuration, currentEditMode: $currentEditMode, currentDrawColor: $currentDrawColor, currentStrokeWidth: $currentStrokeWidth, currentFontStyle: $currentFontStyle, currentTextSize: $currentTextSize, isAudioOnlyMode: $isAudioOnlyMode, isProcessingCapture: $isProcessingCapture, showCurtain: $showCurtain, wasFrontCamera: $wasFrontCamera, showFocusReticle: $showFocusReticle, focusPoint: $focusPoint, selectedStickerIndex: $selectedStickerIndex, selectedTextIndex: $selectedTextIndex)';
}


}

/// @nodoc
abstract mixin class $CameraSessionStateCopyWith<$Res>  {
  factory $CameraSessionStateCopyWith(CameraSessionState value, $Res Function(CameraSessionState) _then) = _$CameraSessionStateCopyWithImpl;
@useResult
$Res call({
 File? capturedImage, File? capturedVideo, File? recordedAudioFile, bool isRecordingVideo, bool isRecordingAudio, int audioDuration, EditMode currentEditMode, Color currentDrawColor, double currentStrokeWidth, TextFontStyle currentFontStyle, double currentTextSize, bool isAudioOnlyMode, bool isProcessingCapture, bool showCurtain, bool wasFrontCamera, bool showFocusReticle, Offset? focusPoint, int? selectedStickerIndex, int? selectedTextIndex
});




}
/// @nodoc
class _$CameraSessionStateCopyWithImpl<$Res>
    implements $CameraSessionStateCopyWith<$Res> {
  _$CameraSessionStateCopyWithImpl(this._self, this._then);

  final CameraSessionState _self;
  final $Res Function(CameraSessionState) _then;

/// Create a copy of CameraSessionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? capturedImage = freezed,Object? capturedVideo = freezed,Object? recordedAudioFile = freezed,Object? isRecordingVideo = null,Object? isRecordingAudio = null,Object? audioDuration = null,Object? currentEditMode = null,Object? currentDrawColor = null,Object? currentStrokeWidth = null,Object? currentFontStyle = null,Object? currentTextSize = null,Object? isAudioOnlyMode = null,Object? isProcessingCapture = null,Object? showCurtain = null,Object? wasFrontCamera = null,Object? showFocusReticle = null,Object? focusPoint = freezed,Object? selectedStickerIndex = freezed,Object? selectedTextIndex = freezed,}) {
  return _then(_self.copyWith(
capturedImage: freezed == capturedImage ? _self.capturedImage : capturedImage // ignore: cast_nullable_to_non_nullable
as File?,capturedVideo: freezed == capturedVideo ? _self.capturedVideo : capturedVideo // ignore: cast_nullable_to_non_nullable
as File?,recordedAudioFile: freezed == recordedAudioFile ? _self.recordedAudioFile : recordedAudioFile // ignore: cast_nullable_to_non_nullable
as File?,isRecordingVideo: null == isRecordingVideo ? _self.isRecordingVideo : isRecordingVideo // ignore: cast_nullable_to_non_nullable
as bool,isRecordingAudio: null == isRecordingAudio ? _self.isRecordingAudio : isRecordingAudio // ignore: cast_nullable_to_non_nullable
as bool,audioDuration: null == audioDuration ? _self.audioDuration : audioDuration // ignore: cast_nullable_to_non_nullable
as int,currentEditMode: null == currentEditMode ? _self.currentEditMode : currentEditMode // ignore: cast_nullable_to_non_nullable
as EditMode,currentDrawColor: null == currentDrawColor ? _self.currentDrawColor : currentDrawColor // ignore: cast_nullable_to_non_nullable
as Color,currentStrokeWidth: null == currentStrokeWidth ? _self.currentStrokeWidth : currentStrokeWidth // ignore: cast_nullable_to_non_nullable
as double,currentFontStyle: null == currentFontStyle ? _self.currentFontStyle : currentFontStyle // ignore: cast_nullable_to_non_nullable
as TextFontStyle,currentTextSize: null == currentTextSize ? _self.currentTextSize : currentTextSize // ignore: cast_nullable_to_non_nullable
as double,isAudioOnlyMode: null == isAudioOnlyMode ? _self.isAudioOnlyMode : isAudioOnlyMode // ignore: cast_nullable_to_non_nullable
as bool,isProcessingCapture: null == isProcessingCapture ? _self.isProcessingCapture : isProcessingCapture // ignore: cast_nullable_to_non_nullable
as bool,showCurtain: null == showCurtain ? _self.showCurtain : showCurtain // ignore: cast_nullable_to_non_nullable
as bool,wasFrontCamera: null == wasFrontCamera ? _self.wasFrontCamera : wasFrontCamera // ignore: cast_nullable_to_non_nullable
as bool,showFocusReticle: null == showFocusReticle ? _self.showFocusReticle : showFocusReticle // ignore: cast_nullable_to_non_nullable
as bool,focusPoint: freezed == focusPoint ? _self.focusPoint : focusPoint // ignore: cast_nullable_to_non_nullable
as Offset?,selectedStickerIndex: freezed == selectedStickerIndex ? _self.selectedStickerIndex : selectedStickerIndex // ignore: cast_nullable_to_non_nullable
as int?,selectedTextIndex: freezed == selectedTextIndex ? _self.selectedTextIndex : selectedTextIndex // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [CameraSessionState].
extension CameraSessionStatePatterns on CameraSessionState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CameraSessionState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CameraSessionState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CameraSessionState value)  $default,){
final _that = this;
switch (_that) {
case _CameraSessionState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CameraSessionState value)?  $default,){
final _that = this;
switch (_that) {
case _CameraSessionState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( File? capturedImage,  File? capturedVideo,  File? recordedAudioFile,  bool isRecordingVideo,  bool isRecordingAudio,  int audioDuration,  EditMode currentEditMode,  Color currentDrawColor,  double currentStrokeWidth,  TextFontStyle currentFontStyle,  double currentTextSize,  bool isAudioOnlyMode,  bool isProcessingCapture,  bool showCurtain,  bool wasFrontCamera,  bool showFocusReticle,  Offset? focusPoint,  int? selectedStickerIndex,  int? selectedTextIndex)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CameraSessionState() when $default != null:
return $default(_that.capturedImage,_that.capturedVideo,_that.recordedAudioFile,_that.isRecordingVideo,_that.isRecordingAudio,_that.audioDuration,_that.currentEditMode,_that.currentDrawColor,_that.currentStrokeWidth,_that.currentFontStyle,_that.currentTextSize,_that.isAudioOnlyMode,_that.isProcessingCapture,_that.showCurtain,_that.wasFrontCamera,_that.showFocusReticle,_that.focusPoint,_that.selectedStickerIndex,_that.selectedTextIndex);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( File? capturedImage,  File? capturedVideo,  File? recordedAudioFile,  bool isRecordingVideo,  bool isRecordingAudio,  int audioDuration,  EditMode currentEditMode,  Color currentDrawColor,  double currentStrokeWidth,  TextFontStyle currentFontStyle,  double currentTextSize,  bool isAudioOnlyMode,  bool isProcessingCapture,  bool showCurtain,  bool wasFrontCamera,  bool showFocusReticle,  Offset? focusPoint,  int? selectedStickerIndex,  int? selectedTextIndex)  $default,) {final _that = this;
switch (_that) {
case _CameraSessionState():
return $default(_that.capturedImage,_that.capturedVideo,_that.recordedAudioFile,_that.isRecordingVideo,_that.isRecordingAudio,_that.audioDuration,_that.currentEditMode,_that.currentDrawColor,_that.currentStrokeWidth,_that.currentFontStyle,_that.currentTextSize,_that.isAudioOnlyMode,_that.isProcessingCapture,_that.showCurtain,_that.wasFrontCamera,_that.showFocusReticle,_that.focusPoint,_that.selectedStickerIndex,_that.selectedTextIndex);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( File? capturedImage,  File? capturedVideo,  File? recordedAudioFile,  bool isRecordingVideo,  bool isRecordingAudio,  int audioDuration,  EditMode currentEditMode,  Color currentDrawColor,  double currentStrokeWidth,  TextFontStyle currentFontStyle,  double currentTextSize,  bool isAudioOnlyMode,  bool isProcessingCapture,  bool showCurtain,  bool wasFrontCamera,  bool showFocusReticle,  Offset? focusPoint,  int? selectedStickerIndex,  int? selectedTextIndex)?  $default,) {final _that = this;
switch (_that) {
case _CameraSessionState() when $default != null:
return $default(_that.capturedImage,_that.capturedVideo,_that.recordedAudioFile,_that.isRecordingVideo,_that.isRecordingAudio,_that.audioDuration,_that.currentEditMode,_that.currentDrawColor,_that.currentStrokeWidth,_that.currentFontStyle,_that.currentTextSize,_that.isAudioOnlyMode,_that.isProcessingCapture,_that.showCurtain,_that.wasFrontCamera,_that.showFocusReticle,_that.focusPoint,_that.selectedStickerIndex,_that.selectedTextIndex);case _:
  return null;

}
}

}

/// @nodoc


class _CameraSessionState extends CameraSessionState {
  const _CameraSessionState({this.capturedImage, this.capturedVideo, this.recordedAudioFile, this.isRecordingVideo = false, this.isRecordingAudio = false, this.audioDuration = 0, this.currentEditMode = EditMode.none, this.currentDrawColor = Colors.white, this.currentStrokeWidth = 5.0, this.currentFontStyle = TextFontStyle.classic, this.currentTextSize = 32.0, this.isAudioOnlyMode = false, this.isProcessingCapture = false, this.showCurtain = false, this.wasFrontCamera = false, this.showFocusReticle = false, this.focusPoint, this.selectedStickerIndex, this.selectedTextIndex}): super._();
  

// Capture State
@override final  File? capturedImage;
@override final  File? capturedVideo;
@override final  File? recordedAudioFile;
@override@JsonKey() final  bool isRecordingVideo;
@override@JsonKey() final  bool isRecordingAudio;
@override@JsonKey() final  int audioDuration;
// Edit State
@override@JsonKey() final  EditMode currentEditMode;
@override@JsonKey() final  Color currentDrawColor;
@override@JsonKey() final  double currentStrokeWidth;
@override@JsonKey() final  TextFontStyle currentFontStyle;
@override@JsonKey() final  double currentTextSize;
// UI/Preview State
@override@JsonKey() final  bool isAudioOnlyMode;
@override@JsonKey() final  bool isProcessingCapture;
@override@JsonKey() final  bool showCurtain;
@override@JsonKey() final  bool wasFrontCamera;
// HUD State
@override@JsonKey() final  bool showFocusReticle;
@override final  Offset? focusPoint;
// Selection state for stickers/text
@override final  int? selectedStickerIndex;
@override final  int? selectedTextIndex;

/// Create a copy of CameraSessionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CameraSessionStateCopyWith<_CameraSessionState> get copyWith => __$CameraSessionStateCopyWithImpl<_CameraSessionState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CameraSessionState&&(identical(other.capturedImage, capturedImage) || other.capturedImage == capturedImage)&&(identical(other.capturedVideo, capturedVideo) || other.capturedVideo == capturedVideo)&&(identical(other.recordedAudioFile, recordedAudioFile) || other.recordedAudioFile == recordedAudioFile)&&(identical(other.isRecordingVideo, isRecordingVideo) || other.isRecordingVideo == isRecordingVideo)&&(identical(other.isRecordingAudio, isRecordingAudio) || other.isRecordingAudio == isRecordingAudio)&&(identical(other.audioDuration, audioDuration) || other.audioDuration == audioDuration)&&(identical(other.currentEditMode, currentEditMode) || other.currentEditMode == currentEditMode)&&(identical(other.currentDrawColor, currentDrawColor) || other.currentDrawColor == currentDrawColor)&&(identical(other.currentStrokeWidth, currentStrokeWidth) || other.currentStrokeWidth == currentStrokeWidth)&&(identical(other.currentFontStyle, currentFontStyle) || other.currentFontStyle == currentFontStyle)&&(identical(other.currentTextSize, currentTextSize) || other.currentTextSize == currentTextSize)&&(identical(other.isAudioOnlyMode, isAudioOnlyMode) || other.isAudioOnlyMode == isAudioOnlyMode)&&(identical(other.isProcessingCapture, isProcessingCapture) || other.isProcessingCapture == isProcessingCapture)&&(identical(other.showCurtain, showCurtain) || other.showCurtain == showCurtain)&&(identical(other.wasFrontCamera, wasFrontCamera) || other.wasFrontCamera == wasFrontCamera)&&(identical(other.showFocusReticle, showFocusReticle) || other.showFocusReticle == showFocusReticle)&&(identical(other.focusPoint, focusPoint) || other.focusPoint == focusPoint)&&(identical(other.selectedStickerIndex, selectedStickerIndex) || other.selectedStickerIndex == selectedStickerIndex)&&(identical(other.selectedTextIndex, selectedTextIndex) || other.selectedTextIndex == selectedTextIndex));
}


@override
int get hashCode => Object.hashAll([runtimeType,capturedImage,capturedVideo,recordedAudioFile,isRecordingVideo,isRecordingAudio,audioDuration,currentEditMode,currentDrawColor,currentStrokeWidth,currentFontStyle,currentTextSize,isAudioOnlyMode,isProcessingCapture,showCurtain,wasFrontCamera,showFocusReticle,focusPoint,selectedStickerIndex,selectedTextIndex]);

@override
String toString() {
  return 'CameraSessionState(capturedImage: $capturedImage, capturedVideo: $capturedVideo, recordedAudioFile: $recordedAudioFile, isRecordingVideo: $isRecordingVideo, isRecordingAudio: $isRecordingAudio, audioDuration: $audioDuration, currentEditMode: $currentEditMode, currentDrawColor: $currentDrawColor, currentStrokeWidth: $currentStrokeWidth, currentFontStyle: $currentFontStyle, currentTextSize: $currentTextSize, isAudioOnlyMode: $isAudioOnlyMode, isProcessingCapture: $isProcessingCapture, showCurtain: $showCurtain, wasFrontCamera: $wasFrontCamera, showFocusReticle: $showFocusReticle, focusPoint: $focusPoint, selectedStickerIndex: $selectedStickerIndex, selectedTextIndex: $selectedTextIndex)';
}


}

/// @nodoc
abstract mixin class _$CameraSessionStateCopyWith<$Res> implements $CameraSessionStateCopyWith<$Res> {
  factory _$CameraSessionStateCopyWith(_CameraSessionState value, $Res Function(_CameraSessionState) _then) = __$CameraSessionStateCopyWithImpl;
@override @useResult
$Res call({
 File? capturedImage, File? capturedVideo, File? recordedAudioFile, bool isRecordingVideo, bool isRecordingAudio, int audioDuration, EditMode currentEditMode, Color currentDrawColor, double currentStrokeWidth, TextFontStyle currentFontStyle, double currentTextSize, bool isAudioOnlyMode, bool isProcessingCapture, bool showCurtain, bool wasFrontCamera, bool showFocusReticle, Offset? focusPoint, int? selectedStickerIndex, int? selectedTextIndex
});




}
/// @nodoc
class __$CameraSessionStateCopyWithImpl<$Res>
    implements _$CameraSessionStateCopyWith<$Res> {
  __$CameraSessionStateCopyWithImpl(this._self, this._then);

  final _CameraSessionState _self;
  final $Res Function(_CameraSessionState) _then;

/// Create a copy of CameraSessionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? capturedImage = freezed,Object? capturedVideo = freezed,Object? recordedAudioFile = freezed,Object? isRecordingVideo = null,Object? isRecordingAudio = null,Object? audioDuration = null,Object? currentEditMode = null,Object? currentDrawColor = null,Object? currentStrokeWidth = null,Object? currentFontStyle = null,Object? currentTextSize = null,Object? isAudioOnlyMode = null,Object? isProcessingCapture = null,Object? showCurtain = null,Object? wasFrontCamera = null,Object? showFocusReticle = null,Object? focusPoint = freezed,Object? selectedStickerIndex = freezed,Object? selectedTextIndex = freezed,}) {
  return _then(_CameraSessionState(
capturedImage: freezed == capturedImage ? _self.capturedImage : capturedImage // ignore: cast_nullable_to_non_nullable
as File?,capturedVideo: freezed == capturedVideo ? _self.capturedVideo : capturedVideo // ignore: cast_nullable_to_non_nullable
as File?,recordedAudioFile: freezed == recordedAudioFile ? _self.recordedAudioFile : recordedAudioFile // ignore: cast_nullable_to_non_nullable
as File?,isRecordingVideo: null == isRecordingVideo ? _self.isRecordingVideo : isRecordingVideo // ignore: cast_nullable_to_non_nullable
as bool,isRecordingAudio: null == isRecordingAudio ? _self.isRecordingAudio : isRecordingAudio // ignore: cast_nullable_to_non_nullable
as bool,audioDuration: null == audioDuration ? _self.audioDuration : audioDuration // ignore: cast_nullable_to_non_nullable
as int,currentEditMode: null == currentEditMode ? _self.currentEditMode : currentEditMode // ignore: cast_nullable_to_non_nullable
as EditMode,currentDrawColor: null == currentDrawColor ? _self.currentDrawColor : currentDrawColor // ignore: cast_nullable_to_non_nullable
as Color,currentStrokeWidth: null == currentStrokeWidth ? _self.currentStrokeWidth : currentStrokeWidth // ignore: cast_nullable_to_non_nullable
as double,currentFontStyle: null == currentFontStyle ? _self.currentFontStyle : currentFontStyle // ignore: cast_nullable_to_non_nullable
as TextFontStyle,currentTextSize: null == currentTextSize ? _self.currentTextSize : currentTextSize // ignore: cast_nullable_to_non_nullable
as double,isAudioOnlyMode: null == isAudioOnlyMode ? _self.isAudioOnlyMode : isAudioOnlyMode // ignore: cast_nullable_to_non_nullable
as bool,isProcessingCapture: null == isProcessingCapture ? _self.isProcessingCapture : isProcessingCapture // ignore: cast_nullable_to_non_nullable
as bool,showCurtain: null == showCurtain ? _self.showCurtain : showCurtain // ignore: cast_nullable_to_non_nullable
as bool,wasFrontCamera: null == wasFrontCamera ? _self.wasFrontCamera : wasFrontCamera // ignore: cast_nullable_to_non_nullable
as bool,showFocusReticle: null == showFocusReticle ? _self.showFocusReticle : showFocusReticle // ignore: cast_nullable_to_non_nullable
as bool,focusPoint: freezed == focusPoint ? _self.focusPoint : focusPoint // ignore: cast_nullable_to_non_nullable
as Offset?,selectedStickerIndex: freezed == selectedStickerIndex ? _self.selectedStickerIndex : selectedStickerIndex // ignore: cast_nullable_to_non_nullable
as int?,selectedTextIndex: freezed == selectedTextIndex ? _self.selectedTextIndex : selectedTextIndex // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
