import 'package:spring_core_dart/src/expression/evaluation_context.dart';

/// Reads and writes map entries as properties (`map.key`), like Spring's
/// `MapAccessor`.
///
/// Registered by default in [StandardEvaluationContext] and
/// [SimpleEvaluationContext]. Reading needs an existing key; writing
/// always succeeds on a map.
///
/// ```dart
/// final data = {'user': {'name': 'Ada'}};
/// SpelExpressionParser()
///     .parseExpression('user.name')
///     .getValue(null, data); // 'Ada'
/// ```
///
/// Spring (Java):
/// ```java
/// StandardEvaluationContext context = new StandardEvaluationContext(data);
/// context.addPropertyAccessor(new MapAccessor());
/// parser.parseExpression("user.name").getValue(context);
/// ```
final class MapAccessor implements PropertyAccessor {
  /// Creates the accessor (stateless).
  const MapAccessor();

  @override
  bool canRead(EvaluationContext context, Object target, String name) =>
      target is Map && target.containsKey(name);

  @override
  Object? read(EvaluationContext context, Object target, String name) =>
      (target as Map)[name];

  @override
  bool canWrite(EvaluationContext context, Object target, String name) =>
      target is Map<String, Object?> || target is Map<Object?, Object?>;

  @override
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  ) => (target as Map)[name] = newValue;
}

/// Getters (and setters) for objects of type [T], from functions.
///
/// The reflection-free way to expose properties of your own classes;
/// `IntrospectionPropertyAccessor` does the same from generated metadata.
///
/// ```dart
/// final context = StandardEvaluationContext(user)
///   ..addPropertyAccessor(FunctionPropertyAccessor<User>(
///     getters: {'name': (u) => u.name},
///     setters: {'name': (u, v) => u.name = v! as String},
///   ));
/// SpelExpressionParser().parseExpression('name').getValue(context);
/// SpelExpressionParser()
///     .parseExpression("name = 'Ada'")
///     .getValue(context);
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring reads getName()/setName() by reflection
/// // (ReflectivePropertyAccessor), so no registration is needed:
/// parser.parseExpression("name")
///     .getValue(new StandardEvaluationContext(user));
/// ```
final class FunctionPropertyAccessor<T extends Object>
    implements PropertyAccessor {
  /// Exposes [getters] (readable properties) and [setters] (writable
  /// properties) of `T`, keyed by property name.
  FunctionPropertyAccessor({
    Map<String, Object? Function(T target)> getters = const {},
    Map<String, void Function(T target, Object? value)> setters = const {},
  }) : _getters = Map.unmodifiable(getters),
       _setters = Map.unmodifiable(setters);

  final Map<String, Object? Function(T target)> _getters;
  final Map<String, void Function(T target, Object? value)> _setters;

  @override
  bool canRead(EvaluationContext context, Object target, String name) =>
      target is T && _getters.containsKey(name);

  @override
  Object? read(EvaluationContext context, Object target, String name) =>
      _getters[name]!(target as T);

  @override
  bool canWrite(EvaluationContext context, Object target, String name) =>
      target is T && _setters.containsKey(name);

  @override
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  ) => _setters[name]!(target as T, newValue);
}

/// Methods of objects of type [T], from functions taking the target and
/// the evaluated arguments.
///
/// ```dart
/// final context = StandardEvaluationContext(user)
///   ..addMethodResolver(FunctionMethodResolver<User>({
///     'greet': (u, args) => 'Hi ${args.first}, I am ${u.name}',
///   }));
/// SpelExpressionParser()
///     .parseExpression("greet('Bob')")
///     .getValue(context); // 'Hi Bob, I am Ada'
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring finds greet(String) by reflection (ReflectiveMethodResolver):
/// parser.parseExpression("greet('Bob')").getValue(context);
/// ```
final class FunctionMethodResolver<T extends Object> implements MethodResolver {
  /// Exposes [methods] of `T`, keyed by method name; each function gets
  /// the target and the argument list (any arity).
  FunctionMethodResolver(
    Map<String, Object? Function(T target, List<Object?> args)> methods,
  ) : _methods = Map.unmodifiable(methods);

