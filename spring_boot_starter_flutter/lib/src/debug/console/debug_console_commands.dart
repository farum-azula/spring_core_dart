import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_command.dart';

// The framework's command of the debug console's commands pane.

/// `help`: every command of the console, the application's included, with
/// how it is written and what it does, in columns
/// (`DebugConsoleCall.printUsage`); `help <command>` that one.
final class HelpCommand extends DebugConsoleCommand {
  /// The command.
  const HelpCommand();

  @override
  String get usage => '[command]';

  @override
  String get help => 'Lists the commands, or tells of one.';

  @override
  Iterable<String> run(DebugConsoleCall call) {
    final asked = call.args.firstOrNull;
    final shown = asked == null
        ? call.commands.entries
        : call.commands.entries.where((entry) => entry.key == asked);
    if (shown.isEmpty) {
      throw DebugConsoleCommandException("no such command; 'help' lists them");
    }
    for (final MapEntry(key: word, value: command) in shown) {
      call.printUsage(word, command.usage, command.help);
    }
    return const [];
  }
}
