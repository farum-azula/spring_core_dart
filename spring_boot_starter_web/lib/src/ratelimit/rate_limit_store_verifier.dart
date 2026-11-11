import 'package:spring_boot_dart/spring_boot_dart.dart';

const _log = SpringLog('spring.web.rate-limit');

/// Asks the rate limiter's store, once the application has started, that
/// what it keeps its buckets in is there (`VerifiableRateLimitStore`): a
/// missing table, function or binding fails the start with what to run,
/// instead of showing as a 503 on the first request under a limit.
///
/// A store that cannot be reached now is a WARN: `on-store-failure`
/// decides for each request until it answers. A store that cannot be
/// asked (one in memory, an application's own) is not asked.
/// `spring.web.rate-limit.verify-store=false` leaves the runner out.
///
/// It runs as an `ApplicationRunner`: after the context is there and
/// before the application is ready, on a server and in a function (where
/// the start is the first request of an instance).
final class RateLimitStoreVerifier implements ApplicationRunner {
  /// The check of [store].
  const RateLimitStoreVerifier(this.store);

  /// The store of the rate limiter.
  final RateLimitStore store;

  @override
  Future<void> run(ApplicationArguments args) async {
    final store = this.store;
    if (store is! VerifiableRateLimitStore) {
      return;
    }
    try {
      await store.verify();
      _log.debug(() => 'The rate limit store ${store.runtimeType} is set up');
    } on RateLimitStoreSetupException {
      rethrow;
    } on Object catch (error) {
      _log.warning(
        'The rate limit store ${store.runtimeType} could not be checked at '
        'startup (${error.runtimeType}): requests under a limit are '
        'answered as spring.web.rate-limit.on-store-failure says until it '
        'can be reached',
        error: error,
      );
    }
  }
}
