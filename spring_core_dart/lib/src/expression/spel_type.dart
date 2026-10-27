import 'dart:math' as math;

import 'package:spring_core_dart/src/core/env/platform_environment_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/env/platform_environment_io.dart';
import 'package:spring_core_dart/src/expression/evaluation_context.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/java_format.dart';
import 'package:spring_core_dart/src/expression/spel_numbers.dart';

/// A type usable in `T(Name)`, `new Name(...)`, `new Name[n]` and
/// `instanceof`, registered in a [StandardTypeLocator] (Dart cannot look up
/// classes by name).
///
/// Statics and constructors are plain functions (or [VarargsFunction]s),
/// so only what you register is reachable from expressions.
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
/// parser.parseExpression('new Point[2]').getValue(context); // [null, null]
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
    String name, {
    required bool Function(Object? value) isInstance,
    Type? type,
    Map<String, Object? Function()> staticFields = const {},
    Map<String, Object> staticMethods = const {},
    Map<String, Object> constructors = const {},
  }) : this._(
         name,
         isInstance,
         type,
         staticFields,
         staticMethods,
         constructors,
         _objectList,
         _objectListOf,
       );

  SpelType._(
    this.name,
    this._isInstance,
    this.type,
    Map<String, Object? Function()> staticFields,
    Map<String, Object> staticMethods,
    Map<String, Object> constructors,
    this._newList,
    this._listOf,
  ) : staticFields = Map.unmodifiable(staticFields),
      staticMethods = Map.unmodifiable(staticMethods),
      constructors = Map.unmodifiable(constructors);

  /// A type for [T] (instance check and array element type from the type
  /// argument).
  ///
  /// ```dart
  /// SpelType.of<User>('User', constructors: {'': User.new});
  /// ```
  static SpelType of<T>(
    String name, {
    Map<String, Object? Function()> staticFields = const {},
    Map<String, Object> staticMethods = const {},
    Map<String, Object> constructors = const {},
  }) => SpelType._(
    name,
    (value) => value is T,
    T,
    staticFields,
    staticMethods,
    constructors,
    (length, fill) => fill is T
        ? List<T>.filled(length, fill, growable: true)
        : List<T?>.filled(length, null, growable: true),
    (elements) => elements.every((e) => e is T)
        ? List<T>.of(elements.cast<T>())
        : List<T?>.of(elements.cast<T?>()),
  );

  static List<Object?> _objectList(int length, Object? fill) =>
      List<Object?>.filled(length, fill, growable: true);

  static List<Object?> _objectListOf(List<Object?> elements) =>
      List<Object?>.of(elements);

  /// The name used in `T(name)` and `new name(...)`.
  final String name;

  /// The Dart type, if there is one (`Math` has none).
  final Type? type;
  final bool Function(Object? value) _isInstance;
  final List<Object?> Function(int length, Object? fill) _newList;
  final List<Object?> Function(List<Object?> elements) _listOf;

  /// `T(Name).FIELD` values.
  final Map<String, Object? Function()> staticFields;

  /// `T(Name).method(args)` functions (Dart functions or
  /// [VarargsFunction]s).
  final Map<String, Object> staticMethods;

  /// `new Name(args)` functions (Dart functions or [VarargsFunction]s);
  /// `''` is the default constructor.
  final Map<String, Object> constructors;

  /// Whether [value] is an instance of this type (`instanceof`).
  bool isInstance(Object? value) => _isInstance(value);

  /// A growable list of [length] elements of this type, all [fill]
  /// (`new Name[length]`; a `List<T?>` when [fill] is `null`).
  List<Object?> newArray(int length, [Object? fill]) => _newList(length, fill);

  /// A list of this element type holding [elements] (`new Name[]{...}`;
  /// a `List<T?>` when an element is `null`).
  List<Object?> arrayOf(List<Object?> elements) => _listOf(elements);

  @override
  String toString() => 'T($name)';
}

