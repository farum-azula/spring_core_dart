import 'package:spring_core_dart/src/core/convert/conversion_service.dart';
import 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';
import 'package:spring_core_dart/src/expression/builtins.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/spel_type.dart';

/// Reads and writes properties of objects, like Spring's `PropertyAccessor`.
///
/// Dart has no reflection in Flutter/AOT, so user classes are accessed
/// through accessors: [MapAccessor], [FunctionPropertyAccessor], or
/// generated introspection metadata (`IntrospectionPropertyAccessor`).
/// The first accessor in [EvaluationContext.propertyAccessors] whose
/// [canRead] / [canWrite] returns `true` wins.
///
/// ```dart
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
  /// Whether this accessor can read property [name] of [target].
  bool canRead(EvaluationContext context, Object target, String name);

  /// Reads property [name] of [target]; only called after [canRead]
  /// returned `true`.
  Object? read(EvaluationContext context, Object target, String name);

  /// Whether this accessor can write property [name] of [target].
  bool canWrite(EvaluationContext context, Object target, String name);

  /// Writes [newValue] to property [name] of [target]; only called after
  /// [canWrite] returned `true`.
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  );
}

/// Calls a resolved method with evaluated arguments, like Spring's
/// `MethodExecutor`.
///
/// ```dart
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

/// Finds methods by name and arguments, like Spring's `MethodResolver`.
///
/// Without reflection, methods of user classes come from resolvers such as
/// `FunctionMethodResolver` or `IntrospectionMethodResolver`; core Dart
/// types are covered by `BuiltinMethodResolver`. Resolvers are asked in
/// order; the first non-null executor is used.
///
/// ```dart
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
  /// An executor for [name] on [target], or `null` if not handled.
  MethodExecutor? resolve(
    EvaluationContext context,
    Object target,
    String name,
    List<Object?> arguments,
  );
}

/// Creates an object with evaluated arguments, like Spring's
/// `ConstructorExecutor`.
///
/// ```dart
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

/// Finds constructors for `new Name(...)`, like Spring's
/// `ConstructorResolver`.
///
/// `StandardEvaluationContext` asks `SpelTypeConstructorResolver` (the
/// constructors registered on a `SpelType`) by default; add your own with
/// `StandardEvaluationContext.addConstructorResolver`. A
/// `SimpleEvaluationContext` has none, so `new` always fails there.
///
/// ```dart
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
  /// An executor creating a [typeName] from [arguments], or `null` if not
  /// handled.
  ///
  /// Throwing an `AccessException` is reported as
  /// `SpelMessage.constructorInvocationProblem`.
  ConstructorExecutor? resolve(
    EvaluationContext context,
    String typeName,
    List<Object?> arguments,
  );
}

/// Reads and writes `target[index]` for custom types, like Spring's
/// `IndexAccessor` (6.2).
///
/// Lists, maps and strings are indexed natively; index accessors are asked
/// for any other target before the fallbacks (other iterables, property
/// access by a string index).
///
/// ```dart
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
  /// Whether this accessor can read [index] of [target].
  bool canRead(EvaluationContext context, Object target, Object? index);

  /// Reads [index] of [target]; only called after [canRead] returned
  /// `true`.
  Object? read(EvaluationContext context, Object target, Object? index);

  /// Whether this accessor can write [index] of [target].
  bool canWrite(EvaluationContext context, Object target, Object? index);

  /// Writes [newValue] to [index] of [target]; only called after
  /// [canWrite] returned `true`.
  void write(
    EvaluationContext context,
    Object target,
    Object? index,
    Object? newValue,
  );
}

/// Finds `T(Name)` types, like Spring's `TypeLocator`.
///
/// Dart cannot load classes by name, so types must be registered as
/// [SpelType]s (see [StandardTypeLocator]).
///
/// ```dart
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
  /// The type registered as [typeName].
  ///
  /// Throws a `SpelEvaluationException` (`typeNotFound`) when unknown.
  SpelType findType(String typeName);
}

