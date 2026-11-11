import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/config/config.dart';
import 'package:spring_boot_starter_web/src/config/web_properties.dart';
import 'package:spring_boot_starter_web/src/dispatcher.dart';
import 'package:spring_boot_starter_web/src/handler_method.dart';
import 'package:spring_boot_starter_web/src/isolates/server_isolate_pool.dart';
import 'package:spring_boot_starter_web/src/ratelimit/client_address.dart';
import 'package:spring_boot_starter_web/src/ratelimit/rate_limit_filter.dart';
import 'package:spring_boot_starter_web/src/ratelimit/rate_limit_key.dart';
import 'package:spring_boot_starter_web/src/ratelimit/rate_limit_store_verifier.dart';
import 'package:spring_boot_starter_web/src/ratelimit/rate_limiter.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _source = 'package:spring_boot_starter_web#RateLimitAutoConfiguration';

/// The rules of `spring.web.rate-limit.rules`, in their order. Throws a
/// [StateError] that names the rule for a limit, a method or a path that
/// cannot be read.
List<RateLimitRule> rateLimitRules(RateLimitProperties properties) => [
  for (final (index, rule) in properties.rules.indexed) _rule(index, rule),
];

RateLimitRule _rule(int index, RateLimitRuleProperties rule) {
  final at = 'spring.web.rate-limit.rules[$index]';
  final limit = rule.limit?.trim() ?? '';
  if (limit.isEmpty) {
    throw StateError('$at.limit is not set: a rule needs one, such as 5/1m');
  }
  try {
    final key = rule.key?.trim() ?? '';
    return RateLimitRule(
      name: switch (rule.name?.trim()) {
        final name? when name.isNotEmpty => name,
        _ => 'rule-${index + 1}',
      },
      path: rule.path,
      methods: {
        for (final method in rule.methods)
          if (method.trim().isNotEmpty) HttpMethod.parse(method.trim()),
      },
      key: key.isEmpty ? UserRateLimitKeyResolver.key : key,
      limit: RateLimit.parse(limit, burst: rule.burst),
      onStoreFailure: rule.onStoreFailure,
    );
  } on FormatException catch (error) {
    throw StateError('$at: ${error.message} (${error.source})');
  } on ArgumentError catch (error) {
    throw StateError('$at: ${error.message}');
  }
}

List<RateLimitRule> _rules(DependencyResolver r, {required bool before}) {
  final limiter = r.dependency<RequestRateLimiter>();
  return [
    for (final rule in rateLimitRules(r.dependency<RateLimitProperties>()))
      if ((limiter..validate(rule)).beforeAuthentication(rule) == before) rule,
  ];
}

