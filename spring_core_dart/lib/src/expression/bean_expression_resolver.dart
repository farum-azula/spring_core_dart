import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/exceptions.dart';
import 'package:spring_core_dart/src/core/env/command_line_property_source.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/platform_environment_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/env/platform_environment_io.dart';
import 'package:spring_core_dart/src/core/env/property_resolver.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/expression/evaluation_context.dart';
import 'package:spring_core_dart/src/expression/expression.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/spel_parser.dart';
import 'package:spring_core_dart/src/expression/spel_parser_configuration.dart';
import 'package:spring_core_dart/src/expression/spel_type.dart';

/// The root object of `@Value('#{...}')` expressions, whose properties are
/// the beans of a bean factory.
///
/// It is why `#{mailer.defaultSender}` in an `@Value` reads the bean named
/// `mailer`: unprefixed names are looked up on this root, and
/// [BeanExpressionContextAccessor] answers them with beans.
/// [StandardBeanExpressionResolver] creates it; applications only use it
/// through those expressions. Two names are always present, unless beans
/// with these names exist: `systemEnvironment`, the map of environment
/// variables (of the `environment` bean when there is one), and
/// `systemProperties`. Dart has no JVM system properties, so
/// `systemProperties` is the map of `--key=value` command-line arguments
/// (the `commandLineArgs` property source of the `environment` bean),
/// which play the part of `-Dkey=value`; compile-time `-D` defines are
/// constants and cannot be enumerated.
///
/// ```dart
/// // What `#{mailer}` and `#{systemEnvironment['HOME']}` see.
/// final root = BeanExpressionContext(beanFactory);
/// root.containsObject('mailer'); // true when the bean exists
/// root.getObject('mailer'); // the bean, or null
/// root.getObject('systemEnvironment'); // {'HOME': ..., ...}
/// root.getObject('systemProperties'); // {'server.port': '9000', ...}
/// ```
///
/// Spring (Java):
/// ```java
/// BeanExpressionContext root = new BeanExpressionContext(beanFactory, null);
/// Object mailer = root.getObject("mailer");
/// ```
final class BeanExpressionContext {
  /// Exposes the beans of [beanFactory].
  const BeanExpressionContext(this.beanFactory);

  /// Name of the environment-variable map (Spring's
  /// `SYSTEM_ENVIRONMENT_BEAN_NAME`).
  static const systemEnvironmentBeanName = 'systemEnvironment';

  /// Name of the system-property map (Spring's
  /// `SYSTEM_PROPERTIES_BEAN_NAME`).
  static const systemPropertiesBeanName = 'systemProperties';

  /// The factory whose beans are exposed.
  final BeanFactory beanFactory;

  /// Whether a bean named [name] exists (always for `systemEnvironment`
  /// and `systemProperties`).
  bool containsObject(String name) =>
      beanFactory.containsBean(name) ||
      name == systemEnvironmentBeanName ||
      name == systemPropertiesBeanName;

  /// The bean named [name], or `null` when there is none.
  Object? getObject(String name) {
    if (beanFactory.containsBean(name)) {
      return beanFactory.getBeanByName(name);
    }
    return switch (name) {
      systemEnvironmentBeanName => _systemEnvironment(),
      systemPropertiesBeanName => _systemProperties(),
      _ => null,
    };
  }

  ConfigurableEnvironment? get _environment {
    if (beanFactory.containsBean('environment')) {
      final environment = beanFactory.getBeanByName('environment');
      if (environment is ConfigurableEnvironment) {
        return environment;
      }
    }
    return null;
  }

  Map<String, String> _systemEnvironment() =>
      _environment?.systemEnvironment ?? platformEnvironment();

  // The command-line arguments stand in for JVM system properties.
  Map<String, Object?> _systemProperties() {
    final source = _environment?.propertySources.get(
      SimpleCommandLinePropertySource.defaultName,
    );
    if (source is! EnumerablePropertySource) {
      return const {};
    }
    return Map.unmodifiable({
      for (final name in source.propertyNames) name: source.getProperty(name),
    });
  }
}

