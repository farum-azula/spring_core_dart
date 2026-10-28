/// Marks a bean method whose results are kept in a cache: the first call
/// with given arguments runs the method and stores the result, and later
/// calls with the same key return the stored result without running it.
///
/// Use it on methods that are slow or costly and give the same answer for
/// the same arguments: a network call, a database query, a heavy
/// computation. The key is made of the arguments unless [key] or
/// [keyGenerator] say otherwise. The caches themselves come from the
/// `CacheManager` (by default caches in memory, set up with
/// `spring.cache.*`).
///
/// The cache works through the bean's generated proxy, so it applies to
/// calls coming from other beans. A call through `this` inside the same
/// class goes straight to the method and is not cached.
///
/// A method returning a `Future` caches the value, not the future: the
/// value is stored when the future completes, errors are never stored, and
/// a hit returns an already completed future. A method returning a `Stream`
/// cannot be cached (a stream can be listened to only once): the startup
/// fails; return a `Future<List<T>>` instead.
///
/// On a class, the annotation applies to every public method of the class
/// that has no cache annotation of its own (not to getters, setters or
/// `toString`).
///
/// [key], [condition] and [unless] are SpEL expressions, written without
/// `#{}`. They see each argument by its name (`#isbn`) and by its position
/// (`#p0`, `#a0`), and `#root.methodName`, `#root.args`, `#root.target`,
/// `#root.targetClass` and `#root.caches`. Only [unless] sees the result,
/// as `#result`. Reading properties of your own classes (`#book.isbn`)
/// needs `@Introspected()` on those classes.
///
/// The annotations of a bean are checked when the bean is created. A wrong
/// combination fails the startup with the method's name: both [key] and
/// [keyGenerator], both [cacheManager] and [cacheResolver], a broken [sync]
/// use, or no cache name at all (unless a cache resolver picks the caches).
///
/// ```dart
/// @Service()
/// class Books {
///   Books(this.repository, this.api);
///   final BookRepository repository;
///   final PriceApi api;
///
///   // Loaded once per isbn; the next calls read the cache.
///   @Cacheable('books')
///   Book find(String isbn) => repository.load(isbn);
///
///   // Only the isbn makes the key; 10-digit isbns and misses are not kept.
///   @Cacheable('books', key: '#isbn', condition: '#isbn.length == 13',
///       unless: '#result == null')
///   Book? findIsbn13(String isbn, bool fresh) => repository.find(isbn);
///
///   // Callers asking for the same price at the same time share one request.
///   @Cacheable('prices', sync: true)
///   Future<double> price(String isbn) => api.price(isbn);
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
///
/// Spring's `@Cacheable` takes several names in one attribute; here the
/// positional [value] takes one name, and [Cacheable.of] takes a list.
class Cacheable {
  /// Caches the results in the cache named [value] (and in [cacheNames],
  /// if any are given too).
  const Cacheable(
    String this.value, {
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.unless,
    this.sync = false,
    this.keyGenerator,
    this.cacheManager,
    this.cacheResolver,
  });

  /// Caches the results in [cacheNames], or, when that list is empty, in
  /// the caches named by the class's `@CacheConfig`.
  ///
  /// Use it for several caches (`@Cacheable.of(cacheNames: ['books',
  /// 'isbn'])`) or to take the names from `@CacheConfig`
  /// (`@Cacheable.of(key: '#isbn')`). Dart cannot mix an optional
  /// positional name with named parameters, hence the second constructor.
  const Cacheable.of({
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.unless,
    this.sync = false,
    this.keyGenerator,
    this.cacheManager,
    this.cacheResolver,
  }) : value = null;

  /// The cache name given to the main constructor; `null` with
  /// [Cacheable.of]. It is used together with [cacheNames].
  final String? value;

  /// More cache names. The key is looked up in each cache in order (the
  /// first hit wins), and a new result is stored in all of them. Empty by
  /// default.
  final List<String> cacheNames;

  /// SpEL computing the key, such as `'#isbn'` to ignore the other
  /// arguments. When `null`, the key is made of all the arguments (one
  /// argument is the key itself, several make a `SimpleKey`). A key that
  /// comes out `null` fails the call with an `ArgumentError`.
  final String? key;

  /// SpEL deciding, before the call, whether the cache is used at all:
  /// when it is not `true` the method simply runs and nothing is stored.
  /// `#result` is not available here. `null` means always.
  final String? condition;

