import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/ratelimit/client_address.dart';
import 'package:spring_boot_starter_web/src/ratelimit/rate_limit_key.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.ratelimit');

/// Limits how often a controller method is called, per user or per
/// client: on a method, or on a controller class for all its methods
/// together (both apply when both are there).
///
/// [limit] reads `<count>/<duration>` and may be a `${...}` placeholder.
/// A request past it is answered with a 429 (`TooManyRequestsException`)
/// and `Retry-After` before its body is read and its arguments are
/// bound. The buckets live in the application's `RateLimitStore`, as
/// those of the rules of `spring.web.rate-limit.rules`; rate limiting
/// must be on (`spring.web.rate-limit.enabled: true`, or a rule).
///
/// ```dart
/// @RestController()
/// @RateLimiter('120/1m')
/// class ReportController {
///   // Ten exports a minute for each user, whatever the rest allows.
///   @PostMapping('/reports/export')
///   @RateLimiter('10/1m', key: '#{authentication.name}')
///   Future<Report> export() => reports.export();
/// }
/// ```
///
/// Spring has none in its core. Resilience4j (Java):
/// ```java
/// @RateLimiter(name = "export")
/// public Report export() { ... }
/// ```
/// whose limit is in `resilience4j.ratelimiter.instances.export.*` and is
/// one for all callers; this one is per key.
class RateLimiter {
  /// A limit of [limit] for each [key].
  const RateLimiter(
    this.limit, {
    this.key,
    this.burst,
    this.name,
    this.onStoreFailure,
  });

  /// The limit as `<count>/<duration>` (`10/1m`), or a placeholder
  /// (`r'${export.limit}'`).
  final String limit;

  /// Who a bucket belongs to, as a rule's `key`: `user` (the default),
  /// `ip`, or a SpEL expression in `#{...}`.
  final String? key;

  /// The most calls at once when it is not the count of [limit].
  final int? burst;

  /// The name in the store's keys and in the logs; default: the class
  /// and method (`ReportController.export`), or the class.
  final String? name;

  /// What happens when the store cannot be reached; default:
  /// `spring.web.rate-limit.on-store-failure`.
  final RateLimitStoreFailure? onStoreFailure;
}

/// One rule of the rate limiter: which requests, counted by what, how
/// many.
///
/// The starter makes them from `spring.web.rate-limit.rules` and from the
/// `@RateLimiter` annotations; [RequestRateLimiter.acquire] applies them.
///
/// ```dart
/// final rule = RateLimitRule(
///   name: 'login',
///   path: '/api/auth/**',
///   methods: {HttpMethod.post},
///   key: 'ip',
///   limit: RateLimit.parse('5/1m'),
/// );
/// ```
///
/// Spring (Java): a route of Spring Cloud Gateway with a
/// `RequestRateLimiter` filter.
final class RateLimitRule {
  /// A rule called [name] for the requests of [path] (every path when
  /// `null`) and [methods] (all when empty).
  RateLimitRule({
    required this.name,
    required this.limit,
    String? path,
    this.methods = const {},
    this.key = UserRateLimitKeyResolver.key,
    this.onStoreFailure,
  }) : path = path == null ? null : PathPattern.parse(path);

  /// The rule's name: the first part of its keys in the store.
  final String name;

  /// The limit of each key.
  final RateLimit limit;

  /// The paths the rule is for; `null` for all.
  final PathPattern? path;

  /// The methods the rule is for; empty for all.
  final Set<HttpMethod> methods;

  /// Who a bucket belongs to: `user`, `ip`, an expression, or a key of a
  /// [RateLimitKeyResolver] bean.
  final String key;

  /// What happens when the store cannot be reached; `null`: the
  /// limiter's.
  final RateLimitStoreFailure? onStoreFailure;

  /// Whether the rule is for [request].
  bool matches(ServerHttpRequest request) =>
      (methods.isEmpty || methods.contains(request.method)) &&
      (path?.matches(request.path) ?? true);

