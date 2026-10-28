import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';
import 'package:spring_core_dart/src/expression/builtins.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/introspection_access.dart';
import 'package:spring_core_dart/src/expression/spel_type.dart';

/// A plug-in that tells expressions how to read and write the properties
/// of some kind of object, so that `point.x` works.
///
/// Java's SpEL reads any public getter by reflection; Dart (in Flutter and
/// AOT builds) has no reflection, so an expression can only see a
/// property some accessor knows. The contexts already bring accessors for
/// maps ([MapAccessor]), `@Introspected` classes
/// (`IntrospectionPropertyAccessor`) and core Dart types
/// (`BuiltinPropertyAccessor`). For a class that is not `@Introspected`,
/// a [FunctionPropertyAccessor] is usually enough; implement this
/// interface for anything more dynamic (a JSON document, a record from a
/// database). For each property the context asks its accessors in order
/// and the first whose [canRead] (or [canWrite]) returns `true` handles
/// it.
///
/// ```dart
/// // A Point class from another package, without introspection data.
/// final class PointAccessor implements PropertyAccessor {
///   @override
///   bool canRead(EvaluationContext c, Object target, String name) =>
///       target is Point && (name == 'x' || name == 'y');
///
///   @override
///   Object? read(EvaluationContext c, Object target, String name) =>
///       name == 'x' ? (target as Point).x : (target as Point).y;
///
///   @override
///   bool canWrite(EvaluationContext c, Object target, String name) =>
///       false;
///
///   @override
///   void write(EvaluationContext c, Object t, String n, Object? v) =>
///       throw UnsupportedError('read-only');
/// }
///
/// final context = StandardEvaluationContext(const Point(1, 2))
///   ..addPropertyAccessor(PointAccessor());
/// ```
///
/// Spring (Java):
/// ```java
/// public class PointAccessor implements PropertyAccessor {
///   public Class<?>[] getSpecificTargetClasses() {
///     return new Class<?>[] {Point.class};
///   }
///   public boolean canRead(EvaluationContext c, Object t, String name) {
///     return name.equals("x") || name.equals("y");
///   }
///   public TypedValue read(EvaluationContext c, Object t, String name) {
///     Point p = (Point) t;
///     return new TypedValue(name.equals("x") ? p.x : p.y);
///   }
///   // canWrite / write ...
/// }
/// context.addPropertyAccessor(new PointAccessor());
/// ```
abstract interface class PropertyAccessor {
  /// Whether this accessor handles reading property [name] of [target];
  /// `false` lets the next accessor try. [target] is never `null`.
  bool canRead(EvaluationContext context, Object target, String name);

  /// The value of property [name] of [target]; only called after
  /// [canRead] returned `true`.
  ///
  /// An exception other than a `SpelEvaluationException` is reported as
  /// `exceptionDuringPropertyRead` (EL1021E) with the error as cause.
  Object? read(EvaluationContext context, Object target, String name);

  /// Whether this accessor handles writing property [name] of [target];
  /// return `false` for read-only properties.
  bool canWrite(EvaluationContext context, Object target, String name);

  /// Stores [newValue] in property [name] of [target]; only called after
  /// [canWrite] returned `true`.
  ///
  /// An exception other than a `SpelEvaluationException` is reported as
  /// `exceptionDuringPropertyWrite` (EL1034E).
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  );
}

/// The function a [MethodResolver] returns to run one method call: it
/// gets the target and the evaluated arguments and returns the result.
///
/// Throw an `AccessException` to report a failure as
/// `exceptionDuringMethodInvocation` (EL1029E); any other exception
/// reaches the caller of `getValue` unchanged.
///
/// ```dart
/// // Runs `text.padLeft(n)` for an expression `text.padLeft(8)`.
/// MethodExecutor executor = (context, target, args) =>
///     (target as String).padLeft(args.first! as int);
/// ```
///
/// Spring (Java):
/// ```java
/// TypedValue result = executor.execute(context, target, arguments);
/// ```
typedef MethodExecutor = Object? Function(
  EvaluationContext context,
  Object target,
  List<Object?> arguments,
);

/// A plug-in that tells expressions which code to run for a method call
/// such as `greeter.greet('Ada')`.
///
/// Without reflection an expression can only call methods some resolver
/// knows. The contexts bring resolvers for `@Introspected` classes
/// (`IntrospectionMethodResolver`) and core Dart types
/// (`BuiltinMethodResolver`); for other classes a `FunctionMethodResolver`
/// is usually enough. Implement this interface when the methods are only
/// known at run time. For each call the context asks its resolvers in
/// order and runs the first [MethodExecutor] returned; when none matches,
/// the call fails with `methodNotFound` (EL1004E).
///
/// ```dart
/// // Lets rules call greet(...) on a Greeter from another package.
/// final class GreeterResolver implements MethodResolver {
///   @override
///   MethodExecutor? resolve(EvaluationContext context, Object target,
///           String name, List<Object?> arguments) =>
///       target is Greeter && name == 'greet'
///           ? (_, t, args) => (t as Greeter).greet(args.first! as String)
///           : null;
/// }
///
/// final context = StandardEvaluationContext(Greeter())
///   ..addMethodResolver(GreeterResolver());
/// SpelExpressionParser()
///     .parseExpression("greet('Ada')")
///     .getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring's ReflectiveMethodResolver finds greet(String) by reflection.
/// context.addMethodResolver(new MyMethodResolver());
/// parser.parseExpression("greet('Ada')").getValue(context);
/// ```
abstract interface class MethodResolver {
  /// An executor that runs method [name] on [target] with [arguments]
  /// (already evaluated), or `null` to let the next resolver try.
  ///
  /// Throwing an `AccessException` here is reported as
  /// `problemLocatingMethod` (EL1031E).
  MethodExecutor? resolve(
    EvaluationContext context,
    Object target,
    String name,
    List<Object?> arguments,
  );
}