  /// SpEL evaluated after the call, with the result as `#result`: when it
  /// is `true` the result is not stored (for example `'#result == null'`
  /// to not remember misses). It does not prevent a cache hit.
  final String? unless;

  /// For methods returning a `Future`: when `true`, calls with the same key
  /// that arrive while the first one is still running wait for it instead
  /// of running the method again. `false` by default.
  ///
  /// Such an operation must be the only cache annotation of the method, use
  /// one cache and have no [unless]; otherwise the startup fails. For a
  /// method that does not return a `Future` it changes nothing.
  final bool sync;

  /// Name of a `KeyGenerator` bean that computes the key, for keys that a
  /// SpEL [key] cannot express well. Not together with [key].
  final String? keyGenerator;

  /// Name of the `CacheManager` bean the caches come from, when it is not
  /// the default one. Not together with [cacheResolver].
  final String? cacheManager;

  /// Name of a `CacheResolver` bean that picks the caches at each call
  /// (for example one cache per tenant). Replaces [cacheManager]; with a
  /// resolver the cache names may even be left out.
  final String? cacheResolver;
}

/// Marks a bean method whose result is always stored in a cache: the
/// method always runs, and its result replaces the cached entry.
///
/// Use it on methods that change data, so the cache that `@Cacheable`
/// methods read holds the new value right away: `save(book)` puts the
/// saved book where `find(isbn)` will look for it. Unlike `@Cacheable` it
/// never skips the call.
///
/// [key] and [condition] are evaluated after the call and may use the
/// result as `#result`. Like the other cache annotations it works for
/// calls from other beans (through the bean's proxy), not for calls
/// through `this`.
///
/// ```dart
/// // After a save, find(isbn) returns the saved book without a query.
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
  /// Stores the result in the cache named [value] (and in [cacheNames], if
  /// any are given too).
  const CachePut(
    String this.value, {
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.unless,
    this.keyGenerator,
    this.cacheManager,
    this.cacheResolver,
  });

  /// Stores the result in [cacheNames], or, when that list is empty, in the
  /// caches named by the class's `@CacheConfig`.
  const CachePut.of({
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.unless,
    this.keyGenerator,
    this.cacheManager,
    this.cacheResolver,
  }) : value = null;

  /// The cache name given to the main constructor; `null` with
  /// [CachePut.of].
  final String? value;

  /// More cache names; the result is stored in every one of them.
  final List<String> cacheNames;

  /// SpEL computing the key; it may read the result (`'#result.isbn'`).
  /// When `null`, the key is made of the arguments.
  final String? key;

  /// SpEL evaluated after the call (it may use `#result`): the result is
  /// stored only when it is `true`. `null` means always.
  ///
  /// When the method also has a `@Cacheable` that finds a hit, the method
  /// still runs if this condition passes; a condition reading `#result`
  /// counts as passing at that point.
  final String? condition;

  /// SpEL with the result as `#result`: when it is `true` nothing is
  /// stored.
  final String? unless;

  /// Name of a `KeyGenerator` bean that computes the key. Not together with
  /// [key].
  final String? keyGenerator;

  /// Name of the `CacheManager` bean the caches come from, when it is not
  /// the default one. Not together with [cacheResolver].
  final String? cacheManager;

  /// Name of a `CacheResolver` bean that picks the caches at each call.
  /// Replaces [cacheManager].
  final String? cacheResolver;
}

/// Marks a bean method that removes entries from caches when it runs.
///
/// Use it on methods that delete or change data, so `@Cacheable` methods
/// do not keep returning the old value: `delete(isbn)` removes the entry
/// of that isbn, and a reload can clear a whole cache with [allEntries].
///
/// By default the entry of [key] is removed after the method returned
/// normally (the result is then available as `#result`); when the method
/// throws, nothing is removed. With [beforeInvocation] the entry is removed
/// before the method runs, so even a failing call clears it. Like the other
/// cache annotations it works for calls from other beans, not through
/// `this`.
///
/// ```dart
/// // A deleted book must not come back from the cache.
/// @CacheEvict('books', key: '#isbn')
/// void delete(String isbn) => repository.delete(isbn);
///
/// // Every book may have changed: empty the cache, even if the reload fails.
/// @CacheEvict('books', allEntries: true, beforeInvocation: true)
/// void reload() => repository.reload();
/// ```
///
/// Spring (Java):
/// ```java
/// @CacheEvict(cacheNames = "books", key = "#isbn")
/// void delete(String isbn) { ... }
///
/// @CacheEvict(
///     cacheNames = "books", allEntries = true, beforeInvocation = true)
/// void reload() { ... }
/// ```
class CacheEvict {
  /// Removes entries from the cache named [value] (and from [cacheNames],
  /// if any are given too).
  const CacheEvict(
    String this.value, {
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.allEntries = false,
    this.beforeInvocation = false,
    this.keyGenerator,
    this.cacheManager,
    this.cacheResolver,
  });