/// A [PropertyAccessor] that reads the beans of a [BeanExpressionContext]
/// as its properties, so that `#{mailer}` is the bean `mailer`.
///
/// [StandardBeanExpressionResolver] registers it for every `@Value`
/// expression; you need it only to evaluate expressions against a
/// [BeanExpressionContext] in a context of your own. Beans cannot be
/// assigned through it.
///
/// ```dart
/// // `mailer` reads the bean of that name.
/// final context = StandardEvaluationContext(BeanExpressionContext(factory))
///   ..addPropertyAccessor(const BeanExpressionContextAccessor());
/// SpelExpressionParser().parseExpression('mailer').getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// context.addPropertyAccessor(new BeanExpressionContextAccessor());
/// parser.parseExpression("mailer").getValue(context);
/// ```
final class BeanExpressionContextAccessor implements PropertyAccessor {
  /// Creates the accessor (stateless).
  const BeanExpressionContextAccessor();

  @override
  bool canRead(EvaluationContext context, Object target, String name) =>
      target is BeanExpressionContext && target.containsObject(name);

  @override
  Object? read(EvaluationContext context, Object target, String name) =>
      (target as BeanExpressionContext).getObject(name);

  @override
  bool canWrite(EvaluationContext context, Object target, String name) => false;

  @override
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  ) => throw UnsupportedError('Beans cannot be assigned');
}

/// A [PropertyAccessor] that reads beans as properties of a [BeanFactory]
/// itself, for expressions whose value is a bean factory
/// (`factory.mailer`).
///
/// [StandardBeanExpressionResolver] registers it for `@Value`
/// expressions. Beans cannot be assigned through it: writing throws an
/// `AccessException`.
///
/// ```dart
/// // The bean factory is the root: `mailer` is a bean.
/// final context = StandardEvaluationContext(beanFactory)
///   ..addPropertyAccessor(const BeanFactoryAccessor());
/// SpelExpressionParser().parseExpression('mailer').getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// context.addPropertyAccessor(new BeanFactoryAccessor());
/// parser.parseExpression("mailer").getValue(context);
/// ```
final class BeanFactoryAccessor implements PropertyAccessor {
  /// Creates the accessor (stateless).
  const BeanFactoryAccessor();

  @override
  bool canRead(EvaluationContext context, Object target, String name) =>
      target is BeanFactory && target.containsBean(name);

  @override
  Object? read(EvaluationContext context, Object target, String name) =>
      (target as BeanFactory).getBeanByName(name);

  @override
  bool canWrite(EvaluationContext context, Object target, String name) => false;

  @override
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  ) => throw AccessException('Beans in a BeanFactory are read-only');
}

/// A [PropertyAccessor] that reads configuration properties of an
/// `Environment`, so that `environment['app.name']` in an expression is
/// the value of `app.name`.
///
/// [StandardBeanExpressionResolver] registers it, which is what makes
/// `#{environment['app.name']}` work in `@Value` (the `environment` bean
/// being the application's environment). Any name is readable and a
/// missing property is `null`; properties cannot be assigned.
///
/// ```dart
/// // In @Value: '#{environment['app.name'].toUpperCase()}'
/// final context = StandardEvaluationContext({'environment': environment})
///   ..addPropertyAccessor(const EnvironmentAccessor());
/// SpelExpressionParser()
///     .parseExpression("environment['app.name']")
///     .getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// context.addPropertyAccessor(new EnvironmentAccessor());
/// parser.parseExpression("environment['app.name']").getValue(context);
/// ```
final class EnvironmentAccessor implements PropertyAccessor {
  /// Creates the accessor (stateless).
  const EnvironmentAccessor();

  @override
  bool canRead(EvaluationContext context, Object target, String name) =>
      target is Environment;

  @override
  Object? read(EvaluationContext context, Object target, String name) =>
      (target as Environment).getProperty(name);

  @override
  bool canWrite(EvaluationContext context, Object target, String name) => false;

  @override
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  ) => throw UnsupportedError('Environment properties are read-only');
}

/// A [MethodResolver] that lets expressions call the methods of an
/// `Environment` (or any `PropertyResolver`) under their Java names.
///
/// It covers `getProperty(key)` and `getProperty(key, default)`,
/// `getRequiredProperty`, `containsProperty`, `resolvePlaceholders`,
/// `resolveRequiredPlaceholders`, and on an `Environment` also
/// `getActiveProfiles()`, `getDefaultProfiles()` and
/// `matchesProfiles(...)`. Spring calls these by reflection; here
/// [StandardBeanExpressionResolver] registers this resolver for `@Value`
/// expressions.
///
/// ```dart
/// // In @Value:
/// // "#{environment.getProperty('app.timeout', '30')}"
/// // "#{environment.matchesProfiles('dev')}"
/// ```
///
/// Spring (Java):
/// ```java
/// @Value("#{environment.getProperty('app.timeout', '30')}")
/// ```
final class EnvironmentMethodResolver implements MethodResolver {
  /// Creates the resolver (stateless).
  const EnvironmentMethodResolver();