/// The function a [ConstructorResolver] returns to run one `new Name(...)`:
/// it gets the evaluated arguments and returns the new object.
///
/// Throw an `AccessException` to report a failure as
/// `constructorInvocationProblem` (EL1003E); any other exception reaches
/// the caller unchanged.
///
/// ```dart
/// // Builds the Point of `new Point(1, 2)`.
/// ConstructorExecutor executor = (context, args) =>
///     Point(args[0]! as int, args[1]! as int);
/// ```
///
/// Spring (Java):
/// ```java
/// TypedValue point = executor.execute(context, 1, 2);
/// ```
typedef ConstructorExecutor = Object? Function(
  EvaluationContext context,
  List<Object?> arguments,
);

/// A plug-in that tells expressions how to create an object for
/// `new Name(...)`.
///
/// Usually not needed: a `StandardEvaluationContext` already runs the
/// constructors registered on a `SpelType` (through
/// `SpelTypeConstructorResolver`), so registering the type is enough.
/// Implement this interface to create objects of types that are not
/// registered, and add it with
/// `StandardEvaluationContext.addConstructorResolver`. A
/// `SimpleEvaluationContext` has no constructor resolvers, so `new`
/// always fails there.
///
/// ```dart
/// // Creates points without registering a Point type.
/// final class PointResolver implements ConstructorResolver {
///   @override
///   ConstructorExecutor? resolve(EvaluationContext context,
///           String typeName, List<Object?> arguments) =>
///       typeName == 'Point' && arguments.length == 2
///           ? (_, args) => Point(args[0]! as int, args[1]! as int)
///           : null;
/// }
///
/// final context = StandardEvaluationContext()
///   ..addConstructorResolver(PointResolver());
/// SpelExpressionParser().parseExpression('new Point(1, 2)')
///     .getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// context.addConstructorResolver(new PointResolver());
/// parser.parseExpression("new Point(1, 2)").getValue(context);
/// ```
abstract interface class ConstructorResolver {
  /// An executor that creates a [typeName] (the name as written after
  /// `new`, dots included) from [arguments], or `null` to let the next
  /// resolver try. When no resolver matches, the call fails with
  /// `constructorNotFound` (EL1002E).
  ///
  /// Throwing an `AccessException` is reported as
  /// `SpelMessage.constructorInvocationProblem`.
  ConstructorExecutor? resolve(
    EvaluationContext context,
    String typeName,
    List<Object?> arguments,
  );
}

/// A plug-in that makes `target[index]` work for your own indexable types.
///
/// Lists, maps and strings are indexed without any accessor. For any
/// other target the context's index accessors are asked in order before
/// the fallbacks (other iterables by position, then `obj['name']` as a
/// property read). Implement it for a type that has its own notion of
/// "element at", such as a matrix row or a sparse vector. Spring added
/// the same interface in 6.2.
///
/// ```dart
/// // `#root[1]` reads row 1 of a Matrix.
/// final class MatrixRowAccessor implements IndexAccessor {
///   @override
///   bool canRead(EvaluationContext c, Object target, Object? index) =>
///       target is Matrix && index is int;
///
///   @override
///   Object? read(EvaluationContext c, Object target, Object? index) =>
///       (target as Matrix).row(index! as int);
///
///   @override
///   bool canWrite(EvaluationContext c, Object t, Object? i) => false;
///
///   @override
///   void write(EvaluationContext c, Object t, Object? i, Object? v) {}
/// }
///
/// final context = StandardEvaluationContext(matrix)
///   ..addIndexAccessor(MatrixRowAccessor());
/// SpelExpressionParser().parseExpression('#root[1]').getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// StandardEvaluationContext context = new StandardEvaluationContext(matrix);
/// context.addIndexAccessor(new MatrixRowAccessor());
/// ```
abstract interface class IndexAccessor {
  /// Whether this accessor handles reading [index] (the evaluated index
  /// value) of [target]. An accessor that answers `true` to [canRead] or
  /// [canWrite] takes over the index for both reads and writes.
  bool canRead(EvaluationContext context, Object target, Object? index);

  /// The element at [index] of [target]; only called after [canRead]
  /// returned `true`. Other exceptions than a `SpelEvaluationException`
  /// are reported as `exceptionDuringIndexRead` (EL1083E).
  Object? read(EvaluationContext context, Object target, Object? index);

  /// Whether this accessor handles writing [index] of [target].
  bool canWrite(EvaluationContext context, Object target, Object? index);

  /// Stores [newValue] at [index] of [target]; only called after
  /// [canWrite] returned `true`. Other exceptions than a
  /// `SpelEvaluationException` are reported as `exceptionDuringIndexWrite`
  /// (EL1084E).
  void write(
    EvaluationContext context,
    Object target,
    Object? index,
    Object? newValue,
  );
}