/// The beans of the rate limiter, when it is on
/// (`spring.web.rate-limit.enabled`, or a rule):
///
/// - the store, unless the application or a starter before this one has
///   a `RateLimitStore`: `primaryIsolateRateLimitStore` when the server
///   has a pool of isolates (or `store: primary-isolate`), with
///   `rateLimitPrimaryIsolateHandler` in the first isolate; else
///   `inMemoryRateLimitStore` (or `store: memory`);
/// - `rateLimitClientAddressResolver` ([ClientAddressResolver]), unless
///   the application declares one;
/// - `requestRateLimiter` ([RequestRateLimiter]) with the
///   [RateLimitKeyResolver] beans;
/// - `rateLimitFilter` and `authenticatedRateLimitFilter`
///   ([RateLimitFilter]): the rules of the configuration, before and
///   after authentication;
/// - `rateLimiterInterceptor` and `rateLimitWebMvcConfigurer`: the
///   `@RateLimiter` annotations.
///
/// And when it was never turned on, `rateLimiterAnnotationGuard`, which
/// stops the start when a controller has `@RateLimiter`.
final rateLimitAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<PrimaryIsolateRateLimitHandler>(
    name: 'rateLimitPrimaryIsolateHandler',
    types: const [PrimaryIsolateRateLimitHandler, PrimaryIsolateHandler],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.rateLimitPrimaryIsolateHandler', [
        ConditionalOnRateLimiting(),
        ConditionalOnPrimaryIsolate(),
      ]),
    ],
    create: (r) => PrimaryIsolateRateLimitHandler(
      InMemoryRateLimitStore(
        maxEntries: r.dependency<RateLimitProperties>().memory.maxEntries,
      ),
    ),
  ),
  BeanDefinition<PrimaryIsolateRateLimitStore>(
    name: 'primaryIsolateRateLimitStore',
    factoryMethodName: 'primaryIsolateRateLimitStore',
    types: const [PrimaryIsolateRateLimitStore, RateLimitStore],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.primaryIsolateRateLimitStore', [
        ConditionalOnRateLimitStore(
          'primary-isolate',
          byDefault: OnServerIsolates(),
        ),
      ]),
    ],
    // Looked up when asked: the handlers of the primary isolate reach
    // the server, whose dispatcher has the rate limiter.
    create: (r) => PrimaryIsolateRateLimitStore.lazy(
      r.provider<PrimaryIsolate>().getObject,
    ),
  ),
  BeanDefinition<InMemoryRateLimitStore>(
    name: 'inMemoryRateLimitStore',
    factoryMethodName: 'inMemoryRateLimitStore',
    types: const [InMemoryRateLimitStore, RateLimitStore, IsolateLocalState],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.inMemoryRateLimitStore', [
        ConditionalOnRateLimitStore('memory'),
      ]),
    ],
    create: (r) => InMemoryRateLimitStore(
      maxEntries: r.dependency<RateLimitProperties>().memory.maxEntries,
    ),
  ),
  BeanDefinition<ClientAddressResolver>(
    name: 'rateLimitClientAddressResolver',
    factoryMethodName: 'rateLimitClientAddressResolver',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.rateLimitClientAddressResolver', [
        ConditionalOnRateLimiting(),
        ConditionalOnMissingBean(ClientAddressResolver),
      ]),
    ],
    create: (r) {
      final properties = r.dependency<RateLimitProperties>();
      final prefix = properties.ipv6PrefixLength;
      if (prefix < 1 || prefix > 128) {
        throw StateError(
          'spring.web.rate-limit.ipv6-prefix-length=$prefix: an IPv6 '
          'prefix length is 1 to 128 (64 by default; 128 counts every '
          'address by itself)',
        );
      }
      try {
        return TrustedProxyClientAddressResolver(
          trustedProxies: properties.trustedProxies,
          header: properties.clientAddressHeader,
          ipv6PrefixLength: prefix,
        );
      } on ArgumentError catch (error) {
        throw StateError(
          'spring.web.rate-limit.trusted-proxies: ${error.message}',
        );
      }
    },
  ),
  // The store's table, function or binding, asked for at startup.
  BeanDefinition<RateLimitStoreVerifier>(
    name: 'rateLimitStoreVerifier',
    factoryMethodName: 'rateLimitStoreVerifier',
    types: const [RateLimitStoreVerifier, ApplicationRunner],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.rateLimitStoreVerifier', [
        ConditionalOnRateLimiting(),
        ConditionalOnProperty(
          'spring.web.rate-limit.verify-store',
          havingValue: 'true',
          matchIfMissing: true,
        ),
        ConditionalOnMissingBean(RateLimitStoreVerifier),
      ]),
    ],
    create: (r) =>
        RateLimitStoreVerifier(r.dependency<RequestRateLimiter>().store),
  ),
  BeanDefinition<RequestRateLimiter>(
    name: 'requestRateLimiter',
    factoryMethodName: 'requestRateLimiter',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.requestRateLimiter', [
        ConditionalOnRateLimiting(),
        ConditionalOnMissingBean(RequestRateLimiter),
      ]),
    ],
    create: (r) {
      final properties = r.dependency<RateLimitProperties>();
      final secret = properties.hashSecret?.trim() ?? '';
      if (properties.hashAddresses && secret.isEmpty) {
        throw StateError(
          'spring.web.rate-limit.hash-addresses is on, but '
          'spring.web.rate-limit.hash-secret is not set',
        );
      }
      return RequestRateLimiter(
        store:
            r.optionalDependency<RateLimitStore>() ??
            (throw StateError(
              'spring.web.rate-limit.store=${properties.store}: the '
              'application has no rate limit store of that name. memory '
              'and primary-isolate come with the web starter, jdbc with '
              'spring_boot_starter_data and a primary DataSource, procedure '
              'with spring_boot_starter_supabase',
            )),
        addresses: r.dependency<ClientAddressResolver>(),
        keyResolvers:
            r.optionalDependencyList<RateLimitKeyResolver>() ??
            const <RateLimitKeyResolver>[],
        onStoreFailure: properties.onStoreFailure,
        storeFailureRetryAfter: properties.storeFailureRetryAfter,
        headers: properties.headers,
        hashSecret: properties.hashAddresses ? secret : null,
        introspector: r.dependency<BeanIntrospector>(),
      );
    },
  ),
  BeanDefinition<RateLimitFilter>(
    name: 'rateLimitFilter',
    types: const [RateLimitFilter, WebFilter, Ordered],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.rateLimitFilter', [ConditionalOnRateLimiting()]),
    ],
    create: (r) => RateLimitFilter(
      r.dependency<RequestRateLimiter>(),
      _rules(r, before: true),
      order: RateLimitFilter.beforeAuthenticationOrder,
    ),
  ),
  BeanDefinition<RateLimitFilter>(
    name: 'authenticatedRateLimitFilter',
    types: const [RateLimitFilter, WebFilter, Ordered],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.authenticatedRateLimitFilter', [
        ConditionalOnRateLimiting(),
      ]),
    ],
    create: (r) => RateLimitFilter(
      r.dependency<RequestRateLimiter>(),
      _rules(r, before: false),
      order: RateLimitFilter.afterAuthenticationOrder,
    ),
  ),
  BeanDefinition<RateLimiterInterceptor>(
    name: 'rateLimiterInterceptor',
    types: const [RateLimiterInterceptor, SmartInitializingSingleton],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.rateLimiterInterceptor', [
        ConditionalOnRateLimiting(),
      ]),
    ],
    create: (r) => RateLimiterInterceptor(
      r.dependency<RequestRateLimiter>(),
      r.dependency<ListableBeanFactory>(),
      r.dependency<Environment>(),
    ),
  ),
  BeanDefinition<RateLimitWebMvcConfigurer>(
    name: 'rateLimitWebMvcConfigurer',
    types: const [RateLimitWebMvcConfigurer, WebMvcConfigurer],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.rateLimitWebMvcConfigurer', [
        ConditionalOnRateLimiting(),
      ]),
    ],
    create: (r) =>
        RateLimitWebMvcConfigurer(r.dependency<RateLimiterInterceptor>()),
  ),
  BeanDefinition<RateLimiterAnnotationGuard>(
    name: 'rateLimiterAnnotationGuard',
    types: const [RateLimiterAnnotationGuard, SmartInitializingSingleton],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.rateLimiterAnnotationGuard', [
        _OnRateLimitingNeverSet(),
      ]),
    ],
    create: (r) =>
        RateLimiterAnnotationGuard(r.dependency<ListableBeanFactory>()),
  ),
];