  final Map<String, Object? Function(T target, List<Object?> args)> _methods;

  @override
  MethodExecutor? resolve(
    EvaluationContext context,
    Object target,
    String name,
    List<Object?> arguments,
  ) {
    final method = target is T ? _methods[name] : null;
    return method == null
        ? null
        : (_, target, args) => method(target as T, args);
  }
}

/// Read-only properties of core Dart types: `length`/`size`, `isEmpty`,
/// `first`, `last`, map `keys`/`values`/`entries`, entry `key`/`value`,
/// date and duration parts, enum `name`/`index`.
///
/// Registered by default; Java-style aliases (`size`, `empty`, `keySet`,
/// `entrySet`) work too.
///
/// ```dart
/// final parser = SpelExpressionParser();
/// parser.parseExpression("'abc'.length").getValue(); // 3
/// parser.parseExpression('{1, 2}.size').getValue(); // 2
/// parser.parseExpression('#d.year').getValue(
///   StandardEvaluationContext()..setVariable('d', DateTime(2026)),
/// ); // 2026
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring reads JavaBean getters reflectively:
/// parser.parseExpression("'abc'.bytes.length").getValue();
/// parser.parseExpression("{1, 2}.size()").getValue();
/// ```
final class BuiltinPropertyAccessor implements PropertyAccessor {
  /// Creates the accessor (stateless).
  const BuiltinPropertyAccessor();

  // One table for canRead and read: _missing marks unknown properties, so
  // a property whose value is null is still readable.
  static Object? _lookup(Object target, String name) => switch ((
    target,
    name,
  )) {
    (String s, 'length' || 'size') => s.length,
    (String s, 'isEmpty' || 'empty') => s.isEmpty,
    (String s, 'isNotEmpty') => s.isNotEmpty,
    (Iterable<Object?> i, 'length' || 'size') => i.length,
    (Iterable<Object?> i, 'isEmpty' || 'empty') => i.isEmpty,
    (Iterable<Object?> i, 'isNotEmpty') => i.isNotEmpty,
    (Iterable<Object?> i, 'first') => i.first,
    (Iterable<Object?> i, 'last') => i.last,
    (Map<Object?, Object?> m, 'length' || 'size') => m.length,
    (Map<Object?, Object?> m, 'isEmpty' || 'empty') => m.isEmpty,
    (Map<Object?, Object?> m, 'isNotEmpty') => m.isNotEmpty,
    (Map<Object?, Object?> m, 'keys' || 'keySet') => m.keys.toList(),
    (Map<Object?, Object?> m, 'values') => m.values.toList(),
    (Map<Object?, Object?> m, 'entries' || 'entrySet') => m.entries.toList(),
    (MapEntry<Object?, Object?> e, 'key') => e.key,
    (MapEntry<Object?, Object?> e, 'value') => e.value,
    (num n, 'isNegative') => n.isNegative,
    (num n, 'isNaN') => n.isNaN,
    (num n, 'isFinite') => n.isFinite,
    (num n, 'isInfinite') => n.isInfinite,
    (num n, 'sign') => n.sign,
    (DateTime d, 'year') => d.year,
    (DateTime d, 'month') => d.month,
    (DateTime d, 'day') => d.day,
    (DateTime d, 'hour') => d.hour,
    (DateTime d, 'minute') => d.minute,
    (DateTime d, 'second') => d.second,
    (DateTime d, 'millisecond') => d.millisecond,
    (DateTime d, 'weekday') => d.weekday,
    (DateTime d, 'isUtc') => d.isUtc,
    (DateTime d, 'millisecondsSinceEpoch') => d.millisecondsSinceEpoch,
    (Duration d, 'inDays') => d.inDays,
    (Duration d, 'inHours') => d.inHours,
    (Duration d, 'inMinutes') => d.inMinutes,
    (Duration d, 'inSeconds') => d.inSeconds,
    (Duration d, 'inMilliseconds') => d.inMilliseconds,
    (Duration d, 'inMicroseconds') => d.inMicroseconds,
    (Duration d, 'isNegative') => d.isNegative,
    (Enum e, 'name') => e.name,
    (Enum e, 'index') => e.index,
    _ => _missing,
  };

