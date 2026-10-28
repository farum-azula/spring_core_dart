import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache.dart';
import 'package:spring_boot_starter_cache/src/cache_interceptor.dart';
import 'package:spring_boot_starter_cache/src/in_memory_cache.dart';
import 'package:spring_boot_starter_cache/src/no_op_cache.dart';

const _source = 'package:spring_boot_starter_cache#CacheAutoConfiguration';

/// Builds the [CacheManager] that the `spring.cache.*` properties of
/// [environment] describe: the manager the starter creates when the
/// application declares none.
///
/// Applications set the properties and let the starter call it. Call it
/// yourself when you declare your own `CacheManager` bean but still want
/// it configured by the same properties, for example to wrap it.
///
/// - `spring.cache.type`: `generic` gives a [SimpleCacheManager] of
///   [caches] (the `Cache` beans) and is the default when there are any;
///   `simple` gives an [InMemoryCacheManager] and is the default
///   otherwise; `none` gives a [NoOpCacheManager] (nothing is cached).
///   Any other value throws a `StateError`, and so does `generic` without
///   caches.
/// - `spring.cache.cache-names`: a fixed set of caches (`books,authors`,
///   or a YAML list); an annotation naming another cache then fails. When
///   missing or empty, caches are created on demand.
/// - `spring.cache.simple.time-to-live`: how long entries live (`10m`,
///   `30s`, `PT1H`, or milliseconds); none by default.
/// - `spring.cache.simple.max-size`: the most entries per cache; no limit
///   by default.
/// - `spring.cache.simple.caches.<name>.time-to-live` / `.max-size`: the
///   same for one cache; what it leaves out comes from the two above.
///
/// Each of [customizers] then gets the new manager, in order.
///
/// ```dart
/// // Your own manager bean, still configured by spring.cache.*.
/// @Configuration()
/// class CacheSetup {
///   @Bean()
///   CacheManager cacheManager(Environment environment) =>
///       cacheManagerFromProperties(environment);
/// }
/// ```
///
/// Spring Boot (Java): `CacheAutoConfiguration` with
/// `GenericCacheConfiguration` / `SimpleCacheConfiguration` /
/// `NoOpCacheConfiguration`.
CacheManager cacheManagerFromProperties(
  Environment environment, {
  List<Cache> caches = const [],
  List<CacheManagerCustomizer> customizers = const [],
}) {
  final manager = _cacheManager(environment, caches);
  for (final customizer in customizers) {
    customizer.customize(manager);
  }
  return manager;
}

CacheManager _cacheManager(Environment environment, List<Cache> caches) {
  final configured = environment.getProperty('spring.cache.type')?.trim();
  // Boot tries generic first: it applies when there are Cache beans.
  final type = configured == null || configured.isEmpty
      ? (caches.isEmpty ? 'simple' : 'generic')
      : configured.toLowerCase();
  switch (type) {
    case 'none':
      return NoOpCacheManager();
    case 'generic':
      if (caches.isEmpty) {
        throw StateError(
          'spring.cache.type=generic needs at least one Cache bean (the '
          'caches of the manager)',
        );
      }
      return SimpleCacheManager(caches);
    case 'simple':
      break;
    default:
      throw StateError(
        "Unsupported spring.cache.type '$type': use 'generic', 'simple' or "
        "'none', or declare a CacheManager bean",
      );
  }
  // A comma list or a YAML list (`spring.cache.cache-names[0]`).
  final names = environment is ConfigurableEnvironment
      ? Binder.get(environment)
            .bind(
              'spring.cache.cache-names',
              const ListType<String>(ClassType<String>()),
            )
            .map<List<String>?>((names) => names)
            .orElse(null)
      : environment.getProperty('spring.cache.cache-names')?.split(',');
  // Like Boot's SimpleCacheConfiguration: only a non-empty list fixes the
  // caches (`spring.cache.cache-names=` keeps them dynamic).
  final cacheNames = [
    for (final name in names ?? const <String>[])
      if (name.trim().isNotEmpty) name.trim(),
  ];
  CacheSpec spec(String prefix) => CacheSpec(
    timeToLive: environment.getPropertyAs<Duration>('$prefix.time-to-live'),
    maxSize: environment.getPropertyAs<int>('$prefix.max-size'),
  );
  return InMemoryCacheManager(
    cacheNames: cacheNames.isEmpty ? null : cacheNames,
    defaultSpec: spec('spring.cache.simple'),
    specFor: (name) {
      final prefix = 'spring.cache.simple.caches.$name';
      if (environment.containsProperty('$prefix.time-to-live') ||
          environment.containsProperty('$prefix.max-size')) {
        final defaults = spec('spring.cache.simple');
        final own = spec(prefix);
        return CacheSpec(
          timeToLive: own.timeToLive ?? defaults.timeToLive,
          maxSize: own.maxSize ?? defaults.maxSize,
        );
      }
      return null;
    },
  );
}

/// The bean definitions the starter adds to every application.
///
/// - `cacheManager`, built by [cacheManagerFromProperties], only when the
///   application declares no [CacheManager] and no bean named
///   `cacheResolver` (as in Spring Boot), with the `Cache` and
///   [CacheManagerCustomizer] beans;
/// - `cacheInterceptor`, the [CacheInterceptor] that does the caching;
/// - `cacheOperationValidator`, the [CacheOperationValidator] that checks
///   the annotations of proxied beans at startup;
/// - `cacheAdvisor`, which applies the interceptor to the members that
///   have cache annotations.
final cacheAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<CacheManager>(
    name: 'cacheManager',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'cacheManager',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.cacheManager', [
        ConditionalOnMissingBean(CacheManager),
        ConditionalOnMissingBean.named('cacheResolver'),
      ]),
    ],
    create: (r) => cacheManagerFromProperties(
      r.dependency<Environment>(),
      caches: r.optionalDependencyList<Cache>() ?? const [],
      customizers:
          r.optionalDependencyList<CacheManagerCustomizer>() ?? const [],
    ),
  ),
  BeanDefinition<CacheInterceptor>(
    name: 'cacheInterceptor',
    types: const [CacheInterceptor, MethodInterceptor],
    source: _source,
    create: (r) => CacheInterceptor(
      beanFactory: r.dependency<BeanFactory>(),
      introspector: r.dependency<BeanIntrospector>(),
    ),
  ),
  BeanDefinition<CacheOperationValidator>(
    name: 'cacheOperationValidator',
    types: const [CacheOperationValidator, BeanPostProcessor, BeanFactoryAware],
    source: _source,
    create: (r) {
      final factory = r.dependency<BeanFactory>();
      return CacheOperationValidator.lazy(
        () => factory.getBean<CacheInterceptor>(),
      );
    },
  ),
  BeanDefinition<DefaultPointcutAdvisor>(
    name: 'cacheAdvisor',
    types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor, Ordered],
    source: _source,
    create: (r) => DefaultPointcutAdvisor(
      const CacheAnnotationPointcut(),
      r.dependency<CacheInterceptor>(),
    ),
  ),
];
