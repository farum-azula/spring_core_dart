import 'dart:async';
import 'dart:collection';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/appenders.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';

/// The last [capacity] log records in memory, ready for a log viewer
/// screen: snapshots, filtering with [LogQuery], live streams, counters and
/// text export.
///
/// The logging system keeps one (`LoggingSystem.buffer`); it is also a
/// bean, so a screen can get it injected.
///
/// ```dart
/// // Flutter: a filtered, live list.
/// StreamBuilder<List<SpringLogRecord>>(
///   stream: buffer.watch(
///     LogQuery(minLevel: SpringLogLevel.info, text: query),
///   ),
///   builder: (context, snapshot) => ListView(
///     children: [
///       for (final record in snapshot.data ?? const <SpringLogRecord>[])
///         ListTile(
///           key: ValueKey(record.sequence),
///           title: Text(record.message),
///           subtitle: Text('${record.loggerName} · ${record.time}'),
///         ),
///     ],
///   ),
/// );
///
/// buffer.counts[SpringLogLevel.error]; // badge
/// buffer.export(query);                // share / copy to clipboard
/// buffer.clear();
/// ```
class LogBuffer extends LogAppender {
  /// A buffer keeping the last [capacity] records.
  LogBuffer({int capacity = 1000, super.threshold}) : _capacity = capacity {
    _checkCapacity(capacity);
  }

  final _records = ListQueue<SpringLogRecord>();
  final _onRecord = StreamController<SpringLogRecord>.broadcast(sync: true);
  final _onChange = StreamController<void>.broadcast();
  bool _changeScheduled = false;
  int _capacity;
  int _dropped = 0;

  /// How many records are kept; the oldest are dropped first.
  int get capacity => _capacity;

  set capacity(int value) {
    _checkCapacity(value);
    _capacity = value;
    if (_trim()) {
      _changed();
    }
  }

  static void _checkCapacity(int value) {
    if (value < 1) {
      throw ArgumentError.value(value, 'capacity', 'must be at least 1');
    }
  }

  /// The kept records, oldest first (a snapshot).
  List<SpringLogRecord> get records => List.unmodifiable(_records);

  /// Number of kept records.
  int get length => _records.length;

  /// Whether no record is kept.
  bool get isEmpty => _records.isEmpty;

  /// Records dropped because the buffer was full (since the last [clear]).
  int get dropped => _dropped;

  /// Kept records per level (every level is present).
  Map<SpringLogLevel, int> get counts {
    final counts = {
      for (final level in SpringLogLevel.values)
        if (level != SpringLogLevel.off) level: 0,
    };
    for (final record in _records) {
      counts[record.level] = counts[record.level]! + 1;
    }
    return Map.unmodifiable(counts);
  }

  /// Names of the loggers in the buffer, sorted (for a filter menu).
  List<String> get loggerNames => List.unmodifiable(
    {for (final record in _records) record.loggerName}.toList()..sort(),
  );

  /// The kept records matching [query], oldest first.
  List<SpringLogRecord> query([LogQuery query = const LogQuery()]) =>
      List.unmodifiable(_records.where(query.matches));

  /// Every record as it is added (synchronously).
  Stream<SpringLogRecord> get onRecord => _onRecord.stream;

  /// Fires once per burst of changes (records added, dropped, cleared).
  Stream<void> get onChange => _onChange.stream;

