import 'package:spring_core_dart/spring_core_dart.dart';

/// Registers a bean only when a property is set, or set to a given value.
///
/// It is how a feature is switched on or off from configuration, without
/// code changes: put it on a `@Component()` class, a `@Bean` method or a
/// configuration class. A starter uses it so that an application can turn
/// one of its beans off with a property.
///
/// The property is [name], or each of [names] (all must match), each
/// after [prefix] (a `.` is added when missing). Without [havingValue] any
/// value except `false` matches; with it, the value must equal it,
/// ignoring case. A property that is not set does not match unless
/// [matchIfMissing] is true. For an `enabled` flag,
/// [ConditionalOnBooleanProperty] says the same more plainly.
///
/// ```dart
/// // Search is on unless feature.search=false.
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
  /// Checks the property [name] (after [prefix]). By default it matches
  /// when the property is set to anything but `false`.
  const ConditionalOnProperty(
    String this.name, {
    this.prefix = '',
    this.havingValue,
    this.matchIfMissing = false,
  }) : names = const [];

  /// Checks every property of [names] (each after [prefix]); all of them
  /// must match.
  const ConditionalOnProperty.names(
    this.names, {
    this.prefix = '',
    this.havingValue,
    this.matchIfMissing = false,
  }) : name = null;

  /// The property checked, when the unnamed constructor was used; null
  /// with [ConditionalOnProperty.names].
  final String? name;

  /// The properties checked with [ConditionalOnProperty.names]; empty with
  /// the unnamed constructor.
  final List<String> names;

  /// Put before each name, so `prefix: 'app'` with `'enabled'` checks
  /// `app.enabled`. Empty by default.
  final String prefix;

  /// The value the property must have, compared ignoring case. `null` (or
  /// empty) accepts any value except `false`.
  final String? havingValue;

  /// Whether a property that is not set matches. False by default, so a
  /// feature guarded this way is off until switched on.
  final bool matchIfMissing;

  /// The full names of the checked properties, with [prefix] applied.
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

/// Registers a bean only when a `true` / `false` property has the wanted
/// value.
///
/// It is the plain way to write an on/off switch such as
/// `app.metrics.enabled`. Unlike [ConditionalOnProperty], the value is
/// read as a boolean: a value that is not a boolean fails the start
/// instead of silently counting as "set".
///
/// ```dart
/// // Metrics only with app.metrics.enabled=true.
/// @Bean()
/// @ConditionalOnBooleanProperty('app.metrics.enabled')
/// Metrics metrics() => Metrics();
///
/// // On by default; app.audit.enabled=false turns it off.
/// @Bean()
/// @ConditionalOnBooleanProperty('app.audit.enabled', matchIfMissing: true)
/// Audit audit() => Audit();
/// ```
///
/// Spring (Java): `@ConditionalOnBooleanProperty("app.metrics.enabled")`.
class ConditionalOnBooleanProperty implements Condition {
  /// Checks the property [name] (after [prefix]). By default it matches
  /// when the property is `true`.
  const ConditionalOnBooleanProperty(
    String this.name, {
    this.prefix = '',
    this.havingValue = true,
    this.matchIfMissing = false,
  }) : names = const [];

  /// Checks every property of [names] (each after [prefix]); all of them
  /// must match.
  const ConditionalOnBooleanProperty.names(
    this.names, {
    this.prefix = '',
    this.havingValue = true,
    this.matchIfMissing = false,
  }) : name = null;

  /// The property checked, when the unnamed constructor was used; null
  /// with [ConditionalOnBooleanProperty.names].
  final String? name;

  /// The properties checked with [ConditionalOnBooleanProperty.names];
  /// empty with the unnamed constructor.
  final List<String> names;

  /// Put before each name, so `prefix: 'app'` with `'enabled'` checks
  /// `app.enabled`. Empty by default.
  final String prefix;

  /// The value that matches; `true` by default. Use `false` for a bean
  /// that replaces a feature when it is switched off.
  final bool havingValue;

  /// Whether a property that is not set matches; false by default.
  final bool matchIfMissing;

  /// The full names of the checked properties, with [prefix] applied.
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

/// Registers a bean only when an expression evaluates to `true`.
///
/// For a rule the other conditions cannot express, such as a combination
/// of several properties. The [expression] is in SpEL, the expression
/// language of `spring_core_dart`; `${...}` placeholders are replaced by
/// property values first. It may be written with or without `#{...}` and
/// is evaluated with the bean factory's expression resolver, so it can
/// refer to `environment` and to beans registered so far. A `null` result
/// counts as `false`; any other non-boolean result fails the start.
/// Prefer [ConditionalOnProperty] when it is enough: it is easier to read.
///
/// ```dart
/// // Only when caching is on (the default) and the shop runs in the EU.
/// @Bean()
/// @ConditionalOnExpression(r"${app.cache:true} and '${app.mode}' == 'eu'")
/// Cache cache() => Cache();
/// ```
///
/// Spring (Java):
/// `@ConditionalOnExpression("${app.cache:true} and '${app.mode}' == 'eu'")`.
class ConditionalOnExpression implements Condition {
  /// Checks [expression]; without one it always matches.
  const ConditionalOnExpression([this.expression = 'true']);

