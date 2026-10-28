import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache.dart';

/// Decides what happens when a [Cache] itself throws while a cache
/// annotation reads or writes it.
///
/// By default ([SimpleCacheErrorHandler]) the error reaches the caller of
/// the cached method, so a broken cache store breaks the method too. A
/// handler that returns normally lets the call go on as if the cache had
/// answered: a failed `get` counts as a miss (the method runs), a failed
/// `put`, `evict` or `clear` is skipped. A handler that throws fails the
/// call. Errors of the cached method itself never come here.
///
/// You need one when the cache lives outside memory (a file, a database)
/// and its failures should not take the feature down. Set it with a
/// `CachingConfigurer`; [LoggingCacheErrorHandler] is the usual choice.
///
/// ```dart
/// // The cache store may be down: log the error, run the method anyway.
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
///
/// Unlike Spring's, the methods also receive the stack trace of the error.
abstract interface class CacheErrorHandler {
  /// Called when [cache] threw [exception] while looking [key] up. Return
  /// to treat the lookup as a miss, or throw to fail the call.
  void handleCacheGetError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
  );

  /// Called when [cache] threw [exception] while storing [value] for
  /// [key]. Return to go on without storing, or throw to fail the call.
  void handleCachePutError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
    Object? value,
  );

  /// Called when [cache] threw [exception] while removing the entry of
  /// [key]. Return to go on, or throw to fail the call.
  void handleCacheEvictError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
    Object? key,
  );

  /// Called when [cache] threw [exception] while removing all its entries
  /// (`allEntries: true`). Return to go on, or throw to fail the call.
  void handleCacheClearError(
    Object exception,
    StackTrace stackTrace,
    Cache cache,
  );
}

/// The [CacheErrorHandler] used by default: it rethrows every cache error
/// with its stack trace, so the caller of the cached method sees it.
///
/// Spring (Java): `SimpleCacheErrorHandler`, which also rethrows.
final class SimpleCacheErrorHandler implements CacheErrorHandler {
  /// The handler; it has no settings.
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

/// A [CacheErrorHandler] that logs each cache error as a warning and lets
/// the call go on: a failed lookup runs the method, a failed write is
/// skipped.
///
/// Use it when a cache is an optimisation the application can live
/// without, so a cache store that is down only slows things down. It logs
/// to `spring.cache` by default.
///
/// ```dart
/// @Configuration()
/// class CacheSetup with CachingConfigurer {
///   // The full stack traces help while the store's failures are studied.
///   @override
///   CacheErrorHandler errorHandler() =>
///       const LoggingCacheErrorHandler(logStackTraces: true);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// new LoggingCacheErrorHandler(true);
/// ```
final class LoggingCacheErrorHandler implements CacheErrorHandler {
  /// A handler logging to [logger] (`spring.cache` by default), with the
  /// stack traces when [logStackTraces] is `true` (`false` by default).
  const LoggingCacheErrorHandler({
    this.logger = const SpringLog('spring.cache'),
    this.logStackTraces = false,
  });

  /// The logger the warnings are written to.
  final SpringLog logger;

  /// Whether the stack trace is logged with the error. When `false`, only
  /// the error's text is appended to the message.
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
