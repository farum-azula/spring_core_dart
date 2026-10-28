import 'package:spring_core_dart/src/beans/bean_definition.dart';
import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';

/// What a [Condition] can look at to decide: the configuration, the bean
/// definitions registered so far, resource files, and the definition being
/// decided.
///
/// A condition receives it in [Condition.matches]; you do not create one.
/// Conditions run while the modules load, before any bean exists: only the
/// definitions registered so far are visible, and a condition must not
/// create beans (asking the factory for a bean here would create it too
/// early).
///
/// ```dart
/// // Register this bean only when no `cache` bean was declared before.
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
  /// The bean definitions registered so far, from the modules and classes
  /// loaded before; ask it whether a bean name is taken.
  BeanDefinitionRegistry get registry;

  /// The bean factory being filled, for questions by type
  /// (`getBeanNamesForType`); the same object as [registry].
  ConfigurableListableBeanFactory get beanFactory;

  /// The configuration: properties (including the `@PropertySource` files
  /// loaded so far) and active profiles.
  Environment get environment;

  /// Finds resource files, for a condition that depends on a file
  /// (`resourceLoader.getResource('file:x').exists()`).
  ResourceLoader get resourceLoader;

  /// The bean definition being decided, so that one condition class can
  /// read the annotations of the bean it guards.
  ///
  /// It carries the [BeanDefinition.annotations] (of the class, or of the
  /// `@Bean` method and its return type), the name and the types: what
  /// Spring passes as `AnnotatedTypeMetadata` to `Condition.matches`.
  /// `null` for the conditions of a `@PropertySource`. A [ConditionGroup]
  /// (the conditions of a `@Configuration` class, shared by its `@Bean`
  /// methods) is evaluated once, with the first definition it guards.
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

/// A rule that decides whether a bean is registered at all.
///
/// Use one when a bean should exist only in some situations that a
/// profile does not describe: a property set, a file present, another bean
/// missing. The rule runs while the modules load, before any bean is
/// created; when it does not match, the bean is not registered, as if it
/// had no annotation. Spring Boot's `@ConditionalOn...` annotations are
/// conditions of this kind.
///
/// Write a class that implements it, then use it in one of two ways:
/// through `@Conditional([MyCondition])` (the class needs a no-argument
/// constructor), or as an annotation itself. Any const annotation class
/// that implements [Condition] is evaluated, so conditions with arguments,
/// such as `@ConditionalOnProperty('feature.enabled')`, are plain classes.
///
/// ```dart
/// // The audit feature exists only with `feature.audit=true`.
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
  /// Whether the annotated bean should be registered; [context] gives
  /// access to the configuration and the definitions registered so far.
  bool matches(ConditionContext context);
}

/// The condition behind `@Profile`: it matches when one of its profile
/// expressions matches the active profiles.
///
/// The generator turns each `@Profile` into one; applications use the
/// annotation. Create one yourself only for a hand-written bean
/// definition or to test a profile expression.
///
/// ```dart
/// // Either entry may match: the dev profile is active, or cloud is not.
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
  /// Matches when any of the profile expressions [profiles] does.
  const ProfileCondition(this.profiles);

  /// Profile expressions such as `dev`, `!prod` or `eu & (dev | test)`.
  final List<String> profiles;

  /// Whether the environment accepts any of [profiles].
  @override
  bool matches(ConditionContext context) =>
      context.environment.matchesProfiles(profiles);
}

/// A [ConditionContext] that remembers results while the modules load, so
/// a [ConditionGroup] is decided only once.
///
/// The application context's condition context implements it; nothing
/// else needs to.
abstract interface class ConditionEvaluationCache {
  /// The result stored under [key]; the first call computes it with
  /// [evaluate].
  bool evaluateOnce(String key, bool Function() evaluate);
}

/// The outcome of one condition evaluated while a context loaded its
/// modules: which bean or class it guarded, and whether it matched.
///
/// Use these to find out why a bean is missing or present. Read them from
/// `AnnotationConfigApplicationContext.conditionEvaluations`;
/// `SpringApplication` prints them for `--debug`, as Spring Boot's
/// `ConditionEvaluationReport` does.
final class ConditionEvaluation {
  /// Records that [condition], guarding [source], gave [matched].
  const ConditionEvaluation(
    this.source,
    this.condition, {
    required this.matched,
  });

  /// What the condition guards: a bean name, a [ConditionGroup.key] (a
  /// configuration class such as `package:app#CacheConfig`) or
  /// `@PropertySource <locations>`.
  final String source;

