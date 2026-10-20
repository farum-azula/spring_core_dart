import 'dart:math' as math;

import 'package:spring_core_dart/src/expression/evaluation_context.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';

/// A type usable in `T(Name)`, `new Name(...)` and `instanceof`, registered
/// in a [StandardTypeLocator] (Dart cannot look up classes by name).
///
/// Statics and constructors are plain functions, so only what you register
/// is reachable from expressions.
///
/// ```dart
/// final locator = StandardTypeLocator()
///   ..registerType(SpelType.of<Point>(
///     'Point',
///     staticFields: {'ORIGIN': () => const Point(0, 0)},
///     staticMethods: {'parse': Point.parse},
///     constructors: {'': Point.new},
///   ));
/// final context = StandardEvaluationContext()..typeLocator = locator;
/// final parser = SpelExpressionParser();
/// parser.parseExpression('T(Point).ORIGIN').getValue(context);
/// parser.parseExpression("T(Point).parse('1,2')").getValue(context);
/// parser.parseExpression('new Point(1, 2)').getValue(context);
/// parser.parseExpression('#p instanceof T(Point)').getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring resolves classes by (fully qualified) name via reflection:
/// parser.parseExpression("T(com.example.Point).ORIGIN").getValue();
/// parser.parseExpression("new com.example.Point(1, 2)").getValue();
/// ```
final class SpelType {
  /// Creates a type named [name]; [isInstance] implements `instanceof`.
  ///
  /// Use [SpelType.of] when there is a Dart type; this constructor is for
  /// pseudo-types without instances such as `Math`.
  SpelType(
    this.name, {
    required this._isInstance,
    this.type,
    Map<String, Object? Function()> staticFields = const {},
    Map<String, Function> staticMethods = const {},
    Map<String, Function> constructors = const {},
  }) : staticFields = Map.unmodifiable(staticFields),
       staticMethods = Map.unmodifiable(staticMethods),
       constructors = Map.unmodifiable(constructors);

  /// A type for [T] (instance check from the type argument).
  ///
  /// ```dart
  /// SpelType.of<User>('User', constructors: {'': User.new});
  /// ```
  static SpelType of<T>(
    String name, {
    Map<String, Object? Function()> staticFields = const {},
    Map<String, Function> staticMethods = const {},
    Map<String, Function> constructors = const {},
  }) => SpelType(
    name,
    type: T,
    isInstance: (value) => value is T,
    staticFields: staticFields,
    staticMethods: staticMethods,
    constructors: constructors,
  );

  /// The name used in `T(name)` and `new name(...)`.
  final String name;

  /// The Dart type, if there is one (`Math` has none).
  final Type? type;
  final bool Function(Object? value) _isInstance;

  /// `T(Name).FIELD` values.
  final Map<String, Object? Function()> staticFields;

  /// `T(Name).method(args)` functions.
  final Map<String, Function> staticMethods;

  /// `new Name(args)` functions; `''` is the default constructor.
  final Map<String, Function> constructors;

  /// Whether [value] is an instance of this type (`instanceof`).
  bool isInstance(Object? value) => _isInstance(value);

  @override
  String toString() => 'T($name)';
}

/// Registry-based [TypeLocator], like Spring's `StandardTypeLocator`.
///
/// Pre-registered: `int`, `double`, `num`, `String`, `bool`, `Object`,
/// `List`, `Map`, `Set`, `DateTime`, `Duration`, `Math` (`PI`, `E`,
/// `max`, `min`, `abs`, `sqrt`, `pow`, `round`, `floor`, `ceil`, `random`).
///
/// ```dart
/// final context = StandardEvaluationContext()
///   ..typeLocator = (StandardTypeLocator()
///     ..registerType(SpelType.of<User>('User',
///         constructors: {'': User.new})));
/// final parser = SpelExpressionParser();
/// parser.parseExpression('T(Math).max(1, 2)').getValue(context); // 2
/// parser.parseExpression("new User('Ada')").getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring loads classes by name; java.lang types need no package.
/// context.setTypeLocator(new StandardTypeLocator(classLoader));
/// parser.parseExpression("T(Math).max(1, 2)").getValue(context);
/// parser.parseExpression("new com.example.User('Ada')").getValue(context);
/// ```
class StandardTypeLocator implements TypeLocator {
  /// Creates a locator with the pre-registered core types.
  StandardTypeLocator() {
    for (final type in _defaults()) {
      registerType(type);
    }
  }

  final _types = <String, SpelType>{};

  /// Adds or replaces [type].
  void registerType(SpelType type) => _types[type.name] = type;

