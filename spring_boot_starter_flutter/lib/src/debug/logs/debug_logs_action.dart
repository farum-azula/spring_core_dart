import 'package:spring_boot_dart/spring_boot_dart.dart' show SpringLogRecord;

/// What a bean adds to the debug panel's Logs tab: a button per
/// [DebugLogsAction]. The tab calls an action with the marked records, or
/// with every record its filter shows when none is marked, oldest first,
/// and shows what it returns. The log export (`debugLogExport`) is one;
/// an application or a library adds its own as a bean.
abstract interface class DebugLogsActions {
  /// The buttons, in order.
  List<DebugLogsAction> get actions;
}

/// A button of the Logs tab: its [label], and what it does with the
/// records ([run]), which returns what to tell the user.
final class DebugLogsAction {
  /// The button [label] calling [run]; [short] where room is scarce (the
  /// debug console), [label] by default.
  const DebugLogsAction(this.label, this.run, {String? short})
    : short = short ?? label;

  /// Its text.
  final String label;

  /// Its text in the debug console's log pane.
  final String short;

  /// Does it with the records, oldest first; the text shown after it.
  final Future<String> Function(List<SpringLogRecord> records) run;
}
