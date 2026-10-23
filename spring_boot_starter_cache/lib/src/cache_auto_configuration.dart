import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/cache.dart';
import 'package:spring_boot_starter_cache/src/cache_interceptor.dart';
import 'package:spring_boot_starter_cache/src/in_memory_cache.dart';
import 'package:spring_boot_starter_cache/src/no_op_cache.dart';

const _source = 'package:spring_boot_starter_cache#CacheAutoConfiguration';

/// The [CacheManager] described by the `spring.cache.*` properties, like
/// Spring Boot's `CacheAutoConfiguration`:
///
/// | Property | Meaning |
/// |---|---|
/// | `spring.cache.type` | `simple` (default): [InMemoryCacheManager]; `none`: [NoOpCacheManager] |
/// | `spring.cache.cache-names` | a fixed set of caches (`books,authors`); otherwise caches are created on demand |
/// | `spring.cache.simple.time-to-live` | how long entries live (`10m`, `PT1H`, milliseconds) |
/// | `spring.cache.simple.max-size` | maximum entries per cache |
/// | `spring.cache.simple.caches.<name>.time-to-live` / `.max-size` | the same for one cache |
///
/// ```dart
/// final manager = cacheManagerFromProperties(context.environment);
/// ```
///
/// Spring Boot (Java): `CacheAutoConfiguration` with
/// `SimpleCacheConfiguration` / `NoOpCacheConfiguration`.
CacheManager cacheManagerFromProperties(Environment environment) {
  final type = (environment.getProperty('spring.cache.type') ?? 'simple')
      .trim()
      .toLowerCase();
  switch (type) {
    case 'none':
      return NoOpCacheManager();
    case 'simple':
      break;
    default:
      throw StateError(
        "Unsupported spring.cache.type '$type': use 'simple' or 'none', or "
        'declare a CacheManager bean',
      );
  }
  final names = environment.getProperty('spring.cache.cache-names');
  CacheSpec spec(String prefix) => CacheSpec(
    timeToLive: environment.getPropertyAs<Duration>('$prefix.time-to-live'),
    maxSize: environment.getPropertyAs<int>('$prefix.max-size'),
  );
  return InMemoryCacheManager(
    cacheNames: names == null
        ? null
        : [
            for (final name in names.split(','))
              if (name.trim().isNotEmpty) name.trim(),
          ],
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

/// The beans of the starter: a `cacheManager` from `spring.cache.*` (only
/// when the application declares no [CacheManager] and no bean named
/// `cacheResolver`, as in Spring Boot), the [CacheInterceptor], the
/// [CacheOperationValidator] that checks the cache annotations of proxied
/// beans at startup and the advisor that applies the interceptor to
/// members with cache annotations.
final cacheAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<CacheManager>(
    name: 'cacheManager',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.cacheManager', [
        ConditionalOnMissingBean(CacheManager),
        ConditionalOnMissingBean.named('cacheResolver'),
      ]),
    ],
    create: (r) => cacheManagerFromProperties(r.dependency<Environment>()),
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
    create: (r) => CacheOperationValidator(r.dependency<CacheInterceptor>()),
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
