import 'dart:collection';

/// Whether [a] and [b] are equal by content: lists, sets, maps and other
/// iterables compare their elements (nested ones too), any other value
/// compares with its own `==`.
///
/// Dart's lists, sets and maps are equal only to themselves, so a class
/// whose `==` compares a `List` field with `==` calls two objects with the
/// same tags different. The `==` the generator writes for
/// `@EqualsAndHashCode` compares such fields with this function, and
/// [deepHash] gives the matching `hashCode`.
///
/// - Two lists, or two iterables that are no sets, are equal when they
///   have equal elements in the same order (a `List` and a lazy
///   `Iterable` with the same elements too).
/// - Two sets are equal when they have equal elements in any order; a set
///   is never equal to an iterable that is no set.
/// - Two maps are equal when they have the same keys (by the keys' own
///   `==`) with equal values.
/// - Anything else: `a == b`, so `null` equals only `null`.
///
/// A collection that contains itself is compared without end, as with
/// `package:collection`'s `DeepCollectionEquality`.
///
/// ```dart
/// deepEquals([1, [2, 3]], [1, [2, 3]]);       // true
/// deepEquals({'a', 'b'}, {'b', 'a'});         // true
/// deepEquals({'a': [1]}, {'a': [1]});         // true
/// deepEquals([1, 2], {1, 2});                 // false: a list, a set
/// [1, 2] == [1, 2];                           // false: two lists
/// ```
///
/// Spring (Java): `java.util.Objects.deepEquals` and the content equality
/// of Java's `List`, `Set` and `Map`, which Lombok's `@EqualsAndHashCode`
/// relies on.
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is Iterable<Object?>) {
    if (a is List<Object?> && b is List<Object?>) {
      return _listsEqual(a, b);
    }
    if (b is! Iterable<Object?>) {
      return false;
    }
    if (a is Set<Object?> || b is Set<Object?>) {
      return a is Set<Object?> && b is Set<Object?> && _setsEqual(a, b);
    }
    return _iterablesEqual(a, b);
  }
  if (a is Map<Object?, Object?>) {
    return b is Map<Object?, Object?> && _mapsEqual(a, b);
  }
  return a == b;
}

/// A hash code of [value] by content, consistent with [deepEquals]: two
/// values [deepEquals] calls equal have the same hash.
///
/// Lists and other iterables that are no sets combine their elements'
/// hashes in order, sets and maps in any order (a map by its keys' own
/// `hashCode` and its values' [deepHash]); any other value gives its own
/// `hashCode`. The `hashCode` the generator writes for
/// `@EqualsAndHashCode` hashes collection fields with it, so an object
/// found by its content in a `Set` or as a `Map` key stays found when an
/// equal list replaces its list.
///
/// ```dart
/// deepHash([1, [2, 3]]) == deepHash([1, [2, 3]]);   // true
/// deepHash({'a', 'b'}) == deepHash({'b', 'a'});     // true
/// deepHash('Dune') == 'Dune'.hashCode;              // true
/// ```
///
/// Spring (Java): `java.util.Arrays.deepHashCode`, and the content hash of
/// Java's `List`, `Set` and `Map`.
int deepHash(Object? value) {
  if (value is Iterable<Object?>) {
    if (value is List<Object?>) {
      var hash = 0;
      for (var i = 0; i < value.length; i++) {
        hash = _combine(hash, deepHash(value[i]));
      }
      return _finish(hash);
    }
    if (value is Set<Object?>) {
      var sum = 0;
      for (final element in value) {
        sum = 0x1fffffff & (sum + deepHash(element));
      }
      return _finish(sum);
    }
    // In order, as a list: a list and an iterable can be equal.
    var hash = 0;
    for (final element in value) {
      hash = _combine(hash, deepHash(element));
    }
    return _finish(hash);
  }
  if (value is Map<Object?, Object?>) {
    var sum = 0;
    for (final MapEntry(:key, value: entry) in value.entries) {
      sum =
          0x1fffffff &
          (sum + _finish(_combine(_combine(0, key.hashCode), deepHash(entry))));
    }
    return _finish(sum);
  }
  return value.hashCode;
}

// Jenkins's one-at-a-time hash, as the SDK combines hashes; within 29 bits,
// so the same on the web.
int _combine(int hash, int value) {
  var result = 0x1fffffff & (hash + value);
  result = 0x1fffffff & (result + ((0x0007ffff & result) << 10));
  return result ^ (result >> 6);
}

int _finish(int hash) {
  var result = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  result = result ^ (result >> 11);
  return 0x1fffffff & (result + ((0x00003fff & result) << 15));
}

bool _listsEqual(List<Object?> a, List<Object?> b) {
  final length = a.length;
  if (length != b.length) {
    return false;
  }
  for (var i = 0; i < length; i++) {
    final left = a[i];
    final right = b[i];
    if (!identical(left, right) && !deepEquals(left, right)) {
      return false;
    }
  }
  return true;
}

bool _iterablesEqual(Iterable<Object?> a, Iterable<Object?> b) {
  final left = a.iterator;
  final right = b.iterator;
  while (true) {
    final more = left.moveNext();
    if (more != right.moveNext()) {
      return false;
    }
    if (!more) {
      return true;
    }
    if (!deepEquals(left.current, right.current)) {
      return false;
    }
  }
}

bool _setsEqual(Set<Object?> a, Set<Object?> b) {
  if (a.length != b.length) {
    return false;
  }
  // Every element found by the set's own lookup: the usual case, and the
  // only one for elements that are no collections.
  if (a.every(b.contains)) {
    return true;
  }
  // Elements equal by content only (lists in sets): each element of [b]
  // takes one equal element of [a].
  final counts = HashMap<Object?, int>(equals: deepEquals, hashCode: deepHash);
  for (final element in a) {
    counts[element] = (counts[element] ?? 0) + 1;
  }
  for (final element in b) {
    final count = counts[element];
    if (count == null || count == 0) {
      return false;
    }
    counts[element] = count - 1;
  }
  return true;
}

bool _mapsEqual(Map<Object?, Object?> a, Map<Object?, Object?> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry(:key, :value) in a.entries) {
    if (!b.containsKey(key) || !deepEquals(value, b[key])) {
      return false;
    }
  }
  return true;
}
