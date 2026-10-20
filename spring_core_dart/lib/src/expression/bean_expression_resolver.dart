import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/expression/evaluation_context.dart';
import 'package:spring_core_dart/src/expression/expression.dart';
import 'package:spring_core_dart/src/expression/spel_parser.dart';

/// The root object of `@Value('#{...}')` expressions: bean names are its
/// properties, like Spring's `BeanExpressionContext`.
///
/// Together with [BeanExpressionContextAccessor] this makes `#{mailer}`
/// evaluate to the bean named `mailer`.
///
/// ```dart
/// final root = BeanExpressionContext(beanFactory);
/// root.containsObject('mailer'); // true when the bean exists
/// root.getObject('mailer'); // the bean, or null
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

  /// The factory whose beans are exposed.
  final BeanFactory beanFactory;

  /// Whether a bean named [name] exists.
  bool containsObject(String name) => beanFactory.containsBean(name);

  /// The bean named [name], or `null` when there is none.
  Object? getObject(String name) =>
      containsObject(name) ? beanFactory.getBeanByName(name) : null;
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

/// Resolves `@beanName` through a [BeanFactory], like Spring's
/// `BeanFactoryResolver`.
///
/// `&name` resolves the factory bean itself (the `&` is passed on).
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
  Object? resolve(EvaluationContext context, String beanName) =>
      beanFactory.getBeanByName(beanName);
}

/// Evaluates `#{...}` in `@Value`, like Spring's
/// `StandardBeanExpressionResolver`. Parsed expressions are cached.
///
/// Each evaluation gets a fresh [StandardEvaluationContext] whose root is
/// a [BeanExpressionContext] (so `#{mailer}` is a bean), with `@bean`
/// references, the `environment` accessor, and your extra accessors and
/// resolvers. Override [customizeEvaluationContext] to add variables.
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
  /// Creates a resolver using [parser] (a [SpelExpressionParser] by
  /// default) and [parserContext]; [propertyAccessors] and
  /// [methodResolvers] are added to every evaluation context.
  StandardBeanExpressionResolver({
    ExpressionParser? parser,
    this.parserContext = ParserContext.template,
    List<PropertyAccessor> propertyAccessors = const [],
    List<MethodResolver> methodResolvers = const [],
  }) : parser = parser ?? SpelExpressionParser(),
       _accessors = List.unmodifiable(propertyAccessors),
       _resolvers = List.unmodifiable(methodResolvers);

  /// The parser for `@Value` strings.
  final ExpressionParser parser;

  /// How strings are parsed; templates (`#{...}`) by default.
  final ParserContext parserContext;
  final List<PropertyAccessor> _accessors;
  final List<MethodResolver> _resolvers;
  final _cache = <String, Expression>{};

  /// Called for each new evaluation context (add variables, accessors...).
  ///
  /// Does nothing by default; override in a subclass.
  void customizeEvaluationContext(StandardEvaluationContext context) {}

  @override
  Object? evaluate(String value, BeanFactory beanFactory) {
    final expression = _cache.putIfAbsent(
      value,
      () => parser.parseExpression(value, parserContext),
    );
    final context = StandardEvaluationContext(
      BeanExpressionContext(beanFactory),
    )..beanResolver = BeanFactoryResolver(beanFactory);
    for (final accessor in [
      ..._accessors,
      const BeanExpressionContextAccessor(),
      const EnvironmentAccessor(),
    ]) {
      context.addPropertyAccessor(accessor);
    }
    _resolvers.forEach(context.addMethodResolver);
    customizeEvaluationContext(context);
    return expression.getValue(context);
  }
}