  @override
  String toString() => '$name ($limit by $key)';
}

/// The error of a request past a rate limit; it is answered with a 429
/// (Too Many Requests), `Retry-After` in seconds and the usual
/// `ProblemDetail`.
///
/// The rate limiter throws it from its filters (then nothing else of the
/// request is processed) and from the interceptor of `@RateLimiter`
/// (where an `@ExceptionHandler` may answer it another way).
///
/// ```dart
/// @ExceptionHandler()
/// ResponseEntity<String> slowDown(TooManyRequestsException e) =>
///     ResponseEntity.status(429).body('Back in ${e.retryAfter.inSeconds}s');
/// ```
///
/// Spring (Java): Resilience4j's `RequestNotPermitted`; Spring Cloud
/// Gateway answers 429 itself.
class TooManyRequestsException extends ErrorResponseException {
  /// The rule called [rule] refused the request; it may come back after
  /// [retryAfter]. [headers] are added to the answer.
  TooManyRequestsException(this.rule, this.retryAfter, {HttpHeaders? headers})
    : super(
        HttpStatus.tooManyRequests,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.tooManyRequests,
          'Too many requests. Try again in ${_seconds(retryAfter)} s.',
        ),
        headers: (headers ?? HttpHeaders())
          ..set('Retry-After', '${_seconds(retryAfter)}'),
      );

  /// The name of the rule that refused.
  final String rule;

  /// How long until the request would pass.
  final Duration retryAfter;

  @override
  String toString() => 'TooManyRequestsException: $rule';
}

/// The error of a request the rate limiter could not count because its
/// store cannot be reached, where the rule denies then
/// (`on-store-failure: deny`, the default); it is answered with a 503 and
/// `Retry-After`.
class RateLimitUnavailableException extends ErrorResponseException {
  /// The store failed for the rule called [rule] with [cause]; the
  /// client may come back after [retryAfter].
  RateLimitUnavailableException(this.rule, this.retryAfter, {super.cause})
    : super(
        HttpStatus.serviceUnavailable,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.serviceUnavailable,
          'The service cannot take the request now. Try again later.',
        ),
        headers: HttpHeaders({'Retry-After': '${_seconds(retryAfter)}'}),
      );

  /// The name of the rule whose bucket could not be read.
  final String rule;

  /// The `Retry-After` of the answer.
  final Duration retryAfter;

  @override
  String toString() => 'RateLimitUnavailableException: $rule';
}

// Whole seconds, rounded up, at least one: `Retry-After: 0` would have
// the client come back at once.
int _seconds(Duration time) {
  final seconds = (time.inMicroseconds / Duration.microsecondsPerSecond).ceil();
  return seconds < 1 ? 1 : seconds;
}

