@Tags(['supabase'])
library;

import 'package:test/test.dart';

import 'realtime_support.dart';

void main() {
  late RealtimePresenceState state;

  setUp(() => state = RealtimePresenceState());

  test('a state: everyone, with what each tracked and without the '
      "protocol's references", () {
    state.syncState({
      'ann': metas({
        'a1': {'name': 'Ann', 'phx_ref_prev': 'a0'},
      }),
      'bob': metas({
        'b1': {'name': 'Bob'},
      }),
    });
    expect(refs(state.presences), ['ann/a1', 'bob/b1']);
    expect(state.presences.first.state, {'name': 'Ann'});
    expect(state.of('bob').single.key, 'bob');
    expect(state.of('nobody'), isEmpty);
    expect(state.keys, ['ann', 'bob']);
    expect(state.isEmpty, isFalse);
  });

  test('a diff: joins are added, leaves are removed by their '
      'reference, an empty key is gone', () {
    state
      ..syncState({
        'ann': metas({'a1': {}}),
        'bob': metas({'b1': {}}),
      })
      ..syncDiff({
        'joins': {
          'cid': metas({'c1': {}}),
        },
        'leaves': {
          'bob': metas({'b1': {}}),
          // Never known: nothing happens.
          'dan': metas({'d1': {}}),
        },
      });
    expect(refs(state.presences), ['ann/a1', 'cid/c1']);
    state.syncDiff({
      'joins': <String, Object?>{},
      'leaves': {
        // Another reference of ann: she stays.
        'ann': metas({'a9': {}}),
      },
    });
    expect(refs(state.presences), ['ann/a1', 'cid/c1']);
  });

  test('one key several times: a join adds a presence after the ones '
      'of the key, a leave takes one away', () {
    state
      ..syncState({
        'ann': metas({
          'a1': {'device': 'phone'},
        }),
      })
      ..syncDiff({
        'joins': {
          'ann': metas({
            'a2': {'device': 'laptop'},
          }),
        },
        'leaves': <String, Object?>{},
      });
    expect(refs(state.presences), ['ann/a1', 'ann/a2']);
    expect(
      [for (final presence in state.of('ann')) presence.state['device']],
      ['phone', 'laptop'],
    );

    // A join with a reference the key has: that one is replaced, and
    // comes last, as phoenix.js keeps them.
    state.syncDiff({
      'joins': {
        'ann': metas({
          'a1': {'device': 'tablet'},
        }),
      },
      'leaves': <String, Object?>{},
    });
    expect(refs(state.presences), ['ann/a2', 'ann/a1']);
    expect(state.of('ann').last.state, {'device': 'tablet'});

    state.syncDiff({
      'joins': <String, Object?>{},
      'leaves': {
        'ann': metas({'a2': {}}),
      },
    });
    expect(refs(state.presences), ['ann/a1']);
    state.syncDiff({
      'joins': <String, Object?>{},
      'leaves': {
        'ann': metas({'a1': {}}),
      },
    });
    expect(state.isEmpty, isTrue);
  });

  test('tracking again in one diff: the new reference joins and the '
      'old one leaves', () {
    state
      ..syncState({
        'ann': metas({
          'a1': {'typing': false},
        }),
      })
      ..syncDiff({
        'joins': {
          'ann': metas({
            'a2': {'typing': true, 'phx_ref_prev': 'a1'},
          }),
        },
        'leaves': {
          'ann': metas({
            'a1': {'typing': false},
          }),
        },
      });
    expect(refs(state.presences), ['ann/a2']);
    expect(state.presences.single.state, {'typing': true});
  });

  test('a new state after a rejoin: who is not in it left, who is new '
      'joined, who is in both stays as known', () {
    state
      ..syncState({
        'ann': metas({
          'a1': {'seen': 'first'},
          'a2': {},
        }),
        'bob': metas({'b1': {}}),
      })
      ..syncState({
        'ann': metas({
          // Known: kept as it was. a2 is gone, a3 is new.
          'a1': {'seen': 'second'},
          'a3': {},
        }),
        'cid': metas({'c1': {}}),
      });
    expect(refs(state.presences), ['ann/a1', 'ann/a3', 'cid/c1']);
    expect(state.of('ann').first.state, {'seen': 'first'});
  });

  test('what is no presence is skipped; clear forgets everyone', () {
    state
      ..syncState({
        'ann': metas({'a1': {}}),
        'odd': 'nope',
        'bare': {'metas': 'nope'},
      })
      ..syncDiff('nope')
      ..syncDiff({'joins': null});
    expect(refs(state.presences), ['ann/a1']);
    state.syncState(null);
    expect(state.isEmpty, isTrue);
    state
      ..syncState({
        'ann': metas({'a1': {}}),
      })
      ..clear();
    expect(state.presences, isEmpty);
  });
}