  @override
  MethodExecutor? resolve(
    EvaluationContext context,
    Object target,
    String name,
    List<Object?> arguments,
  ) {
    if (target is! PropertyResolver) {
      return null;
    }
    final function = switch (name) {
      'getProperty' => ([
        String? key,
        String? defaultValue,
      ]) => target.getProperty(key!, defaultValue: defaultValue),
      'getRequiredProperty' => (String key) => target.getRequiredProperty(key),
      'containsProperty' => (String key) => target.containsProperty(key),
      'resolvePlaceholders' => (String text) => target.resolvePlaceholders(
        text,
      ),
      'resolveRequiredPlaceholders' => (
        String text,
      ) => target.resolveRequiredPlaceholders(text),
      'getActiveProfiles' when target is Environment =>
        () => target.activeProfiles,
      'getDefaultProfiles' when target is Environment =>
        () => target.defaultProfiles,
      'matchesProfiles' when target is Environment => VarargsFunction(
        (List<Object?> expressions) =>
            target.matchesProfiles([for (final e in expressions) '$e']),
      ),
      _ => null,
    };
    if (function == null ||
        (name == 'getProperty' && arguments.isEmpty) ||
        !VarargsFunction.accepts(function, arguments.length)) {
      return null;
    }
    return (_, _, args) => SpelTypeMethodResolver.callChecked(
      function,
      args,
      () => SpelEvaluationException(
        SpelMessage.methodNotFound,
        inserts: ['$name(${args.length} arguments)', target.runtimeType],
      ),
    );
  }
}

/// A [BeanResolver] that answers `@name` references with the beans of a
/// [BeanFactory].
///
/// [StandardBeanExpressionResolver] sets one for `@Value` expressions.
/// Set one on your own `StandardEvaluationContext` when expressions you
/// evaluate should reach the application's beans. `&name` resolves the
/// factory bean itself (the `&` is passed on). A failing lookup
/// (`BeansException`) is reported as
/// `SpelMessage.exceptionDuringBeanResolution`.
///
/// ```dart
/// // `@mailer` is the bean named mailer.
/// final context = StandardEvaluationContext()
///   ..beanResolver = BeanFactoryResolver(beanFactory);
/// SpelExpressionParser().parseExpression('@mailer').getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// context.setBeanResolver(new BeanFactoryResolver(beanFactory));
/// parser.parseExpression("@mailer").getValue(context);
/// ```
final class BeanFactoryResolver implements BeanResolver {
  /// Resolves beans from [beanFactory].
  const BeanFactoryResolver(this.beanFactory);

  /// The factory beans are looked up in.
  final BeanFactory beanFactory;

  @override
  Object? resolve(EvaluationContext context, String beanName) {
    try {
      return beanFactory.getBeanByName(beanName);
    } on BeansException catch (error) {
      throw AccessException(
        'Could not resolve bean reference against BeanFactory',
        error,
      );
    }
  }
}

