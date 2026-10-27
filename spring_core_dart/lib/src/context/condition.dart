import 'package:spring_core_dart/src/beans/bean_definition.dart';
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

  /// The definition whose conditions are being evaluated, like the
  /// `AnnotatedTypeMetadata` Spring passes to `Condition.matches`: its
  /// [BeanDefinition.annotations] (of the class, or of the `@Bean` method
  /// and its return type), name and types. `null` for the conditions of a
  /// `@PropertySource`. A [ConditionGroup] (the conditions of a
  /// `@Configuration` class shared by its `@Bean` methods) is evaluated
  /// once, with the first definition it guards.
  ///
  /// ```dart
  /// class OnExperimental implements Condition {
  ///   const OnExperimental();
  ///
  ///   // Beans annotated @Experimental() only when experiments are on.
  ///   @override
  ///   bool matches(ConditionContext context) {
  ///     final annotations = context.definition?.annotations ?? const [];
  ///     return annotations.whereType<Experimental>().isEmpty ||
  ///         context.environment.getProperty('experiments') == 'on';
  ///   }
  /// }
  /// ```
  BeanDefinition<Object>? get definition;
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

/// A [ConditionContext] that remembers results while modules load (see
/// [ConditionGroup]). The application context's condition context
/// implements it.
abstract interface class ConditionEvaluationCache {
  /// The cached result for [key], computing it with [evaluate] once.
  bool evaluateOnce(String key, bool Function() evaluate);
}

/// The outcome of one condition evaluated while a context loaded its
/// modules: what Spring Boot's `ConditionEvaluationReport` collects (and
/// prints for `--debug`). Read them from
/// `AnnotationConfigApplicationContext.conditionEvaluations`.
final class ConditionEvaluation {
  /// [condition] of [source] gave [matched].
  const ConditionEvaluation(
    this.source,
    this.condition, {
    required this.matched,
  });

  /// What the condition guards: a bean name, a [ConditionGroup.key] (a
  /// configuration class such as `package:app#CacheConfig`) or
  /// `@PropertySource <locations>`.
  final String source;

  /// The evaluated condition.
  final Condition condition;

  /// Whether it matched.
  final bool matched;

  @override
  String toString() =>
      '$source: $condition ${matched ? 'matched' : 'did not match'}';
}

/// Records condition outcomes; the context's [ConditionContext] is one.
/// [ConditionGroup] records its own conditions under its key.
abstract interface class ConditionEvaluationRecorder {
  /// Records that [condition] of [source] gave [matched].
  void recordCondition(String source, Condition condition, bool matched);
}

/// The conditions of one configuration class, evaluated once (per
/// [ConfigurationPhase]) for the class, all of its `@Bean` methods, its
/// `@Import`s, the classes it imports and its `@PropertySource`s, like
/// Spring's per-class condition evaluation: the class is registered all or
/// nothing.
///
/// Without the group, a class condition such as "no `Foo` bean yet" would
/// be re-checked for every `@Bean` method and drop the methods registered
/// after the class's own `Foo`. Generated code wraps class conditions in a
/// group keyed by the class.
///
/// ```dart
/// const group = ConditionGroup('package:app/cache.dart#CacheConfig', [
///   OnMissingCache(),
/// ]);
/// BeanDefinition<CacheConfig>(
///   name: 'cacheConfig',
///   conditions: const [group],
///   ...,
/// );
/// BeanDefinition<Cache>(name: 'cache', conditions: const [group], ...);
/// ```
///
/// Spring (Java): `ConditionEvaluator` tracking configuration classes.
class ConditionGroup implements Condition {
  /// Groups [conditions] under [key] (usually `library#Class`).
  const ConditionGroup(this.key, this.conditions);

  /// Identifies the group within one refresh.
  final String key;

  /// All must match.
  final List<Condition> conditions;

  @override
  bool matches(ConditionContext context) {
    bool evaluate() {
      for (final condition in conditions) {
        final matched = condition.matches(context);
        if (context is ConditionEvaluationRecorder) {
          (context as ConditionEvaluationRecorder).recordCondition(
            key,
            condition,
            matched,
          );
        }
        if (!matched) {
          return false;
        }
      }
      return true;
    }

    return context is ConditionEvaluationCache
        ? (context as ConditionEvaluationCache).evaluateOnce(key, evaluate)
        : evaluate();
  }

