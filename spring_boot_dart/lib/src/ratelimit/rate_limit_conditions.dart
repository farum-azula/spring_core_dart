import 'package:spring_boot_dart/src/properties/properties.dart';
import 'package:spring_boot_dart/src/properties/rate_limit_properties.dart';
import 'package:spring_boot_dart/src/ratelimit/rate_limit.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// The `spring.web.rate-limit.*` properties of [environment], bound: for
/// a condition, which runs before any bean exists.
RateLimitProperties bindRateLimitProperties(Environment environment) =>
    bindBootProperties(environment, RateLimitProperties());

/// Registers a bean only when the rate limiter is on
/// (`spring.web.rate-limit.enabled`, or a rule when that is not set).
///
/// ```dart
/// @Bean()
/// @ConditionalOnRateLimiting()
/// RateLimitAudit audit() => RateLimitAudit();
/// ```
final class ConditionalOnRateLimiting implements Condition {
  /// Requires the rate limiter.
  const ConditionalOnRateLimiting();

  @override
  bool matches(ConditionContext context) =>
      bindRateLimitProperties(context.environment).isOn;

  @override
  String toString() => '@ConditionalOnRateLimiting';
}

/// Registers a `RateLimitStore` bean when it is the one the application
/// asked for, or the best it has: how a library offers its store to the
/// rate limiter, and how the framework's own are chosen.
///
/// It matches when the rate limiter is on, no [RateLimitStore] is
/// registered yet, and
///
/// - `spring.web.rate-limit.store` is [name], or
/// - that property is not set and [byDefault] matches (when given).
///
/// The stores are asked in the order of their modules, the most specific
/// first (a module names the ones it comes after), and the first that
/// matches is the default; a bean of the application is registered
/// before them all and wins.
///
/// ```dart
/// // A store over Redis, the default when the application has a client.
/// BeanDefinition<RateLimitStore>(
///   name: 'redisRateLimitStore',
///   conditions: const [
///     ConditionGroup('redisRateLimitStore', [
///       ConditionalOnRateLimitStore(
///         'redis',
///         byDefault: ConditionalOnBean(RedisClient),
///       ),
///     ]),
///   ],
///   create: (r) => RedisRateLimitStore(r.dependency<RedisClient>()),
/// )
/// ```
///
/// Spring Boot chooses a `CacheManager` the same way: `spring.cache.type`
/// names one, else the first of `CacheConfigurations` whose condition
/// matches.
final class ConditionalOnRateLimitStore implements ConfigurationCondition {
  /// The condition of the store called [name].
  const ConditionalOnRateLimitStore(this.name, {this.byDefault});

  /// The value of `spring.web.rate-limit.store` that asks for this store.
  final String name;

  /// What must hold for this store to be the default; `null`: nothing.
  final Condition? byDefault;

  /// Decided when the bean definitions are registered, so that it sees
  /// the stores of the modules before.
  @override
  ConfigurationPhase get configurationPhase => ConfigurationPhase.registerBean;

  @override
  bool matches(ConditionContext context) {
    final properties = bindRateLimitProperties(context.environment);
    if (!properties.isOn ||
        context.beanFactory.getBeanNamesForType(RateLimitStore).isNotEmpty) {
      return false;
    }
    final asked = properties.store?.trim().toLowerCase();
    if (asked != null && asked.isNotEmpty) {
      return asked == name.toLowerCase();
    }
    return byDefault?.matches(context) ?? true;
  }

  @override
  String toString() =>
      '@ConditionalOnRateLimitStore ($name'
      '${byDefault == null ? '' : '; by default: $byDefault'})';
}
