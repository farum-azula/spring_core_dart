import 'dart:math' as math;

import 'package:spring_core_dart/src/expression/evaluation_context.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/spel_numbers.dart';

/// The operators of SpEL as plain functions: what an expression computes
/// for `/`, `==`, `<`, `+` on text, `and` and the like, apart from the
/// tree that holds the operands.
///
/// The interpreter calls them for every operator, and so does the code the
/// generator writes when it compiles an expression to Dart, so both give
/// the same answer (`7 / 2` is `3`, `1 == 1.0`, `null < 1`, `'a' + null`
/// is `a` and the text `null`). Applications do not call them; they appear
/// in generated code. A function throws the `SpelEvaluationException` the
/// interpreter reports, without the expression and position the
/// interpreter adds to it.
///
/// ```dart
/// // What the compiled form of `#a / #b` and `#a == #b` runs.
/// SpelOperations.divideInts(7, 2); // 3
/// SpelOperations.equals(1, 1.0); // true
/// SpelOperations.compare(null, 1) < 0; // true
/// SpelOperations.concat('n=', 1); // n=1
/// ```
///
/// Spring (Java):
/// ```java
/// // The compiler mode of SpelExpression generates bytecode for them
/// // (OpDivide, OpEQ, OpLT, OpPlus, ...).
/// ```
abstract final class SpelOperations {
  // The context of the interpreter supplies these; compiled code has none.
  static final TypeConverter _converter = StandardTypeConverter();

  static const _maxInt = 2147483647;
  static const _minInt = -2147483648;

  static bool _isLong(int value) => value > _maxInt || value < _minInt;

  // Java's `(int)` cast of a double: NaN is 0, out-of-range values
  // saturate.
  static int _toJavaInt(double value) => value.isNaN
      ? 0
      : value >= _maxInt
      ? _maxInt
      : value <= _minInt
      ? _minInt
      : value.truncate();

  // Java's ArithmeticException for an integer division by zero, the same
  // on the VM and the web (where `~/ 0` fails differently).
  static int _nonZero(int divisor) =>
      divisor == 0 ? throw UnsupportedError('/ by zero') : divisor;

  /// Applies the arithmetic [operation] to two numbers.
  ///
  /// `+`, `-` and `*` are Dart's. `/` truncates toward zero for two ints
  /// and throws an `UnsupportedError` for a zero divisor, like Java's
  /// `ArithmeticException`; with a real operand it gives a double. `%`
  /// keeps the sign of the left operand (`-7 % 3` is `-1`). `^` is
  /// computed as a double and, for two ints, truncated like Java's cast:
  /// `2 ^ -1` is `0`, `2 ^ 100` the largest `int`.
  ///
  /// [leftReal] and [rightReal] mark an operand that is a real number (a
  /// Java `double`) although it is an `int` at run time, as `7.0` is on
  /// the web.
  ///
  /// ```dart
  /// SpelOperations.numeric(Operation.divide, 7, 2); // 3
  /// SpelOperations.numeric(Operation.divide, 7, 2, leftReal: true); // 3.5
  /// SpelOperations.numeric(Operation.modulus, -7, 3); // -1
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// // OpDivide, OpModulus, OpPower
  /// parser.parseExpression("-7 % 3").getValue(); // -1
  /// ```
  static num numeric(
    Operation operation,
    num l,
    num r, {
    bool leftReal = false,
    bool rightReal = false,
  }) {
    final ints = l is int && !leftReal && r is int && !rightReal;
    switch (operation) {
      case Operation.add:
        return l + r;
      case Operation.subtract:
        return l - r;
      case Operation.multiply:
        return l * r;
      case Operation.divide:
        // Java-like integer division: two ints truncate toward zero (and
        // throw on zero, like Java's ArithmeticException); any double
        // gives a double (1 / 0.0 = Infinity).
        if (ints) {
          return l ~/ _nonZero(r);
        }
        return l.toDouble() / r.toDouble();
      case Operation.modulus:
        // remainder (not Dart's %) keeps the sign of the dividend, like
        // Java: -7 % 3 == -1.
        return ints
            ? l.remainder(_nonZero(r))
            : l.toDouble().remainder(r.toDouble());
      case Operation.power:
        // Spring 7's OpPower: a double when an operand is real;
        // otherwise Math.pow cast to long when above Integer.MAX_VALUE
        // or an operand is a long (here: outside the int range), else
        // cast to int, which saturates at Integer.MIN_VALUE.
        final result = math.pow(l.toDouble(), r.toDouble()).toDouble();
        if (!ints) {
          return result;
        }
        return result > _maxInt || _isLong(l) || _isLong(r)
            ? toJavaLong(result)
            : _toJavaInt(result);
    }
  }