  /// The SpEL expression that must give `true`, with or without `#{...}`.
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

/// Registers a bean only when every one of some files exists.
///
/// Useful for a bean that reads a file which only some installations
/// have, such as a certificate or a template, so the application starts
/// without it elsewhere. The locations are resolved like any resource
/// (`classpath:` is `lib/resources/`, `file:` the file system), after
/// `${...}` placeholders are replaced.
///
/// ```dart
/// // TLS only where the operators mounted a certificate.
/// @Bean()
/// @ConditionalOnResource(['file:./config/tls/cert.pem'])
/// TlsSettings tls() => TlsSettings.fromDirectory('./config/tls');
/// ```
///
/// Spring (Java):
/// `@ConditionalOnResource(resources = "file:./config/tls/cert.pem")`.
class ConditionalOnResource implements Condition {
  /// Requires every location of [resources] to exist.
  const ConditionalOnResource(this.resources);

  /// The resource locations that must exist (`classpath:...`,
  /// `file:...`); they may contain `${...}` placeholders.
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

/// Registers a bean only when the application runs on a given cloud
/// platform, such as Kubernetes.
///
/// For beans that only make sense on one platform: health probes on
/// Kubernetes, a log format a platform's collector expects. The platform
/// is detected from the environment variables it sets, or forced with
/// `spring.main.cloud-platform` (useful in tests, or `none` to turn
/// detection off).
///
/// ```dart
/// // Probes for the kubelet; not registered on a laptop.
/// @Bean()
/// @ConditionalOnCloudPlatform(CloudPlatform.kubernetes)
/// Probes probes() => Probes();
/// ```
///
/// Spring (Java): `@ConditionalOnCloudPlatform(CloudPlatform.KUBERNETES)`.
class ConditionalOnCloudPlatform implements Condition {
  /// Requires [platform] to be the active platform.
  const ConditionalOnCloudPlatform(this.platform);

  /// The platform the application must run on.
  final CloudPlatform platform;

  @override
  bool matches(ConditionContext context) =>
      platform.isActive(context.environment);

  @override
  String toString() => '@ConditionalOnCloudPlatform (${platform.name})';
}

/// Which contexts [ConditionalOnBean] and [ConditionalOnMissingBean]
/// search for beans, when contexts have parents.
///
/// Only applications that build a hierarchy of contexts (a parent with
/// shared beans, children per module) need it; the default, [all], is
/// right otherwise.
///
/// Spring (Java): `SearchStrategy`.
enum SearchStrategy {
  /// Only the context being built, not its parents.
  current,

  /// Only the parent contexts, all the way up, not the context being
  /// built.
  ancestors,

  /// The context being built and all its parents. The default.
  all,
}

/// Registers a bean only when some other bean is already registered.
///
/// A starter uses it for beans that build on something the application
/// may or may not have: register database migrations only when there is
/// a `DataSource`, a metrics exporter only when there is a registry.
///
/// The required beans: one of [type] and of every one of [types], one
/// named [name] and every one of [names], and one annotated with each of
/// [annotations] (the exact annotation class, on the bean's class or
/// `@Bean` method). Without any of them, the bean's own type is required
/// (the `@Bean` method's return type). [search] limits the contexts
/// searched.
///
/// The condition is decided when the bean definitions are registered,
/// configuration class by configuration class, so it only sees what was
/// registered before. That is why it belongs on auto-configuration, which
/// comes after the application's beans; on an application class it
/// depends on the order of the classes. As in Spring Boot 3.4+, beans
/// declared with `autowireCandidate: false` or `defaultCandidate: false`
/// do not count when searching by type (for [ConditionalOnMissingBean]
/// either); beans of parent contexts do.
///
/// ```dart
/// // Migrations only when the application has a DataSource.
/// @Bean()
/// @ConditionalOnBean(DataSource)
/// Migrations migrations(DataSource source) => Migrations(source);
///
/// // Both beans must be in this context, not in a parent.
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
  /// Requires a bean of [type]; without [type], a bean of the annotated
  /// bean's own type.
  const ConditionalOnBean([this.type])
    : name = null,
      types = const [],
      names = const [],
      annotations = const [],
      search = SearchStrategy.all;

  /// Requires a bean named [name], in the contexts [search] selects
  /// (Spring Boot's `@ConditionalOnBean(name = "...")`).
  const ConditionalOnBean.named(
    String this.name, {
    this.search = SearchStrategy.all,
  }) : type = null,
       types = const [],
       names = const [],
       annotations = const [];

  /// Requires every bean described: one of each of [types], each of
  /// [names], and one carrying each of [annotations]. When all three are
  /// empty, a bean of the annotated bean's own type is required.
  const ConditionalOnBean.where({
    this.types = const [],
    this.names = const [],
    this.annotations = const [],
    this.search = SearchStrategy.all,
  }) : type = null,
       name = null;

  /// A type a bean must have, given to the unnamed constructor.
  final Type? type;

