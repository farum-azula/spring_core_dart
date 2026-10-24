import 'package:spring_core_dart/spring_core_dart.dart';

/// Registers the bean only when the properties have [havingValue] (any
/// value other than `false` when [havingValue] is `null`), like Spring
/// Boot's `@ConditionalOnProperty`.
///
/// The property is [name], or each of [names] (all must match), each
/// after [prefix] (a `.` is added when missing).
///
/// ```dart
/// @Service()
/// @ConditionalOnProperty('feature.search', matchIfMissing: true)
/// class SearchService {}
///
/// @Bean()
/// @ConditionalOnProperty.names(['a', 'b'], prefix: 'app.feature')
/// Feature feature() => Feature(); // app.feature.a and app.feature.b
/// ```
///
/// Spring (Java):
/// ```java
/// @ConditionalOnProperty(name = "feature.search", matchIfMissing = true)
/// @ConditionalOnProperty(prefix = "app.feature", name = {"a", "b"})
/// ```
class ConditionalOnProperty implements Condition {
  /// Checks property [name] (after [prefix]).
  const ConditionalOnProperty(
    String this.name, {
    this.prefix = '',
    this.havingValue,
    this.matchIfMissing = false,
  }) : names = const [];

  /// Checks every property of [names] (after [prefix]); all must match.
  const ConditionalOnProperty.names(
    this.names, {
    this.prefix = '',
    this.havingValue,
    this.matchIfMissing = false,
  }) : name = null;

  /// The property to check (with the constructor).
  final String? name;

  /// The properties to check (with [ConditionalOnProperty.names]).
  final List<String> names;

  /// Put before each name (`app` and `enabled` check `app.enabled`).
  final String prefix;

  /// Expected value (case-insensitive); `null` accepts anything but `false`.
  final String? havingValue;

  /// Whether a missing property matches.
  final bool matchIfMissing;

  /// The full names of the checked properties.
  List<String> get propertyNames => [
    for (final property in [?name, ...names])
      prefix.isEmpty
          ? property
          : '${prefix.endsWith('.') ? prefix : '$prefix.'}$property',
  ];

