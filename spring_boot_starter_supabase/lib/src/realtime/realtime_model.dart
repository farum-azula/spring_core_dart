import 'package:spring_boot_starter_supabase/src/supabase_exception.dart';

/// What happened to a row that Realtime reports.
///
/// ```dart
/// realtime.postgresChanges(table: 'todos', kind: RealtimeChangeKind.insert);
/// ```
///
/// Supabase (JavaScript): the `event` of
/// `channel.on('postgres_changes', {event: 'INSERT', ...})`.
enum RealtimeChangeKind {
  /// A new row (`INSERT`).
  insert('INSERT'),

  /// A changed row (`UPDATE`).
  update('UPDATE'),

  /// A removed row (`DELETE`).
  delete('DELETE');

  RealtimeChangeKind(this.wire);

  /// The name in the protocol: `INSERT`, `UPDATE` or `DELETE`.
  final String wire;

  /// The kind named [wire] in the protocol (in any case), or `null`.
  static RealtimeChangeKind? of(Object? wire) => switch (wire) {
    final String text =>
      values.where((kind) => kind.wire == text.toUpperCase()).firstOrNull,
    _ => null,
  };
}

/// One change of a row of the database, as Realtime sends it after the
/// change is committed (Postgres Changes).
///
/// The rows are the JSON of the protocol: column names to values, not
/// read into an entity. What the user may not read is left out by the
/// database (row-level security); a row too large for Realtime comes
/// without its large values and says so in [errors].
///
/// ```dart
/// realtime.postgresChanges(table: 'todos').listen((change) {
///   if (change.kind == RealtimeChangeKind.delete) {
///     remove(change.oldRecord['id']);
///   } else {
///     put(change.record);
///   }
/// });
/// ```
///
/// Supabase (JavaScript): `RealtimePostgresChangesPayload` (`eventType`,
/// `new`, `old`, `commit_timestamp`, `errors`).
final class RealtimeRowChange {
  /// A change of [kind] in [schema].[table].
  const RealtimeRowChange({
    required this.kind,
    required this.schema,
    required this.table,
    this.record = const {},
    this.oldRecord = const {},
    this.commitTime,
    this.columns = const {},
    this.errors = const [],
  });

  /// Reads the `data` of a `postgres_changes` message; `null` when it is
  /// not one (no known `type`).
  static RealtimeRowChange? of(Object? data) {
    if (data is! Map) {
      return null;
    }
    final kind = RealtimeChangeKind.of(data['type']);
    if (kind == null) {
      return null;
    }
    return RealtimeRowChange(
      kind: kind,
      schema: '${data['schema'] ?? ''}',
      table: '${data['table'] ?? ''}',
      // As realtime-js: the new row of an insert or an update, the old
      // one of an update or a delete.
      record: kind == RealtimeChangeKind.delete
          ? const {}
          : _row(data['record']),
      oldRecord: kind == RealtimeChangeKind.insert
          ? const {}
          : _row(data['old_record']),
      commitTime: switch (data['commit_timestamp']) {
        final String text => DateTime.tryParse(text),
        _ => null,
      },
      columns: {
        if (data['columns'] case final List<Object?> columns)
          for (final column in columns)
            if (column case {'name': final String name})
              name: '${column['type'] ?? ''}',
      },
      errors: switch (data['errors']) {
        null => const [],
        final List<Object?> errors => [for (final error in errors) '$error'],
        final error => ['$error'],
      },
    );
  }

  static Map<String, Object?> _row(Object? json) => switch (json) {
    final Map<Object?, Object?> row => {
      for (final MapEntry(:key, :value) in row.entries) '$key': value,
    },
    _ => const {},
  };

  /// What happened to the row.
  final RealtimeChangeKind kind;

  /// The schema of the table, such as `public`.
  final String schema;

  /// The table of the row.
  final String table;

  /// The row after the change, column names to JSON values; empty for a
  /// delete.
  final Map<String, Object?> record;

  /// The row before the change: of an update or a delete, and only the
  /// columns the table's replica identity gives (the primary key, unless
  /// the table has `replica identity full`); empty for an insert.
  final Map<String, Object?> oldRecord;

  /// When the change was committed; `null` when the server did not say.
  final DateTime? commitTime;

  /// The PostgreSQL types of the columns (`int8`, `timestamptz`), by
  /// column name; empty when the server did not send them.
  final Map<String, String> columns;

  /// What the server could not do for this change, such as
  /// `Error 413: Payload Too Large`; empty when all went well.
  final List<String> errors;

  @override
  String toString() =>
      'RealtimeRowChange(${kind.wire} $schema.$table'
      '${record.isEmpty ? '' : ': $record'})';
}

/// One presence on a channel: what a client tracks while it is joined
/// (who is online, where a cursor is).
///
/// The same [key] may be present several times, once per connection that
/// tracks under it (a user on two devices); each has its own [ref].
///
/// ```dart
/// room.presence().listen((present) {
///   online.value = {for (final presence in present) presence.key};
/// });
/// ```
///
/// Supabase (JavaScript): one element of `channel.presenceState()[key]`,
/// with [ref] as `presence_ref`.
final class RealtimePresence {
  /// A presence under [key] with the server's [ref] and what the client
  /// tracked as [state].
  const RealtimePresence({
    required this.key,
    required this.ref,
    this.state = const {},
  });

  /// The key the client joined with (`presenceKey`), or the one the
  /// server made up for it.
  final String key;

  /// The server's reference of this one presence (`phx_ref`): it changes
  /// when the client tracks again.
  final String ref;

  /// What the client tracked, as JSON.
  final Map<String, Object?> state;

  @override
  bool operator ==(Object other) =>
      other is RealtimePresence && other.key == key && other.ref == ref;

  @override
  int get hashCode => Object.hash(key, ref);

  @override
  String toString() => 'RealtimePresence($key, $ref, $state)';
}

/// Thrown, or sent as an error event of a channel's streams, when
/// Realtime reports a problem with a channel: a subscription to database
/// changes it could not make (a wrong filter, a table that is not in the
/// publication), a limit that was passed, a token that expired.
///
/// A problem of the database changes ([extension] `postgres_changes`)
/// leaves the channel joined; one of the channel itself ([extension]
/// `system`) is followed by the end of its streams.
///
/// ```dart
/// realtime.postgresChanges(table: 'todos', filter: 'id=nope.1').listen(
///   show,
///   onError: (Object error) => log.warning('no changes: $error'),
/// );
/// ```
///
/// Supabase (JavaScript): the payload of a `system` event with the status
/// `error`, and the `CHANNEL_ERROR` of `subscribe`.
class RealtimeException extends SupabaseException {
  /// A problem of the channel [topic], described by [message].
  RealtimeException(
    super.message, {
    required this.topic,
    this.extension,
    this.status,
    super.cause,
  });

  /// The topic of the channel, such as `realtime:room:42`.
  final String topic;

  /// The part of Realtime that reported it: `postgres_changes`, or
  /// `system` for the channel itself; `null` when this client found the
  /// problem.
  final String? extension;

  /// The status the server gave, usually `error`.
  final String? status;

  @override
  String toString() => describe('RealtimeException');
}
