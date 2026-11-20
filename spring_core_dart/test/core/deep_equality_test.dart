// deepEquals and deepHash: collections compared and hashed by content, as
// the == and hashCode of @EqualsAndHashCode use them.
import 'dart:collection';
import 'dart:typed_data';

import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

// Equal by deepEquals, and so with the same deepHash.
void _same(Object? a, Object? b) {
  expect(deepEquals(a, b), isTrue, reason: '$a == $b');
  expect(deepEquals(b, a), isTrue, reason: '$b == $a');
  expect(deepHash(a), deepHash(b), reason: 'hash of $a and $b');
}

void _different(Object? a, Object? b) {
  expect(deepEquals(a, b), isFalse, reason: '$a != $b');
  expect(deepEquals(b, a), isFalse, reason: '$b != $a');
}

void main() {
  test('values that are no collections compare with their own ==', () {
    _same(1, 1);
    _same('Dune', 'Dune');
    _same(null, null);
    _different(1, 2);
    _different(null, 0);
    _different('1', 1);
    expect(deepHash('Dune'), 'Dune'.hashCode);
    expect(deepHash(null), null.hashCode);
  });

  test('lists by their elements in order, nested ones too', () {
    _same([1, 2], [1, 2]);
    _same(
      <Object?>[
        1,
        [2, 3],
        null,
      ],
      <Object?>[
        1,
        [2, 3],
        null,
      ],
    );
    _same(<int>[], <String>[]);
    _same(Uint8List.fromList([1, 2]), [1, 2]);
    _different([1, 2], [2, 1]);
    _different([1, 2], [1, 2, 3]);
    _different(
      [
        [1],
      ],
      [
        [2],
      ],
    );
  });

  test('an iterable that is no set equals a list of its elements', () {
    _same([1, 2, 3].map((e) => e), [1, 2, 3]);
    _same(Queue.of([1, 2]), [1, 2]);
    _different([1, 2].map((e) => e), [1]);
    _different([1, 2].map((e) => e), [2, 1]);
  });

  test('sets by their elements in any order, never equal to a list', () {
    _same({1, 2}, {2, 1});
    _same(
      <Object?>{
        [1],
        [2],
      },
      <Object?>{
        [2],
        [1],
      },
    );
    _different({1, 2}, [1, 2]);
    _different({1, 2}, {1, 3});
    _different({1}, {1, 2});
    // Each element is matched once: two equal lists against two others.
    _different(
      Set<Object?>.identity()..addAll([
        [1],
        [1],
        [2],
      ]),
      Set<Object?>.identity()..addAll([
        [1],
        [2],
        [2],
      ]),
    );
  });

  test('maps by their keys and values, in any order', () {
    _same({'a': 1, 'b': 2}, {'b': 2, 'a': 1});
    _same(
      {
        'tags': ['sf'],
        'meta': {'pages': 412},
      },
      {
        'meta': {'pages': 412},
        'tags': ['sf'],
      },
    );
    _different({'a': 1}, {'a': 2});
    _different({'a': 1}, {'b': 1});
    _different({'a': 1}, {'a': 1, 'b': 2});
    _different({'a': null}, {'b': null});
    _different({'a': 1}, [1]);
  });

  test('identical values are equal without being compared', () {
    final list = [1, 2];
    expect(deepEquals(list, list), isTrue);
  });
}
