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

/// The root object of `@Value('#{...}')` expressions: bean names are its
/// properties, like Spring's `BeanExpressionContext`.
///
/// Together with [BeanExpressionContextAccessor] this makes `#{mailer}`
/// evaluate to the bean named `mailer`. Like in a Spring application
/// context, `systemEnvironment` is the map of environment variables (of
/// the `environment` bean when there is one), unless beans with these
/// names exist. Dart has no JVM system properties, so `systemProperties`
/// is the map of `--key=value` command-line arguments (the
/// `commandLineArgs` property source of the `environment` bean), which
/// play the part of `-Dkey=value`; compile-time `-D` defines are constants
/// and cannot be enumerated.
///
/// ```dart
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

/// Reads beans as properties of a [BeanExpressionContext], like Spring's
/// `BeanExpressionContextAccessor`.
///
/// Read-only; registered by [StandardBeanExpressionResolver].
///
/// ```dart
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

/// Reads beans as properties of a [BeanFactory] (`factory.mailer`), like
/// Spring's `BeanFactoryAccessor`.
///
/// Read-only; registered by [StandardBeanExpressionResolver].
///
/// ```dart
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

/// Reads environment properties (`environment['app.name']`), like
/// Spring's `EnvironmentAccessor`.
///
/// Any property name is readable; missing ones evaluate to `null`.
/// Read-only; registered by [StandardBeanExpressionResolver].
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

/// The methods of an `Environment` (or any `PropertyResolver`) in SpEL:
/// `environment.getProperty('app.name')`, `getProperty(key, default)`,
/// `getRequiredProperty`, `containsProperty`, `resolvePlaceholders`,
/// `getActiveProfiles()`, `matchesProfiles(...)`.
///
/// Spring calls these reflectively; registered by
/// [StandardBeanExpressionResolver].
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
    final Object? function = switch (name) {
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

/// Resolves `@beanName` through a [BeanFactory], like Spring's
/// `BeanFactoryResolver`.
///
/// `&name` resolves the factory bean itself (the `&` is passed on). A
/// failing lookup (`BeansException`) is reported as
/// `SpelMessage.exceptionDuringBeanResolution`.
///
/// ```dart
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

/// Evaluates `#{...}` in `@Value`, like Spring's
/// `StandardBeanExpressionResolver`. Parsed expressions are cached, and so
/// is the evaluation context of each bean factory.
///
/// The evaluation context's root is a [BeanExpressionContext] (so
/// `#{mailer}` is a bean), with `@bean` references, the `environment`
/// accessor and methods, [BeanFactoryAccessor], the factory's
/// `ConversionService` as type converter, and your extra accessors and
/// resolvers. Override [customizeEvaluationContext] to add variables. The
/// default parser accepts expressions up to 10 000 characters, changed
/// with the compile-time define
/// `-Dspring.context.expression.maxLength=...`, like Spring's property.
///
/// ```dart
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
  /// evaluation context.
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

  /// Compile-time define for the longest `@Value` expression (Spring's
  /// `MAX_SPEL_EXPRESSION_LENGTH_PROPERTY_NAME`).
  static const maxSpelExpressionLengthPropertyName =
      'spring.context.expression.maxLength';

  static const _maxLengthProperty = String.fromEnvironment(
    maxSpelExpressionLengthPropertyName,
  );

  /// The longest expression the default parser accepts:
  /// `-Dspring.context.expression.maxLength` or
  /// `SpelParserConfiguration.defaultMaxExpressionLength`.
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

  /// How strings are parsed; templates (`#{...}`) by default.
  final ParserContext parserContext;
  final List<PropertyAccessor> _accessors;
  final List<MethodResolver> _resolvers;
  final _cache = <String, Expression>{};
  final _contexts = Expando<StandardEvaluationContext>();

  /// Called once for each new evaluation context (add variables,
  /// accessors...).
  ///
  /// Does nothing by default; override in a subclass.
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
    for (final accessor in [
      ..._accessors,
      const BeanExpressionContextAccessor(),
      const BeanFactoryAccessor(),
      const EnvironmentAccessor(),
    ]) {
      context.addPropertyAccessor(accessor);
    }
    for (final resolver in [..._resolvers, const EnvironmentMethodResolver()]) {
      context.addMethodResolver(resolver);
    }
    customizeEvaluationContext(context);
    return context;
  }
}