  /// Removes entries from [cacheNames], or, when that list is empty, from
  /// the caches named by the class's `@CacheConfig`.
  const CacheEvict.of({
    this.cacheNames = const [],
    this.key,
    this.condition,
    this.allEntries = false,
    this.beforeInvocation = false,
    this.keyGenerator,
    this.cacheManager,
    this.cacheResolver,
  }) : value = null;

  /// The cache name given to the main constructor; `null` with
  /// [CacheEvict.of].
  final String? value;

  /// More cache names; the entry is removed from every one of them.
  final List<String> cacheNames;

  /// SpEL computing the key of the entry to remove, such as `'#isbn'`.
  /// When `null`, the key is made of the arguments. Not used with
  /// [allEntries].
  final String? key;

  /// SpEL deciding whether anything is removed: only when it is `true`.
  /// `null` means always.
  final String? condition;

  /// When `true`, every entry of the caches is removed instead of one key.
  /// `false` by default.
  final bool allEntries;

  /// When `true`, the entries are removed before the method runs, so they
  /// are gone even if the method throws. `false` by default: removed after
  /// the method returned normally.
  final bool beforeInvocation;

  /// Name of a `KeyGenerator` bean that computes the key. Not together with
  /// [key].
  final String? keyGenerator;

  /// Name of the `CacheManager` bean the caches come from, when it is not
  /// the default one. Not together with [cacheResolver].
  final String? cacheManager;

  /// Name of a `CacheResolver` bean that picks the caches at each call.
  /// Replaces [cacheManager].
  final String? cacheResolver;
}

/// Groups several cache annotations on one method, for a method that must,
/// say, remove entries from two caches at once.
///
/// Dart allows repeating an annotation, so writing `@CacheEvict` twice
/// works as well; `@Caching` only keeps them together. The operations of
/// all three lists run as if they had been written one by one.
///
/// ```dart
/// // Deleting a book removes it and clears the author lists that named it.
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
  /// Groups the [cacheable], [put] and [evict] operations; each list is
  /// empty by default.
  const Caching({
    this.cacheable = const [],
    this.put = const [],
    this.evict = const [],
  });

  /// The `@Cacheable` operations of the method.
  final List<Cacheable> cacheable;

  /// The `@CachePut` operations of the method.
  final List<CachePut> put;

  /// The `@CacheEvict` operations of the method.
  final List<CacheEvict> evict;
}

/// Sets, on a class, the cache settings its cache annotations share, so
/// they are not repeated on every method.
///
/// It does not cache anything by itself: it only fills in what the
/// `@Cacheable`, `@CachePut` and `@CacheEvict` annotations of the class
/// leave open. An operation takes from it:
///
/// - the cache names, when it names none (`@Cacheable.of()`);
/// - the key generator, when it sets neither `key` nor `keyGenerator`;
/// - the cache resolver, or else the cache manager, when it sets neither
///   `cacheManager` nor `cacheResolver`.
///
/// It is read from the class that declares the method's body, else from
/// its nearest superclass that has one.
///
/// ```dart
/// // Every cached method of the class uses the `books` cache.
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
  /// The shared settings; every one is optional.
  const CacheConfig({
    this.cacheNames = const [],
    this.keyGenerator,
    this.cacheManager,
    this.cacheResolver,
  });

  /// The caches used by operations that name none.
  final List<String> cacheNames;

  /// Name of the `KeyGenerator` bean used by operations that set neither
  /// `key` nor `keyGenerator`.
  final String? keyGenerator;

  /// Name of the `CacheManager` bean used by operations that set neither
  /// `cacheManager` nor `cacheResolver`. Ignored when [cacheResolver] is
  /// set.
  final String? cacheManager;

  /// Name of the `CacheResolver` bean used by operations that set neither
  /// `cacheManager` nor `cacheResolver`; it wins over [cacheManager].
  final String? cacheResolver;
}