/// Finds the type a name stands for in `T(Name)`, `new Name(...)` and
/// `instanceof T(Name)`.
///
/// Java's SpEL loads any class by name. Dart cannot, so the types an
/// expression may use are registered beforehand as [SpelType]s. The usual
/// locator is [StandardTypeLocator], which already knows the core types;
/// register your own types on it. Implement this interface only to look
/// types up somewhere else.
///
/// ```dart
/// // Lets expressions create points with `new Point(1, 2)`.
/// final context = StandardEvaluationContext()
///   ..typeLocator = (StandardTypeLocator()
///     ..registerType(SpelType.of<Point>('Point',
///         constructors: {'': Point.new})));
/// SpelExpressionParser()
///     .parseExpression('new Point(1, 2)')
///     .getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// StandardEvaluationContext context = new StandardEvaluationContext();
/// context.setTypeLocator(
///     new StandardTypeLocator(getClass().getClassLoader()));
/// parser.parseExpression("new com.example.Point(1, 2)").getValue(context);
/// ```
abstract interface class TypeLocator {
  /// The type registered as [typeName], the name as written in the
  /// expression (dots included).
  ///
  /// Throws a `SpelEvaluationException` (`typeNotFound`) when unknown.
  SpelType findType(String typeName);
}

/// Converts a value to another type while an expression is evaluated.
///
/// Expressions need conversions in several places: `Expression.getValueAs`
/// returns the type the caller asked for, a condition must become a
/// `bool`, template parts and the other side of `'text' + x` become
/// strings, a list index such as `'2'` becomes an `int`, and arguments of
/// methods and setters are adapted to the parameter types. The default,
/// [StandardTypeConverter], delegates to a `ConversionService`; replace
/// it to share the conversions of your application (a bean factory does
/// that for `@Value`).
///
/// ```dart
/// final converter = StandardTypeConverter();
/// converter.canConvert('42', int); // true
/// converter.convertValue('42', int); // 42
/// ```
///
/// Spring (Java):
/// ```java
/// TypeConverter converter = new StandardTypeConverter();
/// Object value = converter.convertValue("42",
///     TypeDescriptor.valueOf(String.class),
///     TypeDescriptor.valueOf(Integer.class));
/// ```
abstract interface class TypeConverter {
  /// Whether [value] can be converted to [targetType]; callers check it
  /// before [convertValue] where a failed conversion is not an error.
  bool canConvert(Object? value, Type targetType);

  /// [value] converted to [targetType].
  ///
  /// Throws a `SpelEvaluationException` (`typeConversionError`) on
  /// failure.
  Object? convertValue(Object? value, Type targetType);
}

/// Decides how two values are ordered for `<`, `<=`, `>`, `>=` and
/// `between`.
///
/// The default, [StandardTypeComparator], orders numbers, strings, dates,
/// durations, booleans, enums and other `Comparable`s. Replace it in a
/// `StandardEvaluationContext` when expressions must compare values of
/// your own type that the default does not order the way you need, such
/// as version numbers kept as strings.
///
/// ```dart
/// // `#a < #b` compares two versions by their numeric parts.
/// final context = StandardEvaluationContext()
///   ..typeComparator = const VersionComparator();
/// SpelExpressionParser()
///     .parseExpression('#a < #b')
///     .getValue(context..setVariable('a', v1)..setVariable('b', v2));
/// ```
///
/// Spring (Java):
/// ```java
/// StandardEvaluationContext context = new StandardEvaluationContext();
/// context.setTypeComparator(new VersionComparator());
/// ```
abstract interface class TypeComparator {
  /// Whether [left] and [right] can be ordered; when `false` the operator
  /// fails with `notComparable` (EL1013E) without calling [compare].
  bool canCompare(Object? left, Object? right);

  /// Negative, zero or positive as [left] is less than, equal to or
  /// greater than [right].
  int compare(Object? left, Object? right);
}

/// The arithmetic operators an [OperatorOverloader] can take over.
///
/// The evaluator passes one to the overloader when an operator meets
/// operands it has no built-in rule for. Unary `-x` and `+x` arrive as
/// [subtract] and [add] with a `null` right operand; `x++` and `x--` as
/// [add] and [subtract] with `1`.
///
/// ```dart
/// // Asks whether `left + right` is handled.
/// overloader.overridesOperation(Operation.add, left, right);
/// ```
///
/// Spring (Java):
/// ```java
/// overloader.overridesOperation(Operation.ADD, left, right);
/// ```
enum Operation {
  /// `+`
  add,

  /// `-`
  subtract,

  /// `*`
  multiply,

  /// `/` or `div`
  divide,

  /// `%` or `mod`
  modulus,

  /// `^`
  power,
}

/// A plug-in that gives arithmetic operators a meaning for your own types,
/// such as `+` on two money amounts.
///
/// The evaluator asks it only after its built-in rules (numbers, string
/// concatenation, `'text' * n`, `'d' - 3`) did not apply; without it such
/// an expression fails with `operatorNotSupportedBetweenTypes`
/// (EL1030E). Set it on a `StandardEvaluationContext`; the default,
/// [StandardOperatorOverloader], handles nothing.
///
/// ```dart
/// // `{1} + {2}` concatenates lists.
/// final class ListConcat implements OperatorOverloader {
///   @override
///   bool overridesOperation(Operation op, Object? l, Object? r) =>
///       op == Operation.add && l is List && r is List;
///
///   @override
///   Object? operate(Operation op, Object? l, Object? r) =>
///       [...l! as List, ...r! as List];
/// }
///
/// final context = StandardEvaluationContext()
///   ..operatorOverloader = ListConcat();
/// SpelExpressionParser().parseExpression('{1} + {2}').getValue(context);
/// // [1, 2]
/// ```
///
/// Spring (Java):
/// ```java
/// StandardEvaluationContext context = new StandardEvaluationContext();
/// context.setOperatorOverloader(new ListConcatOverloader());
/// ```
abstract interface class OperatorOverloader {
  /// Whether this overloader handles [operation] for [left] and [right].
  bool overridesOperation(Operation operation, Object? left, Object? right);

