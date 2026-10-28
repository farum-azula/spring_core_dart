import 'dart:convert';

import 'package:spring_core_dart/src/core/convert/data_size.dart';
import 'package:spring_core_dart/src/core/convert/duration_style.dart';
import 'package:spring_core_dart/src/core/convert/generic_conversion_service.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';

/// A conversion service that already knows the types configuration values
/// are usually read as: numbers, booleans, durations, data sizes, URIs,
/// dates, encodings, resources and lists, sets and maps of them.
///
/// It is what the environment, `@Value` injection and
/// `@ConfigurationProperties` binding use unless the application provides
/// a `conversionService` bean, which is why `server.port=8080` can be read
/// as an `int` and `timeout=10s` as a `Duration`. An application creates
/// one itself only to add converters for its own types (as its
/// `conversionService` bean) or to convert values in code or tests.
///
/// Built in:
/// - `String` to `int` (also hex `0x1F` and `#1F`), `double`, `num`,
///   `BigInt`, `bool`, `Uri`, `DateTime` (ISO-8601), `Duration` (`10s`,
///   `5m`, `PT10S`, a plain number of milliseconds), `DataSize` (`10MB`),
///   `RegExp` (the text as is, not trimmed) and `Resource` (a location
///   such as `classpath:a.txt`). For the number, boolean, URI, date,
///   duration, size and encoding targets a blank string becomes `null`.
/// - `bool` from `true`, `on`, `yes`, `1` and `false`, `off`, `no`, `0`, in
///   any case; anything else fails.
/// - `int` to `Duration` (milliseconds) and to `DataSize` (bytes);
///   `BigInt` to `int` (failing on overflow) and `double`; `num` to
///   `BigInt`, `int` (truncated, `1.9` is `1`) and `double`.
/// - `String` to `Encoding` (`utf-8`, `latin1`, like Spring's `Charset`)
///   and back to its name.
/// - Anything to `String` with `toString`, except: an enum is its name
///   (`red`, not `Color.red`), a list or set is `a,b`, a `Duration` is
///   ISO-8601 (`PT10S`) and a `DateTime` is ISO-8601 too.
/// - `List` and `Set` of `String`, `int`, `double`, `num`, `bool`,
///   `BigInt`, `Duration`, `DataSize` and `Uri`, from comma-separated
///   strings, other iterables and single values (a one-element
///   collection).
/// - `Map<String, V>` for those element types and for `Object?`, from any
///   map, keys and values converted.
///
/// Enums are not built in: register them with [addEnum].
///
/// ```dart
/// final service = DefaultConversionService();
/// service.convert<int>('0x1F'); // 31
/// service.convert<Duration>('PT1M'); // 0:01:00.000000
/// service.convert<List<String>>('a, b'); // ['a', 'b']
/// service.convert<String>(const Duration(seconds: 10)); // 'PT10S'
/// service.convert<String>(['a', 'b']); // 'a,b'
/// ```
///
/// Spring (Java):
/// ```java
/// DefaultConversionService service = new DefaultConversionService();
/// Integer value = service.convert("0x1F", Integer.class);
/// // Duration parsing lives in Spring Boot's ApplicationConversionService:
/// Duration timeout = ApplicationConversionService.getSharedInstance()
///     .convert("10s", Duration.class);
/// ```
class DefaultConversionService extends GenericConversionService {
  /// Creates a new service with the default converters, ready for more
  /// registrations of your own.
  DefaultConversionService() {
    addDefaultConverters(this);
  }

  /// One instance shared by everything that was given no service of its
  /// own, such as a new `StandardEnvironment` or bean factory. Do not
  /// register converters on it: the change would leak into every user.
  /// Create your own instance instead.
  ///
  /// Like Spring's `DefaultConversionService.getSharedInstance()`.
  static final DefaultConversionService sharedInstance =
      DefaultConversionService();