/// A function taking a variable number of trailing arguments, like a Java
/// varargs method (`String.join(delimiter, String... elements)`).
///
/// Dart has no varargs: wrap the function and it is called with the first
/// [fixedArity] arguments followed by a `List` of the rest. Accepted by
/// `StandardEvaluationContext.registerFunction`, `SpelType.staticMethods`
/// and `SpelType.constructors`.
///
/// ```dart
/// context.registerFunction(
///   'sum',
///   VarargsFunction((List<Object?> numbers) =>
///       numbers.fold<num>(0, (a, b) => a + (b! as num))),
/// );
/// parser.parseExpression('#sum(1, 2, 3)').getValue(context); // 6
/// parser.parseExpression('#sum()').getValue(context); // 0
/// ```
///
/// Spring (Java):
/// ```java
/// public static int sum(int... numbers) { ... }
/// context.registerFunction("sum",
///     MathUtils.class.getMethod("sum", int[].class));
/// parser.parseExpression("#sum(1, 2, 3)").getValue(context); // 6
/// ```
final class VarargsFunction {
  /// Wraps [function], which takes [fixedArity] positional parameters
  /// followed by one `List<Object?>` parameter for the rest.
  const VarargsFunction(this.function, {this.fixedArity = 0});

  /// The wrapped function.
  final Function function;

  /// How many leading arguments are passed individually.
  final int fixedArity;

  /// Whether [function] (a Dart `Function` or a [VarargsFunction]) can be
  /// called with [count] positional arguments; `true` when this cannot be
  /// told (more than 8 arguments).
  static bool accepts(Object function, int count) => switch (function) {
    VarargsFunction(:final fixedArity) => count >= fixedArity,
    Function() => switch (count) {
      0 => function is Object? Function(),
      1 => function is Object? Function(Never),
      2 => function is Object? Function(Never, Never),
      3 => function is Object? Function(Never, Never, Never),
      4 => function is Object? Function(Never, Never, Never, Never),
      5 => function is Object? Function(Never, Never, Never, Never, Never),
      6 =>
        function is Object? Function(Never, Never, Never, Never, Never, Never),
      7 =>
        function
            is Object? Function(
              Never,
              Never,
              Never,
              Never,
              Never,
              Never,
              Never,
            ),
      8 =>
        function
            is Object? Function(
              Never,
              Never,
              Never,
              Never,
              Never,
              Never,
              Never,
              Never,
            ),
      _ => true,
    },
    _ => false,
  };

  /// The smallest number of arguments [function] accepts (for messages),
  /// or `null` when unknown.
  static int? minimumArity(Object function) {
    for (var count = 0; count <= 8; count++) {
      if (accepts(function, count)) {
        return count;
      }
    }
    return null;
  }

  /// [arguments] converted with [converter] to the parameter types of
  /// [function] where they do not fit, like Spring's
  /// `ReflectionHelper.convertAllArguments`: `#half(3)` with a `double`
  /// parameter gets `3.0`, `'abc'.substring('1')` gets `1`,
  /// `'abc'.charAt(1.0)` gets `1`. Dart has no reflection, so the
  /// parameter types are probed: `int`, `double`, `num`, `String` and
  /// `bool` parameters of the first [maxConvertedArity] positional
  /// parameters convert; an argument that cannot be converted is passed
  /// as it is (the call then fails as usual).
  static List<Object?> convertArguments(
    Object function,
    List<Object?> arguments,
    TypeConverter converter,
  ) {
    final (Function target, int count, int converted) = switch (function) {
      VarargsFunction(:final function, :final fixedArity) => (
        function,
        fixedArity + 1,
        fixedArity,
      ),
      final Function function => (function, arguments.length, arguments.length),
      _ => (_noFunction, 0, 0),
    };
    if (count > maxConvertedArity || converted > arguments.length) {
      return arguments;
    }
    List<Object?>? result;
    for (var i = 0; i < converted; i++) {
      final value = arguments[i];
      if (value == null || _accepts<Object?>(target, count, i)) {
        continue;
      }
      final Type? type;
      if (_accepts<int>(target, count, i) &&
          _accepts<double>(target, count, i)) {
        type = value is num ? null : num;
      } else if (_accepts<double>(target, count, i)) {
        type = value is double ? null : double;
      } else if (_accepts<int>(target, count, i)) {
        type = value is int ? null : int;
      } else if (_accepts<String>(target, count, i)) {
        type = value is String ? null : String;
      } else if (_accepts<bool>(target, count, i)) {
        type = value is bool ? null : bool;
      } else {
        type = null;
      }
      if (type == null) {
        continue;
      }
      try {
        final convertedValue = type == num
            ? _toNum(value, converter)
            : converter.convertValue(value, type);
        (result ??= [...arguments])[i] = convertedValue;
      } on Exception {
        // Not convertible: the call reports the mismatch.
      }
    }
    return result ?? arguments;
  }