  /// Performs [operation]; only called after [overridesOperation]
  /// returned `true`.
  Object? operate(Operation operation, Object? left, Object? right);
}

/// Looks up the object an `@name` (or `&name`) reference stands for.
///
/// Bean references let an expression use a named object of the
/// application, such as `@mailer.defaultSender`. In `@Value('#{...}')`
/// the framework sets a `BeanFactoryResolver` for you. Set one on a
/// `StandardEvaluationContext` yourself when your own expressions should
/// see beans, or implement this interface to serve names from any
/// registry. Without a resolver, `@name` fails with
/// `noBeanResolverRegistered` (EL1057E); a `SimpleEvaluationContext`
/// never has one.
///
/// ```dart
/// // Named objects from a map, for tests or a small rule engine.
/// final class MapBeanResolver implements BeanResolver {
///   MapBeanResolver(this.beans);
///   final Map<String, Object> beans;
///
///   @override
///   Object? resolve(EvaluationContext context, String beanName) =>
///       beans[beanName] ?? (throw AccessException('No bean $beanName'));
/// }
///
/// final context = StandardEvaluationContext()
///   ..beanResolver = MapBeanResolver({'clock': clock});
/// SpelExpressionParser().parseExpression('@clock').getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// context.setBeanResolver(new BeanFactoryResolver(beanFactory));
/// parser.parseExpression("@clock").getValue(context);
/// ```
abstract interface class BeanResolver {
  /// The object named [beanName]; for `&name` the name arrives with its
  /// `&` (the factory bean itself rather than its product).
  ///
  /// Throw an `AccessException` when there is no such object: it is
  /// reported as `exceptionDuringBeanResolution` (EL1058E). Other
  /// exceptions reach the caller unchanged.
  Object? resolve(EvaluationContext context, String beanName);
}

/// The world an expression is evaluated in: its root object, its
/// variables, and the plug-ins that decide which properties, methods,
/// types and beans it can reach.
///
/// The same expression gives different results in different contexts,
/// and a context also decides what an expression is allowed to do. Pick
/// one of the two implementations: [StandardEvaluationContext] for
/// expressions you wrote yourself (everything is available), and
/// [SimpleEvaluationContext] for expressions that come from outside, such
/// as a user-supplied filter (no types, constructors, bean references or
/// variable assignment). A context may be reused for many evaluations;
/// variables set on it stay.
///
/// ```dart
/// // `n` is read on the root object, `#factor` is a variable.
/// EvaluationContext context = StandardEvaluationContext({'n': 2})
///   ..setVariable('factor', 10);
/// SpelExpressionParser().parseExpression('n * #factor').getValue(context);
/// // 20
/// ```
///
/// Spring (Java):
/// ```java
/// EvaluationContext context = new StandardEvaluationContext(root);
/// context.setVariable("factor", 10);
/// parser.parseExpression("n * #factor").getValue(context);
/// ```
abstract interface class EvaluationContext {
  /// The object unprefixed names are read on (`name` means
  /// `#root.name`) when `getValue` is called without a root object.
  Object? get rootObject;

  /// The accessors asked, in order, for `obj.property`.
  List<PropertyAccessor> get propertyAccessors;

  /// The resolvers asked, in order, for `obj.method(...)`.
  List<MethodResolver> get methodResolvers;

  /// The resolvers asked, in order, for `new Name(...)`; empty when the
  /// context does not allow constructors.
  List<ConstructorResolver> get constructorResolvers;

  /// The accessors asked, in order, for `target[index]` when the target
  /// is not a list, map or string.
  List<IndexAccessor> get indexAccessors;

  /// Finds the types of `T(Name)`, `new Name(...)` and `instanceof`.
  TypeLocator get typeLocator;

  /// Converts values: for `getValueAs`, conditions, templates, indexes
  /// and method arguments.
  TypeConverter get typeConverter;

  /// Orders values for `<`, `<=`, `>`, `>=` and `between`.
  TypeComparator get typeComparator;

  /// Gives arithmetic operators a meaning for operands with no built-in
  /// rule.
  OperatorOverloader get operatorOverloader;

  /// Looks up `@name` and `&name`, or `null` when the context has no bean
  /// references (they then fail with EL1057E).
  BeanResolver? get beanResolver;

  /// Whether expressions may assign (`=`, `++`, `--`) and
  /// `Expression.setValue` may write; when `false` both fail with
  /// `notAssignable` (EL1068E).
  bool get isAssignmentEnabled;

  /// Sets the variable `#name` to [value] from Dart code, before the
  /// expression is evaluated.
  ///
  /// Variables are how an expression gets values that are not on its
  /// root: the method arguments of a cache key (`#isbn`), a request, the
  /// current user. Unset variables read as `null`.
  void setVariable(String name, Object? value);

  /// Stores the value from [valueSupplier] in `#name` and returns it; the
  /// evaluator calls this for `#name = ...` and `#name++` inside an
  /// expression.
  ///
  /// It is separate from [setVariable] so that a context can refuse
  /// assignments written in expressions while still accepting variables
  /// set from code: a `SimpleEvaluationContext` throws
  /// `SpelMessage.variableAssignmentNotSupported` (EL1080E).
  Object? assignVariable(String name, Object? Function() valueSupplier);

