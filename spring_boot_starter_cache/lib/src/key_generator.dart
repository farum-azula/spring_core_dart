import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Computes the cache key of a call from the bean, the method and the
/// arguments.
///
/// A cache annotation without `key` gets its key from a key generator; the
/// default one, [SimpleKeyGenerator], uses the arguments as they are. Write
/// your own when the key needs code that a SpEL `key` cannot express well,
/// or when many methods share the same rule. Declare it as a bean and name
/// it with `keyGenerator:` in the annotation or in `@CacheConfig`, or make
/// it the default of every operation with a `CachingConfigurer`.
///
/// ```dart
/// // `978-0-13` and `978013` are the same book: one cache entry for both.
/// class IsbnKeys implements KeyGenerator {
///   const IsbnKeys();
///
///   @override
///   Object? generate(
///     Object target,
///     MethodSignature method,
///     List<Object?> args,
///   ) => (args.first! as String).replaceAll('-', '');
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
  /// The key of a call of [method] on the bean [target] with [args].
  ///
  /// Keys are compared with `==` and `hashCode`, so equal calls must give
  /// equal keys. Returning `null` fails the call with an `ArgumentError`.
  Object? generate(Object target, MethodSignature method, List<Object?> args);
}

/// The [KeyGenerator] used when an annotation has no `key`: it makes the key
/// from the arguments of the call.
///
/// - no arguments: [SimpleKey.empty], so the method has a single entry;
/// - one argument: the argument itself (`find('978-0')` has the key
///   `'978-0'`);
/// - several arguments, or one that is `null`, a list, a set or a map: a
///   [SimpleKey] of the arguments, which compares by content.
///
/// The keys are only as good as the arguments' `==`: a class of your own
/// used as an argument needs `==` and `hashCode`, or the calls never hit.
/// You do not normally create it; it is here for a key generator that
/// builds on it.
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
///
/// Spring wraps only a single array argument; here a single list, set or
/// map is wrapped too, because Dart collections compare by identity.
final class SimpleKeyGenerator implements KeyGenerator {
  /// The generator; it has no settings.
  const SimpleKeyGenerator();

  @override
  Object? generate(Object target, MethodSignature method, List<Object?> args) =>
      generateKey(args);

  /// The key of a call with [args], by the rules above; usable without an
  /// instance, for a key generator of your own that falls back to them.
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

/// A cache key made of several values, equal to another key when the values
/// are equal, also inside nested lists, sets and maps.
///
/// [SimpleKeyGenerator] builds one for a method with several arguments (or
/// one collection argument). You meet it when you read a cache by hand or
/// write a [KeyGenerator] that combines values.
///
/// ```dart
/// // A cache entry of `price(isbn, currency)`, read in a test.
/// cache.get(SimpleKey(['978-0', 'EUR']))?.value;
///
/// SimpleKey(['978-0', 2]) == SimpleKey(['978-0', 2]); // true
/// SimpleKey([[1, 2]]) == SimpleKey([[1, 2]]);         // true
/// ```
///
/// Spring (Java):
/// ```java
/// new SimpleKey("978-0", 2).equals(new SimpleKey("978-0", 2)); // true
/// ```
final class SimpleKey {
  /// A key of [params], in this order; the list is copied.
  SimpleKey(List<Object?> params) : params = List.unmodifiable(params);

  const SimpleKey._empty() : params = const [];

  /// The key of a call without arguments.
  static const SimpleKey empty = SimpleKey._empty();

  /// The values of the key, unmodifiable.
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
