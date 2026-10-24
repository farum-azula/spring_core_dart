import 'dart:convert';

import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';
import 'package:spring_core_dart/src/core/convert/data_size.dart';
import 'package:spring_core_dart/src/core/convert/duration_style.dart';
import 'package:spring_core_dart/src/core/convert/generic_conversion_service.dart';

/// [GenericConversionService] with the standard converters, like Spring's
/// `DefaultConversionService`.
///
/// Built in:
/// - `String` → `int` (also hex `0x1F` / `#1F`), `double`, `num`, `BigInt`,
///   `bool`, `Uri`, `DateTime` (ISO-8601), `Duration` (`10s`, `5m`,
///   `PT10S`, plain millis), `RegExp`; an empty or blank string becomes
///   `null`.
/// - `int` → `Duration` (milliseconds); `BigInt` → `int` (failing on
///   overflow) and `double`; `num` → `BigInt`.
/// - `String` → `Encoding` (`utf-8`, `latin1`, ...; Spring's `Charset`)
///   and back to its name.
/// - Enums → `String`: the name (`red`, not `Color.red`).
/// - `bool` from `true/on/yes/1` and `false/off/no/0`, case-insensitive.
/// - `num` → `int`, `double`; anything → `String` (`toString`; a list or
///   set as `a,b`; `Duration` as ISO-8601 `PT10S` and `DateTime` in their
///   parseable forms).
/// - `List` / `Set` of `String`, `int`, `double`, `num`, `bool`, `BigInt`,
///   `Duration`, `Uri` from comma-separated strings, other iterables and
///   single values (a one-element collection).
/// - `Map` → `Map<String, V>` for those element types and `Object?`, keys
///   and values converted.
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
  /// Creates a service with all default converters registered.
  DefaultConversionService() {
    addDefaultConverters(this);
  }

  /// A lazily created shared instance; do not register converters on it.
  ///
  /// Like Spring's `DefaultConversionService.getSharedInstance()`.
  static final DefaultConversionService sharedInstance =
      DefaultConversionService();

  /// Registers the default converters on [service].
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
