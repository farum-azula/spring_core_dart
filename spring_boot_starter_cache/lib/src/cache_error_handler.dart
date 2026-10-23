import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache.dart';

/// Handles errors thrown by a [Cache] during cache operations, like
/// Spring's `CacheErrorHandler`. When a method returns normally, the call
/// goes on as if the cache had answered: a failed `get` counts as a miss,
/// a failed `put`, `evict` or `clear` is skipped. Rethrow to fail the
/// call ([SimpleCacheErrorHandler], the default).
///
/// Set one with a `CachingConfigurer`:
///
/// ```dart
/// @Configuration()
/// class CacheSetup with CachingConfigurer {
///   @override
///   CacheErrorHandler errorHandler() => LoggingCacheErrorHandler();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Configuration
/// class CacheSetup implements CachingConfigurer {
///   @Override
///   public CacheErrorHandler errorHandler() {
///     return new LoggingCacheErrorHandler();
///   }
/// }
/// ```
abstract interface class CacheErrorHandler {
  /// [cache] failed to look [key] up.
  void handleCacheGetError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
  );

  /// [cache] failed to store [value] for [key].
  void handleCachePutError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
    Object? value,
  );

  /// [cache] failed to remove [key].
  void handleCacheEvictError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
  );

  /// [cache] failed to clear.
  void handleCacheClearError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
  );
}

/// The default [CacheErrorHandler], like Spring's
/// `SimpleCacheErrorHandler`: rethrows, so cache errors reach the caller.
final class SimpleCacheErrorHandler implements CacheErrorHandler {
  /// Creates the handler.
  const SimpleCacheErrorHandler();

  @override
  void handleCacheGetError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
  ) => Error.throwWithStackTrace(exception, stackTrace);

  @override
  void handleCachePutError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
    Object? value,
  ) => Error.throwWithStackTrace(exception, stackTrace);

  @override
  void handleCacheEvictError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
  ) => Error.throwWithStackTrace(exception, stackTrace);

  @override
  void handleCacheClearError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
  ) => Error.throwWithStackTrace(exception, stackTrace);
}

/// A [CacheErrorHandler] that logs cache errors at warning level and lets
/// the calls go on (a failed lookup runs the method), like Spring's
/// `LoggingCacheErrorHandler`.
///
/// ```dart
/// LoggingCacheErrorHandler(logStackTraces: true)
/// ```
///
/// Spring (Java):
/// ```java
/// new LoggingCacheErrorHandler(true);
/// ```
final class LoggingCacheErrorHandler implements CacheErrorHandler {
  /// A handler logging to [logger] (`spring.cache` by default), with the
  /// stack traces when [logStackTraces] is `true`.
  const LoggingCacheErrorHandler({
    this.logger = const SpringLog('spring.cache'),
    this.logStackTraces = false,
  });

  /// Where the errors go.
  final SpringLog logger;

  /// Whether the error and its stack trace are logged too.
  final bool logStackTraces;

  void _log(String message, Object exception, StackTrace stackTrace) =>
      logger.warning(
        logStackTraces ? message : '$message: $exception',
        error: logStackTraces ? exception : null,
        stackTrace: logStackTraces ? stackTrace : null,
      );

  @override
  void handleCacheGetError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
  ) => _log(
    "Cache '${cache.name}' failed to get entry with key '$key'",
    exception,
    stackTrace,
  );

  @override
  void handleCachePutError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
    Object? value,
  ) => _log(
    "Cache '${cache.name}' failed to put entry with key '$key'",
    exception,
    stackTrace,
  );

  @override
  void handleCacheEvictError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
  ) => _log(
    "Cache '${cache.name}' failed to evict entry with key '$key'",
    exception,
    stackTrace,
  );

  @override
  void handleCacheClearError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
  ) => _log(
    "Cache '${cache.name}' failed to clear entries",
    exception,
    stackTrace,
  );
}