  /// How many positional parameters [convertArguments] can probe.
  static const maxConvertedArity = 4;

  static void _noFunction() {}

  // A String into a `num` parameter: an int when it reads as one, else a
  // double (Java picks the overload; Dart has one `num`).
  static Object? _toNum(Object value, TypeConverter converter) {
    if (value is String) {
      return int.tryParse(value.trim()) ??
          converter.convertValue(value, double);
    }
    return converter.convertValue(value, double);
  }

  // Whether parameter [index] of [function], called with [count]
  // positional arguments, accepts an [X].
  static bool _accepts<X>(Function function, int count, int index) =>
      switch ((count, index)) {
        (1, 0) => function is Object? Function(X),
        (2, 0) => function is Object? Function(X, Never),
        (2, 1) => function is Object? Function(Never, X),
        (3, 0) => function is Object? Function(X, Never, Never),
        (3, 1) => function is Object? Function(Never, X, Never),
        (3, 2) => function is Object? Function(Never, Never, X),
        (4, 0) => function is Object? Function(X, Never, Never, Never),
        (4, 1) => function is Object? Function(Never, X, Never, Never),
        (4, 2) => function is Object? Function(Never, Never, X, Never),
        (4, 3) => function is Object? Function(Never, Never, Never, X),
        _ => true,
      };

