import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:nock/core/theme/app_colors.dart';
import 'package:nock/core/theme/app_typography.dart';
import 'package:nock/features/camera/domain/models/camera_models.dart';
import 'package:nock/features/camera/presentation/widgets/camera_buttons.dart';

/// Overlay widget managing editing tools (Draw, Text, Stickers)
/// Includes the specific toolbars for each mode and the full-screen text input.
class EditToolsOverlay extends StatelessWidget {
  final EditMode currentEditMode;
  final List<Color> drawColors;
  final Color currentDrawColor;
  final double currentStrokeWidth;
  final double currentTextSize;
  final TextFontStyle currentFontStyle;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<double> onTextSizeChanged;
  final ValueChanged<TextFontStyle> onFontStyleChanged;
  final VoidCallback onFinishTextEditing;
  
  // Text Editing Dependencies
  final ValueNotifier<List<TextOverlay>> textOverlaysNotifier;
  final int? selectedTextIndex;
  final TextEditingController textController;
  final FocusNode textFocusNode;
  final bool isEditingText;

  const EditToolsOverlay({
    super.key,
    required this.currentEditMode,
    required this.drawColors,
    required this.currentDrawColor,
    required this.currentStrokeWidth,
    required this.currentTextSize,
    required this.currentFontStyle,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onTextSizeChanged,
    required this.onFontStyleChanged,
    required this.onFinishTextEditing,
    required this.textOverlaysNotifier,
    required this.selectedTextIndex,
    required this.textController,
    required this.textFocusNode,
    required this.isEditingText,
  });

  @override
  Widget build(BuildContext context) {
    if (isEditingText) {
      return _buildTextInputField(context);
    }
    
    switch (currentEditMode) {
      case EditMode.draw:
        return _buildDrawToolbar();
      case EditMode.sticker:
        return const SizedBox.shrink(); // Handled by bottom sheet
      case EditMode.text:
        return _buildTextToolbar();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDrawToolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Stroke width
          ToolbarIconButton(
            icon: currentStrokeWidth < 10 ? PhosphorIcons.circle(PhosphorIconsStyle.fill) : PhosphorIcons.circle(PhosphorIconsStyle.bold),
            iconSize: currentStrokeWidth.clamp(12, 24),
            onTap: () {
               final newWidth = currentStrokeWidth >= 15 ? 3.0 : currentStrokeWidth + 4.0;
               onStrokeWidthChanged(newWidth);
            },
          ),
          const SizedBox(width: 8),
          // Colors
          ...drawColors.map((color) {
            final isSelected = color == currentDrawColor;
            return GestureDetector(
              onTap: () => onColorChanged(color),
              child: Container(
                width: 32, height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.primaryAction : Colors.white38,
                    width: isSelected ? 3 : 1,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTextToolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Colors
          ...drawColors.map((color) {
            final isSelected = color == currentDrawColor;
            return GestureDetector(
              onTap: () {
                onColorChanged(color);
                if (selectedTextIndex != null) {
                  final currentTexts = List<TextOverlay>.from(textOverlaysNotifier.value);
                  currentTexts[selectedTextIndex!].color = color;
                  textOverlaysNotifier.value = currentTexts; // Notify
                }
              },
              child: Container(
                width: 32, height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.primaryAction : Colors.white38,
                    width: isSelected ? 3 : 1,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTextInputField(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final topPadding = MediaQuery.of(context).padding.top;
    
    return Material(
      color: Colors.transparent, // User requested: remove bg color
      child: GestureDetector(
        onTap: onFinishTextEditing,
        behavior: HitTestBehavior.translucent, // Capture taps on empty space to dismiss
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Centered Inline Input (NoteIt-style)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: IntrinsicWidth(
                  child: TextField(
                    controller: textController,
                    focusNode: textFocusNode,
                    autofocus: true,
                    style: currentFontStyle.getStyle(currentTextSize, currentDrawColor),
                    textAlign: TextAlign.center,
                    maxLines: null,
                    decoration: const InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Type...',
                      hintStyle: TextStyle(color: Colors.white30),
                    ),
                    cursorColor: Colors.white,
                    onChanged: (value) {
                      if (selectedTextIndex != null) {
                        // Update text in notifier without setState rebuild
                        final currentTexts = List<TextOverlay>.from(textOverlaysNotifier.value);
                        currentTexts[selectedTextIndex!].text = value;
                        // Avoid notifying on every keystroke if it causes lag, 
                        // but usually it's fine with RepaintBoundary
                        textOverlaysNotifier.value = currentTexts;
                      }
                    },
                  ),
                ),
              ),
            ),

            // 2. Styling Toolbar (docked to keyboard)
            Positioned(
              bottom: keyboardHeight,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {}, // INTERCEPT: Prevent tap-to-dismiss when interacting with toolbar
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       // Size slider (mini version)
                       Padding(
                         padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                         child: Row(
                           children: [
                             PhosphorIcon(PhosphorIcons.textT(PhosphorIconsStyle.light), color: Colors.white, size: 14),
                             Expanded(
                               child: Slider(
                                 value: currentTextSize,
                                 min: 16, max: 64,
                                 onChanged: (v) => onTextSizeChanged(v),
                                 activeColor: AppColors.primaryAction,
                               ),
                             ),
                             PhosphorIcon(PhosphorIcons.textT(PhosphorIconsStyle.bold), color: Colors.white, size: 24),
                           ],
                         ),
                       ),
                       // Font styles
                       SizedBox(
                         height: 40,
                         child: ListView(
                           scrollDirection: Axis.horizontal,
                           padding: const EdgeInsets.symmetric(horizontal: 16),
                           children: TextFontStyle.values.map((style) => _buildFontStyleChip(style)).toList(),
                         ),
                       ),
                       const SizedBox(height: 12),
                       // Colors
                       SingleChildScrollView(
                         scrollDirection: Axis.horizontal,
                         padding: const EdgeInsets.symmetric(horizontal: 16),
                         child: Row(
                           children: drawColors.map((color) {
                             final isSelected = color == currentDrawColor;
                             return GestureDetector(
                               onTap: () {
                                 onColorChanged(color);
                                   if (selectedTextIndex != null) {
                                      final currentTexts = List<TextOverlay>.from(textOverlaysNotifier.value);
                                      currentTexts[selectedTextIndex!].color = color;
                                      textOverlaysNotifier.value = currentTexts;
                                   }
                               },
                               child: Container(
                                 width: 32, height: 32,
                                 margin: const EdgeInsets.symmetric(horizontal: 4),
                                 decoration: BoxDecoration(
                                   color: color,
                                   shape: BoxShape.circle,
                                   border: Border.all(
                                     color: isSelected ? AppColors.primaryAction : Colors.white38,
                                     width: isSelected ? 3 : 1,
                                   ),
                                 ),
                               ),
                             );
                           }).toList(),
                         ),
                       ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. DONE Button (Top Right)
            Positioned(
              top: topPadding + 12,
              right: 16,
              child: TextButton(
                onPressed: onFinishTextEditing,
                child: const Text('DONE', style: TextStyle(color: AppColors.primaryAction, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFontStyleChip(TextFontStyle style) {
    final isSelected = currentFontStyle == style;
    
    return GestureDetector(
      onTap: () => onFontStyleChanged(style),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryAction : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          style.displayName,
          style: style.getStyle(
            14, 
            isSelected ? Colors.black : AppColors.textSecondary,
          ).copyWith(fontSize: 14),
        ),
      ),
    );
  }
}