  static const _missing = Object();

  @override
  bool canRead(EvaluationContext context, Object target, String name) =>
      !identical(_lookup(target, name), _missing);

  @override
  Object? read(EvaluationContext context, Object target, String name) =>
      _lookup(target, name);

  @override
  bool canWrite(EvaluationContext context, Object target, String name) => false;

  @override
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  ) => throw UnsupportedError('Built-in properties are read-only');
}

/// Common methods of core Dart types, with Dart names and the names
/// Spring users know (`size()`, `toUpperCase()`, `charAt()`, `equals()`).
///
/// Covers `String`, `List`, `Iterable`, `Map`, `num`, `DateTime` and
/// `Duration`, plus `toString()`, `hashCode()`, `equals()` and
/// `compareTo()` on any object. Registered by default in
/// [StandardEvaluationContext]; in a [SimpleEvaluationContext] only after
/// `withInstanceMethods()`.
///
/// ```dart
/// final parser = SpelExpressionParser();
/// parser.parseExpression("'abc'.toUpperCase()").getValue(); // 'ABC'
/// parser.parseExpression("'a,b'.split(',').size()").getValue(); // 2
/// parser.parseExpression("{a: 1}.getOrDefault('b', 0)").getValue(); // 0
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring calls the JDK methods reflectively:
/// parser.parseExpression("'abc'.toUpperCase()").getValue();
/// parser.parseExpression("'a,b'.split(',').length").getValue();
/// ```
final class BuiltinMethodResolver implements MethodResolver {
  /// Creates the resolver (stateless).
  const BuiltinMethodResolver();

  @override
  MethodExecutor? resolve(
    EvaluationContext context,
    Object target,
    String name,
    List<Object?> arguments,
  ) {
    final function = _method(target, name, arguments.length);
    return function == null
        ? null
        : (_, _, args) => Function.apply(function, args);
  }

  // Type-specific methods first, then the universal Object methods.
  // Arguments are matched by Function.apply, so a wrong count or type
  // surfaces as a call error (reported as methodNotFound).
  static Function? _method(Object target, String name, int arity) {
    final specific = switch (target) {
      String s => _string(s, name, arity),
      Map<Object?, Object?> m => _map(m, name),
      List<Object?> l => _list(l, name, arity) ?? _iterable(l, name),
      Iterable<Object?> i => _iterable(i, name),
      num n => _num(n, name),
      DateTime d => _date(d, name),
      Duration d => _duration(d, name),
      _ => null,
    };
    return specific ??
        switch (name) {
          'toString' => target.toString,
          'hashCode' => () => target.hashCode,
          'equals' => (Object? other) => target == other,
          'compareTo' when target is Comparable => target.compareTo,
          _ => null,
        };
  }