  /// Calls [function] (a Dart `Function` or a [VarargsFunction]) with
  /// [arguments].
  ///
  /// Throws a `NoSuchMethodError` when the arguments do not fit, and
  /// whatever the function throws.
  static Object? apply(Object function, List<Object?> arguments) {
    switch (function) {
      case VarargsFunction(:final function, :final fixedArity):
        if (arguments.length < fixedArity) {
          throw NoSuchMethodError.withInvocation(
            function,
            Invocation.method(#call, arguments),
          );
        }
        return Function.apply(function, [
          ...arguments.take(fixedArity),
          arguments.sublist(fixedArity),
        ]);
      case Function():
        return Function.apply(function, arguments);
      default:
        throw NoSuchMethodError.withInvocation(
          function,
          Invocation.method(#call, arguments),
        );
    }
  }
}

/// Registry-based [TypeLocator], like Spring's `StandardTypeLocator`.
///
/// Pre-registered: the Dart types `int`, `double`, `num`, `String`,
/// `bool`, `Object`, `List`, `Map`, `Set`, `DateTime`, `Duration`, the
/// pseudo-type `Math` (Java's `java.lang.Math`), and Java names that map
/// onto Dart types: `Integer`, `Long`, `Short`, `Byte` (`int`), `Double`,
/// `Float` (`double`), `Number` (`num`), `Boolean` (`bool`), `long`,
/// `short`, `byte`, `float`, `boolean`, `ArrayList`, `HashMap`,
/// `LinkedHashMap`, `HashSet`, `LinkedHashSet`, `StringBuilder` and
/// `StringBuffer` (Dart's `StringBuffer`), plus the statics of `Objects`
/// (`isNull`, `requireNonNull`, `hash`, ...) and `System`
/// (`currentTimeMillis`, `nanoTime`, `getenv`; Dart has no system
/// properties, so `getProperty` returns its default). Names may carry an
/// import prefix (`java.lang.Integer`, `java.util.List`).
///
/// ```dart
/// final context = StandardEvaluationContext()
///   ..typeLocator = (StandardTypeLocator()
///     ..registerType(SpelType.of<User>('User',
///         constructors: {'': User.new})));
/// final parser = SpelExpressionParser();
/// parser.parseExpression('T(Math).max(1, 2)').getValue(context); // 2
/// parser.parseExpression("T(Integer).parseInt('7')").getValue(context);
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
  /// Creates a locator with the pre-registered types and the import
  /// prefixes `java.lang`, `java.util` and `dart.core`.
  StandardTypeLocator() {
    _defaults().forEach(registerType);
  }

  final _types = <String, SpelType>{};
  final _imports = <String>['java.lang', 'java.util', 'dart.core'];

  /// Adds or replaces [type].
  void registerType(SpelType type) => _types[type.name] = type;

  /// Names of the registered types.
  Iterable<String> get typeNames => _types.keys;

  /// Adds an import prefix (Spring's `registerImport`): `T(app.Point)`
  /// then finds a type registered as `Point`, and `T(Point)` one
  /// registered as `app.Point`.
  void registerImport(String prefix) => _imports.add(prefix);

  /// Removes an import prefix (Spring's `removeImport`).
  void removeImport(String prefix) => _imports.remove(prefix);

  /// The import prefixes (Spring's `getImportPrefixes`), unmodifiable.
  List<String> get importPrefixes => List.unmodifiable(_imports);

  @override
  SpelType findType(String typeName) {
    final exact = _types[typeName];
    if (exact != null) {
      return exact;
    }
    for (final prefix in _imports) {
      final candidate = typeName.startsWith('$prefix.')
          ? _types[typeName.substring(prefix.length + 1)]
          : _types['$prefix.$typeName'];
      if (candidate != null) {
        return candidate;
      }
    }
    throw SpelEvaluationException(
      SpelMessage.typeNotFound,
      inserts: [typeName],
    );
  }

  static final _random = math.Random();

  static num _widen(num a, num b, num result) =>
      a is double || b is double ? result.toDouble() : result;

  // Statics of Java's Integer / Long / Short / Byte.
  static SpelType _javaInteger(String name, int min, int max) =>
      SpelType.of<int>(
        name,
        // `new Integer(5)`, `new Long('5')`.
        constructors: {
          '': (Object value) =>
              value is int ? value : _parseJavaInt(value.toString()),
        },
        staticFields: {'MAX_VALUE': () => max, 'MIN_VALUE': () => min},
        staticMethods: {
          'parseInt': _parseJavaInt,
          'parseLong': _parseJavaInt,
          'valueOf': (Object value) =>
              value is int ? value : _parseJavaInt(value.toString()),
          'toString': (int value, [int radix = 10]) =>
              value.toRadixString(radix),
          'toHexString': (int value) => value.toRadixString(16),
          'toBinaryString': (int value) => value.toRadixString(2),
          'max': (int a, int b) => math.max(a, b),
          'min': (int a, int b) => math.min(a, b),
          'sum': (int a, int b) => a + b,
          'compare': (int a, int b) => a.compareTo(b),
          'signum': (int a) => a.sign,
          'abs': (int a) => a.abs(),
        },
      );

  static int _parseJavaInt(String value, [int radix = 10]) =>
      int.parse(value, radix: radix);

  static SpelType _javaDouble(String name) => SpelType.of<double>(
    name,
    constructors: {
      '': (Object value) =>
          value is num ? value.toDouble() : double.parse(value.toString()),
    },
    staticFields: {
      'MAX_VALUE': () => double.maxFinite,
      'MIN_VALUE': () => double.minPositive,
      'NaN': () => double.nan,
      'POSITIVE_INFINITY': () => double.infinity,
      'NEGATIVE_INFINITY': () => double.negativeInfinity,
    },
    staticMethods: {
      'parseDouble': double.parse,
      'parseFloat': double.parse,
      'valueOf': (Object value) =>
          value is num ? value.toDouble() : double.parse(value.toString()),
      'isNaN': (num value) => value.isNaN,
      'isInfinite': (num value) => value.isInfinite,
      'isFinite': (num value) => value.isFinite,
      'max': (num a, num b) => math.max(a, b).toDouble(),
      'min': (num a, num b) => math.min(a, b).toDouble(),
      'sum': (num a, num b) => (a + b).toDouble(),
      'compare': (num a, num b) => a.compareTo(b),
    },
  );

  static SpelType _javaBoolean(String name) => SpelType.of<bool>(
    name,
    constructors: {
      '': (Object? value) =>
          value is bool ? value : '$value'.toLowerCase() == 'true',
    },
    staticFields: {'TRUE': () => true, 'FALSE': () => false},
    staticMethods: {
      'parseBoolean': (String? value) => value?.toLowerCase() == 'true',
      'valueOf': (Object? value) =>
          value is bool ? value : '$value'.toLowerCase() == 'true',
      'logicalAnd': (bool a, bool b) => a && b,
      'logicalOr': (bool a, bool b) => a || b,
      'logicalXor': (bool a, bool b) => a != b,
    },
  );

  // Java's Character, over single-character strings (SpEL has no char
  // literals: 'a' is a String).
  static SpelType _javaCharacter(String name) => SpelType(
    name,
    isInstance: (value) => value is String && value.length == 1,
    type: String,
    staticFields: {'MIN_VALUE': () => '\u0000', 'MAX_VALUE': () => '\uffff'},
    staticMethods: {
      'isDigit': (String c) => _single(c, RegExp(r'^\p{Nd}$', unicode: true)),
      'isLetter': (String c) => _single(c, RegExp(r'^\p{L}$', unicode: true)),
      'isLetterOrDigit': (String c) =>
          _single(c, RegExp(r'^[\p{L}\p{Nd}]$', unicode: true)),
      'isWhitespace': (String c) => _single(c, RegExp(r'^\s$')),
      'isUpperCase': (String c) => c.toUpperCase() == c && c.toLowerCase() != c,
      'isLowerCase': (String c) => c.toLowerCase() == c && c.toUpperCase() != c,
      'toUpperCase': (String c) => c.toUpperCase(),
      'toLowerCase': (String c) => c.toLowerCase(),
      'valueOf': (Object? c) => '$c',
      'toString': (Object? c) => '$c',
      'getNumericValue': (String c) => int.tryParse(c, radix: 36) ?? -1,
    },
  );

  static bool _single(String c, RegExp pattern) => pattern.hasMatch(c);

  static SpelType _list(String name) => SpelType.of<List<Object?>>(
    name,
    constructors: {
      '': ([Object? source]) =>
          source is Iterable ? List<Object?>.of(source) : <Object?>[],
    },
    staticMethods: {
      // Java's List.of(E...): an unmodifiable list of the arguments.
      'of': const VarargsFunction(List<Object?>.unmodifiable),
      'copyOf': (Iterable<Object?> items) => List<Object?>.unmodifiable(items),
    },
  );

  static SpelType _map(String name) => SpelType.of<Map<Object?, Object?>>(
    name,
    constructors: {
      '': ([Map<Object?, Object?>? source]) =>
          source == null ? <Object?, Object?>{} : {...source},
    },
    staticMethods: {
      // Java's Map.of(k1, v1, k2, v2, ...).
      'of': VarargsFunction((List<Object?> keysAndValues) {
        if (keysAndValues.length.isOdd) {
          throw ArgumentError('Map.of needs keys and values in pairs');
        }
        return Map<Object?, Object?>.unmodifiable({
          for (var i = 0; i < keysAndValues.length; i += 2)
            keysAndValues[i]: keysAndValues[i + 1],
        });
      }),
      'copyOf': (Map<Object?, Object?> map) =>
          Map<Object?, Object?>.unmodifiable(map),
    },
  );

  static SpelType _set(String name) => SpelType.of<Set<Object?>>(
    name,
    constructors: {
      '': ([Object? source]) =>
          source is Iterable ? Set<Object?>.of(source) : <Object?>{},
    },
    staticMethods: {
      // Java's Set.of(E...).
      'of': const VarargsFunction(Set<Object?>.unmodifiable),
      'copyOf': (Iterable<Object?> items) => Set<Object?>.unmodifiable(items),
    },
  );

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
        // Java's String.format(format, args...).
        'format': VarargsFunction(
          (Object? format, List<Object?> args) => javaFormat('$format', args),
          fixedArity: 1,
        ),
        'fromCharCodes': (Iterable<int> codes) => String.fromCharCodes(codes),
        // Java's String.join(delimiter, elements...) or (delimiter,
        // iterable).
        'join': VarargsFunction((Object? delimiter, List<Object?> elements) {
          final items = elements.length == 1 && elements.single is Iterable
              ? elements.single! as Iterable<Object?>
              : elements;
          return items.join('$delimiter');
        }, fixedArity: 1),
      },
    ),
    SpelType.of<bool>(
      'bool',
      staticMethods: {'parse': (String v) => v.toLowerCase() == 'true'},
    ),
    SpelType.of<Object>('Object', constructors: {'': Object.new}),
    _list('List'),
    _list('ArrayList'),
    _map('Map'),
    _map('HashMap'),
    _map('LinkedHashMap'),
    _set('Set'),
    _set('HashSet'),
    _set('LinkedHashSet'),
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
    // Java names mapped onto Dart types.
    _javaInteger('Integer', -2147483648, 2147483647),
    _javaInteger('Long', minJavaLong, maxJavaLong),
    _javaInteger('Short', -32768, 32767),
    _javaInteger('Byte', -128, 127),
    _javaInteger('long', minJavaLong, maxJavaLong),
    _javaInteger('short', -32768, 32767),
    _javaInteger('byte', -128, 127),
    _javaDouble('Double'),
    _javaDouble('Float'),
    _javaDouble('float'),
    SpelType.of<num>('Number'),
    _javaBoolean('Boolean'),
    _javaBoolean('boolean'),
    _javaCharacter('Character'),
    _javaCharacter('char'),
    _javaObjects(),
    _javaSystem(),
    // java.lang.StringBuilder / StringBuffer: a Dart StringBuffer with
    // Java's methods (`append` returns the builder; see
    // BuiltinMethodResolver).
    _stringBuilder('StringBuilder'),
    _stringBuilder('StringBuffer'),
    // java.lang.Math: real functions return doubles, like Java.
    SpelType(
      'Math',
      isInstance: (_) => false,
      staticFields: {'PI': () => math.pi, 'E': () => math.e},
      staticMethods: {
        'max': (num a, num b) => _widen(a, b, math.max(a, b)),
        'min': (num a, num b) => _widen(a, b, math.min(a, b)),
        'abs': (num a) => a.abs(),
        'sqrt': (num a) => math.sqrt(a),
        'cbrt': (num a) => a < 0
            ? -math.pow(-a.toDouble(), 1 / 3).toDouble()
            : math.pow(a.toDouble(), 1 / 3).toDouble(),
        'pow': (num a, num b) => math.pow(a.toDouble(), b.toDouble()),
        'exp': (num a) => math.exp(a),
        'log': (num a) => math.log(a),
        'log10': (num a) => math.log(a) / math.ln10,
        'sin': (num a) => math.sin(a),
        'cos': (num a) => math.cos(a),
        'tan': (num a) => math.tan(a),
        'asin': (num a) => math.asin(a),
        'acos': (num a) => math.acos(a),
        'atan': (num a) => math.atan(a),
        'atan2': (num y, num x) => math.atan2(y, x),
        'hypot': (num x, num y) => math.sqrt(x * x + y * y),
        'toRadians': (num a) => a * math.pi / 180,
        'toDegrees': (num a) => a * 180 / math.pi,
        // Java: round(x) is floor(x + 0.5) as a long; floor and ceil are
        // doubles.
        'round': (num a) =>
            a is int ? a : toJavaLong((a + 0.5).floorToDouble()),
        'floor': (num a) => a.toDouble().floorToDouble(),
        'ceil': (num a) => a.toDouble().ceilToDouble(),
        'rint': (num a) => _rint(a.toDouble()),
        'signum': (num a) => a.toDouble().sign,
        'floorDiv': _floorDiv,
        'floorMod': (int a, int b) => a - _floorDiv(a, b) * b,
        'random': _random.nextDouble,
      },
    ),
  ];

  static SpelType _stringBuilder(String name) => SpelType.of<StringBuffer>(
    name,
    // `new StringBuilder()`, `new StringBuilder('abc')`, and Java's
    // capacity `new StringBuilder(16)` (empty).
    constructors: {
      '': ([Object? initial]) => initial == null || initial is int
          ? StringBuffer()
          : StringBuffer('$initial'),
    },
  );

  // java.util.Objects.
  static SpelType _javaObjects() => SpelType(
    'Objects',
    isInstance: (_) => false,
    staticMethods: {
      'equals': (Object? a, Object? b) => a == b,
      'deepEquals': (Object? a, Object? b) => _deepEquals(a, b),
      'hashCode': (Object? value) => value?.hashCode ?? 0,
      'hash': const VarargsFunction(Object.hashAll),
      'toString': (Object? value, [String? nullDefault]) =>
          value == null ? nullDefault ?? 'null' : '$value',
      'isNull': (Object? value) => value == null,
      'nonNull': (Object? value) => value != null,
      'requireNonNull': (Object? value, [String? message]) =>
          value ?? (throw ArgumentError(message ?? 'null')),
      'requireNonNullElse': (Object? value, Object? fallback) =>
          value ??
          fallback ??
          (throw ArgumentError('defaultObj must not be null')),
      'checkIndex': (int index, int length) {
        RangeError.checkValidIndex(index, null, 'index', length);
        return index;
      },
    },
  );

  static bool _deepEquals(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) {
        return false;
      }
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }

  // java.lang.System: the clock and environment variables (none on the
  // web). Dart has no system properties: getProperty gives the default.
  static SpelType _javaSystem() => SpelType(
    'System',
    isInstance: (_) => false,
    staticMethods: {
      'currentTimeMillis': () => DateTime.now().millisecondsSinceEpoch,
      'nanoTime': () => DateTime.now().microsecondsSinceEpoch * 1000,
      'getenv': ([String? name]) {
        final environment = platformEnvironment();
        return name == null
            ? Map<String, String>.of(environment)
            : environment[name];
      },
      'getProperty': (String name, [String? fallback]) => fallback,
      'lineSeparator': () => '\n',
      'identityHashCode': (Object? value) => identityHashCode(value),
    },
  );

  // Java's Math.rint: the closest integral double, ties to the even one
  // (Dart's roundToDouble rounds ties away from zero); the sign of a zero
  // result is the argument's (`rint(-0.4)` is `-0.0`).
  static double _rint(double a) {
    if (!a.isFinite || a.abs() >= 4503599627370496) {
      return a; // 2^52 and above: already integral
    }
    final floor = a.floorToDouble();
    final fraction = a - floor;
    final result = fraction < 0.5
        ? floor
        : fraction > 0.5
        ? floor + 1
        : (floor % 2 == 0 ? floor : floor + 1);
    return result == 0 ? (a.isNegative ? -0.0 : 0.0) : result;
  }

  // Java's Math.floorDiv: the quotient rounded towards negative infinity.
  static int _floorDiv(int a, int b) {
    final quotient = a ~/ b;
    return a.remainder(b) != 0 && (a < 0) != (b < 0) ? quotient - 1 : quotient;
  }
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
    if (function == null ||
        !VarargsFunction.accepts(function, arguments.length)) {
      return null;
    }
    return (context, _, args) => callChecked(
      function,
      VarargsFunction.convertArguments(function, args, context.typeConverter),
      () => SpelEvaluationException(
        SpelMessage.methodNotFound,
        inserts: ['$name(${_types(args)})', target],
      ),
    );
  }

  /// Calls [function] with [arguments]; a `NoSuchMethodError` or
  /// `TypeError` (arguments that do not fit, as Dart cannot tell them from
  /// errors inside the function) becomes [notFound]; anything else the
  /// function throws propagates unchanged.
  static Object? callChecked(
    Object function,
    List<Object?> arguments,
    SpelEvaluationException Function() notFound,
  ) {
    try {
      return VarargsFunction.apply(function, arguments);
    } on NoSuchMethodError catch (error, stackTrace) {
      Error.throwWithStackTrace(_withCause(notFound(), error), stackTrace);
    } on TypeError catch (error, stackTrace) {
      Error.throwWithStackTrace(_withCause(notFound(), error), stackTrace);
    }
  }

  static SpelEvaluationException _withCause(
    SpelEvaluationException error,
    Object cause,
  ) => SpelEvaluationException(
    error.messageCode,
    inserts: error.inserts,
    cause: cause,
  );

  static String _types(List<Object?> args) =>
      args.map((a) => a == null ? 'null' : '${a.runtimeType}').join(',');
}

