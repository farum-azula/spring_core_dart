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
///   `30s`, `PT1H`, or milliseconds); none by default, `0` keeps nothing.
/// - `spring.cache.simple.max-size`: the most entries per cache; no limit
///   by default, `0` keeps nothing.
/// - `spring.cache.simple.caches.<name>.time-to-live` / `.max-size`: the
///   same for one cache; what it leaves out comes from the two above. A
///   name with dots goes in brackets, as in any Spring Boot map
///   (`caches[books.byIsbn].max-size`); the plain form is read too. The
///   property may take any relaxed form, the environment variables'
///   included: `SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAX_SIZE` (or
///   `_MAXSIZE`, `_TIME_TO_LIVE`, `_TIMETOLIVE`) sets the cache `books`.
///
/// A negative size or time to live throws an `ArgumentError` naming the
/// property, as Caffeine refuses them; the per-cache ones are checked
/// here too, before their caches exist.
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
  // Caffeine refuses a negative maximumSize or expireAfterWrite; 0 keeps
  // nothing in both.
  int? maxSize(String key, int? value) {
    if (value != null && value < 0) {
      throw ArgumentError.value(
        value,
        key,
        'must not be negative (0 keeps no entry)',
      );
    }
    return value;
  }

  Duration? timeToLive(String key, Duration? value) {
    if (value != null && value.isNegative) {
      throw ArgumentError.value(
        '$value',
        key,
        'must not be negative (0 keeps no entry)',
      );
    }
    return value;
  }

  CacheSpec spec(String prefix) => CacheSpec(
    timeToLive: timeToLive(
      '$prefix.time-to-live',
      environment.getPropertyAs<Duration>('$prefix.time-to-live'),
    ),
    maxSize: maxSize(
      '$prefix.max-size',
      environment.getPropertyAs<int>('$prefix.max-size'),
    ),
  );
  final defaults = spec('spring.cache.simple');
  // Bound and checked now, so a wrong value fails the start instead of
  // the first use of the cache; `null` for an environment without
  // property sources to list.
  final perCache = environment is ConfigurableEnvironment
      ? _perCacheSpecs(environment, maxSize, timeToLive)
      : null;
  CacheSpec? specFor(String name) {
    final prefix = 'spring.cache.simple.caches.$name';
    final own = perCache != null
        ? perCache[name]
        : environment.containsProperty('$prefix.time-to-live') ||
              environment.containsProperty('$prefix.max-size')
        ? spec(prefix)
        : null;
    if (own == null) {
      return null;
    }
    return CacheSpec(
      timeToLive: own.timeToLive ?? defaults.timeToLive,
      maxSize: own.maxSize ?? defaults.maxSize,
    );
  }

  return InMemoryCacheManager(
    cacheNames: cacheNames.isEmpty ? null : cacheNames,
    defaultSpec: defaults,
    specFor: specFor,
  );
}

// The properties of a cache's limits, by the relaxed form they are
// compared in: lower case, without `-`, `_` and the `.` an environment
// variable's `_` becomes.
const _perCacheProperties = {
  'maxsize': 'max-size',
  'timetolive': 'time-to-live',
};

// The limits of `spring.cache.simple.caches.<name>.*`, bound as Spring
// Boot binds a map: a cache name with dots in brackets
// (`caches[books.byIsbn].max-size`, in YAML `"[books.byIsbn]":`), or
// written plainly (`caches.prices.eu.max-size`). The property is the
// longest end of the key that is `max-size` or `time-to-live` in a relaxed
// form (`maxSize`, `max_size`, `MAXSIZE`, or `max.size`: the variable
// SPRING_CACHE_SIMPLE_CACHES_BOOKS_MAX_SIZE binds as `books` /
// `max.size`, which the last element alone read as a cache `books.max`
// with a property `size`, ignored); the cache name is all before it. A key
// ending in no such property is ignored, as Boot ignores unknown ones.
// Each value is converted and checked by [maxSize] and [timeToLive], with
// the property as written (an environment variable's as `max-size` /
// `time-to-live`). Of two forms of one property, the first bound wins:
// the binder lists the sources from the highest precedence down.
Map<String, CacheSpec> _perCacheSpecs(
  ConfigurableEnvironment environment,
  int? Function(String key, int? value) maxSize,
  Duration? Function(String key, Duration? value) timeToLive,
) {
  const prefix = 'spring.cache.simple.caches';
  final bound = Binder.get(environment)
      .bind(
        prefix,
        const MapType<String, Map<String, String>>(
          ClassType<String>(),
          MapType<String, String>(ClassType<String>(), ClassType<String>()),
        ),
      )
      .orElse(const {});
  final values = <String, Map<String, (String, String)>>{};
  for (final MapEntry(key: first, value: properties) in bound.entries) {
    for (final MapEntry(key: rest, :value) in properties.entries) {
      if (value.trim().isEmpty) {
        continue;
      }
      final elements = rest.split('.');
      for (var start = 0; start < elements.length; start++) {
        final canonical = elements
            .skip(start)
            .join()
            .toLowerCase()
            .replaceAll(RegExp('[-_]'), '');
        final dashed = _perCacheProperties[canonical];
        if (dashed == null) {
          continue;
        }
        final name = [first, ...elements.take(start)].join('.');
        final key = [
          if (first.contains('.')) '$prefix[$first]' else '$prefix.$first',
          ...elements.take(start),
          if (start == elements.length - 1) elements.last else dashed,
        ].join('.');
        (values[name] ??= {}).putIfAbsent(canonical, () => (key, value));
        break;
      }
    }
  }
  final conversion = environment.conversionService;
  return {
    for (final MapEntry(key: name, value: properties) in values.entries)
      name: CacheSpec(
        timeToLive: switch (properties['timetolive']) {
          (final key, final value) => timeToLive(
            key,
            conversion.convert<Duration>(value),
          ),
          null => null,
        },
        maxSize: switch (properties['maxsize']) {
          (final key, final value) => maxSize(
            key,
            conversion.convert<int>(value),
          ),
          null => null,
        },
      ),
  };
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