/// Evaluates the `#{...}` parts of `@Value` strings (and of other
/// framework values, such as `@ConditionalOnExpression`) against the
/// beans of a bean factory.
///
/// Every application context installs one, so `@Value('#{mailer.from}')`
/// works without setup; most applications never touch it. Replace or
/// subclass it to give those expressions more: variables, accessors for
/// classes that are not `@Introspected`, or a parser with other limits.
///
/// The text is parsed as a template (placeholders `${...}` have already
/// been resolved by then), and parsed expressions are cached by text. Each
/// bean factory gets one evaluation context, created on first use and
/// kept: its root is a [BeanExpressionContext] (so `#{mailer}` is a bean),
/// with `@bean` references, the `environment` accessor and methods,
/// [BeanFactoryAccessor], the factory's `ConversionService` as type
/// converter, and the extra accessors and resolvers you pass. Override
/// [customizeEvaluationContext] to add variables or functions. The
/// default parser accepts expressions up to 10 000 characters, changed
/// with the compile-time define
/// `-Dspring.context.expression.maxLength=...`, like Spring's property.
///
/// ```dart
/// // `#answer` becomes available in every `@Value` expression.
/// class MyResolver extends StandardBeanExpressionResolver {
///   MyResolver() : super(propertyAccessors: [userAccessor]);
///
///   @override
///   void customizeEvaluationContext(StandardEvaluationContext context) =>
///       context.setVariable('answer', 42);
/// }
///
/// final factory = DefaultListableBeanFactory()
///   ..beanExpressionResolver = MyResolver();
/// factory.value<int>('#{#answer + 1}'); // 43
/// ```
///
/// Spring (Java):
/// ```java
/// beanFactory.setBeanExpressionResolver(
///     new StandardBeanExpressionResolver(classLoader) {
///       @Override
///       protected void customizeEvaluationContext(
///           StandardEvaluationContext context) {
///         context.setVariable("answer", 42);
///       }
///     });
/// ```
class StandardBeanExpressionResolver implements BeanExpressionResolver {
  /// Creates a resolver using [parser] (a [SpelExpressionParser] limited to
  /// [maxExpressionLength] characters by default) and [parserContext];
  /// [propertyAccessors] and [methodResolvers] are added to every
  /// evaluation context, before the built-in ones. An application context
  /// passes the accessor and resolver of its own introspector.
  StandardBeanExpressionResolver({
    ExpressionParser? parser,
    this.parserContext = ParserContext.template,
    List<PropertyAccessor> propertyAccessors = const [],
    List<MethodResolver> methodResolvers = const [],
  }) : parser =
           parser ??
           SpelExpressionParser(
             SpelParserConfiguration.builder()
                 .maximumExpressionLength(maxExpressionLength())
                 .build(),
           ),
       _accessors = List.unmodifiable(propertyAccessors),
       _resolvers = List.unmodifiable(methodResolvers);

  /// The name of the compile-time define that sets the longest `@Value`
  /// expression (`dart run -Dspring.context.expression.maxLength=20000`;
  /// Spring's `MAX_SPEL_EXPRESSION_LENGTH_PROPERTY_NAME`).
  static const maxSpelExpressionLengthPropertyName =
      'spring.context.expression.maxLength';

  static const _maxLengthProperty = String.fromEnvironment(
    maxSpelExpressionLengthPropertyName,
  );

  /// The longest expression the default parser accepts: the value of
  /// `-Dspring.context.expression.maxLength`, or
  /// `SpelParserConfiguration.defaultMaxExpressionLength` (10 000) when it
  /// is not defined.
  ///
  /// Throws an [ArgumentError] when the define is not a positive integer.
  static int maxExpressionLength() {
    final value = _maxLengthProperty.trim();
    if (value.isEmpty) {
      return SpelParserConfiguration.defaultMaxExpressionLength;
    }
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      throw ArgumentError.value(
        value,
        maxSpelExpressionLengthPropertyName,
        'Must be a positive integer',
      );
    }
    return parsed;
  }

  /// The parser for `@Value` strings.
  final ExpressionParser parser;

  /// How strings are parsed: templates with `#{...}` by default, so text
  /// around the expressions is kept.
  final ParserContext parserContext;
  final List<PropertyAccessor> _accessors;
  final List<MethodResolver> _resolvers;
  final _cache = <String, Expression>{};
  final _contexts = Expando<StandardEvaluationContext>();

  /// Called once for the evaluation context of each bean factory, after
  /// the built-in setup and before its first evaluation.
  ///
  /// Override it in a subclass to add variables, functions or accessors
  /// that every expression should see. Does nothing by default.
  void customizeEvaluationContext(StandardEvaluationContext context) {}

  @override
  Object? evaluate(String value, BeanFactory beanFactory) {
    final expression = _cache.putIfAbsent(
      value,
      () => parser.parseExpression(value, parserContext),
    );
    return expression.getValue(
      _contexts[beanFactory] ??= _newContext(beanFactory),
    );
  }

  StandardEvaluationContext _newContext(BeanFactory beanFactory) {
    final context = StandardEvaluationContext(
      BeanExpressionContext(beanFactory),
    )..beanResolver = BeanFactoryResolver(beanFactory);
    if (beanFactory is ConfigurableBeanFactory) {
      // Looked up at each conversion: the factory's service may change.
      context.typeConverter = StandardTypeConverter.lazy(
        () => beanFactory.conversionService,
      );
    }
    [
      ..._accessors,
      const BeanExpressionContextAccessor(),
      const BeanFactoryAccessor(),
      const EnvironmentAccessor(),
    ].forEach(context.addPropertyAccessor);
    [
      ..._resolvers,
      const EnvironmentMethodResolver(),
    ].forEach(context.addMethodResolver);
    customizeEvaluationContext(context);
    return context;
  }
}