  /// Names of the registered types.
  Iterable<String> get typeNames => _types.keys;

  @override
  SpelType findType(String typeName) =>
      _types[typeName] ??
      (throw SpelEvaluationException(
        SpelMessage.typeNotFound,
        "Type '$typeName' is not registered in the TypeLocator",
      ));

  static final _random = math.Random();

  // Core types with Java-flavoured statics (MAX_VALUE, valueOf, ofMillis,
  // ...) so typical Spring expressions keep working.
  static List<SpelType> _defaults() => [
    SpelType.of<int>(
      'int',
      // The largest integers exact on every platform (VM and JavaScript).
      staticFields: {
        'MAX_VALUE': () => 9007199254740991,
        'MIN_VALUE': () => -9007199254740991,
      },
      staticMethods: {
        'parse': int.parse,
        'tryParse': int.tryParse,
        'valueOf': int.parse,
      },
    ),
    SpelType.of<double>(
      'double',
      staticFields: {
        'MAX_VALUE': () => double.maxFinite,
        'NaN': () => double.nan,
        'INFINITY': () => double.infinity,
      },
      staticMethods: {'parse': double.parse, 'tryParse': double.tryParse},
    ),
    SpelType.of<num>('num', staticMethods: {'parse': num.parse}),
    SpelType.of<String>(
      'String',
      constructors: {'': ([Object? value = '']) => '$value'},
      staticMethods: {
        'valueOf': (Object? value) => '$value',
        'fromCharCode': String.fromCharCode,
      },
    ),
    SpelType.of<bool>(
      'bool',
      staticMethods: {'parse': (String v) => v.toLowerCase() == 'true'},
    ),
    SpelType.of<Object>('Object', constructors: {'': Object.new}),
    SpelType.of<List<Object?>>(
      'List',
      constructors: {'': () => <Object?>[]},
      staticMethods: {
        'of': (Iterable<Object?> items) => List<Object?>.of(items),
      },
    ),
    SpelType.of<Map<Object?, Object?>>(
      'Map',
      constructors: {'': () => <Object?, Object?>{}},
    ),
    SpelType.of<Set<Object?>>('Set', constructors: {'': () => <Object?>{}}),
    SpelType.of<DateTime>(
      'DateTime',
      constructors: {
        '': (
          int year, [
          int month = 1,
          int day = 1,
          int hour = 0,
          int minute = 0,
          int second = 0,
        ]) => DateTime(year, month, day, hour, minute, second),
      },
      staticMethods: {'now': DateTime.now, 'parse': DateTime.parse},
    ),
    SpelType.of<Duration>(
      'Duration',
      staticMethods: {
        'ofMillis': (int value) => Duration(milliseconds: value),
        'ofSeconds': (int value) => Duration(seconds: value),
        'ofMinutes': (int value) => Duration(minutes: value),
        'ofHours': (int value) => Duration(hours: value),
        'ofDays': (int value) => Duration(days: value),
      },
    ),
    SpelType(
      'Math',
      isInstance: (_) => false,
      staticFields: {'PI': () => math.pi, 'E': () => math.e},
      staticMethods: {
        'max': (num a, num b) => math.max(a, b),
        'min': (num a, num b) => math.min(a, b),
        'abs': (num a) => a.abs(),
        'sqrt': (num a) => math.sqrt(a),
        'pow': (num a, num b) => math.pow(a, b),
        'round': (num a) => a.round(),
        'floor': (num a) => a.floor(),
        'ceil': (num a) => a.ceil(),
        'random': _random.nextDouble,
      },
    ),
  ];
}

/// Resolves methods of registered types used as `T(Name).method(...)`.
///
/// Used automatically when the target of a method call is a [SpelType];
/// you do not need to register it.
///
/// ```dart
/// SpelExpressionParser()
///     .parseExpression("T(int).parse('42')")
///     .getValue(); // 42
/// ```
///
/// Spring (Java):
/// ```java
/// // Static methods are found reflectively on the Class object:
/// parser.parseExpression("T(Integer).parseInt('42')").getValue();
/// ```
final class SpelTypeMethodResolver implements MethodResolver {
  /// Creates the resolver (stateless).
  const SpelTypeMethodResolver();

  @override
  MethodExecutor? resolve(
    EvaluationContext context,
    Object target,
    String name,
    List<Object?> arguments,
  ) {
    if (target is! SpelType) {
      return null;
    }
    final function = target.staticMethods[name];
    return function == null
        ? null
        : (_, _, args) => Function.apply(function, args);
  }
}
