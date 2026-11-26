import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_commands_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_keys.dart';

/// The input line at the bottom of the debug console's `commands` pane:
/// `>` in the debug theme's accent and the line, `help` as a dim hint
/// while it is empty. A line sent with Enter runs ([CommandsPane.run]); up
/// and down go back through the pane's history. While the line has the
/// focus it takes every key typed: nothing reaches the app; Escape gives
/// the focus back, the console's own keys hide the console. Taking the
/// focus makes the console's panes interact.
class DebugConsoleInputField extends StatefulWidget {
  /// The field of [commandLine] in [console].
  const DebugConsoleInputField({
    required this.commandLine,
    required this.console,
    super.key,
  });

  /// How high the line is.
  static const double height = 18;

  /// What runs the lines.
  final CommandsPane commandLine;

  /// The console.
  final DebugConsole console;

  @override
  State<DebugConsoleInputField> createState() => _DebugConsoleInputFieldState();
}

class _DebugConsoleInputFieldState extends State<DebugConsoleInputField> {
  final _controller = TextEditingController();
  late final _focus = FocusNode(
    debugLabel: 'debug console input',
    onKeyEvent: _key,
  )..addListener(_focused);

  // Where up and down are in the history: its length is the line being
  // typed.
  int? _at;
  String _typed = '';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Focused (a tap with ⌥ held, Tab): the panes interact, so the line stays
  // under the finger after ⌥ is let go; the focus gone, they stay so.
  void _focused() {
    if (_focus.hasFocus) {
      widget.console.interaction = DebugConsoleInteraction.interact;
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final history = widget.commandLine.history;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      node.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (widget.commandLine.closeKeys().any(
      (keys) => acceptsWhileTyping(keys, event, keyboard),
    )) {
      node.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
      widget.console.shown = false;
      return KeyEventResult.handled;
    }
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    if (history.isEmpty) {
      return KeyEventResult.handled;
    }
    final at = _at ?? history.length;
    if (at == history.length) {
      _typed = _controller.text;
    }
    final next = (key == LogicalKeyboardKey.arrowUp ? at - 1 : at + 1).clamp(
      0,
      history.length,
    );
    _at = next;
    final text = next == history.length ? _typed : history[next];
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    return KeyEventResult.handled;
  }

  Future<void> _submit(String line) async {
    _controller.clear();
    _at = null;
    _typed = '';
    _focus.requestFocus();
    await widget.commandLine.run(line, widget.console);
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final text = style.code.copyWith(
      height: 1.25,
      decoration: TextDecoration.none,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: SizedBox(
        height: DebugConsoleInputField.height,
        child: Row(
          children: [
            Text('> ', style: text.copyWith(color: style.accent)),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => _controller.text.isEmpty
                        ? Text('help', style: text.copyWith(color: style.muted))
                        : const SizedBox.shrink(),
                  ),
                  EditableText(
                    key: const ValueKey('debug-console-input'),
                    controller: _controller,
                    focusNode: _focus,
                    style: text,
                    cursorColor: style.accent,
                    backgroundCursorColor: style.muted,
                    maxLines: 1,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.send,
                    onEditingComplete: () {},
                    onSubmitted: _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