/// Applies rate limit rules to requests: the bean `requestRateLimiter`.
///
/// For each rule it works out who the request is counted as (the
/// [keyResolvers], else the client's address), takes one permit from that
/// bucket in the [store], and
///
/// - throws a [TooManyRequestsException] when a rule refuses: the request
///   passes only when every rule allows it (the rules before the one
///   that refused have counted it);
/// - when a rule's key cannot be resolved because of how it is written
///   ([RateLimitKeyException]: an expression that reads a property
///   nothing has), counts by the client's address and logs one line at
///   WARN for the rule, once;
/// - when the store fails, does what the rule's `on-store-failure` says:
///   `deny` throws a [RateLimitUnavailableException] (503), `allow` lets
///   the request go on, not counted. Either way one line is logged at
///   WARN on `spring.web.ratelimit`, at most every ten seconds, with the
///   rule's name and never the key;
/// - with [headers], sets `RateLimit-Limit`, `RateLimit-Remaining` and
///   `RateLimit-Reset` (seconds) of the rule that leaves the least.
///
/// A key in the store is `<rule>:<kind>:<value>`, such as
/// `login:ip:203.0.113.7` or `api:user:ada`. With `hashSecret` an address
/// is replaced by its HMAC-SHA-256 in hexadecimal; any value longer than
/// 200 characters is replaced by its SHA-256.
///
/// The filters and the `@RateLimiter` interceptor call it; application
/// code may too, for a limit decided in code:
///
/// ```dart
/// await limiter.acquire(request, response, [uploads]);
/// ```
///
/// Spring (Java): Spring Cloud Gateway's `RequestRateLimiter` filter
/// factory (a `KeyResolver` and a `RateLimiter`).
final class RequestRateLimiter {
  /// A limiter over [store].
  RequestRateLimiter({
    required this.store,
    required this.addresses,
    List<RateLimitKeyResolver> keyResolvers = const [],
    this.onStoreFailure = RateLimitStoreFailure.deny,
    this.storeFailureRetryAfter = const Duration(seconds: 5),
    this.headers = true,
    String? hashSecret,
    BeanIntrospector? introspector,
  }) : _hashKey = hashSecret == null ? null : utf8.encode(hashSecret),
       keyResolvers = List.unmodifiable([
         ...keyResolvers,
         const AddressRateLimitKeyResolver(),
         const UserRateLimitKeyResolver(),
         ExpressionRateLimitKeyResolver(introspector: introspector),
       ]);

  /// Where the buckets are.
  final RateLimitStore store;

  /// Gives the client's address.
  final ClientAddressResolver addresses;

  /// The key resolvers, in the order they are asked: the application's,
  /// then the built-in ones.
  final List<RateLimitKeyResolver> keyResolvers;

  /// What happens when the store fails, for a rule that does not say.
  final RateLimitStoreFailure onStoreFailure;

  /// The `Retry-After` of the 503 of a store failure.
  final Duration storeFailureRetryAfter;

  /// Whether the `RateLimit-*` headers are set.
  final bool headers;

  final List<int>? _hashKey;
  DateTime? _warnedAt;
  final _warnedKeys = <String>{};

  static const _context = 'spring.web.rateLimit.clientAddress';
  static const _tightest = 'spring.web.rateLimit.remaining';

  /// The resolver of the rule key [key]. Throws a [StateError] when no
  /// resolver knows it.
  RateLimitKeyResolver resolverOf(String key) =>
      keyResolvers.where((r) => r.supports(key)).firstOrNull ??
      (throw StateError(
        'No RateLimitKeyResolver knows the rate limit key "$key": use '
        'user, ip, a SpEL expression in #{...}, or declare a resolver bean',
      ));

  /// Whether [rule] is decided before authentication (its key does not
  /// read the user).
  bool beforeAuthentication(RateLimitRule rule) =>
      resolverOf(rule.key).beforeAuthentication(rule.key);

  /// Checks [rule] now, so that a mistake stops the start: its key has a
  /// resolver, its expression parses. Throws a [StateError] that names
  /// the rule.
  ///
  /// What an expression reads is only known with a request: a property
  /// that does not exist is found at the first one, and warned about
  /// once ([acquire]).
  void validate(RateLimitRule rule) {
    final resolver = resolverOf(rule.key);
    if (resolver is ExpressionRateLimitKeyResolver) {
      try {
        resolver.validate(rule.key);
      } on ExpressionException catch (error) {
        throw StateError(
          'The rate limit rule ${rule.name}: its key ${rule.key} is not '
          'an expression that can be read: ${error.simpleMessage}',
        );
      }
    }
  }

