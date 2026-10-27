import 'dart:math' as math;

import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/env/system_environment_property_source.dart';

/// Random values for `random.*` properties, like Spring Boot's
/// `RandomValuePropertySource`.
///
/// - `random.int`, `random.long`: any int (a long is 64 bits on the VM and
///   at most 53 bits on the web);
/// - `random.int(10)`, `random.int[5,10]`, `random.long(100)`: in a range
///   (the lower bound is inclusive, the upper one exclusive);
/// - `random.uuid`: a random version 4 UUID;
/// - any other `random.*` (`random.value`): 32 random hex digits.
///
/// Every lookup gives a new value. Spring Boot's `SpringApplication` (and
/// `spring_boot_dart`) adds it to the environment, so config files can use
/// `${random.uuid}`.
///
/// ```dart
/// RandomValuePropertySource.addToEnvironment(environment);
/// environment.getProperty('random.int[1,7]'); // e.g. '4'
/// environment.resolvePlaceholders(r'app-${random.uuid}');
/// ```
///
/// Spring (Java):
/// ```java
/// RandomValuePropertySource.addToEnvironment(environment);
/// environment.getProperty("random.int[1,7]");
/// ```
final class RandomValuePropertySource extends AbstractPropertySource<Object> {
  /// Creates the source called [name], using [random] (a secure random
  /// generator when `null`).
  RandomValuePropertySource({
    String name = randomPropertySourceName,
    math.Random? random,
  }) : _given = random,
       super(name, const Object());

  /// The name Spring Boot gives this source.
  static const randomPropertySourceName = 'random';

  static const _prefix = 'random.';

  final math.Random? _given;
  // Created on first use: nothing is drawn unless a `random.*` key is read.
  late final math.Random _random = _given ?? math.Random.secure();

  // 2^32 and 2^31 as literals: on the web `1 << 32` is 0.
  static const _two32 = 4294967296;
  static const _two31 = 2147483648;

  /// Adds a [RandomValuePropertySource] right after the system environment
  /// (or last), unless [environment] has one already.
  static void addToEnvironment(ConfigurableEnvironment environment) {
    final sources = environment.propertySources;
    if (sources.containsSource(randomPropertySourceName)) {
      return;
    }
    final source = RandomValuePropertySource();
    if (sources.containsSource(SystemEnvironmentPropertySource.defaultName)) {
      sources.addAfter(SystemEnvironmentPropertySource.defaultName, source);
    } else {
      sources.addLast(source);
    }
  }

  @override
  Object? getProperty(String name) {
    if (!name.startsWith(_prefix)) {
      return null;
    }
    return _value(name.substring(_prefix.length));
  }

  Object _value(String type) {
    if (type == 'int') {
      return _random.nextInt(_two32) - _two31;
    }
    if (type == 'long') {
      return _nextLong();
    }
    if (_range(type, 'int') case final range?) {
      final (min, max) = _bounds(range, 'int');
      return min + _below(max - min);
    }
    if (_range(type, 'long') case final range?) {
      final (min, max) = _bounds(range, 'long');
      return min + _below(max - min);
    }
    if (type == 'uuid') {
      return _uuid();
    }
    return _hex(16);
  }

  // The range of `int(10)` / `int[5,10]`: the text between the brackets.
  static String? _range(String type, String prefix) {
    if (type.startsWith(prefix) && type.length > prefix.length + 1) {
      return type.substring(prefix.length + 1, type.length - 1);
    }
    return null;
  }

  // `max` (from 0) or `min,max`, checked like Boot's Range.of.
  static (int, int) _bounds(String range, String type) {
    final tokens = range.split(',');
    int parse(String token) =>
        int.tryParse(token.trim()) ??
        (throw FormatException("Invalid random.$type range '$range'"));
    final first = parse(tokens[0]);
    if (tokens.length == 1) {
      if (first <= 0) {
        throw StateError('Bound must be positive.');
      }
      return (0, first);
    }
    final second = parse(tokens[1]);
    if (first >= second) {
      throw StateError('Lower bound must be less than upper bound.');
    }
    return (first, second);
  }

  // Decided at run time, as it was written: on the web 0 and 0.0 are the
  // same number.
  // ignore: prefer_const_declarations
  static final bool _web = identical(0, 0.0);

  // A uniformly random int in [0, bound).
  int _below(int bound) {
    if (bound <= _two32) {
      return _random.nextInt(bound);
    }
    // Larger bounds: a random 53-bit (web) or 63-bit (VM) value, reduced.
    return _nextLong() % bound;
  }

  int _nextLong() {
    if (_web) {
      // 53 bits, the integers exact in JavaScript.
      final high = _random.nextInt(1 << 21) - (1 << 20);
      return high * _two32 + _random.nextInt(_two32);
    }
    return (_random.nextInt(_two32) << 32) | _random.nextInt(_two32);
  }

  String _uuid() {
    final bytes = [for (var i = 0; i < 16; i++) _random.nextInt(256)];
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4.
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // IETF variant.
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
        '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
        '${hex.sublist(10).join()}';
  }

  String _hex(int length) => [
    for (var i = 0; i < length; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}
