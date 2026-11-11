import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_supabase/src/supabase_credentials.dart';

/// The buckets of the rate limiter in the project's database, reached
/// through its REST API: the [RateLimitStore] of an application that
/// uses Supabase without a database connection, such as an edge function
/// (`spring.web.rate-limit.store: procedure`, the default on the REST
/// path).
///
/// An acquisition is one call of the database function [function]
/// (`rate_limit_acquire`), which does all of the arithmetic in one
/// statement on the database's clock: every server and every edge
/// function instance shares the limits. The call is made as the service
/// role ([SupabaseCredentials.asServiceRole]), whatever the user of the
/// request: the table and the function are closed to `anon` and
/// `authenticated`, so no client can read or reset a counter.
///
/// The table and the function come from a migration of the project: the
/// SQL is in the package,
/// `package:spring_boot_starter_supabase/sql/rate_limit.sql`.
///
/// ```sql
/// select * from rate_limit_acquire('login:ip:203.0.113.7', 5, 5.0 / 60, 1);
/// -- allowed | remaining | retry_after_ms
/// ```
///
/// ```dart
/// final store = SupabaseRateLimitStore(
///   store: supabaseDataStore,
///   credentials: supabaseCredentials,
/// );
/// ```
///
/// Spring (Java): Spring Cloud Gateway's `RedisRateLimiter` runs a Lua
/// script in Redis the same way: the arithmetic next to the data.
final class SupabaseRateLimitStore implements VerifiableRateLimitStore {
  /// A store that calls [function] of [store] as the service role of
  /// [credentials]. Throws an [ArgumentError] when [function] is no
  /// function name.
  SupabaseRateLimitStore({
    required this.store,
    required this.credentials,
    this.function = 'rate_limit_acquire',
  }) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(function)) {
      throw ArgumentError.value(
        function,
        'function',
        'The rate limit function is the name of a database function',
      );
    }
  }

  /// The store whose database has the function (the REST API).
  final FunctionDataStore store;

  /// Gives the service role.
  final SupabaseCredentials credentials;

  /// The name of the database function.
  final String function;

  /// The key of the acquisition [verify] makes: a bucket of its own.
  static const verifyKey = 'spring:verify';

  /// Calls the function once, for a bucket of its own ([verifyKey]). A
  /// function (or its table) the project does not have, one that answers
  /// something else, or a service role that may not call it, is a
  /// [RateLimitStoreSetupException] with the migration to run. A project
  /// that cannot be reached is thrown as it is.
  @override
  Future<void> verify() async {
    String setup(Object error) =>
        'The rate limiter cannot call the database function $function of '
        'the Supabase project ($error). Run sql/rate_limit.sql of '
        'spring_boot_starter_supabase as a migration of the project (it '
        'creates the table and the function, for the service role only), '
        'or name the function with spring.supabase.rate-limit.function; '
        'the store needs spring.supabase.service-role-key';
    try {
      await tryAcquire(verifyKey, const RateLimit(1, Duration(seconds: 1)));
    } on InvalidDataAccessResourceUsageException catch (error) {
      throw RateLimitStoreSetupException(setup(error.message));
    } on PermissionDeniedDataAccessException catch (error) {
      throw RateLimitStoreSetupException(setup(error.message));
    } on InvalidDataAccessApiUsageException catch (error) {
      throw RateLimitStoreSetupException(setup(error.message));
    } on StateError catch (error) {
      throw RateLimitStoreSetupException(setup(error.message));
    }
  }

  @override
  Future<RateLimitDecision> tryAcquire(
    String key,
    RateLimit limit, {
    int permits = 1,
  }) async {
    final rows = await credentials.asServiceRole(
      () => store.callFunction(function, {
        'p_key': key,
        'p_capacity': limit.capacity,
        'p_refill_per_second': limit.refillPerSecond,
        'p_permits': permits,
      }),
    );
    return switch (rows) {
      [
        {
          'allowed': final bool allowed,
          'remaining': final num remaining,
          'retry_after_ms': final num retryAfter,
        },
      ] =>
        RateLimitDecision(
          allowed: allowed,
          remaining: remaining.toInt(),
          retryAfter: Duration(milliseconds: retryAfter.toInt()),
        ),
      _ => throw StateError(
        'The database function $function did not answer allowed, remaining '
        'and retry_after_ms: is it the one of sql/rate_limit.sql?',
      ),
    };
  }
}
