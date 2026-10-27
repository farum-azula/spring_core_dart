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
      if (prefix.isEmpty)
        property
      else
        '${prefix.endsWith('.') ? prefix : '$prefix.'}$property',
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
      if (prefix.isEmpty)
        property
      else
        '${prefix.endsWith('.') ? prefix : '$prefix.'}$property',
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

/// Registers the bean only when [platform] is the active [CloudPlatform]
/// (detected from environment variables, or set by
/// `spring.main.cloud-platform`), like Spring Boot's
/// `@ConditionalOnCloudPlatform`.
///
/// ```dart
/// @Bean()
/// @ConditionalOnCloudPlatform(CloudPlatform.kubernetes)
/// Probes probes() => Probes();
/// ```
///
/// Spring (Java): `@ConditionalOnCloudPlatform(CloudPlatform.KUBERNETES)`.
class ConditionalOnCloudPlatform implements Condition {
  /// Requires [platform].
  const ConditionalOnCloudPlatform(this.platform);

  /// The platform that must be active.
  final CloudPlatform platform;

  @override
  bool matches(ConditionContext context) =>
      platform.isActive(context.environment);

  @override
  String toString() => '@ConditionalOnCloudPlatform (${platform.name})';
}

/// Where `@ConditionalOnBean` / `@ConditionalOnMissingBean` look for beans,
/// like Spring Boot's `SearchStrategy`.
enum SearchStrategy {
  /// Only this context.
  current,

  /// Only the parent contexts (all of them).
  ancestors,

  /// This context and its parents.
  all,
}

/// Registers the bean only when the given beans are already registered,
/// like Spring Boot's `@ConditionalOnBean`: a bean of [type] (and of every
/// one of [types]), named [name] (and every one of [names]), and annotated
/// with each of [annotations] (the exact annotation class). Without any of
/// them, the type is the bean's own (the `@Bean` method's return type).
/// [search] limits the contexts searched.
///
/// Conditions see the definitions registered before them: put them on
/// auto-configuration (registered after the application's beans). Like
/// Boot 3.4+, beans with `autowireCandidate: false` or
/// `defaultCandidate: false` do not count by type (for
/// [ConditionalOnMissingBean] either); beans of parent contexts do.
///
/// ```dart
/// @Bean()
/// @ConditionalOnBean(DataSource)
/// Migrations migrations(DataSource source) => Migrations(source);
///
/// @Bean()
/// @ConditionalOnBean.where(
///   types: [DataSource, Clock],
///   search: SearchStrategy.current,
/// )
/// Audit audit() => Audit();
/// ```
///
/// Spring (Java): `@ConditionalOnBean(DataSource.class)`,
/// `@ConditionalOnBean(value = {DataSource.class, Clock.class},
/// search = SearchStrategy.CURRENT)`.
class ConditionalOnBean implements ConfigurationCondition {
  /// Requires a bean of [type]; without it, of the bean's own type.
  const ConditionalOnBean([this.type])
    : name = null,
      types = const [],
      names = const [],
      annotations = const [],
      search = SearchStrategy.all;

  /// Requires a bean named [name] (Spring Boot's
  /// `@ConditionalOnBean(name = "...")`).
  const ConditionalOnBean.named(
    String this.name, {
    this.search = SearchStrategy.all,
  }) : type = null,
       types = const [],
       names = const [],
       annotations = const [];

  /// Requires every bean described: all of [types], [names] and
  /// [annotations]; the bean's own type when all are empty.
  const ConditionalOnBean.where({
    this.types = const [],
    this.names = const [],
    this.annotations = const [],
    this.search = SearchStrategy.all,
  }) : type = null,
       name = null;

  /// The required bean type.
  final Type? type;

  /// The required bean name.
  final String? name;

  /// More required bean types.
  final List<Type> types;

  /// More required bean names.
  final List<String> names;

  /// Annotation classes each required on some bean (its class or `@Bean`
  /// method).
  final List<Type> annotations;

  /// The contexts searched.
  final SearchStrategy search;

  /// Decided when the bean definitions are registered, after every
  /// earlier configuration class (Boot's `OnBeanCondition` is a
  /// `REGISTER_BEAN` `ConfigurationCondition`).
  @override
  ConfigurationPhase get configurationPhase => ConfigurationPhase.registerBean;