  static Function? _string(String s, String name, int arity) => switch (name) {
    'length' || 'size' => () => s.length,
    'isEmpty' => () => s.isEmpty,
    'isNotEmpty' => () => s.isNotEmpty,
    'toUpperCase' => s.toUpperCase,
    'toLowerCase' => s.toLowerCase,
    'trim' => s.trim,
    'strip' => s.trim,
    'trimLeft' => s.trimLeft,
    'trimRight' => s.trimRight,
    'substring' => (int start, [int? end]) => s.substring(start, end),
    'startsWith' => (String prefix) => s.startsWith(prefix),
    'endsWith' => (String suffix) => s.endsWith(suffix),
    'contains' => (String other) => s.contains(other),
    'indexOf' => (String other) => s.indexOf(other),
    'lastIndexOf' => (String other) => s.lastIndexOf(other),
    'charAt' => (int index) => s[index],
    'split' => (String separator) => s.split(separator),
    'replace' ||
    'replaceAll' => (String from, String to) => s.replaceAll(from, to),
    'concat' => (Object? other) => '$s$other',
    'repeat' => (int times) => s * times,
    'padLeft' => (int width, [String padding = ' ']) => s.padLeft(
      width,
      padding,
    ),
    'padRight' => (int width, [String padding = ' ']) => s.padRight(
      width,
      padding,
    ),
    'equalsIgnoreCase' => (
      String other,
    ) => s.toLowerCase() == other.toLowerCase(),
    'matches' => (String regex) => RegExp('^(?:$regex)\$').hasMatch(s),
    'isBlank' => () => s.trim().isEmpty,
    'codeUnitAt' => (int index) => s.codeUnitAt(index),
    _ => null,
  };

  static Function? _list(List<Object?> l, String name, int arity) =>
      switch (name) {
        'get' || 'elementAt' => (int index) => l[index],
        'indexOf' => (Object? item) => l.indexOf(item),
        'lastIndexOf' => (Object? item) => l.lastIndexOf(item),
        'sublist' ||
        'subList' => (int start, [int? end]) => l.sublist(start, end),
        'add' => (Object? item) {
          l.add(item);
          return true;
        },
        'reversed' => () => l.reversed.toList(),
        _ => null,
      };

  static Function? _iterable(Iterable<Object?> i, String name) =>
      switch (name) {
        'size' || 'length' => () => i.length,
        'isEmpty' => () => i.isEmpty,
        'isNotEmpty' => () => i.isNotEmpty,
        'contains' => (Object? item) => i.contains(item),
        'join' => ([String separator = '']) => i.join(separator),
        'toList' => () => i.toList(),
        'toSet' => () => i.toSet(),
        'first' => () => i.first,
        'last' => () => i.last,
        _ => null,
      };

  static Function? _map(Map<Object?, Object?> m, String name) => switch (name) {
    'get' => (Object? key) => m[key],
    'getOrDefault' => (
      Object? key,
      Object? fallback,
    ) => m.containsKey(key) ? m[key] : fallback,
    'containsKey' => (Object? key) => m.containsKey(key),
    'containsValue' => (Object? value) => m.containsValue(value),
    'size' || 'length' => () => m.length,
    'isEmpty' => () => m.isEmpty,
    'isNotEmpty' => () => m.isNotEmpty,
    'keySet' || 'keys' => () => m.keys.toSet(),
    'values' => () => m.values.toList(),
    'put' => (Object? key, Object? value) {
      final previous = m[key];
      m[key] = value;
      return previous;
    },
    _ => null,
  };

  static Function? _num(num n, String name) => switch (name) {
    'abs' => n.abs,
    'round' => n.round,
    'floor' => n.floor,
    'ceil' => n.ceil,
    'toInt' || 'intValue' => n.toInt,
    'toDouble' || 'doubleValue' => n.toDouble,
    'toStringAsFixed' => (int digits) => n.toStringAsFixed(digits),
    'clamp' => (num low, num high) => n.clamp(low, high),
    'remainder' => (num other) => n.remainder(other),
    _ => null,
  };

  static Function? _date(DateTime d, String name) => switch (name) {
    'isBefore' => (DateTime other) => d.isBefore(other),
    'isAfter' => (DateTime other) => d.isAfter(other),
    'add' => (Duration duration) => d.add(duration),
    'subtract' => (Duration duration) => d.subtract(duration),
    'difference' => (DateTime other) => d.difference(other),
    'toIso8601String' => d.toIso8601String,
    'toUtc' => d.toUtc,
    'toLocal' => d.toLocal,
    _ => null,
  };

  static Function? _duration(Duration d, String name) => switch (name) {
    'abs' => d.abs,
    'toMillis' => () => d.inMilliseconds,
    'toSeconds' || 'getSeconds' => () => d.inSeconds,
    _ => null,
  };
}