/// Converts values, like Spring's expression `TypeConverter`.
///
/// Used by `Expression.getValueAs`, boolean conditions, template parts and
/// introspection setters. The default is [StandardTypeConverter].
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
  /// Whether [value] can be converted to [targetType].
  bool canConvert(Object? value, Type targetType);

  /// Converts [value] to [targetType].
  ///
  /// Throws a `SpelEvaluationException` (`typeConversionError`) on
  /// failure.
  Object? convertValue(Object? value, Type targetType);
}

/// Orders values for `<`, `>`, `between`, like Spring's `TypeComparator`.
///
/// The default is [StandardTypeComparator]; replace it to order your own
/// types.
///
/// ```dart
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
  /// Whether [left] and [right] can be ordered.
  bool canCompare(Object? left, Object? right);

  /// Negative, zero or positive as [left] is less than, equal to or
  /// greater than [right].
  int compare(Object? left, Object? right);
}

/// Arithmetic operators, like Spring's `Operation`.
///
/// Passed to an [OperatorOverloader] when an arithmetic operator meets
/// operands it does not handle natively.
///
/// ```dart
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

/// Arithmetic on non-numeric operands, like Spring's `OperatorOverloader`.
///
/// Consulted after the built-in rules (numbers, string concatenation,
/// string repetition) did not apply.
///
/// ```dart
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

/// Resolves `@beanName` / `&factoryBean`, like Spring's `BeanResolver`.
///
/// `BeanFactoryResolver` adapts a bean factory; any lookup works.
///
/// ```dart
/// final class MapBeanResolver implements BeanResolver {
///   MapBeanResolver(this.beans);
///   final Map<String, Object> beans;
///
///   @override
///   Object? resolve(EvaluationContext context, String beanName) =>
///       beans[beanName] ?? (throw StateError('No bean $beanName'));
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
  /// The bean named [beanName] (prefixed with `&` for `&factoryBean`).
  ///
  /// Throwing is reported as a `SpelEvaluationException`
  /// (`beanNotFound`).
  Object? resolve(EvaluationContext context, String beanName);
}

/// Everything an expression can use while evaluating, like Spring's
/// `EvaluationContext`.
///
/// Use [StandardEvaluationContext] for trusted expressions and
/// [SimpleEvaluationContext] for restricted ones (e.g. user input).
///
/// ```dart
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
  /// The default root object (`#root`).
  Object? get rootObject;

  /// Accessors for `obj.property`, asked in order.
  List<PropertyAccessor> get propertyAccessors;

  /// Resolvers for `obj.method(...)`, asked in order.
  List<MethodResolver> get methodResolvers;

  /// Resolvers for `new Name(...)`, asked in order; empty when
  /// constructors are not supported.
  List<ConstructorResolver> get constructorResolvers;

  /// Accessors for `target[index]` on types other than lists, maps and
  /// strings, asked in order.
  List<IndexAccessor> get indexAccessors;

  /// Finds types for `T(Name)`, `new Name(...)` and `instanceof`.
  TypeLocator get typeLocator;

  /// Converts values (`getValueAs`, conditions, templates).
  TypeConverter get typeConverter;

  /// Orders values for relational operators and `between`.
  TypeComparator get typeComparator;

  /// Handles arithmetic on non-numeric operands.
  OperatorOverloader get operatorOverloader;

  /// Resolves `@bean` and `&bean`, or `null` when bean references are not
  /// supported.
  BeanResolver? get beanResolver;

  /// Whether assignment (`=`, `++`, `--`) is allowed.
  bool get isAssignmentEnabled;

  /// Sets the variable `#name` to [value] (programmatic use).
  void setVariable(String name, Object? value);

  /// Assigns the value from [valueSupplier] to `#name` for an assignment
  /// inside an expression (`#name = ...`, `#name++`) and returns it, like
  /// Spring's `assignVariable`.
  ///
  /// A `SimpleEvaluationContext` throws
  /// `SpelMessage.variableAssignmentNotSupported` instead.
  Object? assignVariable(String name, Object? Function() valueSupplier);

  /// The value of variable `#name`, or `null` when unset.
  Object? lookupVariable(String name);
}