  /// A name a bean must have, given to [ConditionalOnBean.named].
  final String? name;

  /// Types that must each be present, given to [ConditionalOnBean.where].
  final List<Type> types;

  /// Names that must each be present, given to [ConditionalOnBean.where].
  final List<String> names;

  /// Annotation classes that must each be on some bean (its class or its
  /// `@Bean` method); the exact class counts, not a subclass.
  final List<Type> annotations;

  /// The contexts searched; [SearchStrategy.all] by default.
  final SearchStrategy search;

  /// Decided when the bean definitions are registered, after every
  /// earlier configuration class, so that it sees their beans (Spring
  /// Boot's `OnBeanCondition` is a `REGISTER_BEAN`
  /// `ConfigurationCondition`).
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

/// Registers a bean only when exactly one bean of a type can be injected
/// where that type is asked for.
///
/// [ConditionalOnBean] is satisfied by several beans of a type, but a
/// bean that takes one of them as a constructor parameter would then fail
/// with an ambiguity. This condition checks that the injection works:
/// there is one candidate, or one `@Primary()` among several, or one that
/// is not `@Fallback()`. Beans with `autowireCandidate: false` or
/// `defaultCandidate: false` do not count; beans of parent contexts do.
/// Like [ConditionalOnBean], it only sees beans registered before it.
///
/// ```dart
/// // Safe to inject a DataSource here: there is exactly one to choose.
/// @Bean()
/// @ConditionalOnSingleCandidate(DataSource)
/// Migrations migrations(DataSource source) => Migrations(source);
/// ```
///
/// Spring (Java): `@ConditionalOnSingleCandidate(DataSource.class)`.
class ConditionalOnSingleCandidate implements ConfigurationCondition {
  /// Requires that a single bean of [type] can be injected.
  const ConditionalOnSingleCandidate(this.type);

  /// The type that must have a single injectable bean.
  final Type type;

  /// Decided when the bean definitions are registered, after every
  /// earlier configuration class, so that it sees their beans (Spring
  /// Boot's `OnBeanCondition` is a `REGISTER_BEAN`
  /// `ConfigurationCondition`).
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

/// Registers a bean only when no such bean is registered yet: the way a
/// library offers a default that the application can replace.
///
/// This is the most used condition of auto-configuration. A starter
/// declares its `Clock`, `HttpClient` or `ObjectMapper` with it; when the
/// application declares its own bean of that type, the starter's bean is
/// not registered and the application's is injected everywhere. Because
/// auto-configuration is registered after the application's beans, the
/// application's bean is always seen.
///
/// What must be missing: a bean of [type] or of any of [types], named
/// [name] or any of [names], or carrying one of [annotations]. Without
/// any of them, a bean of the annotated bean's own type (the `@Bean`
/// method's return type). Beans of [ignored] types do not count; [search]
/// limits the contexts searched. As with [ConditionalOnBean], beans
/// declared with `autowireCandidate: false` or `defaultCandidate: false`
/// do not count when searching by type.
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
  /// Requires that no bean of [type] exists; without [type], no bean of
  /// the annotated bean's own type.
  const ConditionalOnMissingBean([this.type])
    : name = null,
      types = const [],
      names = const [],
      annotations = const [],
      ignored = const [],
      search = SearchStrategy.all;

  /// Requires that no bean named [name] exists in the contexts [search]
  /// selects (Spring Boot's `@ConditionalOnMissingBean(name = "...")`).
  const ConditionalOnMissingBean.named(
    String this.name, {
    this.search = SearchStrategy.all,
  }) : type = null,
       types = const [],
       names = const [],
       annotations = const [],
       ignored = const [];

  /// Requires that none of the beans described exists: none of [types],
  /// none named in [names], none carrying one of [annotations]. When all
  /// three are empty, no bean of the annotated bean's own type. Beans of
  /// the [ignored] types do not count.
  const ConditionalOnMissingBean.where({
    this.types = const [],
    this.names = const [],
    this.annotations = const [],
    this.ignored = const [],
    this.search = SearchStrategy.all,
  }) : type = null,
       name = null;

  /// A type no bean may have, given to the unnamed constructor.
  final Type? type;

  /// A name no bean may have, given to [ConditionalOnMissingBean.named].
  final String? name;

  /// Types no bean may have, given to [ConditionalOnMissingBean.where].
  final List<Type> types;

  /// Names no bean may have, given to [ConditionalOnMissingBean.where].
  final List<String> names;

  /// Annotation classes no bean may carry on its class or `@Bean` method;
  /// the exact class counts, not a subclass.
  final List<Type> annotations;

  /// Bean types that do not count, for example a test double that should
  /// not make the real bean back off.
  final List<Type> ignored;

  /// The contexts searched; [SearchStrategy.all] by default.
  final SearchStrategy search;

  /// Decided when the bean definitions are registered, after every
  /// earlier configuration class, so that it sees their beans (Spring
  /// Boot's `OnBeanCondition` is a `REGISTER_BEAN`
  /// `ConfigurationCondition`).
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