  @override
  bool matches(ConditionContext context) {
    final spec = _BeanSpec(
      context,
      'ConditionalOnBean',
      types: [?type, ...types],
      names: [?name, ...names],
      annotations: annotations,
      ignored: const [],
      search: search,
    );
    return spec.types.every(spec.hasType) &&
        spec.names.every(spec.hasName) &&
        spec.annotations.every(spec.hasAnnotation);
  }

  @override
  String toString() {
    final description = _describe(
      [?type, ...types],
      [?name, ...names],
      annotations,
      const [],
      search,
    );
    return '@ConditionalOnBean ($description)';
  }
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
class ConditionalOnSingleCandidate implements ConfigurationCondition {
  /// Requires a single candidate of [type].
  const ConditionalOnSingleCandidate(this.type);

  /// The bean type.
  final Type type;

  /// Decided when the bean definitions are registered, after every
  /// earlier configuration class (Boot's `OnBeanCondition` is a
  /// `REGISTER_BEAN` `ConfigurationCondition`).
  @override
  ConfigurationPhase get configurationPhase => ConfigurationPhase.registerBean;

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

/// Registers the bean only when none of the given beans is registered yet,
/// like Spring Boot's `@ConditionalOnMissingBean`: the default a library
/// provides backs off when the application declares its own bean. No bean
/// of [type] (nor of any of [types]), named [name] (nor any of [names]) or
/// annotated with one of [annotations]; without any of them, no bean of the
/// bean's own type (the `@Bean` method's return type). Beans of [ignored]
/// types do not count; [search] limits the contexts searched.
///
/// ```dart
/// @AutoConfiguration()
/// class HttpAutoConfiguration {
///   @Bean()
///   @ConditionalOnMissingBean()
///   HttpClientSettings httpSettings() => HttpClientSettings();
///
///   @Bean()
///   @ConditionalOnMissingBean.where(ignored: [TestClock])
///   Clock clock() => SystemClock();
/// }
/// ```
///
/// Spring (Java): `@ConditionalOnMissingBean`,
/// `@ConditionalOnMissingBean(ignored = TestClock.class)`.
class ConditionalOnMissingBean implements ConfigurationCondition {
  /// Requires that no bean of [type] exists; without it, of the bean's own
  /// type.
  const ConditionalOnMissingBean([this.type])
    : name = null,
      types = const [],
      names = const [],
      annotations = const [],
      ignored = const [],
      search = SearchStrategy.all;

  /// Requires that no bean named [name] exists (Spring's
  /// `@ConditionalOnMissingBean(name = "...")`).
  const ConditionalOnMissingBean.named(
    String this.name, {
    this.search = SearchStrategy.all,
  }) : type = null,
       types = const [],
       names = const [],
       annotations = const [],
       ignored = const [];

  /// Requires that none of the beans described exists: of [types], named
  /// [names] or annotated with [annotations]; of the bean's own type when
  /// all are empty.
  const ConditionalOnMissingBean.where({
    this.types = const [],
    this.names = const [],
    this.annotations = const [],
    this.ignored = const [],
    this.search = SearchStrategy.all,
  }) : type = null,
       name = null;

  /// The bean type that must be missing.
  final Type? type;

  /// The bean name that must be missing.
  final String? name;

  /// More bean types that must be missing.
  final List<Type> types;

  /// More bean names that must be missing.
  final List<String> names;

  /// Annotation classes no bean may carry.
  final List<Type> annotations;

  /// Bean types that do not count.
  final List<Type> ignored;

  /// The contexts searched.
  final SearchStrategy search;

  /// Decided when the bean definitions are registered, after every
  /// earlier configuration class (Boot's `OnBeanCondition` is a
  /// `REGISTER_BEAN` `ConfigurationCondition`).
  @override
  ConfigurationPhase get configurationPhase => ConfigurationPhase.registerBean;

  @override
  bool matches(ConditionContext context) {
    final spec = _BeanSpec(
      context,
      'ConditionalOnMissingBean',
      types: [?type, ...types],
      names: [?name, ...names],
      annotations: annotations,
      ignored: ignored,
      search: search,
    );
    return !spec.types.any(spec.hasType) &&
        !spec.names.any(spec.hasName) &&
        !spec.annotations.any(spec.hasAnnotation);
  }

