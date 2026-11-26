import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_command.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_command_line.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_scroll.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// The debug console's `commands` pane (the `commandsPane` bean, order 10):
/// what the commands printed ([output]) over the input line
/// ([DebugConsoleInputField]). A line typed and sent with Enter runs the
/// command its first word names ([commands], by their words: the
/// application's `@ConsoleCommand` classes and the framework's `help`), and
/// what it returns is printed under the line typed. Up and down go back
/// through the last [historySize] lines.
///
/// In the build only when `spring.flutter.debug.console.panes` names
/// `commands` or holds `*`, and the application's commands with it; shown
/// at the start when `spring.flutter.debug.console.shown-panes` names it.
final class CommandsPane extends DebugConsolePane {
  /// The pane running [commands], remembering [historySize] lines, [lines]
  /// of output high at the start.
  CommandsPane(
    this.commands, {
    this.historySize = 50,
    this.lines = 6,
    this.closeKeys = _none,
  });

  static List<ShortcutActivator> _none() => const [];

  /// The keys of the console's action (`debug.console`): pressed in the
  /// line, they hide the console, though a key alone is otherwise the
  /// text's.
  final List<ShortcutActivator> Function() closeKeys;

  /// The commands by their words, the application's first.
  final Map<String, DebugConsoleCommand> commands;

  /// How many lines typed it remembers.
  final int historySize;

  /// How many lines of output high it starts, over the input line.
  final int lines;

  /// What the commands printed.
  final DebugConsoleOutput output = DebugConsoleOutput();

  final List<String> _history = [];

  /// The lines typed, oldest first.
  List<String> get history => List.unmodifiable(_history);

  @override
  String get title => 'Commands';

  @override
  double get minHeight =>
      DebugConsoleView.lineHeight + DebugConsoleInputField.height;

  @override
  double get initialHeight =>
      DebugConsoleView.lineHeight * math.max(1, lines) +
      DebugConsoleInputField.height;

  @override
  Widget build(BuildContext context, DebugConsole console) =>
      DebugConsoleCommandsView(pane: this, console: console);

  /// Runs [line] in [console]: prints it, then what its command returns,
  /// or what went wrong.
  Future<void> run(String line, DebugConsole console) async {
    final words = line.trim().split(RegExp(r'\s+'));
    if (words.first.isEmpty) {
      return;
    }
    if (_history.isEmpty || _history.last != line.trim()) {
      _history.add(line.trim());
      if (_history.length > historySize) {
        _history.removeAt(0);
      }
    }
    output.add('> ${line.trim()}', DebugConsoleLineKind.input);
    final name = words.first;
    final command = commands[name];
    if (command == null) {
      output.add(
        "$name: no such command; 'help' lists them",
        DebugConsoleLineKind.error,
      );
      return;
    }
    try {
      final lines = await command.run(
        DebugConsoleCall(
          args: words.sublist(1),
          console: console,
          commands: commands,
          output: output,
        ),
      );
      for (final out in lines) {
        output.add(out, DebugConsoleLineKind.output);
      }
    } on Object catch (error) {
      output.add('$name: $error', DebugConsoleLineKind.error);
    }
  }
}

/// The `commands` pane's widget: what the commands printed
/// ([DebugConsoleOutputView]) over the input line.
class DebugConsoleCommandsView extends StatelessWidget {
  /// The view of [pane] in [console].
  const DebugConsoleCommandsView({
    required this.pane,
    required this.console,
    super.key,
  });

  /// The pane.
  final CommandsPane pane;

  /// The console.
  final DebugConsole console;

  @override
  Widget build(BuildContext context) {
    final text = DebugStyle.of(
      context,
    ).code.copyWith(height: 1.25, decoration: TextDecoration.none);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DebugConsoleOutputView(output: pane.output, text: text),
        ),
        DebugConsoleInputField(commandLine: pane, console: console),
      ],
    );
  }
}