  /// Registers the default converters on [service], for a
  /// [GenericConversionService] (or subclass) that you build yourself but
  /// that should still understand the standard types.
  ///
  /// ```dart
  /// final service = GenericConversionService();
  /// DefaultConversionService.addDefaultConverters(service);
  /// ```
  static void addDefaultConverters(GenericConversionService service) {
    // Blank input means "no value" (null), like Spring's string converters.
    String? text(String source) {
      final trimmed = source.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    service
      // `Resource` from a location, like Spring's ResourceEditor (inside a
      // context, `@Value` uses the context's own resource loader instead).
      ..addConverter<String, Resource>(
        (location) => DefaultResourceLoader().getResource(location.trim()),
      )
      ..addConverter<Object, String>((source) => source.toString())
      // `red`, not `Color.red` (Spring's EnumToStringConverter).
      ..addConverter<Enum, String>((source) => source.name)
      // Spring's StringToCharsetConverter.
      ..addConverter<String, Encoding>(
        (s) => _map(
          text(s),
          (name) =>
              Encoding.getByName(name) ??
              (throw ArgumentError.value(name, 'source', 'Unknown encoding')),
        ),
      )
      ..addConverter<Encoding, String>((source) => source.name)
      // Like Spring's NumberUtils: an overflow is an error.
      ..addConverter<BigInt, int>(
        (source) => source.isValidInt
            ? source.toInt()
            : throw ArgumentError.value(source, 'source', 'Overflow for int'),
      )
      ..addConverter<BigInt, double>((source) => source.toDouble())
      ..addConverter<num, BigInt>((source) {
        if (source is double && !source.isFinite) {
          throw ArgumentError.value(source, 'source', 'Not a finite number');
        }
        return BigInt.from(source);
      })
      // `[a, b]` reads as `a,b`, like Spring's CollectionToStringConverter.
      ..addConverter<Iterable<Object?>, String>(
        (source) => source.map(service.convert<String?>).join(','),
      )
      // ISO-8601 (`PT1H30M`), like Boot's DurationToStringConverter.
      ..addConverter<Duration, String>(DurationStyle.formatIso)
      ..addConverter<DateTime, String>((source) => source.toIso8601String())
      // Truncated like Spring's NumberUtils (`1.9` is `1`); NaN and
      // infinity cannot be converted.
      ..addConverter<num, int>((source) {
        if (source is double && !source.isFinite) {
          throw ArgumentError.value(source, 'source', 'Not a finite number');
        }
        return source.toInt();
      })
      ..addConverter<num, double>((source) => source.toDouble())
      ..addConverter<String, int>((s) => _map(text(s), _parseInt))
      ..addConverter<String, double>((s) => _map(text(s), double.parse))
      ..addConverter<String, num>((s) => _map(text(s), num.parse))
      ..addConverter<String, BigInt>((s) => _map(text(s), BigInt.parse))
      ..addConverter<String, bool>((s) => _map(text(s), _parseBool))
      ..addConverter<String, Uri>((s) => _map(text(s), Uri.parse))
      ..addConverter<String, DateTime>((s) => _map(text(s), DateTime.parse))
      ..addConverter<String, Duration>(
        (s) => _map(text(s), DurationStyle.parse),
      )
      // Not trimmed: whitespace can be significant in a pattern.
      ..addConverter<String, RegExp>((s) => RegExp(s))
      ..addConverter<int, Duration>((s) => Duration(milliseconds: s))
      ..addConverter<String, DataSize>((s) => _map(text(s), DataSize.parse))
      ..addConverter<int, DataSize>(DataSize.ofBytes)
      ..addConverter<DataSize, String>((size) => size.toString())
      ..addCollectionConverters<String>()
      ..addCollectionConverters<int>()
      ..addCollectionConverters<double>()
      ..addCollectionConverters<num>()
      ..addCollectionConverters<bool>()
      ..addCollectionConverters<BigInt>()
      ..addCollectionConverters<Duration>()
      ..addCollectionConverters<DataSize>()
      ..addCollectionConverters<Uri>()
      ..addMapConverters<String, String>()
      ..addMapConverters<String, int>()
      ..addMapConverters<String, double>()
      ..addMapConverters<String, num>()
      ..addMapConverters<String, bool>()
      ..addMapConverters<String, BigInt>()
      ..addMapConverters<String, Duration>()
      ..addMapConverters<String, DataSize>()
      ..addMapConverters<String, Uri>()
      ..addMapConverters<String, Object?>();
  }

  // Applies [parse] unless the trimmed input was blank.
  static T? _map<T>(String? value, T Function(String) parse) =>
      value == null ? null : parse(value);

  static int _parseInt(String value) {
    final lower = value.toLowerCase();
    final negative = lower.startsWith('-');
    final digits = negative || lower.startsWith('+')
        ? lower.substring(1)
        : lower;
    // Hex like Spring's NumberUtils (0x, #).
    final hex = digits.startsWith('0x')
        ? digits.substring(2)
        : digits.startsWith('#')
        ? digits.substring(1)
        : null;
    final result = hex != null ? int.parse(hex, radix: 16) : int.parse(digits);
    return negative ? -result : result;
  }

  static bool _parseBool(String value) => switch (value.toLowerCase()) {
    'true' || 'on' || 'yes' || '1' => true,
    'false' || 'off' || 'no' || '0' => false,
    _ => throw ArgumentError.value(value, 'value', 'Invalid boolean value'),
  };
}
