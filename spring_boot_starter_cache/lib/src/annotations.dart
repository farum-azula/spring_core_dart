/// Caches the result of a method: the first call with given arguments runs
/// the method and stores the result, later calls with an equal key return
/// it without running the method, like Spring's `@Cacheable`.
///
/// Works through the generated AOP proxy of the bean (see the package
/// README): calls through `this` inside the bean are not cached.
///
/// [key], [condition] and [unless] are SpEL expressions (without `#{}`),
/// with the arguments as `#name`, `#p0` / `#a0` and `#root.methodName`,
/// `#root.args`, `#root.target`, `#root.targetClass`, `#root.caches`;
/// [unless] also sees the result as `#result`.
///
/// ```dart
/// @Service()
/// class Books {
///   @Cacheable('books')
///   Book find(String isbn) => repository.load(isbn);
///
///   @Cacheable('books', key: '#isbn', condition: '#isbn.length == 13',
///       unless: '#result == null')
///   Book? findIsbn13(String isbn, bool fresh) => repository.find(isbn);
///
///   @Cacheable('prices', sync: true)
///   Future<double> price(String isbn) => api.price(isbn); // value cached
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Books {
///   @Cacheable("books")
///   Book find(String isbn) { return repository.load(isbn); }
///
///   @Cacheable(cacheNames = "books", key = "#isbn",
///       condition = "#isbn.length() == 13", unless = "#result == null")
///   Book findIsbn13(String isbn, boolean fresh) { ... }
/// }
/// ```
class Cacheable {
  /// Caches in the cache named [value] (and [cacheNames]).
  const Cacheable(
    String this.value, {
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.unless,
    this.sync = false,
    this.keyGenerator,
    this.cacheManager,
  });

  /// Caches in [cacheNames], or in those of the class's `@CacheConfig`
  /// when empty: `@Cacheable.of(cacheNames: ['books', 'isbn'])`,
  /// `@Cacheable.of(key: '#isbn')`.
  const Cacheable.of({
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.unless,
    this.sync = false,
    this.keyGenerator,
    this.cacheManager,
  }) : value = null;

  /// A cache name (Spring's `value`, an alias of `cacheNames`).
  final String? value;

  /// Cache names; the result is looked up in each, in order, and stored in
  /// all of them.
  final List<String> cacheNames;

  /// SpEL computing the key; default: the arguments (see `SimpleKey`).
  final String? key;

  /// SpEL; caching applies only when it is `true` (no `#result`).
  final String? condition;

  /// SpEL with `#result`; the result is not stored when it is `true`.
  final String? unless;

  /// For methods returning a `Future`: concurrent calls with the same key
  /// share one call instead of running the method several times.
  final bool sync;

  /// Name of a `KeyGenerator` bean to compute the key (instead of [key]).
  final String? keyGenerator;

  /// Name of the `CacheManager` bean to use.
  final String? cacheManager;
}

/// Always runs the method and stores its result, like Spring's
/// `@CachePut`: updates the cache without skipping the call.
///
/// [key] and [condition] are evaluated after the call and may use
/// `#result`.
///
/// ```dart
/// @CachePut('books', key: '#result.isbn') // Book is @Introspected
/// Book save(Book book) => repository.save(book);
/// ```
///
/// Spring (Java):
/// ```java
/// @CachePut(cacheNames = "books", key = "#result.isbn")
/// Book save(Book book) { return repository.save(book); }
/// ```
class CachePut {
  /// Stores the result in the cache named [value] (and [cacheNames]).
  const CachePut(
    String this.value, {
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.unless,
    this.keyGenerator,
    this.cacheManager,
  });

  /// Stores the result in [cacheNames], or in those of `@CacheConfig`.
  const CachePut.of({
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.unless,
    this.keyGenerator,
    this.cacheManager,
  }) : value = null;

  /// A cache name (Spring's `value`).
  final String? value;

  /// Cache names.
  final List<String> cacheNames;

  /// SpEL computing the key (may use `#result`).
  final String? key;

  /// SpEL; the result is stored only when it is `true` (may use
  /// `#result`).
  final String? condition;

  /// SpEL with `#result`; nothing is stored when it is `true`.
  final String? unless;

  /// Name of a `KeyGenerator` bean.
  final String? keyGenerator;

  /// Name of the `CacheManager` bean.
  final String? cacheManager;
}

/// Removes entries from caches, like Spring's `@CacheEvict`.
///
/// By default the entry of [key] is removed after the method returned
/// normally (`#result` is available); [allEntries] clears the caches, and
/// [beforeInvocation] evicts before the call, even when it then throws.
///
/// ```dart
/// @CacheEvict('books', key: '#isbn')
/// void delete(String isbn) => repository.delete(isbn);
///
/// @CacheEvict('books', allEntries: true, beforeInvocation: true)
/// void reload() => repository.reload();
/// ```
///
/// Spring (Java):
/// ```java
/// @CacheEvict(cacheNames = "books", key = "#isbn")
/// void delete(String isbn) { ... }
///
/// @CacheEvict(cacheNames = "books", allEntries = true, beforeInvocation = true)
/// void reload() { ... }
/// ```
class CacheEvict {
  /// Evicts from the cache named [value] (and [cacheNames]).
  const CacheEvict(
    String this.value, {
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.allEntries = false,
    this.beforeInvocation = false,
    this.keyGenerator,
    this.cacheManager,
  });

  /// Evicts from [cacheNames], or from those of `@CacheConfig`.
  const CacheEvict.of({
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.allEntries = false,
    this.beforeInvocation = false,
    this.keyGenerator,
    this.cacheManager,
  }) : value = null;

  /// A cache name (Spring's `value`).
  final String? value;

  /// Cache names.
  final List<String> cacheNames;

  /// SpEL computing the key to remove.
  final String? key;

  /// SpEL; evicts only when it is `true`.
  final String? condition;

  /// Clears the whole caches instead of one key.
  final bool allEntries;

  /// Evicts before the method runs (also when it throws).
  final bool beforeInvocation;

  /// Name of a `KeyGenerator` bean.
  final String? keyGenerator;

  /// Name of the `CacheManager` bean.
  final String? cacheManager;
}

/// Several cache annotations of the same kind on one method, like
/// Spring's `@Caching`.
///
/// Dart allows repeating an annotation, so `@CacheEvict` can also simply be
/// written twice; `@Caching` groups them for readability.
///
/// ```dart
/// @Caching(evict: [
///   CacheEvict('books', key: '#isbn'),
///   CacheEvict('authors', allEntries: true),
/// ])
/// void delete(String isbn) { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// @Caching(evict = {
///     @CacheEvict(cacheNames = "books", key = "#isbn"),
///     @CacheEvict(cacheNames = "authors", allEntries = true)})
/// void delete(String isbn) { ... }
/// ```
class Caching {
  /// Groups [cacheable], [put] and [evict] operations.
  const Caching({
    this.cacheable = const [],
    this.put = const [],
    this.evict = const [],
  });

  /// `@Cacheable` operations.
  final List<Cacheable> cacheable;

  /// `@CachePut` operations.
  final List<CachePut> put;

  /// `@CacheEvict` operations.
  final List<CacheEvict> evict;
}

/// Defaults for the cache annotations of a class, like Spring's
/// `@CacheConfig`: an operation without cache names, key generator or
/// cache manager takes them from here.
///
/// ```dart
/// @Service()
/// @CacheConfig(cacheNames: ['books'])
/// class Books {
///   @Cacheable.of()
///   Book find(String isbn) => ...;
///
///   @CacheEvict.of()
///   void delete(String isbn) => ...;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// @CacheConfig(cacheNames = "books")
/// class Books {
///   @Cacheable
///   Book find(String isbn) { ... }
/// }
/// ```
class CacheConfig {
  /// Class-wide defaults.
  const CacheConfig({
    this.cacheNames = const [],
    this.keyGenerator,
    this.cacheManager,
  });

  /// Default cache names.
  final List<String> cacheNames;

  /// Default `KeyGenerator` bean name.
  final String? keyGenerator;

  /// Default `CacheManager` bean name.
  final String? cacheManager;
}
