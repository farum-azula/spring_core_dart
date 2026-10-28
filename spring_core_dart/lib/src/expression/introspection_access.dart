import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/type_info.dart';
import 'package:spring_core_dart/src/expression/evaluation_context.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/spel_type.dart';

/// A [PropertyAccessor] that reads and writes the properties of
/// `@Introspected` classes, using the metadata the code generator wrote
/// for them.
///
/// It is how expressions see your own classes without reflection: the
/// generator describes each `@Introspected` class in a
/// [BeanIntrospection], registered in a [BeanIntrospector]. Both contexts
/// already have one over `BeanIntrospector.shared`, and an application
/// context adds one over its own introspector for `@Value('#{...}')`.
/// Create one yourself only for another introspector. A written value
/// that is not of the property type is converted with the context's type
/// converter when it can be; others (an `English` for a `Greeter`
/// property) are passed as they are.
///
/// ```dart
/// // A Person described by the introspector of a plugin, not the shared
/// // one: `address.city` is read and `age` set from a string.
/// final context = StandardEvaluationContext(person)
///   ..addPropertyAccessor(IntrospectionPropertyAccessor(pluginIntrospector));
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
  /// Reads the classes described in [introspector].
  const IntrospectionPropertyAccessor(this.introspector);

  /// The registry the descriptions of the targets' classes come from.
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
    property.setValue(
      target,
      _convert(context, newValue, property.type, property.typeInfo),
    );
  }

  /// A new, empty value for property [name] of [target]: an empty list,
  /// set or map of the declared element types, or an instance of an
  /// introspected class with a no-argument constructor; `null` when the
  /// type is not known well enough.
  ///
  /// The evaluator calls it when
  /// `SpelParserConfiguration.autoGrowNullReferences` is on and a path
  /// such as `order.lines[0]` meets a `null` property.
  ///
  /// ```dart
  /// accessor.newValue(order, 'lines'); // <OrderLine>[]
  /// ```
  Object? newValue(Object target, String name) {
    final property = _property(target, name);
    if (property == null) {
      return null;
    }
    final typeInfo = property.typeInfo;
    if (typeInfo != null) {
      return typeInfo.accept(_NewValue(introspector));
    }
    final introspection = introspector.forType(property.type);
    return introspection != null && introspection.isInstantiable
        ? introspection.instantiate()
        : null;
  }
}

/// A [MethodResolver] that calls the methods of `@Introspected` classes,
/// using the metadata the code generator wrote for them.
///
/// Like [IntrospectionPropertyAccessor], it replaces Java's reflection: a
/// `StandardEvaluationContext` has one over `BeanIntrospector.shared`, a
/// `SimpleEvaluationContext` after `withInstanceMethods()`, and an
/// application context adds one over its own introspector for
/// `@Value('#{...}')`.
///
/// A method matches by name when it declares at least as many parameters
/// as there are arguments. Arguments that are not already of the
/// parameter type are converted with the context's type converter when it
/// can, and passed as they are otherwise, so a subtype is accepted
/// (`#{greeter.greet(@english)}` with a `Greeter` parameter). Arguments
/// that still do not fit (a `TypeError`) are reported as
/// `SpelMessage.methodNotFound`; other exceptions of the method propagate
/// unchanged, like Spring.
///
/// ```dart
/// // hello('Bob') on a Person described by a plugin's introspector.
/// final context = StandardEvaluationContext(person)
///   ..addMethodResolver(IntrospectionMethodResolver(pluginIntrospector));
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
  /// Calls the methods of the classes described in [introspector].
  const IntrospectionMethodResolver(this.introspector);

  /// The registry the descriptions of the targets' classes come from.
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
    return (context, target, args) {
      final converted = [
        for (var i = 0; i < args.length; i++)
          _convert(context, args[i], method.parameterTypes[i], null),
      ];
      return SpelTypeMethodResolver.callChecked(
        (Object? bean, List<Object?> values) => method.invoke(bean!, values),
        [target, converted],
        () => SpelEvaluationException(
          SpelMessage.methodNotFound,
          inserts: [
            // A string that cannot be split without changing it.
            // ignore: lines_longer_than_80_chars
            '$name(${args.map((a) => a == null ? 'null' : a.runtimeType).join(',')})',
            target.runtimeType,
          ],
        ),
      );
    };
  }
}

// [value] for a property or parameter of [type]: unchanged when it already
// fits (or nothing can convert it, e.g. a subtype of an interface the
// conversion service does not know), converted otherwise.
Object? _convert(
  EvaluationContext context,
  Object? value,
  Type type,
  TypeInfo<Object?>? typeInfo,
) {
  if (value == null ||
      value.runtimeType == type ||
      (typeInfo?.isInstance(value) ?? false)) {
    return value;
  }
  final converter = context.typeConverter;
  return converter.canConvert(value, type)
      ? converter.convertValue(value, type)
      : value;
}

// Creates an empty value of a described type, for auto-grow.
final class _NewValue implements TypeInfoVisitor<Object?> {
  const _NewValue(this.introspector);

  final BeanIntrospector introspector;

  @override
  Object? visitClass<T>(ClassType<T> type) {
    final introspection = introspector.forTypeArgument<T>();
    return introspection != null && introspection.isInstantiable
        ? introspection.instantiate()
        : null;
  }

  @override
  Object? visitList<E>(ListType<E> type) => <E>[];

  @override
  Object? visitSet<E>(SetType<E> type) => <E>{};

  @override
  Object? visitMap<K, V>(MapType<K, V> type) => <K, V>{};

  @override
  Object? visitEnum<E extends Enum>(EnumType<E> type) => null;

  @override
  Object? visitGeneric<T>(GenericType<T> type) => null;

  @override
  Object? visitDynamic(DynamicType type) => null;
}
