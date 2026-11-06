import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:neon_ui/spring_gen/spring_auto_configuration.spring.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// A text input on `EditableText` with mouse selection. The frame is
/// `styles.neon-text-field`: the border lights up on focus and turns red
/// with [error].
class NeonTextField extends StatefulWidget {
  const NeonTextField({
    super.key,
    required this.controller,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.error = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType keyboardType;
  final bool error;
  final bool enabled;

  @override
  State<NeonTextField> createState() => _NeonTextFieldState();
}

class _NeonTextFieldState extends State<NeonTextField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  // The frame's node only watches whether the input inside has focus.
  final _frame = FocusNode(skipTraversal: true);
  final _input = FocusNode();
  late final _gestures = TextSelectionGestureDetectorBuilder(delegate: this);

  @override
  final GlobalKey<EditableTextState> editableTextKey =
      GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  void dispose() {
    _frame.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return ThemeStates(
      style: theme.styles.neonTextField,
      error: widget.error,
      focusNode: _frame,
      mouseCursor: SystemMouseCursors.text,
      showFocusAlways: true,
      onPressed: widget.enabled ? _input.requestFocus : null,
      builder: (context, s) => Container(
        height: s.height,
        padding: s.padding,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: s.fill,
          border: Border.all(color: s.border, width: s.borderWidth),
          borderRadius: BorderRadius.circular(s.radius),
        ),
        // The frame turns Enter and Space into a press; inside the input
        // they must stay text.
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.space):
                DoNothingAndStopPropagationTextIntent(),
            SingleActivator(LogicalKeyboardKey.enter):
                DoNothingAndStopPropagationTextIntent(),
          },
          child: _gestures.buildGestureDetector(
            behavior: HitTestBehavior.translucent,
            child: EditableText(
              key: editableTextKey,
              controller: widget.controller,
              focusNode: _input,
              readOnly: !widget.enabled,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              onChanged: widget.onChanged,
              maxLines: 1,
              rendererIgnoresPointer: true,
              style: theme.typography.bodyLarge.copyWith(color: s.text),
              cursorColor: theme.colors.primary,
              backgroundCursorColor: theme.colors.outline,
              selectionColor: s.selection,
              selectionControls: emptyTextSelectionControls,
            ),
          ),
        ),
      ),
    );
  }
}
