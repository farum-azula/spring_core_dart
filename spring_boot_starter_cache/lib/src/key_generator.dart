import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Computes cache keys from a call, like Spring's `KeyGenerator`. Used
/// when an annotation has no `key`; a `KeyGenerator` bean can be named
/// with `keyGenerator:`.
///
/// ```dart
/// class IsbnKeys implements KeyGenerator {
///   const IsbnKeys();
///
///   @override
///   Object? generate(Object target, MethodSignature method, List<Object?> args) =>
///       (args.first! as String).replaceAll('-', '');
/// }
///
/// @Configuration()
/// class Keys {
///   @Bean()
///   KeyGenerator isbnKeys() => const IsbnKeys();
/// }
///
/// @Cacheable('books', keyGenerator: 'isbnKeys')
/// Book find(String isbn) => ...;
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// KeyGenerator isbnKeys() {
///   return (target, method, params) -> ((String) params[0]).replace("-", "");
/// }
/// ```
abstract interface class KeyGenerator {
  /// The key of a call of [method] on [target] with [args].
  Object? generate(Object target, MethodSignature method, List<Object?> args);
}

/// The default [KeyGenerator], like Spring's `SimpleKeyGenerator`: no
/// arguments give [SimpleKey.empty], one argument is the key itself
/// (collections are wrapped so they compare by content), several give a
/// [SimpleKey] of all of them.
///
/// ```dart
/// const generator = SimpleKeyGenerator();
/// generator.generate(books, signature, []);           // SimpleKey.empty
/// generator.generate(books, signature, ['978-0']);    // '978-0'
/// generator.generate(books, signature, ['978-0', 2]); // SimpleKey([978-0, 2])
/// ```
///
/// Spring (Java):
/// ```java
/// new SimpleKeyGenerator().generate(books, method, "978-0", 2);
/// ```
final class SimpleKeyGenerator implements KeyGenerator {
  /// Creates the generator.
  const SimpleKeyGenerator();

  @override
  Object? generate(Object target, MethodSignature method, List<Object?> args) =>
      generateKey(args);

  /// The key of [args] (see the class documentation).
  static Object generateKey(List<Object?> args) {
    if (args.isEmpty) {
      return SimpleKey.empty;
    }
    if (args.length == 1) {
      final arg = args.single;
      if (arg != null && arg is! Iterable && arg is! Map) {
        return arg;
      }
    }
    return SimpleKey(args);
  }
}

/// A key made of several values that compares by content (nested lists,
/// sets and maps too), like Spring's `SimpleKey`.
///
/// ```dart
/// SimpleKey(['978-0', 2]) == SimpleKey(['978-0', 2]); // true
/// SimpleKey([[1, 2]]) == SimpleKey([[1, 2]]);         // true
/// ```
///
/// Spring (Java):
/// ```java
/// new SimpleKey("978-0", 2).equals(new SimpleKey("978-0", 2)); // true
/// ```
final class SimpleKey {
  /// A key of [params] (copied).
  SimpleKey(List<Object?> params) : params = List.unmodifiable(params);

  const SimpleKey._empty() : params = const [];

  /// The key of a call without arguments.
  static const SimpleKey empty = SimpleKey._empty();

  /// The values.
  final List<Object?> params;

  @override
  bool operator ==(Object other) =>
      other is SimpleKey && _deepEquals(params, other.params);

  @override
  int get hashCode => _deepHash(params);

  @override
  String toString() => 'SimpleKey [${params.join(',')}]';
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Set && b is Set) {
    return a.length == b.length &&
        a.every((x) => b.any((y) => _deepEquals(x, y)));
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _deepEquals(a[k], b[k]));
  }
  return a == b;
}

int _deepHash(Object? value) => switch (value) {
  final List<Object?> list => Object.hashAll(list.map(_deepHash)),
  final Set<Object?> set => Object.hashAllUnordered(set.map(_deepHash)),
  final Map<Object?, Object?> map => Object.hashAllUnordered(
    map.entries.map((e) => Object.hash(_deepHash(e.key), _deepHash(e.value))),
  ),
  _ => value.hashCode,
};
