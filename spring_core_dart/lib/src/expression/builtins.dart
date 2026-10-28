import 'dart:convert';

import 'package:spring_core_dart/src/expression/evaluation_context.dart';
import 'package:spring_core_dart/src/expression/expression_exceptions.dart';
import 'package:spring_core_dart/src/expression/java_format.dart';
import 'package:spring_core_dart/src/expression/spel_patterns.dart';
import 'package:spring_core_dart/src/expression/spel_type.dart';

/// A [PropertyAccessor] that treats the entries of a map as properties,
/// so `user.name` works when `user` is a map such as decoded JSON.
///
/// Both contexts register it by default (unless built with
/// `SimpleEvaluationContext.forPropertyAccessors`), so you rarely create
/// one. A key that is not in the map is not readable here: the next
/// accessor is asked, and the expression fails if none can read it
/// (`map['missing']` gives `null` instead). Writing stores the key, new
/// or not; a value of the wrong type for a typed map fails with
/// `exceptionDuringPropertyWrite` (EL1034E).
///
/// ```dart
/// // A JSON payload read without a class.
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

/// A [PropertyAccessor] for objects of type [T], built from one getter
/// (and optionally one setter) function per property name.
///
/// Use it to make a class readable in expressions when it is not
/// `@Introspected`, for instance a class from another package: list the
/// properties expressions may see, nothing else is exposed.
/// `IntrospectionPropertyAccessor` does the same for `@Introspected`
/// classes from generated metadata.
///
/// ```dart
/// // `name` can be read and assigned on a User.
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
  /// properties) of `T`, keyed by property name. A setter receives the
  /// value unconverted, so it casts it itself.
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

/// A [MethodResolver] for objects of type [T], built from one function per
/// method name.
///
/// Use it to let expressions call a few methods of a class that is not
/// `@Introspected`. Each function gets the target and the list of
/// evaluated arguments, whatever their number, and checks them itself;
/// arguments are not converted.
///
/// ```dart
/// // greet('Bob') can be called on a User.
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

/// A [PropertyAccessor] for the common read-only properties of core Dart
/// types, which expressions cannot reach otherwise without reflection.
///
/// It covers `length`/`size`, `isEmpty`, `isNotEmpty`, `first` and `last`
/// of strings and iterables; `keys`, `values` and `entries` of maps (as
/// lists) and `key`/`value` of entries; `isNegative`, `isNaN`, `sign`, ...
/// of numbers; the parts of a `DateTime` (`year`, `month`, `weekday`, ...)
/// and of a `Duration` (`inSeconds`, ...); `name` and `index` of enums.
/// Java-style names work too (`size`, `empty`, `keySet`, `entrySet`).
/// Both contexts register it by default.
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
    (final String s, 'length' || 'size') => s.length,
    (final String s, 'isEmpty' || 'empty') => s.isEmpty,
    (final String s, 'isNotEmpty') => s.isNotEmpty,
    (final Iterable<Object?> i, 'length' || 'size') => i.length,
    (final Iterable<Object?> i, 'isEmpty' || 'empty') => i.isEmpty,
    (final Iterable<Object?> i, 'isNotEmpty') => i.isNotEmpty,
    (final Iterable<Object?> i, 'first') => i.first,
    (final Iterable<Object?> i, 'last') => i.last,
    (final Map<Object?, Object?> m, 'length' || 'size') => m.length,
    (final Map<Object?, Object?> m, 'isEmpty' || 'empty') => m.isEmpty,
    (final Map<Object?, Object?> m, 'isNotEmpty') => m.isNotEmpty,
    (final Map<Object?, Object?> m, 'keys' || 'keySet') => m.keys.toList(),
    (final Map<Object?, Object?> m, 'values') => m.values.toList(),
    (final Map<Object?, Object?> m, 'entries' || 'entrySet') =>
      m.entries.toList(),
    (final MapEntry<Object?, Object?> e, 'key') => e.key,
    (final MapEntry<Object?, Object?> e, 'value') => e.value,
    (final num n, 'isNegative') => n.isNegative,
    (final num n, 'isNaN') => n.isNaN,
    (final num n, 'isFinite') => n.isFinite,
    (final num n, 'isInfinite') => n.isInfinite,
    (final num n, 'sign') => n.sign,
    (final DateTime d, 'year') => d.year,
    (final DateTime d, 'month') => d.month,
    (final DateTime d, 'day') => d.day,
    (final DateTime d, 'hour') => d.hour,
    (final DateTime d, 'minute') => d.minute,
    (final DateTime d, 'second') => d.second,
    (final DateTime d, 'millisecond') => d.millisecond,
    (final DateTime d, 'weekday') => d.weekday,
    (final DateTime d, 'isUtc') => d.isUtc,
    (final DateTime d, 'millisecondsSinceEpoch') => d.millisecondsSinceEpoch,
    (final Duration d, 'inDays') => d.inDays,
    (final Duration d, 'inHours') => d.inHours,
    (final Duration d, 'inMinutes') => d.inMinutes,
    (final Duration d, 'inSeconds') => d.inSeconds,
    (final Duration d, 'inMilliseconds') => d.inMilliseconds,
    (final Duration d, 'inMicroseconds') => d.inMicroseconds,
    (final Duration d, 'isNegative') => d.isNegative,
    (final Enum e, 'name') => e.name,
    (final Enum e, 'index') => e.index,
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

