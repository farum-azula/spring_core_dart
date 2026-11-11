import 'package:spring_boot_starter_supabase/src/realtime/realtime_model.dart';

/// Who is present on a channel, kept up to date from the two messages of
/// the protocol: `presence_state` (everyone, after a join) and
/// `presence_diff` (who came and who left since).
///
/// A channel keeps one behind `RealtimeChannelSession.presence`;
/// applications use it only to follow presences of a Phoenix channel by
/// hand. The merge is the one of `phoenix.js`, by key and by the
/// reference of each presence (`phx_ref`).
///
/// ```dart
/// final present = RealtimePresenceState()
///   ..syncState({
///     'ann': {
///       'metas': [
///         {'phx_ref': 'a1', 'name': 'Ann'},
///       ],
///     },
///   })
///   ..syncDiff({
///     'joins': {
///       'bob': {
///         'metas': [
///           {'phx_ref': 'b1', 'name': 'Bob'},
///         ],
///       },
///     },
///     'leaves': <String, Object?>{},
///   });
/// present.presences; // ann (a1), bob (b1)
/// ```
///
/// Phoenix (JavaScript): `Presence.syncState` and `Presence.syncDiff`.
final class RealtimePresenceState {
  /// Nobody present.
  RealtimePresenceState();

  // The presences of each key, in the order they came.
  final _state = <String, List<RealtimePresence>>{};

  /// Whether nobody is present.
  bool get isEmpty => _state.isEmpty;

  /// The keys that are present, in the order they came.
  Iterable<String> get keys => _state.keys;

  /// Everyone present: the presences of each key, in the order they came.
  List<RealtimePresence> get presences => List.unmodifiable([
    for (final presences in _state.values) ...presences,
  ]);

  /// The presences of [key]; empty when it is not present.
  List<RealtimePresence> of(String key) =>
      List.unmodifiable(_state[key] ?? const <RealtimePresence>[]);

  /// Takes [state], the payload of a `presence_state` message
  /// (`{key: {metas: [{phx_ref, ...}]}}`): who is there now. What was
  /// known and is not in it has left, what is new has come; a presence
  /// that is in both stays as it was.
  void syncState(Object? state) {
    final next = _read(state);
    final joins = <String, List<RealtimePresence>>{};
    final leaves = <String, List<RealtimePresence>>{};
    for (final MapEntry(:key, value: current) in _state.entries) {
      if (!next.containsKey(key)) {
        leaves[key] = current;
      }
    }
    for (final MapEntry(:key, value: arrived) in next.entries) {
      final current = _state[key];
      if (current == null) {
        joins[key] = arrived;
        continue;
      }
      final joined = _without(arrived, current);
      final left = _without(current, arrived);
      if (joined.isNotEmpty) {
        joins[key] = joined;
      }
      if (left.isNotEmpty) {
        leaves[key] = left;
      }
    }
    _apply(joins, leaves);
  }

  /// Takes [diff], the payload of a `presence_diff` message
  /// (`{joins: {key: {metas}}, leaves: {key: {metas}}}`): the presences
  /// in `joins` are added to their key (after the ones it has, replacing
  /// those with the same reference), the ones in `leaves` are removed by
  /// their reference, and a key without any presence left is gone.
  void syncDiff(Object? diff) {
    if (diff is! Map) {
      return;
    }
    _apply(_read(diff['joins']), _read(diff['leaves']));
  }

  /// Forgets everyone, when the channel is left.
  void clear() => _state.clear();

  void _apply(
    Map<String, List<RealtimePresence>> joins,
    Map<String, List<RealtimePresence>> leaves,
  ) {
    for (final MapEntry(:key, value: arrived) in joins.entries) {
      final current = _state[key];
      _state[key] = [
        if (current != null) ..._without(current, arrived),
        ...arrived,
      ];
    }
    for (final MapEntry(:key, value: left) in leaves.entries) {
      final current = _state[key];
      if (current == null) {
        continue;
      }
      final remaining = _without(current, left);
      if (remaining.isEmpty) {
        _state.remove(key);
      } else {
        _state[key] = remaining;
      }
    }
  }

  // The presences of [all] whose reference is not among [others].
  static List<RealtimePresence> _without(
    List<RealtimePresence> all,
    List<RealtimePresence> others,
  ) {
    final refs = {for (final presence in others) presence.ref};
    return [
      for (final presence in all)
        if (!refs.contains(presence.ref)) presence,
    ];
  }

  // `{key: {metas: [{phx_ref, ...}]}}` as presences by key.
  static Map<String, List<RealtimePresence>> _read(Object? json) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (value case {'metas': final List<Object?> metas})
          '$key': [
            for (final meta in metas)
              if (meta is Map)
                RealtimePresence(
                  key: '$key',
                  ref: '${meta['phx_ref'] ?? ''}',
                  state: {
                    for (final MapEntry(key: name, :value) in meta.entries)
                      if (name != 'phx_ref' && name != 'phx_ref_prev')
                        '$name': value,
                  },
                ),
          ],
  };

  @override
  String toString() => 'RealtimePresenceState(${_state.keys.join(', ')})';
}