  /// The evaluated condition; its `toString` describes it in the report.
  final Condition condition;

  /// Whether the condition matched.
  final bool matched;

  @override
  String toString() =>
      '$source: $condition ${matched ? 'matched' : 'did not match'}';
}

/// Receives the outcome of every condition evaluated, for
/// [ConditionEvaluation] reports.
///
/// The application context's [ConditionContext] implements it; a
/// [ConditionGroup] records its own conditions under its key.
abstract interface class ConditionEvaluationRecorder {
  /// Records that [condition], guarding [source], gave [matched].
  void recordCondition(String source, Condition condition, bool matched);
}

/// The conditions of one configuration class, decided once for the whole
/// class, so that the class is registered all or nothing.
///
/// A class's conditions also guard its `@Bean` methods, its `@Import`s,
/// the classes it imports and its `@PropertySource`s. Without the group, a
/// class condition such as "no `Foo` bean yet" would be checked again for
/// every `@Bean` method, and would drop the methods that come after the
/// class's own `Foo`. The group is decided once per [ConfigurationPhase],
/// as Spring decides per class.
///
/// The generator wraps class conditions in a group keyed by the class;
/// write one only for hand-written definitions that belong together.
///
/// ```dart
/// // The class and its cache bean: both or neither.
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
  /// Groups [conditions] under [key], usually `library#Class`.
  const ConditionGroup(this.key, this.conditions);

  /// Identifies the group within one refresh; the cached decision and the
  /// report entries are stored under it.
  final String key;

  /// The conditions of the class; all must match.
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

  /// Whether the conditions that count in [phase] all match (see
  /// [conditionsMatch]); decided once per phase.
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

/// The moment of loading at which a [ConfigurationCondition] is decided.
///
/// Spring (Java): `ConfigurationCondition.ConfigurationPhase`.
enum ConfigurationPhase {
  /// While the configuration is parsed: decides whether a configuration
  /// class is used at all (its imports, `@PropertySource`s, selectors) and
  /// whether a component is registered. Few beans are known yet.
  parseConfiguration,

  /// When the bean definitions of configuration classes (the class itself
  /// and its `@Bean` methods) are registered: after every module has been
  /// parsed, class by class in parse order (Spring's
  /// `ConfigurationClassBeanDefinitionReader`). Use it for conditions on
  /// other beans. Such a condition sees the components and the beans
  /// registered while parsing, and the `@Bean` methods and registrar beans
  /// of the classes read before (application classes before
  /// auto-configurations, imported classes before their importer).
  registerBean,
}

/// A [Condition] decided in one [ConfigurationPhase] only; plain
/// conditions count in both.
///
/// It exists for conditions on other beans. "Is there a `Clock` bean?" can
/// only be answered once the classes before have registered theirs, so
/// such a condition asks for [ConfigurationPhase.registerBean]. Spring
/// Boot's `@ConditionalOnBean`, `@ConditionalOnMissingBean` and
/// `@ConditionalOnSingleCandidate` work that way (`OnBeanCondition`).
/// Application code rarely writes one.
///
/// A `registerBean` condition does not stop a configuration class from
/// being parsed (its property sources load, its selectors run); it
/// decides, when the class is read, whether the class, its `@Bean` methods
/// and its imports (registrars, selected classes) are registered — one
/// decision for all of them. On a `@Bean` method it is decided when that
/// method is registered. A scanned or imported component is a
/// lite configuration class: such a condition on it is decided when the
/// component is read, at its place in class order. Only a hand-written
/// definition with neither a `source` nor a `factoryMethodName` is decided
/// at once.
///
/// ```dart
/// // A default clock that steps aside when the application has one.
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
  /// The phase in which the condition is decided; in the other phase it
  /// counts as matching.
  ConfigurationPhase get configurationPhase;
}

/// Whether every one of [conditions] matches; the context calls it for
/// each definition while the modules load.
///
/// In [phase], a [ConfigurationCondition] of the other phase is not
/// evaluated and counts as matching; without a phase every condition is
/// evaluated. Evaluation stops at the first condition that does not
/// match. With a [source], each outcome is recorded when [context] is a
/// [ConditionEvaluationRecorder]. Spring's `ConditionEvaluator.shouldSkip`,
/// inverted.
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
/// [ConfigurationCondition] of [phase]; the context uses it to tell which
/// definitions must wait for the `registerBean` phase.
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
