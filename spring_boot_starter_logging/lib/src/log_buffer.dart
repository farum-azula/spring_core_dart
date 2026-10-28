import 'dart:async';
import 'dart:collection';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/appenders.dart';
import 'package:spring_boot_starter_logging/src/log_pattern.dart';

/// The most recent log records, kept in memory so the application can
/// show them: [records], filtering with [LogQuery], live streams,
/// counters and text export.
///
/// A mobile or desktop app has no terminal its users can read. With this
/// buffer an app can offer a log screen, a "send logs" button for bug
/// reports, or an error badge in a debug menu. The logging system keeps
/// one, `LoggingSystem.buffer`, which receives every record; it is also
/// the `logBuffer` bean, so a screen can get it injected. Its size and
/// threshold come from `logging.buffer.capacity` and
/// `logging.threshold.buffer`, and `logging.buffer.enabled=false` turns it
/// off. There is no Spring counterpart.
///
/// ```dart
/// // Flutter: a live list, filtered by what the user typed in `search`.
/// final query = LogQuery(minLevel: SpringLogLevel.info, text: search);
/// StreamBuilder<List<SpringLogRecord>>(
///   stream: buffer.watch(query),
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
/// buffer.counts[SpringLogLevel.error]; // the number on an error badge
/// buffer.export(query);                // text to share or copy
/// buffer.clear();                      // the "clear" button
/// ```
class LogBuffer extends LogAppender {
  /// A buffer keeping the last [capacity] records (at least 1, else an
  /// [ArgumentError]) of level [threshold] and above. Applications use
  /// the logging system's buffer rather than create one.
  LogBuffer({int capacity = 1000, super.threshold}) : _capacity = capacity {
    _checkCapacity(capacity);
  }

  final _records = ListQueue<SpringLogRecord>();
  final _onRecord = StreamController<SpringLogRecord>.broadcast(sync: true);
  final _onChange = StreamController<void>.broadcast();
  bool _changeScheduled = false;
  int _capacity;
  int _dropped = 0;

  /// How many records are kept: when a new record would exceed it, the
  /// oldest is dropped and counted in [dropped]. Lowering it drops the
  /// oldest records at once. It must be at least 1, else an
  /// [ArgumentError] is thrown.
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

  /// The kept records, oldest first, as an unmodifiable copy that does not
  /// change when new records arrive.
  List<SpringLogRecord> get records => List.unmodifiable(_records);

  /// How many records are kept now; at most [capacity].
  int get length => _records.length;

  /// Whether no record is kept.
  bool get isEmpty => _records.isEmpty;

  /// How many records were dropped because the buffer was full, since the
  /// buffer was created or last cleared; useful for a "1 200 older lines
  /// not shown" note.
  int get dropped => _dropped;

  /// How many kept records each level has, for badges. Every level but
  /// [SpringLogLevel.off] is a key, with `0` when it has no record.
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

  /// The names of the loggers that have a kept record, sorted and without
  /// repeats, to fill a filter menu.
  List<String> get loggerNames => List.unmodifiable(
    {for (final record in _records) record.loggerName}.toList()..sort(),
  );

  /// The kept records that match [query] (all of them by default), oldest
  /// first, as an unmodifiable list.
  List<SpringLogRecord> query([LogQuery query = const LogQuery()]) =>
      List.unmodifiable(_records.where(query.matches));

  /// Each record as it enters the buffer, delivered synchronously during
  /// the logging call. Use it to react to single records, such as showing
  /// a snack bar on an error; to redraw a list, [watch] is cheaper.
  Stream<SpringLogRecord> get onRecord => _onRecord.stream;

  /// An event after each burst of changes (records added or dropped, the
  /// buffer cleared or made smaller): many records logged in one
  /// synchronous run give one event, at the end of the microtask.
  Stream<void> get onChange => _onChange.stream;

  /// The records matching [query] as a stream of lists, made for
  /// Flutter's `StreamBuilder`: the current list when listened to, then a
  /// new list after each burst of changes that alters the matching
  /// records. A burst that adds only records the query rejects emits
  /// nothing.
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

  /// Removes every record and resets [dropped] to 0, for a "clear"
  /// button; [watch] streams then emit an empty list.
  void clear() {
    _records.clear();
    _dropped = 0;
    _changed();
  }

  /// The records matching [query] as text, for sharing or copying to the
  /// clipboard: each record formatted with [pattern], joined by line
  /// breaks.
  ///
  /// The default pattern is `%d{HH:mm:ss.SSS} %5p [%logger] %m%X%n%ex`:
  /// the time without the date, the level, the logger, the message with
  /// its fields, and the error with its stack trace, without colours.
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

/// A filter for the records of a [LogBuffer], such as "warnings and
/// errors of `neon.shop` that mention payment".
///
/// A log screen keeps one in its state and passes it to
/// [LogBuffer.watch], [LogBuffer.query] or [LogBuffer.export]. It is
/// immutable: each change of a filter control makes a new query with
/// [copyWith]. A record must match every criterion that is set; a `null`
/// or empty criterion matches everything, so `const LogQuery()` matches
/// every record.
///
/// ```dart
/// var query = const LogQuery(minLevel: SpringLogLevel.info);
/// query = query.copyWith(text: 'payment');     // the search box
/// query = query.copyWith(logger: 'neon.shop'); // and its descendants
/// query = query.copyWith(minLevel: null);      // all levels again
/// ```
final class LogQuery {
  /// A query with the given criteria; with none it matches every record.
  const LogQuery({
    this.minLevel,
    this.levels,
    this.logger,
    this.text,
    this.fields = const {},
    this.since,
  });

  /// Keeps records of this level or above; `null` keeps every level.
  final SpringLogLevel? minLevel;

  /// Keeps only records of these levels, for level toggle chips; `null`
  /// keeps every level. Combined with [minLevel], both must match.
  final Set<SpringLogLevel>? levels;

  /// Keeps records of this logger or its descendants: `neon` matches
  /// `neon` and `neon.shop`, not `neonx`. The case must match.
  final String? logger;

  /// Text to search for, ignoring case and surrounding spaces, in the
  /// message, the logger name, the error and the field values.
  final String? text;

  /// Keeps records whose fields have these values, compared as text, so
  /// `{'request': '42'}` matches the field `request` with the number 42.
  final Map<String, Object?> fields;

  /// Keeps records logged at or after this time, for "since the last
  /// action"; `null` keeps all.
  final DateTime? since;

  static const Object _unset = Object();

  /// A copy with the given criteria replaced; the others stay. Pass `null`
  /// to remove a criterion, except [fields]: `null` keeps it, and
  /// `const {}` removes it.
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

  /// Whether [record] matches every criterion of this query.
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