/// [TypeConverter] backed by a [ConversionService], like Spring's
/// `StandardTypeConverter`.
///
/// ```dart
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

  /// The service doing the conversions.
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

/// Compares numbers, strings, dates, durations, enums and `Comparable`s;
/// `null` is smaller than anything, like Spring's `StandardTypeComparator`.
///
/// Numbers compare by value across `int` and `double`; booleans with
/// `false < true` (Java's `Boolean` is `Comparable`); values of one enum
/// type by their index (like Java enums, which are `Comparable` by
/// ordinal); other `Comparable`s only with values of the same kind.
///
/// ```dart
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

/// Supports no operator overloading (Spring's default).
///
/// ```dart
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

/// The full-featured context, like Spring's `StandardEvaluationContext`.
///
/// Comes with [MapAccessor] and the built-in accessors/methods for core
/// Dart types; add accessors for your own classes. Supports variables,
/// functions, `T(...)` types, constructors, bean references and
/// assignment. Do not use it for untrusted expressions; use
/// [SimpleEvaluationContext] instead.
///
/// ```dart
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
/// Spring reads `name` reflectively; in Dart an accessor is required.
class StandardEvaluationContext implements EvaluationContext {
  /// Creates a context whose `#root` is [rootObject].
  StandardEvaluationContext([this.rootObject]);

  @override
  Object? rootObject;

  @override
  final List<PropertyAccessor> propertyAccessors = [
    const MapAccessor(),
    const BuiltinPropertyAccessor(),
  ];

  @override
  final List<MethodResolver> methodResolvers = [const BuiltinMethodResolver()];

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

  /// Adds [accessor] before the default ones.
  ///
  /// The defaults ([MapAccessor], [BuiltinPropertyAccessor]) stay last, so
  /// user accessors are asked first; when they were removed from
  /// [propertyAccessors], [accessor] is appended.
  void addPropertyAccessor(PropertyAccessor accessor) => _insertBeforeDefaults(
    propertyAccessors,
    accessor,
    (a) => a is MapAccessor || a is BuiltinPropertyAccessor,
  );

  /// Adds [resolver] before the built-in one (or appends it when
  /// `BuiltinMethodResolver` was removed from [methodResolvers]).
  void addMethodResolver(MethodResolver resolver) => _insertBeforeDefaults(
    methodResolvers,
    resolver,
    (r) => r is BuiltinMethodResolver,
  );

  /// Adds [resolver] before the default `SpelTypeConstructorResolver`
  /// (Spring's `addConstructorResolver`).
  void addConstructorResolver(ConstructorResolver resolver) =>
      _insertBeforeDefaults(
        constructorResolvers,
        resolver,
        (r) => r is SpelTypeConstructorResolver,
      );

  /// Adds [accessor] after the existing index accessors (Spring's
  /// `addIndexAccessor`).
  void addIndexAccessor(IndexAccessor accessor) => indexAccessors.add(accessor);

  static void _insertBeforeDefaults<T>(
    List<T> list,
    T element,
    bool Function(T) isDefault,
  ) {
    final index = list.indexWhere(isDefault);
    list.insert(index < 0 ? list.length : index, element);
  }

  /// Makes [function] callable as `#name(args)`.
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

/// A restricted context for data binding, like Spring's
/// `SimpleEvaluationContext`: no type references, no constructors, no bean
/// references, no assignment to variables; assignment to properties only
/// in read-write mode; methods only when enabled.
///
/// Created through [SimpleEvaluationContextBuilder]. Safe for expressions
/// from less trusted sources.
///
/// ```dart
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