  /// `l / r` for two ints: truncating, and an `UnsupportedError` when [r]
  /// is zero.
  static int divideInts(int l, int r) => numeric(Operation.divide, l, r) as int;

  /// `l % r` for two ints: the sign of [l], an `UnsupportedError` when [r]
  /// is zero.
  static int modulusInts(int l, int r) =>
      numeric(Operation.modulus, l, r) as int;

  /// `l ^ r` for two ints: the power truncated to an int (or a long).
  static int powerInts(int l, int r) => numeric(Operation.power, l, r) as int;

  /// `l % r` when an operand is a real number: a double.
  static double modulusReals(num l, num r) =>
      l.toDouble().remainder(r.toDouble());

  /// `l ^ r` when an operand is a real number: a double.
  static double powerReals(num l, num r) =>
      math.pow(l.toDouble(), r.toDouble()).toDouble();

  /// `l / r` for numbers of which it is not known whether both are ints
  /// (see [numeric], also for [leftReal] and [rightReal]).
  static num divide(
    num l,
    num r, {
    bool leftReal = false,
    bool rightReal = false,
  }) => numeric(
    Operation.divide,
    l,
    r,
    leftReal: leftReal,
    rightReal: rightReal,
  );

  /// `l % r` for numbers of which it is not known whether both are ints
  /// (see [numeric]).
  static num modulus(
    num l,
    num r, {
    bool leftReal = false,
    bool rightReal = false,
  }) => numeric(
    Operation.modulus,
    l,
    r,
    leftReal: leftReal,
    rightReal: rightReal,
  );

  /// `l ^ r` for numbers of which it is not known whether both are ints
  /// (see [numeric]).
  static num power(
    num l,
    num r, {
    bool leftReal = false,
    bool rightReal = false,
  }) => numeric(
    Operation.power,
    l,
    r,
    leftReal: leftReal,
    rightReal: rightReal,
  );

  /// The text of [value] as the other side of a `+` on a string: `null`
  /// is `'null'`, a real number that is an `int` at run time ([real]) is
  /// Java's `7.0`, anything else is converted by [typeConverter] (a list
  /// becomes `1,2`) and printed with `toString` when it cannot be.
  ///
  /// ```dart
  /// SpelOperations.text(null); // null
  /// SpelOperations.text([1, 2]); // 1,2
  /// ```
  static String text(
    Object? value, {
    bool real = false,
    TypeConverter? typeConverter,
  }) {
    if (value == null) {
      return 'null';
    }
    // A real number that is an `int` at run time (the web): Java's `7.0`.
    if (real && value is int) {
      return javaRealString(value);
    }
    final converter = typeConverter ?? _converter;
    if (converter.canConvert(value, String)) {
      final converted = converter.convertValue(value, String);
      if (converted is String) {
        return converted;
      }
    }
    return '$value';
  }

  /// Java's `Double.toString` of [value], what `toString()` of a real
  /// number gives: `2.5`, and `7.0` also where an integral double is an
  /// `int` at run time (the web, where Dart prints `7`).
  ///
  /// ```dart
  /// SpelOperations.doubleToString(7.0); // 7.0
  /// ```
  static String doubleToString(double value) {
    final Object boxed = value;
    return boxed is int ? javaRealString(boxed) : '$value';
  }

