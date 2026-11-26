import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_command.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_logs_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_export.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_format.dart';

/// `export [log|jsonl]`: the records marked in the console's `logs` pane,
/// or every record its filter shows when none is marked, exported as a
/// file of that format (`log` by default) by the log export
/// (`debugLogExport`); what the export tells is printed. In the build only
/// with the log export (`spring.flutter.debug.logs.export.enabled`), the
/// `logs` pane and the `commands` pane.
final class ExportCommand extends DebugConsoleCommand {
  /// The command exporting the records of [logs] through [export].
  const ExportCommand(this.export, this.logs);

  /// The log export.
  final DebugLogExport export;

  /// The pane whose records it exports.
  final LogsPane logs;

  @override
  String get usage =>
      '[${[for (final format in export.formats) format.extension].join('|')}]';

  @override
  String get help => 'Exports the marked records, else those shown.';

  @override
  Future<List<String>> run(DebugConsoleCall call) async {
    final asked = call.args.firstOrNull ?? export.formats.first.extension;
    final DebugLogFormat format;
    try {
      format = export.format(asked);
    } on ArgumentError {
      throw DebugConsoleCommandException('no format $asked: $usage');
    }
    return [await export.exportRecords(logs.chosenRecords, format)];
  }
}