  @override
  bool matches(ConditionContext context) {
    final expected = havingValue;
    for (final property in propertyNames) {
      final value = context.environment.getProperty(property);
      if (value == null) {
        if (!matchIfMissing) {
          return false;
        }
        continue;
      }
      final matched = expected == null || expected.isEmpty
          ? value.toLowerCase() != 'false'
          : value.toLowerCase() == expected.toLowerCase();
      if (!matched) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() =>
      '@ConditionalOnProperty (${propertyNames.join(', ')}'
      '${havingValue == null ? '' : '=$havingValue'})';
}

/// Registers the bean only when the boolean property [name] (after
/// [prefix]) is [havingValue], like Spring Boot's
/// `@ConditionalOnBooleanProperty`. A value that is not a boolean fails.
///
/// ```dart
/// @Bean()
/// @ConditionalOnBooleanProperty('app.metrics.enabled')
/// Metrics metrics() => Metrics();
/// ```
///
/// Spring (Java): `@ConditionalOnBooleanProperty("app.metrics.enabled")`.
class ConditionalOnBooleanProperty implements Condition {
  /// Checks property [name] (after [prefix]).
  const ConditionalOnBooleanProperty(
    String this.name, {
    this.prefix = '',
    this.havingValue = true,
    this.matchIfMissing = false,
  }) : names = const [];

  /// Checks every property of [names] (after [prefix]); all must match.
  const ConditionalOnBooleanProperty.names(
    this.names, {
    this.prefix = '',
    this.havingValue = true,
    this.matchIfMissing = false,
  }) : name = null;

  /// The property to check (with the constructor).
  final String? name;

  /// The properties to check (with [ConditionalOnBooleanProperty.names]).
  final List<String> names;

  /// Put before each name.
  final String prefix;

  /// The value that matches.
  final bool havingValue;

  /// Whether a missing property matches.
  final bool matchIfMissing;

  /// The full names of the checked properties.
  List<String> get propertyNames => [
    for (final property in [?name, ...names])
      prefix.isEmpty
          ? property
          : '${prefix.endsWith('.') ? prefix : '$prefix.'}$property',
  ];

  @override
  bool matches(ConditionContext context) {
    for (final property in propertyNames) {
      final value = context.environment.getPropertyAs<bool>(property);
      if (value == null ? !matchIfMissing : value != havingValue) {
        return false;
      }
    }
    return true;
  }

  @override
  String toString() =>
      '@ConditionalOnBooleanProperty (${propertyNames.join(', ')}='
      '$havingValue)';
}

/// Registers the bean only when the SpEL [expression] is `true`, like
/// Spring Boot's `@ConditionalOnExpression`. `${...}` placeholders are
/// resolved first; the expression may be written with or without `#{...}`
/// and is evaluated with the bean factory's expression resolver (beans,
/// `environment`, ...).
///
/// ```dart
/// @Bean()
/// @ConditionalOnExpression(r"${app.cache:true} and '${app.mode}' == 'eu'")
/// Cache cache() => Cache();
/// ```
///
/// Spring (Java):
/// `@ConditionalOnExpression("${app.cache:true} and '${app.mode}' == 'eu'")`.
class ConditionalOnExpression implements Condition {
  /// Checks [expression].
  const ConditionalOnExpression([this.expression = 'true']);

  /// The SpEL expression.
  final String expression;

  @override
  bool matches(ConditionContext context) {
    final wrapped = expression.startsWith('#{') ? expression : '#{$expression}';
    final resolved = context.environment.resolvePlaceholders(wrapped);
    final factory = context.beanFactory;
    final result =
        (factory.beanExpressionResolver ?? StandardBeanExpressionResolver())
            .evaluate(resolved, factory);
    return switch (result) {
      null => false,
      final bool value => value,
      _ => throw StateError(
        '@ConditionalOnExpression("$expression") gave '
        '${result.runtimeType} $result; it must give a bool',
      ),
    };
  }

  @override
  String toString() => '@ConditionalOnExpression ($expression)';
}

/// Registers the bean only when every resource of [resources] exists,
/// like Spring Boot's `@ConditionalOnResource` (`${...}` placeholders are
/// resolved).
///
/// ```dart
/// @Bean()
/// @ConditionalOnResource(['classpath:banner.txt'])
/// Banner banner() => Banner();
/// ```
///
/// Spring (Java): `@ConditionalOnResource(resources = "classpath:banner.txt")`.
class ConditionalOnResource implements Condition {
  /// Requires all of [resources].
  const ConditionalOnResource(this.resources);

  /// Resource locations (`classpath:`, `file:`, ...).
  final List<String> resources;

  @override
  bool matches(ConditionContext context) => resources.every(
    (location) => context.resourceLoader
        .getResource(context.environment.resolvePlaceholders(location))
        .exists(),
  );

  @override
  String toString() => '@ConditionalOnResource (${resources.join(', ')})';
}

/// Registers the bean only when a bean of [type] is already registered,
/// like Spring Boot's `@ConditionalOnBean`.
///
/// Conditions see the definitions registered before them: put them on
/// auto-configuration (registered after the application's beans). Like
/// Boot 3.4+, beans with `autowireCandidate: false` or
/// `defaultCandidate: false` do not count (for [ConditionalOnMissingBean]
/// either); beans of parent contexts do.
///
/// ```dart
/// @Bean()
/// @ConditionalOnBean(DataSource)
/// Migrations migrations(DataSource source) => Migrations(source);
/// ```
///
/// Spring (Java): `@ConditionalOnBean(DataSource.class)`.
class ConditionalOnBean implements Condition {
  /// Requires a bean of [type].
  const ConditionalOnBean(Type this.type) : name = null;

  /// Requires a bean named [name] (Spring Boot's
  /// `@ConditionalOnBean(name = "...")`).
  const ConditionalOnBean.named(String this.name) : type = null;

  /// The required bean type.
  final Type? type;

  /// The required bean name.
  final String? name;

  @override
  bool matches(ConditionContext context) => name != null
      ? context.beanFactory.containsBean(name!)
      : context.beanFactory.containsBeanOfType(type!);

  @override
  String toString() =>
      '@ConditionalOnBean (${name != null ? 'name: $name' : 'types: $type'})';
}

/// Registers the bean only when exactly one bean of [type] can be injected
/// (one candidate, or one primary — or one non-fallback — among several),
/// like Spring Boot's `@ConditionalOnSingleCandidate`. Beans with
/// `autowireCandidate: false` or `defaultCandidate: false` do not count;
/// beans of parent contexts do.
///
/// ```dart
/// @Bean()
/// @ConditionalOnSingleCandidate(DataSource)
/// Migrations migrations(DataSource source) => Migrations(source);
/// ```
///
/// Spring (Java): `@ConditionalOnSingleCandidate(DataSource.class)`.
class ConditionalOnSingleCandidate implements Condition {
  /// Requires a single candidate of [type].
  const ConditionalOnSingleCandidate(this.type);

  /// The bean type.
  final Type type;

  @override
  bool matches(ConditionContext context) {
    final definitions = <BeanDefinition<Object>?>[];
    for (
      ConfigurableListableBeanFactory? factory = context.beanFactory;
      factory != null;
      factory = switch (factory.parentBeanFactory) {
        final ConfigurableListableBeanFactory parent => parent,
        _ => null,
      }
    ) {
      for (final name in factory.getBeanNamesForType(type)) {
        final definition = factory.containsBeanDefinition(name)
            ? factory.getBeanDefinition(name)
            : null;
        if (definition == null ||
            (definition.autowireCandidate && definition.defaultCandidate)) {
          definitions.add(definition);
        }
      }
    }
    if (definitions.length == 1) {
      return true;
    }
    return definitions.where((d) => d?.primary ?? false).length == 1 ||
        definitions.where((d) => !(d?.fallback ?? false)).length == 1;
  }

  @override
  String toString() => '@ConditionalOnSingleCandidate (types: $type)';
}

/// Registers the bean only when no bean of [type] is registered yet, like
/// Spring Boot's `@ConditionalOnMissingBean`: the default a library
/// provides backs off when the application declares its own bean.
///
/// ```dart
/// @AutoConfiguration()
/// class HttpAutoConfiguration {
///   @Bean()
///   @ConditionalOnMissingBean(HttpClientSettings)
///   HttpClientSettings httpSettings() => HttpClientSettings();
/// }
/// ```
///
/// Spring (Java): `@ConditionalOnMissingBean` (the type is inferred from the
/// `@Bean` method there; here it is given explicitly).
class ConditionalOnMissingBean implements Condition {
  /// Requires that no bean of [type] exists.
  const ConditionalOnMissingBean(Type this.type) : name = null;

  /// Requires that no bean named [name] exists (Spring's
  /// `@ConditionalOnMissingBean(name = "...")`).
  const ConditionalOnMissingBean.named(String this.name) : type = null;

  /// The bean type that must be missing.
  final Type? type;

  /// The bean name that must be missing.
  final String? name;

  @override
  bool matches(ConditionContext context) => name != null
      ? !context.beanFactory.containsBean(name!)
      : !context.beanFactory.containsBeanOfType(type!);

  @override
  String toString() =>
      '@ConditionalOnMissingBean '
      '(${name != null ? 'name: $name' : 'types: $type'})';
}