  /// The records matching [query]: the current list first, then a new list
  /// after every burst of changes. Made for `StreamBuilder`.
  Stream<List<SpringLogRecord>> watch([LogQuery query = const LogQuery()]) {
    late final StreamController<List<SpringLogRecord>> controller;
    StreamSubscription<void>? subscription;
    (int, int?)? last;
    void emit() {
      final records = this.query(query);
      // The matching records are identified by count and newest sequence.
      final key = (records.length, records.lastOrNull?.sequence);
      if (key != last) {
        last = key;
        controller.add(records);
      }
    }

    controller = StreamController<List<SpringLogRecord>>(
      onListen: () {
        emit();
        subscription = onChange.listen((_) => emit());
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  void write(SpringLogRecord record) {
    _records.addLast(record);
    _trim();
    _onRecord.add(record);
    _changed();
  }

  /// Removes every record.
  void clear() {
    _records.clear();
    _dropped = 0;
    _changed();
  }

  /// The records matching [query] as text, one record per [pattern]
  /// (without the date by default; [LogPattern.formatLine], joined by line
  /// breaks), for sharing or copying.
  String export([LogQuery query = const LogQuery(), LogPattern? pattern]) {
    final format =
        pattern ?? LogPattern('%d{HH:mm:ss.SSS} %5p [%logger] %m%X%n%ex');
    return [for (final record in this.query(query)) format.formatLine(record)]
        .join('\n');
  }

  bool _trim() {
    var trimmed = false;
    while (_records.length > _capacity) {
      _records.removeFirst();
      _dropped++;
      trimmed = true;
    }
    return trimmed;
  }

  // Coalesces bursts (e.g. 100 records in one frame) into one event.
  void _changed() {
    if (_changeScheduled) {
      return;
    }
    _changeScheduled = true;
    scheduleMicrotask(() {
      _changeScheduled = false;
      _onChange.add(null);
    });
  }

  @override
  String toString() => 'LogBuffer($length/$capacity)';
}

/// A filter for [LogBuffer] records: immutable, so it can live in a
/// screen's state and be changed with [copyWith].
///
/// All criteria must match; `null` / empty criteria match everything.
///
/// ```dart
/// var query = const LogQuery(minLevel: SpringLogLevel.info);
/// query = query.copyWith(text: 'payment');     // search box
/// query = query.copyWith(logger: 'neon.shop'); // and descendants
/// query = query.copyWith(minLevel: null);      // all levels again
/// ```
final class LogQuery {
  /// A query; the default matches every record.
  const LogQuery({
    this.minLevel,
    this.levels,
    this.logger,
    this.text,
    this.fields = const {},
    this.since,
  });

  /// Records of this level or above.
  final SpringLogLevel? minLevel;

  /// Only these levels (level toggle chips).
  final Set<SpringLogLevel>? levels;

  /// Records of this logger or its descendants (`neon` matches
  /// `neon.shop`).
  final String? logger;

  /// Case-insensitive search in the message, logger name, error and field
  /// values.
  final String? text;

  /// Records whose fields have these values (`{'request': '42'}`), compared
  /// as text.
  final Map<String, Object?> fields;

  /// Records created at or after this time.
  final DateTime? since;

  static const Object _unset = Object();

  /// A copy with the given criteria replaced; pass `null` to remove one.
  LogQuery copyWith({
    Object? minLevel = _unset,
    Object? levels = _unset,
    Object? logger = _unset,
    Object? text = _unset,
    Map<String, Object?>? fields,
    Object? since = _unset,
  }) => LogQuery(
    minLevel: identical(minLevel, _unset)
        ? this.minLevel
        : minLevel as SpringLogLevel?,
    levels: identical(levels, _unset)
        ? this.levels
        : levels as Set<SpringLogLevel>?,
    logger: identical(logger, _unset) ? this.logger : logger as String?,
    text: identical(text, _unset) ? this.text : text as String?,
    fields: fields ?? this.fields,
    since: identical(since, _unset) ? this.since : since as DateTime?,
  );

  /// Whether [record] matches every criterion.
  bool matches(SpringLogRecord record) {
    final minLevel = this.minLevel;
    if (minLevel != null && record.level.index < minLevel.index) {
      return false;
    }
    final levels = this.levels;
    if (levels != null && !levels.contains(record.level)) {
      return false;
    }
    final logger = this.logger;
    if (logger != null &&
        logger.isNotEmpty &&
        record.loggerName != logger &&
        !record.loggerName.startsWith('$logger.')) {
      return false;
    }
    final since = this.since;
    if (since != null && record.time.isBefore(since)) {
      return false;
    }
    for (final MapEntry(:key, :value) in fields.entries) {
      if (!record.fields.containsKey(key) ||
          '${record.fields[key]}' != '$value') {
        return false;
      }
    }
    final text = this.text?.trim().toLowerCase();
    if (text != null && text.isNotEmpty) {
      bool has(Object? value) =>
          value != null && '$value'.toLowerCase().contains(text);
      return has(record.message) ||
          has(record.loggerName) ||
          has(record.error) ||
          record.fields.values.any(has);
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is LogQuery &&
      other.minLevel == minLevel &&
      _sameSet(other.levels, levels) &&
      other.logger == logger &&
      other.text == text &&
      other.since == since &&
      _sameMap(other.fields, fields);

  @override
  int get hashCode => Object.hash(
    minLevel,
    levels == null ? null : Object.hashAllUnordered(levels!),
    logger,
    text,
    since,
    Object.hashAllUnordered(fields.keys),
  );

  static bool _sameSet(Set<Object?>? a, Set<Object?>? b) => a == null
      ? b == null
      : b != null && a.length == b.length && a.containsAll(b);

  static bool _sameMap(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);

  @override
  String toString() =>
      'LogQuery(minLevel: $minLevel, levels: $levels, '
      'logger: $logger, text: $text, fields: $fields, since: $since)';
}