  /// Like [matches] in [phase] (see [conditionsMatch]); cached per phase.
  bool matchesIn(ConditionContext context, ConfigurationPhase phase) {
    bool evaluate() =>
        conditionsMatch(conditions, context, phase: phase, source: key);
    return context is ConditionEvaluationCache
        ? (context as ConditionEvaluationCache).evaluateOnce(
            '$key@${phase.name}',
            evaluate,
          )
        : evaluate();
  }
}

/// When a [ConfigurationCondition] is evaluated, like Spring's
/// `ConfigurationCondition.ConfigurationPhase`.
enum ConfigurationPhase {
  /// While configuration is parsed: whether a configuration class is used
  /// at all (its imports, `@PropertySource`s, selectors) and whether a
  /// component is registered.
  parseConfiguration,

  /// When the bean definitions of configuration classes (the class itself
  /// and its `@Bean` methods) are registered: after every module has been
  /// parsed, class by class in parse order (Spring's
  /// `ConfigurationClassBeanDefinitionReader`). Such a condition sees the
  /// components and the beans registered while parsing, and the `@Bean`
  /// methods and registrar beans of the classes read before (application
  /// classes before auto-configurations, imported classes before their
  /// importer).
  registerBean,
}

/// A [Condition] evaluated in one [ConfigurationPhase] only, like Spring's
/// `ConfigurationCondition`; plain conditions are evaluated in both.
///
/// A `registerBean` condition does not stop a configuration class from
/// being parsed (its property sources load, its selectors run); it
/// decides, when the class is read, whether the class, its `@Bean` methods
/// and its imports (registrars, selected classes) are registered — one
/// decision for all of them. On a `@Bean` method it is decided when that
/// method is registered. Spring Boot's `@ConditionalOnBean`,
/// `@ConditionalOnMissingBean` and `@ConditionalOnSingleCandidate` work
/// that way (`OnBeanCondition`). A scanned or imported component is a
/// lite configuration class: such a condition on it is decided when the
/// component is read, at its place in class order. Only a hand-written
/// definition with neither a `source` nor a `factoryMethodName` is decided
/// at once.
///
/// ```dart
/// class OnMissingClock implements ConfigurationCondition {
///   const OnMissingClock();
///
///   @override
///   ConfigurationPhase get configurationPhase =>
///       ConfigurationPhase.registerBean;
///
///   @override
///   bool matches(ConditionContext context) =>
///       context.beanFactory.getBeanNamesForType(Clock).isEmpty;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class OnMissingClock implements ConfigurationCondition {
///   public ConfigurationPhase getConfigurationPhase() {
///     return ConfigurationPhase.REGISTER_BEAN;
///   }
///   public boolean matches(
///       ConditionContext c, AnnotatedTypeMetadata m) { ... }
/// }
/// ```
abstract interface class ConfigurationCondition implements Condition {
  /// The phase the condition is evaluated in.
  ConfigurationPhase get configurationPhase;
}

/// Whether every one of [conditions] matches, like Spring's
/// `ConditionEvaluator.shouldSkip`: in [phase], a [ConfigurationCondition]
/// of the other phase is not evaluated (counts as matching); without a
/// phase every condition is evaluated.
///
/// ```dart
/// conditionsMatch(definition.conditions, context,
///     phase: ConfigurationPhase.parseConfiguration);
/// ```
bool conditionsMatch(
  Iterable<Condition> conditions,
  ConditionContext context, {
  ConfigurationPhase? phase,
  String? source,
}) {
  for (final condition in conditions) {
    final skipped = switch (condition) {
      ConfigurationCondition(:final configurationPhase) =>
        phase != null && configurationPhase != phase,
      _ => false,
    };
    final matches = switch (condition) {
      _ when skipped => true,
      final ConditionGroup group when phase != null => group.matchesIn(
        context,
        phase,
      ),
      _ => condition.matches(context),
    };
    // Outcomes go to the evaluation report under [source]; a group
    // records its own conditions under its key.
    if (source != null &&
        !skipped &&
        condition is! ConditionGroup &&
        context is ConditionEvaluationRecorder) {
      (context as ConditionEvaluationRecorder).recordCondition(
        source,
        condition,
        matches,
      );
    }
    if (!matches) {
      return false;
    }
  }
  return true;
}

/// Whether [conditions] (also inside a [ConditionGroup]) include a
/// [ConfigurationCondition] of [phase].
bool hasPhaseCondition(
  Iterable<Condition> conditions,
  ConfigurationPhase phase,
) => conditions.any(
  (condition) => switch (condition) {
    ConfigurationCondition(:final configurationPhase) =>
      configurationPhase == phase,
    ConditionGroup(:final conditions) => hasPhaseCondition(conditions, phase),
    _ => false,
  },
);