  /// [l] followed by [r], failing with
  /// `SpelMessage.maxConcatenatedStringLengthExceeded` beyond
  /// `SpelLimits.maxConcatenatedStringLength` characters.
  static String join(String l, String r) {
    if (l.length + r.length > SpelLimits.maxConcatenatedStringLength) {
      throw SpelEvaluationException(
        SpelMessage.maxConcatenatedStringLengthExceeded,
        inserts: [SpelLimits.maxConcatenatedStringLength],
      );
    }
    return '$l$r';
  }

  /// `l + r` when one side is a string: the other side is turned into text
  /// with [text] ([leftReal] and [rightReal] as in [numeric]).
  ///
  /// ```dart
  /// SpelOperations.concat('a', 1); // a1
  /// SpelOperations.concat(null, 'b'); // nullb
  /// ```
  static String concat(
    Object? l,
    Object? r, {
    bool leftReal = false,
    bool rightReal = false,
    TypeConverter? typeConverter,
  }) => join(
    l is String ? l : text(l, real: leftReal, typeConverter: typeConverter),
    r is String ? r : text(r, real: rightReal, typeConverter: typeConverter),
  );

  /// [value] as a `bool` for `and`, `or`, `!` and the condition of `? :`:
  /// a `bool` as it is, anything [typeConverter] can turn into one
  /// (`'true'`) converted; `null` and other values fail with
  /// `SpelMessage.typeConversionError`.
  ///
  /// ```dart
  /// SpelOperations.toBool(true); // true
  /// SpelOperations.toBool('true'); // true
  /// SpelOperations.toBool(null); // throws
  /// ```
  static bool toBool(Object? value, [TypeConverter? typeConverter]) {
    if (value is bool) {
      return value;
    }
    final converter = typeConverter ?? _converter;
    if (value != null && converter.canConvert(value, bool)) {
      final converted = converter.convertValue(value, bool);
      if (converted is bool) {
        return converted;
      }
    }
    throw SpelEvaluationException(
      SpelMessage.typeConversionError,
      inserts: [_typeName(value), 'bool'],
    );
  }

  /// The `==` of SpEL, also used by `!=`: numbers are equal by value
  /// (`1 == 1.0`), collections deeply (lists in order, sets and maps by
  /// content, with numbers inside compared like Java's `equals`, so
  /// `{2.0} == {2}` is `false`), other values by `==` or, for comparable
  /// values of the same type, `compareTo == 0`, like Spring.
  ///
  /// [comparator] orders the comparable values. [isRealElement] tells
  /// whether the number at `key` of a collection is a real number although
  /// it is an `int` at run time (the web), for collections the interpreter
  /// built; none by default.
  ///
  /// ```dart
  /// SpelOperations.equals(1, 1.0); // true
  /// SpelOperations.equals([1, 2], [1, 2]); // true
  /// SpelOperations.equals('a', null); // false
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// // OpEQ: equal(context, left, right)
  /// parser.parseExpression("{1, 2} == {1, 2}").getValue(); // true
  /// ```
  static bool equals(
    Object? l,
    Object? r, {
    TypeComparator comparator = const StandardTypeComparator(),
    bool Function(Object collection, Object? key, Object? value)? isRealElement,
  }) {
    // Numbers compare by value like Spring's OpEQ (`1 == 1.0`), with
    // Java's double semantics: NaN equals nothing, `0.0 == -0.0`.
    if (l is num && r is num) {
      return l == r;
    }
    if (_deepEquals(l, r, isRealElement)) {
      return true;
    }
    if (l is Comparable &&
        r is Comparable &&
        l.runtimeType == r.runtimeType &&
        comparator.canCompare(l, r)) {
      return comparator.compare(l, r) == 0;
    }
    return false;
  }

