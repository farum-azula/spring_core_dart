import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart'
    show SpringLogLevel, SpringLogRecord;
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_span.dart';

/// Which log records the debug panel's Logs tab and the debug console show
/// (the `debugLogFilter` bean): from a [level] up, with [text] in the
/// message or the logger's name. One filter for both, so a level chosen
/// in the tab changes the console at once; a bean, so it is kept while the
/// panel is closed.
///
/// It starts as `spring.flutter.debug.console.filter.*` says.
class DebugLogFilter extends ChangeNotifier {
  /// Records of [level] and above containing [text].
  DebugLogFilter({this._level = SpringLogLevel.trace, String text = ''})
    : _text = text,
      _needle = text.toLowerCase();

  SpringLogLevel _level;
  String _text;
  String _needle;

  /// The lowest level shown.
  SpringLogLevel get level => _level;

  set level(SpringLogLevel value) {
    if (value != _level) {
      _level = value;
      notifyListeners();
    }
  }

  /// What a record's message or logger name must contain, in any case;
  /// empty: every record.
  String get text => _text;

  set text(String value) {
    if (value != _text) {
      _text = value;
      _needle = value.toLowerCase();
      notifyListeners();
    }
  }

  /// Whether [record] is shown.
  bool matches(SpringLogRecord record) {
    if (record.level.index < _level.index) {
      return false;
    }
    return _needle.isEmpty ||
        record.message.toLowerCase().contains(_needle) ||
        record.loggerName.toLowerCase().contains(_needle);
  }
}

/// The levels to filter by, with their labels: the lowest level shown.
const debugLogLevels = [
  ('All', SpringLogLevel.trace),
  ('Debug', SpringLogLevel.debug),
  ('Info', SpringLogLevel.info),
  ('Warning', SpringLogLevel.warning),
  ('Error', SpringLogLevel.error),
];

/// [record] in one line: its time, level, logger and message.
String debugLogLine(SpringLogRecord record) =>
    '${debugLogTime(record)} ${debugLogLevel(record)} '
    '${record.loggerName}: ${record.message}';
