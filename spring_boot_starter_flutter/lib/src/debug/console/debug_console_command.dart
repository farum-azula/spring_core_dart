import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console.dart';

/// A command of the debug console's `commands` pane (in the build when
/// `spring.flutter.debug.console.panes` names `commands` or holds `*`): a
/// bean, run by its word,
/// the first word of the line typed: the one its `@ConsoleCommand` gives
/// when it has one, else [name] (a command registered as a plain bean or
/// made by hand). A [name] that disagrees with the annotation fails the
/// build (and, for one the build cannot read, the start). What it returns
/// is printed into the console.
///
/// The framework's own, `help`, is a bean like an application's, and comes
/// after them: an application's command of the same name replaces it.
///
/// ```dart
/// @ConsoleCommand('reload')
/// class ReloadCommand extends DebugConsoleCommand {
///   ReloadCommand(this.catalog);
///
///   final Catalog catalog;
///
///   @override
///   String get usage => '';
///
///   @override
///   String get help => 'Loads the catalog again.';
///
///   @override
///   Future<List<String>> run(DebugConsoleCall call) async {
///     await catalog.reload();
///     return ['${catalog.size} items'];
///   }
/// }
/// ```
///
/// Spring has no counterpart (Spring Shell's `@Command` is the closest).
abstract class DebugConsoleCommand {
  /// A command.
  const DebugConsoleCommand();

  /// Its word when no `@ConsoleCommand` names it; `null` (the default):
  /// the annotation's.
  String? get name => null;

  /// How its arguments are written, after its word, for `help`
  /// (`[command]` for `help`); empty without one.
  String get usage;

  /// What it does, in one line, for `help`.
  String get help;

  /// Runs it with the words after its name ([DebugConsoleCall.args]);
  /// the lines returned are printed into the console. A throw is printed
  /// as an error.
  FutureOr<Iterable<String>> run(DebugConsoleCall call);
}

/// One line typed into the debug console: the words after the command's
/// word, the console, every command by its word (what `help` lists), and
/// the commands pane's [output].
final class DebugConsoleCall {
  /// The call of [args] in [console], among [commands], printing into
  /// [output].
  const DebugConsoleCall({
    required this.args,
    required this.console,
    required this.commands,
    required this.output,
  });

  /// The words after the command's name.
  final List<String> args;

  /// The console it was typed into.
  final DebugConsole console;

  /// Every command of the console by its word, the application's first.
  final Map<String, DebugConsoleCommand> commands;

  /// What the commands pane shows.
  final DebugConsoleOutput output;

  /// Prints [text] into the commands pane, a line per line of it.
  void print(
    String text, {
    DebugConsoleLineKind kind = DebugConsoleLineKind.output,
  }) => output.add(text, kind);

  /// Prints a row of a list of commands: [command]'s word, how its
  /// arguments are written ([usage]) and what it does ([help]); the rows
  /// printed together line up in columns.
  void printUsage(String command, String usage, String help) =>
      output.addUsage((command: command, usage: usage, help: help));
}

/// What a line printed into the debug console's commands pane is.
enum DebugConsoleLineKind {
  /// A line typed in (`> help`).
  input,

  /// What a command printed.
  output,

  /// What went wrong.
  error,

  /// A row of a list of commands ([DebugConsoleLine.usage]).
  usage,
}

/// A row of a list of commands: a command's word, how its arguments are
/// written, what it does.
typedef DebugConsoleUsage = ({String command, String usage, String help});

/// A line printed into the debug console's commands pane; [usage] is the
/// row of a [DebugConsoleLineKind.usage] line.
typedef DebugConsoleLine = ({
  DateTime time,
  String text,
  DebugConsoleLineKind kind,
  DebugConsoleUsage? usage,
});

/// The lines printed into the debug console's commands pane, at most
/// [limit] of them.
final class DebugConsoleOutput extends ChangeNotifier {
  /// The most lines kept.
  static const int limit = 500;

  final List<DebugConsoleLine> _lines = [];

  /// The lines, oldest first.
  List<DebugConsoleLine> get lines => List.unmodifiable(_lines);

  /// Adds [text] as lines of [kind].
  void add(String text, DebugConsoleLineKind kind) {
    final time = DateTime.now();
    for (final line in text.split('\n')) {
      _lines.add((time: time, text: line, kind: kind, usage: null));
    }
    _trim();
  }

  /// Adds [usage] as a row of a list of commands.
  void addUsage(DebugConsoleUsage usage) {
    _lines.add((
      time: DateTime.now(),
      text: [
        usage.command,
        if (usage.usage.isNotEmpty) usage.usage,
        ' ${usage.help}',
      ].join(' '),
      kind: DebugConsoleLineKind.usage,
      usage: usage,
    ));
    _trim();
  }

  void _trim() {
    if (_lines.length > limit) {
      _lines.removeRange(0, _lines.length - limit);
    }
    notifyListeners();
  }

  /// Forgets every line.
  void clear() {
    _lines.clear();
    notifyListeners();
  }
}

/// What a command throws to print [message] as an error line: a wrong
/// argument, a name it does not know.
final class DebugConsoleCommandException implements Exception {
  /// The error [message].
  const DebugConsoleCommandException(this.message);

  /// What is printed.
  final String message;

  @override
  String toString() => message;
}