/// Resolves `new Name(...)` with the constructors registered on a
/// [SpelType], the counterpart of Spring's `ReflectiveConstructorResolver`.
///
/// Registered by default in `StandardEvaluationContext`. A
/// `NoSuchMethodError` or `TypeError` from the call (arguments that do not
/// fit) is reported as `SpelMessage.constructorNotFound`; anything else the
/// constructor throws propagates unchanged, like Spring.
///
/// ```dart
/// final context = StandardEvaluationContext()
///   ..typeLocator = (StandardTypeLocator()
///     ..registerType(SpelType.of<Point>('Point',
///         constructors: {'': Point.new})));
/// SpelExpressionParser().parseExpression('new Point(1, 2)')
///     .getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// // ReflectiveConstructorResolver finds Point(int, int) by reflection.
/// parser.parseExpression("new com.example.Point(1, 2)").getValue(context);
/// ```
final class SpelTypeConstructorResolver implements ConstructorResolver {
  /// Creates the resolver (stateless).
  const SpelTypeConstructorResolver();

  @override
  ConstructorExecutor? resolve(
    EvaluationContext context,
    String typeName,
    List<Object?> arguments,
  ) {
    final type = context.typeLocator.findType(typeName);
    final constructor = type.constructors[''];
    if (constructor == null ||
        !VarargsFunction.accepts(constructor, arguments.length)) {
      return null;
    }
    return (context, args) => SpelTypeMethodResolver.callChecked(
      constructor,
      VarargsFunction.convertArguments(
        constructor,
        args,
        context.typeConverter,
      ),
      () => SpelEvaluationException(
        SpelMessage.constructorNotFound,
        inserts: [typeName, '(${SpelTypeMethodResolver._types(args)})'],
      ),
    );
  }
}