  /// The value of variable `#name`, or `null` when unset. Registered
  /// functions are variables too.
  Object? lookupVariable(String name);
}

/// The default [TypeConverter]: it hands every conversion to a
/// [ConversionService].
///
/// Every context starts with one over the shared
/// `DefaultConversionService` (strings to numbers, booleans, durations,
/// lists, ...). Create one over your own service when expressions should
/// convert with the converters your application registered. Failures
/// become `typeConversionError` (EL1001E) with the original error as
/// cause.
///
/// ```dart
/// // Expressions convert with the application's converters.
/// final context = StandardEvaluationContext()
///   ..typeConverter = StandardTypeConverter(myConversionService);
/// SpelExpressionParser()
///     .parseExpression("'1,2'")
///     .getValueAs<List<int>>(context); // [1, 2]
/// ```
///
/// Spring (Java):
/// ```java
/// context.setTypeConverter(new StandardTypeConverter(conversionService));
/// ```
final class StandardTypeConverter implements TypeConverter {
  /// Converts with [conversionService], or the shared
  /// `DefaultConversionService` when omitted.
  StandardTypeConverter([ConversionService? conversionService])
    : _conversionService = _always(
        conversionService ?? DefaultConversionService.sharedInstance,
      );

  /// Converts with the service [conversionService] returns, looked up at
  /// every conversion (Spring's `Supplier` constructor): a bean factory's
  /// service may be replaced after the evaluation context was created.
  StandardTypeConverter.lazy(ConversionService Function() conversionService)
    : _conversionService = conversionService;

  final ConversionService Function() _conversionService;

  static ConversionService Function() _always(ConversionService service) =>
      () => service;

  /// The service doing the conversions (looked up again on each access
  /// for a [StandardTypeConverter.lazy] converter).
  ConversionService get conversionService => _conversionService();

  @override
  bool canConvert(Object? value, Type targetType) =>
      conversionService.canConvert(value, targetType);

  @override
  Object? convertValue(Object? value, Type targetType) {
    try {
      return conversionService.convertTo(value, targetType);
    } on Exception catch (error) {
      throw SpelEvaluationException(
        SpelMessage.typeConversionError,
        inserts: [value.runtimeType, targetType],
        cause: error,
      );
    }
  }
}

/// The default [TypeComparator]: it orders numbers, strings, dates,
/// durations, booleans, enums and other `Comparable`s, with `null` before
/// everything.
///
/// Numbers compare by value across `int` and `double`; booleans with
/// `false < true` (Java's `Boolean` is `Comparable`); values of one enum
/// type by their index (like Java enums, which are `Comparable` by
/// ordinal); other `Comparable`s only with values of the same kind, so a
/// string never compares with a date. Every context uses it unless you
/// set another comparator; you rarely call it yourself.
///
/// ```dart
/// // What `1 < 2.5`, `null < 'a'` and `'a' < 1` do in an expression.
/// const comparator = StandardTypeComparator();
/// comparator.compare(1, 2.5); // negative
/// comparator.compare(null, 'a'); // negative
/// comparator.compare(Level.low, Level.high); // negative
/// comparator.canCompare('a', 1); // false
/// ```
///
/// Spring (Java):
/// ```java
/// TypeComparator comparator = new StandardTypeComparator();
/// comparator.compare(1, 2.5); // negative
/// ```
final class StandardTypeComparator implements TypeComparator {
  /// Creates the comparator (stateless).
  const StandardTypeComparator();

  @override
  bool canCompare(Object? left, Object? right) =>
      left == null ||
      right == null ||
      (left is num && right is num) ||
      (left is bool && right is bool) ||
      (left is Enum &&
          right is Enum &&
          left.runtimeType == right.runtimeType) ||
      (left is Comparable && right is Comparable && _sameKind(left, right));

  // Comparable values only compare with the same kind (a String never
  // compares with a DateTime, even though both are Comparable).
  static bool _sameKind(Object left, Object right) =>
      left.runtimeType == right.runtimeType ||
      (left is String && right is String) ||
      (left is DateTime && right is DateTime) ||
      (left is Duration && right is Duration);

  @override
  int compare(Object? left, Object? right) {
    if (left == null) {
      return right == null ? 0 : -1;
    }
    if (right == null) {
      return 1;
    }
    if (left is num && right is num) {
      return left.compareTo(right);
    }
    if (left is bool && right is bool) {
      // Java's Boolean is Comparable: false < true.
      return left == right ? 0 : (left ? 1 : -1);
    }
    if (left is Comparable && right is Comparable && _sameKind(left, right)) {
      return left.compareTo(right);
    }
    if (left is Enum &&
        right is Enum &&
        left.runtimeType == right.runtimeType) {
      return left.index.compareTo(right.index);
    }
    throw SpelEvaluationException(
      SpelMessage.notComparable,
      inserts: [left.runtimeType, right.runtimeType],
    );
  }
}

/// The default [OperatorOverloader]: it takes over no operator, so
/// arithmetic on operands without a built-in rule fails with
/// `operatorNotSupportedBetweenTypes` (EL1030E).
///
/// Every context starts with it; replace it on a
/// `StandardEvaluationContext` to give operators a meaning for your types.
///
/// ```dart
/// // `{1} + {2}` is not supported by default.
/// const StandardOperatorOverloader()
///     .overridesOperation(Operation.add, [1], [2]); // false
/// ```
///
/// Spring (Java):
/// ```java
/// OperatorOverloader overloader = new StandardOperatorOverloader();
/// ```
final class StandardOperatorOverloader implements OperatorOverloader {
  /// Creates the overloader (stateless).
  const StandardOperatorOverloader();