/// Adds the [RateLimiterInterceptor] to the controllers' interceptors.
final class RateLimitWebMvcConfigurer with WebMvcConfigurer {
  /// A configurer adding [interceptor].
  RateLimitWebMvcConfigurer(this.interceptor);

  /// The interceptor of `@RateLimiter`.
  final RateLimiterInterceptor interceptor;

  @override
  void addInterceptors(InterceptorRegistry registry) =>
      registry.addInterceptor(interceptor);
}

/// Whether the server shares its port among isolates: this isolate was
/// started by a pool, or it is the first one and `server.isolates.*` ask
/// for a pool. The rate limiter then keeps its buckets in the first
/// isolate by default.
final class OnServerIsolates implements Condition {
  /// The condition.
  const OnServerIsolates();

  @override
  bool matches(ConditionContext context) =>
      isServerIsolate ||
      (IsolateInfo.current.primary &&
          bindServerSettings(context.environment).isolates.pooled);

  @override
  String toString() => 'the server has a pool of isolates';
}

// Rate limiting neither on nor turned off: nobody said anything.
final class _OnRateLimitingNeverSet implements Condition {
  const _OnRateLimitingNeverSet();

  @override
  bool matches(ConditionContext context) {
    final properties = bindRateLimitProperties(context.environment);
    return properties.enabled == null && !properties.isOn;
  }

  @override
  String toString() => 'spring.web.rate-limit is not set';
}