/// A [MethodResolver] for the common methods of core Dart types, under
/// their Dart names and the Java names Spring expressions use
/// (`size()`, `toUpperCase()`, `charAt()`, `equals()`, `getOrDefault()`,
/// `putIfAbsent()`).
///
/// Without reflection expressions could not call `'abc'.toUpperCase()`;
/// this table makes the usual methods of `String`, `List`, `Set`,
/// `Iterable`, `Map`, `int`, `num`, `DateTime`, `Duration` and
/// `StringBuffer` (Java's `StringBuilder`) available, plus `toString()`,
/// `hashCode()`, `equals()` and `compareTo()` on any object. A
/// [StandardEvaluationContext] registers it by default; a
/// [SimpleEvaluationContext] only after `withInstanceMethods()`.
///
/// Where Dart and Java share a name, the method behaves like Dart's:
/// `split`, `replaceAll` and `contains` take plain strings (not regular
/// expressions), `List.remove(x)` removes an element (not the one at an
/// index); `matches` uses Dart's `RegExp`. String also has Java's
/// `formatted`, `getBytes` (UTF-8) and `chars`.
///
/// Number, string and bool arguments are converted to the parameter type
/// when needed (`'abc'.substring('1')`). Arguments that still do not fit
/// are reported as `SpelMessage.methodNotFound`; errors raised by the
/// method itself (`RangeError` for `'abc'.charAt(9)`) propagate
/// unchanged, like Java exceptions from Spring's reflective calls.
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
    final function = _method(target, name);
    if (function == null ||
        !VarargsFunction.accepts(function, arguments.length)) {
      return null;
    }
    return (context, _, args) => SpelTypeMethodResolver.callChecked(
      function,
      VarargsFunction.convertArguments(function, args, context.typeConverter),
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
  }

  // Type-specific methods first, then the universal Object methods: a
  // Function or a VarargsFunction.
  static Object? _method(Object target, String name) {
    final specific = switch (target) {
      final String s => _string(s, name),
      final Map<Object?, Object?> m => _map(m, name),
      final List<Object?> l => _list(l, name) ?? _iterable(l, name),
      final Set<Object?> s => _set(s, name) ?? _iterable(s, name),
      final Iterable<Object?> i => _iterable(i, name),
      final int n => _int(n, name) ?? _num(n, name),
      final num n => _num(n, name),
      final DateTime d => _date(d, name),
      final Duration d => _duration(d, name),
      final StringBuffer b => _stringBuilder(b, name),
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

  static Object? _string(String s, String name) => switch (name) {
    'length' || 'size' => () => s.length,
    'isEmpty' => () => s.isEmpty,
    'isNotEmpty' => () => s.isNotEmpty,
    'isBlank' => () => s.trim().isEmpty,
    'toUpperCase' => s.toUpperCase,
    'toLowerCase' => s.toLowerCase,
    'trim' || 'strip' => s.trim,
    'trimLeft' || 'stripLeading' => s.trimLeft,
    'trimRight' || 'stripTrailing' => s.trimRight,
    'substring' => (int start, [int? end]) => s.substring(start, end),
    'startsWith' => (String prefix, [int index = 0]) => s.startsWith(
      prefix,
      index,
    ),
    'endsWith' => (String suffix) => s.endsWith(suffix),
    'contains' => (String other) => s.contains(other),
    'indexOf' => (String other, [int start = 0]) => s.indexOf(other, start),
    'lastIndexOf' => (String other, [int? start]) => s.lastIndexOf(
      other,
      start,
    ),
    'charAt' => (int index) => s[index],
    'codeUnitAt' || 'codePointAt' => (int index) => s.codeUnitAt(index),
    'toCharArray' => () => s.split(''),
    'split' => (String separator) => s.split(separator),
    'lines' => () => s.split(RegExp(r'\r\n|\r|\n')),
    'replace' ||
    'replaceAll' => (String from, String to) => s.replaceAll(from, to),
    'replaceFirst' => (String from, String to) => s.replaceFirst(from, to),
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
    'compareToIgnoreCase' => (String other) => s.toLowerCase().compareTo(
      other.toLowerCase(),
    ),
    'contentEquals' => (Object? other) => s == '$other',
    'matches' => (String regex) => SpelPatterns.compile(regex).hasMatch(s),
    // Java's formatted(args...), String.format with this as the format.
    'formatted' => VarargsFunction((List<Object?> args) => javaFormat(s, args)),
    // UTF-8 bytes, like getBytes(StandardCharsets.UTF_8).
    'getBytes' => () => utf8.encode(s).toList(),
    'chars' => () => s.codeUnits.toList(),
    _ => null,
  };

  static Function? _list(List<Object?> l, String name) => switch (name) {
    'get' || 'elementAt' => (int index) => l[index],
    'set' => (int index, Object? item) {
      final previous = l[index];
      l[index] = item;
      return previous;
    },
    'getFirst' => () => l.first,
    'getLast' => () => l.last,
    'indexOf' => (Object? item) => l.indexOf(item),
    'lastIndexOf' => (Object? item) => l.lastIndexOf(item),
    'sublist' || 'subList' => (int start, [int? end]) => l.sublist(start, end),
    // add(e) like both; add(index, e) like Java's List.add.
    'add' => (Object? first, [Object? second = _none]) {
      if (identical(second, _none)) {
        l.add(first);
        return true;
      }
      l.insert(first! as int, second);
      return null;
    },
    'insert' => (int index, Object? item) => l.insert(index, item),
    'addAll' => (Iterable<Object?> items) {
      l.addAll(items);
      return items.isNotEmpty;
    },
    'remove' => (Object? item) => l.remove(item),
    'removeAt' => (int index) => l.removeAt(index),
    'removeFirst' => () => l.removeAt(0),
    'removeLast' => l.removeLast,
    'clear' => l.clear,
    'reversed' => () => l.reversed.toList(),
    'removeAll' => (Iterable<Object?> items) {
      final before = l.length;
      l.removeWhere(items.contains);
      return l.length != before;
    },
    'retainAll' => (Iterable<Object?> items) {
      final before = l.length;
      l.retainWhere(items.contains);
      return l.length != before;
    },
    // Java's sort(null): natural order.
    'sort' => ([Object? comparator]) {
      if (comparator != null) {
        throw ArgumentError('Only sort(null) (natural order) is supported');
      }
      l.sort();
    },
    _ => null,
  };

  static Function? _set(Set<Object?> s, String name) => switch (name) {
    'add' => (Object? item) => s.add(item),
    'addAll' => (Iterable<Object?> items) {
      final before = s.length;
      s.addAll(items);
      return s.length != before;
    },
    'remove' => (Object? item) => s.remove(item),
    'clear' => s.clear,
    'union' => (Set<Object?> other) => s.union(other),
    'intersection' => (Set<Object?> other) => s.intersection(other),
    'difference' => (Set<Object?> other) => s.difference(other),
    _ => null,
  };

  static Function? _iterable(Iterable<Object?> i, String name) =>
      switch (name) {
        'size' || 'length' => () => i.length,
        'isEmpty' => () => i.isEmpty,
        'isNotEmpty' => () => i.isNotEmpty,
        'contains' => (Object? item) => i.contains(item),
        'containsAll' => (Iterable<Object?> items) => items.every(i.contains),
        'join' => ([String separator = '']) => i.join(separator),
        'toList' || 'toArray' => () => i.toList(),
        'toSet' => () => i.toSet(),
        'first' => () => i.first,
        'last' => () => i.last,
        'single' => () => i.single,
        'elementAt' => (int index) => i.elementAt(index),
        'take' => (int count) => i.take(count).toList(),
        'skip' => (int count) => i.skip(count).toList(),
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
    'entrySet' || 'entries' => () => m.entries.toList(),
    'put' => (Object? key, Object? value) {
      final previous = m[key];
      m[key] = value;
      return previous;
    },
    // Java's putIfAbsent(key, value): the existing value, or null after
    // storing the new one.
    'putIfAbsent' => (Object? key, Object? value) {
      final existing = m[key];
      if (existing != null) {
        return existing;
      }
      m[key] = value;
      return null;
    },
    'putAll' || 'addAll' => (Map<Object?, Object?> other) => m.addAll(other),
    'remove' => (Object? key) => m.remove(key),
    'clear' => m.clear,
    _ => null,
  };

  static Function? _int(int n, String name) => switch (name) {
    'toRadixString' => (int radix) => n.toRadixString(radix),
    'isEven' => () => n.isEven,
    'isOdd' => () => n.isOdd,
    'gcd' => (int other) => n.gcd(other),
    _ => null,
  };

  static Function? _num(num n, String name) => switch (name) {
    'abs' => n.abs,
    'round' => n.round,
    'floor' => n.floor,
    'ceil' => n.ceil,
    'truncate' => n.truncate,
    'toInt' || 'intValue' || 'longValue' => n.toInt,
    'toDouble' || 'doubleValue' || 'floatValue' => n.toDouble,
    'toStringAsFixed' => (int digits) => n.toStringAsFixed(digits),
    'clamp' => (num low, num high) => n.clamp(low, high),
    'remainder' => (num other) => n.remainder(other),
    _ => null,
  };

  // Java's StringBuilder over a Dart StringBuffer (`new StringBuilder()`).
  static Function? _stringBuilder(StringBuffer b, String name) {
    StringBuffer replace(String text) => b
      ..clear()
      ..write(text);
    return switch (name) {
      'append' => (Object? value) => b..write(value),
      'length' => () => b.length,
      'isEmpty' => () => b.isEmpty,
      'charAt' => (int index) => b.toString()[index],
      'indexOf' => (String text) => b.toString().indexOf(text),
      'insert' => (int offset, Object? value) {
        final text = b.toString();
        return replace(
          '${text.substring(0, offset)}$value${text.substring(offset)}',
        );
      },
      'reverse' => () => replace(b.toString().split('').reversed.join()),
      'setLength' => (int length) {
        final text = b.toString();
        replace(
          length <= text.length
              ? text.substring(0, length)
              : text.padRight(length, '\u0000'),
        );
      },
      'deleteCharAt' => (int index) {
        final text = b.toString();
        RangeError.checkValidIndex(index, text);
        return replace(text.substring(0, index) + text.substring(index + 1));
      },
      'delete' => (int start, int end) {
        final text = b.toString();
        final stop = end > text.length ? text.length : end;
        return replace(text.substring(0, start) + text.substring(stop));
      },
      'replace' => (int start, int end, String replacement) {
        final text = b.toString();
        final stop = end > text.length ? text.length : end;
        return replace(text.replaceRange(start, stop, replacement));
      },
      _ => null,
    };
  }

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
    'toMinutes' => () => d.inMinutes,
    'toHours' => () => d.inHours,
    'toDays' => () => d.inDays,
    _ => null,
  };

  static const _none = Object();
}