  @override
  bool overridesOperation(Operation operation, Object? left, Object? right) =>
      false;

  @override
  Object? operate(Operation operation, Object? left, Object? right) =>
      throw SpelEvaluationException(
        SpelMessage.operatorNotSupportedBetweenTypes,
        inserts: [operation.name, left.runtimeType, right.runtimeType],
      );
}

/// An evaluation context with every feature of the language enabled: the
/// one to use for expressions you or your application wrote.
///
/// It reads maps ([MapAccessor]), the properties and methods of
/// `@Introspected` classes registered in `BeanIntrospector.shared`
/// (`IntrospectionPropertyAccessor` and `IntrospectionMethodResolver`,
/// which replace Java's reflection), and the common properties and
/// methods of core Dart types. It supports variables, functions, `T(...)`
/// types, constructors, bean references (once [beanResolver] is set) and
/// assignment. Add accessors or resolvers for classes that are not
/// `@Introspected`, or for the introspector of an application context;
/// the `@Value('#{...}')` expressions of a context have those already.
///
/// An expression evaluated here can call any method it can reach and
/// assign values, so never use it for text that comes from users; use
/// [SimpleEvaluationContext] for that.
///
/// ```dart
/// // A notification template: the user is the root, the greeting a
/// // variable, `#shout` a function.
/// final context = StandardEvaluationContext(user)
///   ..addPropertyAccessor(FunctionPropertyAccessor<User>(
///     getters: {'name': (u) => u.name},
///   ))
///   ..setVariable('greeting', 'Hello')
///   ..registerFunction('shout', (String s) => s.toUpperCase());
/// SpelExpressionParser()
///     .parseExpression("#shout(#greeting + ' ' + name)")
///     .getValue(context); // 'HELLO ADA'
/// ```
///
/// Spring (Java):
/// ```java
/// StandardEvaluationContext context = new StandardEvaluationContext(user);
/// context.setVariable("greeting", "Hello");
/// context.registerFunction("shout",
///     StringUtils.class.getMethod("shout", String.class));
/// parser.parseExpression("#shout(#greeting + ' ' + name)")
///     .getValue(context, String.class);
/// ```
///
/// Spring reads `name` reflectively; in Dart the class must be
/// `@Introspected` (registered in `BeanIntrospector.shared`) or have an
/// accessor.
class StandardEvaluationContext implements EvaluationContext {
  /// Creates a context whose `#root` is [rootObject] (none when omitted;
  /// it can be set later, and `getValue` can pass another root per call).
  StandardEvaluationContext([this.rootObject]);

  @override
  Object? rootObject;

  final _introspectionAccessor = IntrospectionPropertyAccessor(
    BeanIntrospector.shared,
  );
  final _introspectionResolver = IntrospectionMethodResolver(
    BeanIntrospector.shared,
  );

  @override
  late final List<PropertyAccessor> propertyAccessors = [
    const MapAccessor(),
    _introspectionAccessor,
    const BuiltinPropertyAccessor(),
  ];

  @override
  late final List<MethodResolver> methodResolvers = [
    _introspectionResolver,
    const BuiltinMethodResolver(),
  ];

  @override
  final List<ConstructorResolver> constructorResolvers = [
    const SpelTypeConstructorResolver(),
  ];

  @override
  final List<IndexAccessor> indexAccessors = [];

  @override
  TypeLocator typeLocator = StandardTypeLocator();

  @override
  TypeConverter typeConverter = StandardTypeConverter();

  @override
  TypeComparator typeComparator = const StandardTypeComparator();

  @override
  OperatorOverloader operatorOverloader = const StandardOperatorOverloader();

  @override
  BeanResolver? beanResolver;

  @override
  bool get isAssignmentEnabled => true;

  final _variables = <String, Object?>{};

  /// Adds [accessor] so that it is asked before the built-in ones.
  ///
  /// The defaults ([MapAccessor], the shared introspection accessor,
  /// [BuiltinPropertyAccessor]) stay last, so your accessor wins for the
  /// properties it handles; accessors you add later come after the ones
  /// you added before. When the defaults were removed from
  /// [propertyAccessors], [accessor] is appended.
  void addPropertyAccessor(PropertyAccessor accessor) => _insertBeforeDefaults(
    propertyAccessors,
    accessor,
    (a) =>
        a is MapAccessor ||
        identical(a, _introspectionAccessor) ||
        a is BuiltinPropertyAccessor,
  );

  /// Adds [resolver] so that it is asked before the built-in ones (the
  /// shared introspection resolver and `BuiltinMethodResolver`), or
  /// appends it when they were removed from [methodResolvers].
  void addMethodResolver(MethodResolver resolver) => _insertBeforeDefaults(
    methodResolvers,
    resolver,
    (r) => identical(r, _introspectionResolver) || r is BuiltinMethodResolver,
  );

  /// Adds [resolver] so that it is asked before the default
  /// `SpelTypeConstructorResolver`, which only knows registered types.
  void addConstructorResolver(ConstructorResolver resolver) =>
      _insertBeforeDefaults(
        constructorResolvers,
        resolver,
        (r) => r is SpelTypeConstructorResolver,
      );