  /// Takes one permit of each of [rules] for [request] and sets the
  /// headers on [response]. Throws a [TooManyRequestsException] when a
  /// rule refuses and a [RateLimitUnavailableException] when the store
  /// fails under a rule that denies then.
  Future<void> acquire(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Iterable<RateLimitRule> rules,
  ) async {
    // The address is worked out once for the request; the principal is
    // read from the request as this caller sees it (a later filter sees
    // the one authentication set).
    final address =
        request.attributes[_context] as _Address? ??
        (request.attributes[_context] = _Address(
          () => addresses.resolve(request),
        ));
    final current = RateLimitRequest(request, address: () => address.value);
    for (final rule in rules) {
      final key = await _key(rule, current);
      final RateLimitDecision decision;
      try {
        decision = await store.tryAcquire(key, rule.limit);
      } on Object catch (error) {
        final failure = rule.onStoreFailure ?? onStoreFailure;
        _warn(rule, error, failure);
        if (failure == RateLimitStoreFailure.allow) {
          continue;
        }
        throw RateLimitUnavailableException(
          rule.name,
          storeFailureRetryAfter,
          cause: error,
        );
      }
      if (!decision.allowed) {
        _log.debug(() => 'Refused by the rate limit ${rule.name}');
        final answer = HttpHeaders();
        if (headers) {
          _write(answer, rule.limit, 0, _seconds(decision.retryAfter));
          _write(
            response.headers,
            rule.limit,
            0,
            _seconds(decision.retryAfter),
          );
        }
        throw TooManyRequestsException(
          rule.name,
          decision.retryAfter,
          headers: answer,
        );
      }
      if (headers) {
        final least = request.attributes[_tightest] as int?;
        if (least == null || decision.remaining < least) {
          request.attributes[_tightest] = decision.remaining;
          final missing = rule.limit.capacity - decision.remaining;
          _write(
            response.headers,
            rule.limit,
            decision.remaining,
            (missing / rule.limit.refillPerSecond).ceil(),
          );
        }
      }
    }
  }

  static void _write(
    HttpHeaders headers,
    RateLimit limit,
    int left,
    int reset,
  ) {
    headers
      ..set('RateLimit-Limit', '${limit.capacity}')
      ..set('RateLimit-Remaining', '$left')
      ..set('RateLimit-Reset', '$reset');
  }

  Future<String> _key(RateLimitRule rule, RateLimitRequest request) async {
    RateLimitSubject? resolved;
    try {
      resolved = await resolverOf(rule.key).resolve(rule.key, request);
    } on RateLimitKeyException catch (error) {
      _warnKey(rule, error);
    }
    final subject =
        resolved ?? RateLimitSubject.address(request.address ?? 'unknown');
    var value = subject.value;
    final hashKey = _hashKey;
    if (subject.isAddress && hashKey != null) {
      value = Sha256.hex(Sha256.hmac(hashKey, utf8.encode(value)));
    } else if (value.length > 200) {
      value = Sha256.hex(Sha256.digest(utf8.encode(value)));
    }
    return '${rule.name}:${subject.kind}:$value';
  }

  // Once per rule, not per request: whoever sends the requests must not
  // be the one who decides how much is logged.
  void _warnKey(RateLimitRule rule, RateLimitKeyException error) {
    if (!_warnedKeys.add(rule.name)) {
      return;
    }
    _log.warning(
      'The key ${rule.key} of the rate limit rule ${rule.name} cannot be '
      'resolved (${error.message}): the rule counts by the address of '
      'the client instead. This is logged once',
    );
  }

  // The rule and the kind of error, never the key: it names a client.
  void _warn(RateLimitRule rule, Object error, RateLimitStoreFailure failure) {
    final now = DateTime.now();
    final last = _warnedAt;
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _warnedAt = now;
    final outcome = switch (failure) {
      RateLimitStoreFailure.deny => 'refused with 503',
      RateLimitStoreFailure.allow => 'let through, not counted',
    };
    _log.warning(
      'The rate limit store failed for the rule ${rule.name} '
      '(${error.runtimeType}): requests are $outcome '
      '(on-store-failure: ${failure.name})',
    );
  }
}

final class _Address {
  _Address(this._resolve);

  final String? Function() _resolve;

  late final String? value = _resolve();
}