  /// Properties can be read but not assigned (Spring's
  /// `SimpleEvaluationContext.forReadOnlyDataBinding()`).
  static SimpleEvaluationContextBuilder forReadOnlyDataBinding() =>
      SimpleEvaluationContextBuilder._(assignment: false);

  /// Properties can be read and assigned (Spring's
  /// `SimpleEvaluationContext.forReadWriteDataBinding()`).
  static SimpleEvaluationContextBuilder forReadWriteDataBinding() =>
      SimpleEvaluationContextBuilder._(assignment: true);

  /// Only the given accessors (instead of [MapAccessor] and the built-in
  /// one); assignment enabled (Spring's
  /// `SimpleEvaluationContext.forPropertyAccessors(...)`).
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

  /// Always throws: expressions in a simple context cannot assign
  /// variables (Spring's EL1080E). Use [setVariable] from code.
  @override
  Object? assignVariable(String name, Object? Function() valueSupplier) =>
      throw SpelEvaluationException(
        SpelMessage.variableAssignmentNotSupported,
        inserts: ['#$name'],
      );

  @override
  Object? lookupVariable(String name) => _variables[name];
}

/// Builder of [SimpleEvaluationContext], like Spring's
/// `SimpleEvaluationContext.Builder`.
///
/// Obtain one from [SimpleEvaluationContext.forReadOnlyDataBinding],
/// [SimpleEvaluationContext.forReadWriteDataBinding] or
/// [SimpleEvaluationContext.forPropertyAccessors].
///
/// ```dart
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
           accessors ?? [const MapAccessor(), const BuiltinPropertyAccessor()];

  bool _assignment;
  final List<PropertyAccessor> _accessors;
  final _resolvers = <MethodResolver>[];
  final _indexAccessors = <IndexAccessor>[];
  bool _instanceMethods = false;
  TypeConverter _converter = StandardTypeConverter();
  Object? _root;

  /// Enables built-in instance methods (and [extra] resolvers).
  ///
  /// [extra] resolvers, like those of [withMethodResolvers], are asked
  /// before `BuiltinMethodResolver`.
  SimpleEvaluationContextBuilder withInstanceMethods([
    List<MethodResolver> extra = const [],
  ]) {
    _resolvers.addAll(extra);
    _instanceMethods = true;
    return this;
  }

  /// Adds method resolvers, e.g. a `FunctionMethodResolver` for your own
  /// types (Spring's `withMethodResolvers`).
  SimpleEvaluationContextBuilder withMethodResolvers(
    List<MethodResolver> resolvers,
  ) {
    _resolvers.addAll(resolvers);
    return this;
  }

  /// Adds index accessors for custom indexable types (Spring's
  /// `withIndexAccessors`).
  SimpleEvaluationContextBuilder withIndexAccessors(
    List<IndexAccessor> accessors,
  ) {
    _indexAccessors.addAll(accessors);
    return this;
  }

  /// Uses [converter] instead of the default [StandardTypeConverter].
  SimpleEvaluationContextBuilder withTypeConverter(TypeConverter converter) {
    _converter = converter;
    return this;
  }

  /// Uses a [StandardTypeConverter] backed by [service].
  SimpleEvaluationContextBuilder withConversionService(
    ConversionService service,
  ) => withTypeConverter(StandardTypeConverter(service));

  /// Sets the default root object (`#root`).
  SimpleEvaluationContextBuilder withRootObject(Object? root) {
    _root = root;
    return this;
  }

  /// Disables assignment, e.g. for a builder from `forPropertyAccessors`
  /// (Spring's `withAssignmentDisabled`).
  SimpleEvaluationContextBuilder withAssignmentDisabled() {
    _assignment = false;
    return this;
  }

  /// Creates the context; accessor and resolver lists are unmodifiable.
  SimpleEvaluationContext build() => SimpleEvaluationContext._(
    _root,
    List.unmodifiable(_accessors),
    List.unmodifiable([
      ..._resolvers,
      if (_instanceMethods) const BuiltinMethodResolver(),
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