  // Java's equals for collections: List.equals is ordered and
  // element-wise, Set.equals and Map.equals compare contents.
  static bool _deepEquals(
    Object? l,
    Object? r,
    bool Function(Object collection, Object? key, Object? value)? isRealElement,
  ) {
    if (identical(l, r)) {
      return true;
    }
    if (l is List && r is List) {
      if (l.length != r.length) {
        return false;
      }
      for (var i = 0; i < l.length; i++) {
        if (!_elementEquals(l, i, l[i], r, i, r[i], isRealElement)) {
          return false;
        }
      }
      return true;
    }
    if (l is Set && r is Set) {
      return l.length == r.length &&
          l.every(
            (a) => r.any(
              (b) => _elementEquals(l, null, a, r, null, b, isRealElement),
            ),
          );
    }
    if (l is Map && r is Map) {
      if (l.length != r.length) {
        return false;
      }
      for (final MapEntry(:key, :value) in l.entries) {
        if (!r.containsKey(key) ||
            !_elementEquals(l, key, value, r, key, r[key], isRealElement)) {
          return false;
        }
      }
      return true;
    }
    return l == r;
  }

  // Java's equals of two elements: numbers are equal only when of the same
  // kind (`{2.0} == {2}` is false: Double.equals(Integer) is false), reals
  // like Double.equals (NaN equals NaN, 0.0 does not equal -0.0). On the
  // web an integral real is an `int`; the marks of collections SpEL built
  // tell them apart.
  static bool _elementEquals(
    Object lc,
    Object? lk,
    Object? l,
    Object rc,
    Object? rk,
    Object? r,
    bool Function(Object collection, Object? key, Object? value)? isRealElement,
  ) {
    if (l is num && r is num) {
      final lReal =
          l is double &&
          (l is! int || (isRealElement?.call(lc, lk, l) ?? false));
      final rReal =
          r is double &&
          (r is! int || (isRealElement?.call(rc, rk, r) ?? false));
      if (lReal != rReal) {
        return false;
      }
      return lReal ? l.compareTo(r.toDouble()) == 0 : l == r;
    }
    return _deepEquals(l, r, isRealElement);
  }

  /// Negative, zero or positive as [l] is less than, equal to or greater
  /// than [r], for `<`, `<=`, `>` and `>=`: `null` comes before everything,
  /// numbers compare by value, and values that cannot be ordered fail with
  /// `SpelMessage.notComparable`. [comparator] decides, the standard one
  /// by default.
  ///
  /// ```dart
  /// SpelOperations.compare(1, 2.5) < 0; // true
  /// SpelOperations.compare(null, 'a') < 0; // true
  /// SpelOperations.compare('a', 1); // throws
  /// ```
  ///
  /// Spring (Java):
  /// ```java
  /// // OpLT, OpLE, OpGT, OpGE: context.getTypeComparator().compare(l, r)
  /// ```
  static int compare(
    Object? l,
    Object? r, [
    TypeComparator comparator = const StandardTypeComparator(),
  ]) {
    if (!comparator.canCompare(l, r)) {
      throw SpelEvaluationException(
        SpelMessage.notComparable,
        inserts: [_typeName(l), _typeName(r)],
      );
    }
    return comparator.compare(l, r);
  }

  /// The element at [index] of [list], failing with
  /// `SpelMessage.collectionIndexOutOfBounds` outside it (also for a
  /// negative [index]), as `list[index]` does.
  ///
  /// ```dart
  /// SpelOperations.listElement(['a', 'b'], 1); // b
  /// SpelOperations.listElement(['a', 'b'], 2); // throws
  /// ```
  static E listElement<E>(List<E> list, int index) {
    if (index < 0 || index >= list.length) {
      throw SpelEvaluationException(
        SpelMessage.collectionIndexOutOfBounds,
        inserts: [list.length, index],
      );
    }
    return list[index];
  }

  /// The character at [index] of [text], failing with
  /// `SpelMessage.stringIndexOutOfBounds` outside it, as `'text'[index]`
  /// does.
  ///
  /// ```dart
  /// SpelOperations.stringElement('abc', 1); // b
  /// ```
  static String stringElement(String text, int index) {
    if (index < 0 || index >= text.length) {
      throw SpelEvaluationException(
        SpelMessage.stringIndexOutOfBounds,
        inserts: [text.length, index],
      );
    }
    return text[index];
  }

  // The type name of [value] for messages (`null` for `null`).
  static String _typeName(Object? value) =>
      value == null ? 'null' : '${value.runtimeType}';
}
