import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_logs_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_filter.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_marks.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_text.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_logs_action.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart'
    show LogBuffer, LoggingSystem, SpringLogRecord;

/// The debug console's `logs` pane (the `logsPane` bean, order 0, on top):
/// the records of the logging system's buffer, newest at the bottom, each
/// coloured as the console colours it and wrapped when long, by [filter],
/// the `debugLogFilter` bean the debug panel's Logs tab shares (a level
/// chosen there changes the pane at once). A wheel, a trackpad or a drag
/// over the records scrolls back through older ones, as far as the buffer
/// keeps them, and it follows the newest again once scrolled to the bottom
/// ([paused] while it does not).
///
/// It adds to the console's header, while it shows, `paused` and its
/// selection (`Select`; [selecting], [marks], [chosenRecords], [actions]);
/// a selection that starts makes the console's panes interact
/// (`DebugConsole.interaction`).
///
/// In the build only when `spring.flutter.debug.console.panes` names `logs`
/// or holds `*`, or is not set (its default is `[logs]`); with it out, its
/// view, its selection and the console's `export` command are no code in
/// the app. The records are written to the buffer all the same.
final class LogsPane extends DebugConsolePane with ChangeNotifier {
  /// The pane of [buffer] by [filter], [maxLines] lines high at the start;
  /// records are copied in the pattern of [logging]'s console, and
  /// [actions] (the log export) add words to its selection.
  LogsPane({
    required this.filter,
    this.buffer,
    this._logging,
    List<DebugLogsActions> actions = const [],
    int maxLines = 12,
  }) : actions = List.unmodifiable([
         for (final source in actions) ...source.actions,
       ]),
       maxLines = math.max(1, maxLines);

  /// The records; `null`: the app has no logging system.
  final LogBuffer? buffer;

  /// Which records show.
  final DebugLogFilter filter;

  final LoggingSystem? _logging;

  /// The words of its selection (the log export's), called with
  /// [chosenRecords].
  final List<DebugLogsAction> actions;

  /// How many lines of records high it starts.
  final int maxLines;

  /// The records marked whole (its pick mode).
  final DebugLogMarks marks = DebugLogMarks();

  /// Whether it is scrolled up, the lines read kept.
  final ValueNotifier<bool> paused = ValueNotifier(false);

  bool _selecting = false;

  /// Whether it selects: its records take taps (a tap marks one) and their
  /// text selects. Off, every tap on it goes through to the app; a long
  /// press, or a click with ⇧, ⌘ or Ctrl, on a record marks it and turns it
  /// on. Turned off, the marks are cleared.
  bool get selecting => _selecting;

  set selecting(bool value) {
    if (value == _selecting) {
      return;
    }
    _selecting = value;
    if (!value) {
      marks.clear();
    }
    notifyListeners();
  }

  /// The records an action or the `export` command takes: the marked
  /// ones, else every record the filter shows; oldest first.
  List<SpringLogRecord> get chosenRecords {
    final records = buffer?.records ?? const <SpringLogRecord>[];
    return marks.isEmpty
        ? [
            for (final record in records)
              if (filter.matches(record)) record,
          ]
        : marks.of(records);
  }

  /// [records] as plain text in the console's pattern, without colours.
  String plainText(Iterable<SpringLogRecord> records) => debugLogPlainLines(
    records,
    _logging?.console.pattern ?? debugLogFallbackPattern,
  );

  @override
  String get title => 'Logs';

  @override
  double get initialHeight => DebugConsoleView.lineHeight * maxLines;

  @override
  Widget build(BuildContext context, DebugConsole console) =>
      DebugConsoleLogsView(pane: this, console: console);

  @override
  Widget buildHeader(BuildContext context, DebugConsole console) =>
      DebugConsoleLogsHeader(pane: this);

  @override
  void dispose() {
    paused.dispose();
    marks.dispose();
    super.dispose();
  }
}
