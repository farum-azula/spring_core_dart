import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/expression/evaluation_context.dart';

/// Reads and writes properties of `@Introspected` objects in SpEL, the
/// counterpart of Spring's reflective property accessor.
///
/// Property metadata comes from generated [BeanIntrospection]s instead of
/// reflection. Written values are converted to the property type with the
/// context's type converter. Application contexts register it for
/// `@Value('#{...}')` automatically.
///
/// ```dart
/// final context = StandardEvaluationContext(person)
///   ..addPropertyAccessor(
///     IntrospectionPropertyAccessor(BeanIntrospector.shared),
///   );
/// final parser = SpelExpressionParser();
/// parser.parseExpression('address.city').getValue(context);
/// parser.parseExpression('age').setValue(context, null, '7'); // age = 7
/// ```
///
/// Spring (Java):
/// ```java
/// // ReflectivePropertyAccessor is registered by default:
/// StandardEvaluationContext context = new StandardEvaluationContext(person);
/// parser.parseExpression("address.city").getValue(context);
/// parser.parseExpression("age").setValue(context, "7");
/// ```
final class IntrospectionPropertyAccessor implements PropertyAccessor {
  /// Looks up introspections of targets in [introspector].
  const IntrospectionPropertyAccessor(this.introspector);

  /// The registry of generated introspections.
  final BeanIntrospector introspector;

  BeanProperty<Object>? _property(Object target, String name) =>
      introspector.findIntrospection(target)?.getProperty(name);

  @override
  bool canRead(EvaluationContext context, Object target, String name) =>
      _property(target, name) != null;

  @override
  Object? read(EvaluationContext context, Object target, String name) =>
      _property(target, name)!.getValue(target);

  @override
  bool canWrite(EvaluationContext context, Object target, String name) =>
      _property(target, name)?.isWritable ?? false;

  @override
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  ) {
    final property = _property(target, name)!;
    final value = newValue == null
        ? null
        : context.typeConverter.convertValue(newValue, property.type);
    property.setValue(target, value);
  }
}

/// Calls methods of `@Introspected` objects in SpEL; arguments are
/// converted to the parameter types.
///
/// A method matches by name when it declares at least as many parameters
/// as there are arguments.
///
/// ```dart
/// final context = StandardEvaluationContext(person)
///   ..addMethodResolver(
///     IntrospectionMethodResolver(BeanIntrospector.shared),
///   );
/// SpelExpressionParser()
///     .parseExpression("hello('Bob')")
///     .getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// // ReflectiveMethodResolver is registered by default:
/// parser.parseExpression("hello('Bob')").getValue(context);
/// ```
final class IntrospectionMethodResolver implements MethodResolver {
  /// Looks up introspections of targets in [introspector].
  const IntrospectionMethodResolver(this.introspector);

  /// The registry of generated introspections.
  final BeanIntrospector introspector;

  @override
  MethodExecutor? resolve(
    EvaluationContext context,
    Object target,
    String name,
    List<Object?> arguments,
  ) {
    final method = introspector.findIntrospection(target)?.getMethod(name);
    if (method == null || method.parameterTypes.length < arguments.length) {
      return null;
    }
    return (context, target, args) => method.invoke(target, [
      for (var i = 0; i < args.length; i++)
        args[i] == null
            ? null
            : context.typeConverter.convertValue(
                args[i],
                method.parameterTypes[i],
              ),
    ]);
  }
}