/// What the commands printed ([CommandsPane.output]), above the input
/// line: oldest on top, in a list of its own that scrolls back and follows
/// the newest. The line typed is dim, what a command printed in the text's
/// colour, an error in the theme's error colour; the rows of a list of
/// commands (`help`) line up in two columns, the command's word and its
/// arguments in the theme's command and argument colours. Drawn again at
/// most once a frame. As high as its parent lets it be.
class DebugConsoleOutputView extends StatefulWidget {
  /// The view of [output], its text [text].
  const DebugConsoleOutputView({
    required this.output,
    required this.text,
    super.key,
  });

  /// What it shows.
  final DebugConsoleOutput output;

  /// The text's style.
  final TextStyle text;

  @override
  State<DebugConsoleOutputView> createState() => _DebugConsoleOutputViewState();
}

class _DebugConsoleOutputViewState extends State<DebugConsoleOutputView> {
  final _scroll = ScrollController();
  int? _frame;

  @override
  void initState() {
    super.initState();
    widget.output.addListener(_printed);
  }

  @override
  void didUpdateWidget(DebugConsoleOutputView old) {
    super.didUpdateWidget(old);
    if (old.output != widget.output) {
      old.output.removeListener(_printed);
      widget.output.addListener(_printed);
    }
  }

  @override
  void dispose() {
    widget.output.removeListener(_printed);
    if (_frame case final frame?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    }
    _scroll.dispose();
    super.dispose();
  }

  // A command printed: back to the newest, drawn in the next frame.
  void _printed() {
    if (_scroll.hasClients && _scroll.offset != 0) {
      _scroll.jumpTo(0);
    }
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final text = widget.text;
    final lines = widget.output.lines.reversed.toList();
    final command = text.copyWith(color: style.command);
    final argument = text.copyWith(color: style.argument);
    return SizedBox.expand(
      key: const ValueKey('debug-console-commands'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final column = _firstColumn(
            lines,
            command,
            argument,
            constraints.maxWidth / 2,
          );
          return DebugConsoleScrollArea(
            controller: _scroll,
            child: ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: EdgeInsets.zero,
              physics: const ClampingScrollPhysics(),
              itemCount: lines.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(top: 1),
                child: _line(lines[i], style, column, command, argument),
              ),
            ),
          );
        },
      ),
    );
  }

  static TextSpan _usageSpan(
    DebugConsoleUsage usage,
    TextStyle command,
    TextStyle argument,
  ) => TextSpan(
    children: [
      TextSpan(text: usage.command, style: command),
      if (usage.usage.isNotEmpty)
        TextSpan(text: ' ${usage.usage}', style: argument),
    ],
  );

  // The width of the rows' first column: the widest command and its
  // arguments, at most [max].
  double _firstColumn(
    List<DebugConsoleLine> lines,
    TextStyle command,
    TextStyle argument,
    double max,
  ) {
    var widest = 0.0;
    for (final line in lines) {
      if (line.usage case final usage?) {
        final painter = TextPainter(
          text: _usageSpan(usage, command, argument),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        widest = math.max(widest, painter.width);
        painter.dispose();
      }
    }
    return math.min(widest.ceilToDouble() + 12, max);
  }

  Widget _line(
    DebugConsoleLine line,
    DebugStyle style,
    double column,
    TextStyle command,
    TextStyle argument,
  ) {
    final text = widget.text;
    if (line.usage case final usage?) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: column,
            child: Text.rich(_usageSpan(usage, command, argument), style: text),
          ),
          Expanded(
            child: Text(
              usage.help,
              style: text.copyWith(color: style.foreground),
            ),
          ),
        ],
      );
    }
    return Text(
      line.text,
      style: text.copyWith(
        color: switch (line.kind) {
          DebugConsoleLineKind.input => style.muted,
          DebugConsoleLineKind.error => style.error,
          DebugConsoleLineKind.output ||
          DebugConsoleLineKind.usage => style.foreground,
        },
      ),
    );
  }
}