  @override
  String toString() {
    final description = _describe(
      [?type, ...types],
      [?name, ...names],
      annotations,
      ignored,
      search,
    );
    return '@ConditionalOnMissingBean ($description)';
  }
}

String _describe(
  List<Type> types,
  List<String> names,
  List<Type> annotations,
  List<Type> ignored,
  SearchStrategy search,
) => [
  if (types.isNotEmpty) 'types: ${types.join(', ')}',
  if (names.length == 1) 'name: ${names.single}',
  if (names.length > 1) 'names: ${names.join(', ')}',
  if (annotations.isNotEmpty) 'annotations: ${annotations.join(', ')}',
  if (ignored.isNotEmpty) 'ignored: ${ignored.join(', ')}',
  if (search != SearchStrategy.all) 'search: ${search.name}',
  if (types.isEmpty && names.isEmpty && annotations.isEmpty)
    "the bean's own type",
].join('; ');

// The beans `@ConditionalOnBean` / `@ConditionalOnMissingBean` look for,
// like Spring Boot's `OnBeanCondition.Spec`.
final class _BeanSpec {
  _BeanSpec(
    ConditionContext context,
    String annotation, {
    required List<Type> types,
    required this.names,
    required this.annotations,
    required List<Type> ignored,
    required SearchStrategy search,
  }) : factories = _factories(context.beanFactory, search),
       types = types.isEmpty && names.isEmpty && annotations.isEmpty
           ? [_deduce(context, annotation)]
           : types {
    for (final type in ignored) {
      for (final factory in factories) {
        _ignored.addAll(factory.getBeanNamesForType(type));
      }
    }
  }

  final List<ListableBeanFactory> factories;
  final List<Type> types;
  final List<String> names;
  final List<Type> annotations;
  final _ignored = <String>{};

  // Boot deduces the type from the `@Bean` method's return type.
  static Type _deduce(ConditionContext context, String annotation) {
    final definition = context.definition;
    if (definition == null) {
      throw StateError(
        '@$annotation did not specify a bean using type, name or annotation '
        "and the attempt to deduce the bean's type failed",
      );
    }
    return definition.beanType;
  }

  static List<ListableBeanFactory> _factories(
    ConfigurableListableBeanFactory factory,
    SearchStrategy search,
  ) {
    final all = <ListableBeanFactory>[];
    for (
      BeanFactory? current = factory;
      current != null;
      current = current is HierarchicalBeanFactory
          ? current.parentBeanFactory
          : null
    ) {
      if (current is ListableBeanFactory) {
        all.add(current);
      }
    }
    return switch (search) {
      SearchStrategy.current => all.take(1).toList(),
      SearchStrategy.ancestors => all.skip(1).toList(),
      SearchStrategy.all => all,
    };
  }

  // Whether [name] in [factory] counts: not ignored, and (for a
  // definition) an autowire and default candidate.
  bool _counts(ListableBeanFactory factory, String name) {
    if (_ignored.contains(name)) {
      return false;
    }
    if (factory is! BeanDefinitionRegistry ||
        !(factory as BeanDefinitionRegistry).containsBeanDefinition(name)) {
      return true;
    }
    final definition = (factory as BeanDefinitionRegistry).getBeanDefinition(
      name,
    );
    return definition.autowireCandidate && definition.defaultCandidate;
  }

  bool hasType(Type type) => factories.any(
    (factory) =>
        factory.getBeanNamesForType(type).any((name) => _counts(factory, name)),
  );

  bool hasName(String name) =>
      !_ignored.contains(name) &&
      factories.any(
        (factory) => factory is HierarchicalBeanFactory
            ? (factory as HierarchicalBeanFactory).containsLocalBean(name)
            : factory.containsBean(name),
      );

  bool hasAnnotation(Type annotation) => factories.any(
    (factory) => factory.beanDefinitionNames.any(
      (name) =>
          !_ignored.contains(name) &&
          factory is BeanDefinitionRegistry &&
          (factory as BeanDefinitionRegistry)
              .getBeanDefinition(name)
              .annotations
              .any((a) => a.runtimeType == annotation),
    ),
  );
}
