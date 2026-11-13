// The collections a @Signal field hands out: the same elements as the
// field's own collection, with every read followed and every change in
// place told, once for each change, also inside a batch.
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';

/// Counts how often [read] is run again after the first time.
int Function() _reruns(void Function() read) {
  var runs = 0;
  signals.effect(() {
    read();
    runs++;
  });
  return () => runs - 1;
}

void main() {
  test('a list: the same elements, reads followed, each change told once', () {
    final source = <int>[3, 1, 2];
    final list = FollowedList<int>(source, 'numbers');
    final reruns = _reruns(() => list.length);

    list.add(4);
    expect(source, [3, 1, 2, 4]);
    expect(reruns(), 1);

    // Many elements moved, one change.
    list.sort();
    expect(source, [1, 2, 3, 4]);
    expect(reruns(), 2);

    list
      ..removeWhere((n) => n.isEven)
      ..[0] = 7;
    expect(source, [7, 3]);
    expect(reruns(), 4);
    expect(list, isA<List<int>>());
  });

  test('a change inside a batch is told when the batch ends', () {
    final list = FollowedList<int>([], 'numbers');
    final reruns = _reruns(() => list.isEmpty);

    signals.batch(() {
      list
        ..add(1)
        ..add(2);
      expect(reruns(), 0);
    });
    expect(reruns(), 1);
  });

  test('a set tells only of what changed it', () {
    final set = FollowedSet<String>({'a'}, 'tags');
    final reruns = _reruns(() => set.contains('b'));

    expect(set.add('a'), isFalse);
    expect(reruns(), 0);
    expect(set.add('b'), isTrue);
    expect(reruns(), 1);
    expect(set.remove('missing'), isFalse);
    expect(reruns(), 1);
    set.clear();
    expect(set.source, isEmpty);
    expect(reruns(), 2);
  });

  test('a map', () {
    final source = <String, int>{'a': 1};
    final map = FollowedMap<String, int>(source, 'prices');
    final reruns = _reruns(() => map['a']);

    map['b'] = 2;
    expect(source, {'a': 1, 'b': 2});
    expect(reruns(), 1);
    expect(map.remove('missing'), isNull);
    expect(reruns(), 1);
    map.remove('a');
    expect(reruns(), 2);
    expect(map.keys, ['b']);
  });

  test('a queue', () {
    final queue = FollowedQueue<int>(Queue.of([1, 2]), 'jobs');
    final reruns = _reruns(() => queue.length);

    queue.addFirst(0);
    expect(queue.toList(), [0, 1, 2]);
    expect(queue.removeLast(), 2);
    expect(reruns(), 2);
    expect(queue, isA<Queue<int>>());
  });

  group('a field', () {
    test('hands a list out as a followed one of its element type', () {
      final member = ValueMember(
        'Basket.items',
        <String>['a'],
        arguments: const [TypeCapture<String>()],
      );
      final handed = member.read();
      expect(handed, isA<FollowedList<String>>());
      expect(handed, isA<List<String>>());
      // The field keeps the list itself.
      expect(member.peek(), isNot(isA<FollowedList<String>>()));
      // What was handed out, assigned back, is the same list.
      expect(member.unwrap(handed), same(member.peek()));
      expect(member.unwrap(<String>['b']), ['b']);
    });

    test('without the element type a list stays plain', () {
      final member = ValueMember('Basket.items', <String>['a']);
      expect(member.read(), isNot(isA<FollowedList<String>>()));
    });

    test('a map takes two types; null is a plain value', () {
      final map = ValueMember(
        'Prices.byIsbn',
        <String, int>{},
        arguments: const [TypeCapture<String>(), TypeCapture<int>()],
      );
      expect(map.read(), isA<FollowedMap<String, int>>());

      final empty = ValueMember(
        'Basket.items',
        null,
        arguments: const [TypeCapture<String>()],
      );
      expect(empty.read(), isNull);
      empty.write(<String>['a']);
      expect(empty.read(), isA<FollowedList<String>>());
      expect(empty.changes, 1);
    });
  });
}
