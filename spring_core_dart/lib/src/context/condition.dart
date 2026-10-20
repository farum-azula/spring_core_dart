import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';

/// What a [Condition] can inspect, like Spring's `ConditionContext`.
///
/// Conditions run while modules are loaded, so only the definitions
/// registered so far are visible and no beans should be created.
///
/// ```dart
/// class OnMissingCache implements Condition {
///   const OnMissingCache();
///
///   @override
///   bool matches(ConditionContext context) =>
///       !context.registry.containsBeanDefinition('cache');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class OnMissingCache implements Condition {
///   public boolean matches(ConditionContext ctx, AnnotatedTypeMetadata m) {
///     return !ctx.getRegistry().containsBeanDefinition("cache");
///   }
/// }
/// ```
abstract interface class ConditionContext {
  /// Definitions registered so far (earlier modules and beans).
  BeanDefinitionRegistry get registry;

  /// The bean factory being populated.
  ConfigurableListableBeanFactory get beanFactory;

  /// The environment, including already loaded `@PropertySource` files.
  Environment get environment;

  /// Loader for checking resources (for example `resourceLoader
  /// .getResource('file:x').exists()`).
  ResourceLoader get resourceLoader;
}

/// Decides whether a bean is registered, like Spring's `Condition`.
///
/// Used through `@Conditional([MyCondition])` (no-argument constructor),
/// or directly as an annotation: any const annotation class that
/// implements [Condition] is evaluated, so attribute-style conditions such
/// as `@ConditionalOnProperty('feature.enabled')` are plain classes.
///
/// ```dart
/// class ConditionalOnProperty implements Condition {
///   const ConditionalOnProperty(this.name, {this.havingValue = 'true'});
///
///   final String name;
///   final String havingValue;
///
///   @override
///   bool matches(ConditionContext context) =>
///       context.environment.getProperty(name) == havingValue;
/// }
///
/// @Component()
/// @ConditionalOnProperty('feature.audit')
/// class AuditFeature {}
/// ```
///
/// Spring (Java):
/// ```java
/// class OnAuditEnabled implements Condition {
///   public boolean matches(ConditionContext ctx, AnnotatedTypeMetadata m) {
///     return "true".equals(
///         ctx.getEnvironment().getProperty("feature.audit"));
///   }
/// }
///
/// @Component
/// @Conditional(OnAuditEnabled.class)
/// class AuditFeature {}
/// ```
///
/// Unlike Spring there is no `AnnotatedTypeMetadata` parameter: an
/// annotation-style condition reads its own fields instead.
abstract interface class Condition {
  /// Whether the annotated bean should be registered.
  bool matches(ConditionContext context);
}

/// Matches when the profile expressions match the environment, used for
/// `@Profile`.
///
/// ```dart
/// const condition = ProfileCondition(['dev', '!cloud']);
/// final register = condition.matches(conditionContext);
/// ```
///
/// Spring (Java):
/// ```java
/// // org.springframework.context.annotation.ProfileCondition, applied
/// // by @Profile({"dev", "!cloud"})
/// ```
final class ProfileCondition implements Condition {
  /// Creates a condition for the profile expressions [profiles].
  const ProfileCondition(this.profiles);

  /// Profile expressions such as `dev`, `!prod` or `eu & (dev | test)`.
  final List<String> profiles;

  /// Whether the environment accepts any of [profiles].
  @override
  bool matches(ConditionContext context) =>
      context.environment.matchesProfiles(profiles);
}
