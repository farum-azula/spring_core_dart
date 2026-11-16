import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The kind of `CacheManager` the starter builds.
enum CacheType {
  /// Uses the application's `Cache` beans (a `SimpleCacheManager`).
  generic,

  /// Keeps entries in memory (an `InMemoryCacheManager`).
  simple,

  /// Caches nothing, so the methods always run (a `NoOpCacheManager`).
  none,

  /// Keeps entries on disk, so they survive a restart (a
  /// `DiskCacheManager`): the app's `cache` place in Flutter, a folder
  /// elsewhere. Not Spring Boot's.
  disk,
}

/// The `spring.cache.*` properties.
///
/// Spring Boot (Java): `CacheProperties`.
@ConfigurationProperties('spring.cache')
class CacheProperties {
  /// The kind of cache manager. Default: `generic` when the application
  /// has `Cache` beans, else `simple`.
  CacheType? type;

  /// A fixed set of caches (`books,authors`, or a YAML list); an annotation
  /// that names another cache then fails. Default: empty (caches are
  /// created on demand).
  List<String> cacheNames = [];

  /// The settings of the `simple` cache manager.
  SimpleCacheProperties simple = SimpleCacheProperties();

  /// The settings of the `disk` cache manager.
  DiskCacheProperties disk = DiskCacheProperties();

  /// Whether a key made of a resource that knows the version of its
  /// content (a file the Flutter starter downloaded and keeps) is its
  /// address and that version, so a result made from a file that changed
  /// at the same address is made again. Off by default: the version is a
  /// digest of the content. Not Spring Boot's.
  bool resourceVersion = false;
}

/// The `spring.cache.disk.*` properties: `spring.cache.type: disk`.
@Introspected()
class DiskCacheProperties {
  /// An entry expires this long after it was written, by the wall clock
  /// (it outlives a restart). Default: none; `0` keeps nothing.
  Duration? timeToLive;

  /// The most bytes each cache keeps on disk; past it the oldest written
  /// go. Only the cache's own folder counts (`spring/caches/<name>/`): the
  /// resources the Flutter starter downloads have a limit of their own,
  /// `spring.flutter.resources.cache.max-size`. Default: none.
  DataSize? maxSize;

  /// The folder of the entries where no `CacheStore` bean gives a place
  /// (a server, a program without Flutter). Default: `.spring/cache` in the
  /// working folder.
  String? directory;

  /// The version entries are written by; an entry of another one is not
  /// read, so results made from what a new version changed are made
  /// again. Default: none (every entry is read).
  String? version;

  /// The time an entry of single caches lives, by cache name.
  Map<String, DiskCacheLimits> caches = {};
}

/// The settings of one cache of `spring.cache.disk.caches.<name>.*`.
@Introspected()
class DiskCacheLimits {
  /// The same as `spring.cache.disk.time-to-live`, for this cache.
  Duration? timeToLive;
}

/// The `spring.cache.simple.*` properties.
@Introspected()
class SimpleCacheProperties {
  /// An entry expires this long after it was written (`10m`, `30s`,
  /// `PT1H`, or milliseconds), measured on a monotonic clock as Caffeine's
  /// ticker (setting the system clock moves no expiry). Default: none; `0`
  /// keeps nothing; a negative value fails the start.
  Duration? timeToLive;

  /// The most entries per cache; when full, the least recently used entry
  /// goes. Default: none; `0` keeps nothing; a negative value fails the
  /// start.
  int? maxSize;

  /// The limits of single caches, by cache name; what one leaves out comes
  /// from the two settings above. A name with dots goes in brackets
  /// (`caches[books.byIsbn].max-size`).
  Map<String, CacheLimits> caches = {};
}

/// The limits of one cache (`spring.cache.simple.caches.<name>.*`).
@Introspected()
class CacheLimits {
  /// The same as `spring.cache.simple.time-to-live`, for this cache. A
  /// negative value fails the start. Default: the global one.
  Duration? timeToLive;

  /// The same as `spring.cache.simple.max-size`, for this cache. A negative
  /// value fails the start. Default: the global one.
  int? maxSize;
}