  /// Adds [accessor] after the index accessors already added; there are
  /// none by default.
  void addIndexAccessor(IndexAccessor accessor) => indexAccessors.add(accessor);

  static void _insertBeforeDefaults<T>(
    List<T> list,
    T element,
    bool Function(T) isDefault,
  ) {
    final index = list.indexWhere(isDefault);
    list.insert(index < 0 ? list.length : index, element);
  }

  /// Makes [function] callable from expressions as `#name(args)`.
  ///
  /// Functions are the way to offer helpers that belong to no object,
  /// such as a formatting or a lookup function.
  ///
  /// ```dart
  /// context.registerFunction('reverse',
  ///     (String s) => s.split('').reversed.join());
  /// parser.parseExpression("#reverse('abc')").getValue(context); // 'cba'
  /// ```
  ///
  /// Functions share the namespace of variables. [function] is a Dart
  /// `Function`, or a `VarargsFunction` to accept a variable number of
  /// trailing arguments.
  void registerFunction(String name, Object function) =>
      _variables[name] = function;

  /// Sets several variables at once.
  void setVariables(Map<String, Object?> variables) =>
      _variables.addAll(variables);

  @override
  void setVariable(String name, Object? value) => _variables[name] = value;

  @override
  Object? assignVariable(String name, Object? Function() valueSupplier) {
    final value = valueSupplier();
    setVariable(name, value);
    return value;
  }

  @override
  Object? lookupVariable(String name) => _variables[name];
}

/// An evaluation context that only lets an expression read (and, if
/// allowed, write) properties: the one to use for expressions that come
/// from outside, such as a filter typed by a user or a field path sent by
/// a client.
///
/// A [StandardEvaluationContext] lets an expression create objects, call
/// static methods and reach beans, which is dangerous for text you did
/// not write. Here `T(...)`, `new`, `@bean` references and assignments to
/// variables always fail; properties can be assigned only in read-write
/// mode, and methods can be called only after
/// [SimpleEvaluationContextBuilder.withInstanceMethods] or
/// [SimpleEvaluationContextBuilder.withMethodResolvers]. Properties are
/// read on maps, `@Introspected` classes and core Dart types, as in the
/// standard context. Create one with [forReadOnlyDataBinding],
/// [forReadWriteDataBinding] or [forPropertyAccessors], then `build()`.
///
/// ```dart
/// // A search filter typed by a user: it may read, never change.
/// final context = SimpleEvaluationContext.forReadOnlyDataBinding()
///     .withRootObject({'name': 'Ada'})
///     .build();
/// SpelExpressionParser().parseExpression('name').getValue(context);
/// // 'Ada'
/// SpelExpressionParser().parseExpression("name = 'x'").getValue(context);
/// // throws SpelEvaluationException (notAssignable)
/// SpelExpressionParser().parseExpression('#v = 1').getValue(context);
/// // throws SpelEvaluationException (variableAssignmentNotSupported)
/// ```
///
/// Spring (Java):
/// ```java
/// EvaluationContext context = SimpleEvaluationContext
///     .forReadOnlyDataBinding()
///     .withRootObject(root)
///     .build();
/// parser.parseExpression("name").getValue(context);
/// ```
class SimpleEvaluationContext implements EvaluationContext {
  SimpleEvaluationContext._(
    this.rootObject,
    this.propertyAccessors,
    this.methodResolvers,
    this.indexAccessors,
    this.typeConverter,
    this.isAssignmentEnabled,
  );

  /// A builder for a context whose expressions can read properties but
  /// not assign them, for evaluating conditions or paths.
  static SimpleEvaluationContextBuilder forReadOnlyDataBinding() =>
      SimpleEvaluationContextBuilder._(assignment: false);

  /// A builder for a context whose expressions can read and assign
  /// properties (`Expression.setValue` on `address.city`), for binding
  /// submitted fields to an object.
  static SimpleEvaluationContextBuilder forReadWriteDataBinding() =>
      SimpleEvaluationContextBuilder._(assignment: true);

  /// A builder for a context that reads properties only through
  /// [accessors], instead of [MapAccessor], the introspection accessor and
  /// the built-in one; assignment is enabled (turn it off with
  /// [SimpleEvaluationContextBuilder.withAssignmentDisabled]).
  ///
  /// Use it to expose exactly the properties you list and nothing else.
  ///
  /// ```dart
  /// SimpleEvaluationContext.forPropertyAccessors([
  ///   FunctionPropertyAccessor<User>(getters: {'name': (u) => u.name}),
  /// ]).withRootObject(user).build();
  /// ```
  static SimpleEvaluationContextBuilder forPropertyAccessors(
    List<PropertyAccessor> accessors,
  ) => SimpleEvaluationContextBuilder._(assignment: true, accessors: accessors);

  @override
  final Object? rootObject;

  @override
  final List<PropertyAccessor> propertyAccessors;

  @override
  final List<MethodResolver> methodResolvers;

  @override
  final List<IndexAccessor> indexAccessors;

  @override
  final TypeConverter typeConverter;

  @override
  final bool isAssignmentEnabled;

  final _variables = <String, Object?>{};

  @override
  List<ConstructorResolver> get constructorResolvers => const [];

  @override
  TypeLocator get typeLocator => const _NoTypeLocator();

  @override
  TypeComparator get typeComparator => const StandardTypeComparator();

  @override
  OperatorOverloader get operatorOverloader =>
      const StandardOperatorOverloader();

  @override
  BeanResolver? get beanResolver => null;

  @override
  void setVariable(String name, Object? value) => _variables[name] = value;

  /// Always throws `variableAssignmentNotSupported` (EL1080E):
  /// expressions in a simple context cannot assign variables. Variables
  /// set from code with [setVariable] can still be read.
  @override
  Object? assignVariable(String name, Object? Function() valueSupplier) =>
      throw SpelEvaluationException(
        SpelMessage.variableAssignmentNotSupported,
        inserts: ['#$name'],
      );

  @override
  Object? lookupVariable(String name) => _variables[name];
}

/// Sets up a [SimpleEvaluationContext]: which methods, index accessors,
/// conversions and root object it has.
///
/// Get one from [SimpleEvaluationContext.forReadOnlyDataBinding],
/// [SimpleEvaluationContext.forReadWriteDataBinding] or
/// [SimpleEvaluationContext.forPropertyAccessors], chain the `with...`
/// calls you need, then call [build]. Everything not enabled here stays
/// off.
///
/// ```dart
/// // Binding a submitted form: fields may be set, and methods such as
/// // `name.trim()` may be called.
/// final context = SimpleEvaluationContext.forReadWriteDataBinding()
///     .withInstanceMethods()
///     .withConversionService(DefaultConversionService())
///     .withRootObject(form)
///     .build();
/// ```
///
/// Spring (Java):
/// ```java
/// EvaluationContext context = SimpleEvaluationContext
///     .forReadWriteDataBinding()
///     .withInstanceMethods()
///     .withConversionService(conversionService)
///     .withRootObject(form)
///     .build();
/// ```
final class SimpleEvaluationContextBuilder {
  SimpleEvaluationContextBuilder._({
    required this._assignment,
    List<PropertyAccessor>? accessors,
  }) : _accessors =
           accessors ??
           [
             const MapAccessor(),
             // Spring's DataBindingPropertyAccessor: public properties.
             IntrospectionPropertyAccessor(BeanIntrospector.shared),
             const BuiltinPropertyAccessor(),
           ];

  bool _assignment;
  final List<PropertyAccessor> _accessors;
  final _resolvers = <MethodResolver>[];
  final _indexAccessors = <IndexAccessor>[];
  bool _instanceMethods = false;
  TypeConverter _converter = StandardTypeConverter();
  Object? _root;

  /// Lets expressions call instance methods: those of `@Introspected`
  /// classes in `BeanIntrospector.shared` (Spring's
  /// `DataBindingMethodResolver`) and the built-in ones of core Dart
  /// types, such as `name.toUpperCase()`. Off by default.
  ///
  /// [extra] resolvers, like those of [withMethodResolvers], are asked
  /// first.
  SimpleEvaluationContextBuilder withInstanceMethods([
    List<MethodResolver> extra = const [],
  ]) {
    _resolvers.addAll(extra);
    _instanceMethods = true;
    return this;
  }

  /// Lets expressions call only the methods [resolvers] offer, such as a
  /// `FunctionMethodResolver` listing a few methods of your own type.
  /// They are asked before the ones [withInstanceMethods] enables.
  SimpleEvaluationContextBuilder withMethodResolvers(
    List<MethodResolver> resolvers,
  ) {
    _resolvers.addAll(resolvers);
    return this;
  }

  /// Adds index accessors so that `target[index]` works on your own
  /// indexable types; lists, maps and strings need none.
  SimpleEvaluationContextBuilder withIndexAccessors(
    List<IndexAccessor> accessors,
  ) {
    _indexAccessors.addAll(accessors);
    return this;
  }

  /// Uses [converter] instead of a [StandardTypeConverter] over the shared
  /// `DefaultConversionService`.
  SimpleEvaluationContextBuilder withTypeConverter(TypeConverter converter) {
    _converter = converter;
    return this;
  }

  /// Converts with [service], typically the application's conversion
  /// service, through a [StandardTypeConverter].
  SimpleEvaluationContextBuilder withConversionService(
    ConversionService service,
  ) => withTypeConverter(StandardTypeConverter(service));

  /// Sets the default root object (`#root`), used when `getValue` gets no
  /// root of its own.
  SimpleEvaluationContextBuilder withRootObject(Object? root) {
    _root = root;
    return this;
  }

  /// Forbids assignment, for example in a builder from
  /// [SimpleEvaluationContext.forPropertyAccessors] whose properties
  /// should only be read.
  SimpleEvaluationContextBuilder withAssignmentDisabled() {
    _assignment = false;
    return this;
  }

  /// Creates the context. Its accessor and resolver lists are
  /// unmodifiable: what the builder did not enable cannot be added later.
  SimpleEvaluationContext build() => SimpleEvaluationContext._(
    _root,
    List.unmodifiable(_accessors),
    List.unmodifiable([
      ..._resolvers,
      if (_instanceMethods) ...[
        IntrospectionMethodResolver(BeanIntrospector.shared),
        const BuiltinMethodResolver(),
      ],
    ]),
    List.unmodifiable(_indexAccessors),
    _converter,
    _assignment,
  );
}

// SimpleEvaluationContext has no type support: every T(...) fails, like
// Spring's (TYPE_NOT_FOUND).
final class _NoTypeLocator implements TypeLocator {
  const _NoTypeLocator();

  @override
  SpelType findType(String typeName) => throw SpelEvaluationException(
    SpelMessage.typeNotFound,
    inserts: [typeName],
  );
}
