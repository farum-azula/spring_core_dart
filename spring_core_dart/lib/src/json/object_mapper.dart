import 'dart:convert';

import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/type_info.dart';
import 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';
import 'package:spring_core_dart/src/json/annotations.dart';
import 'package:spring_core_dart/src/json/json_exception.dart';
import 'package:spring_core_dart/src/json/json_serializer.dart';
import 'package:spring_core_dart/src/json/naming.dart';

/// Converts objects to JSON and back, like Jackson's `ObjectMapper` — on
/// metadata written by the generator instead of reflection, so it works in
/// AOT, Flutter, the web and minified builds.
///
/// A class becomes JSON-ready with `@Introspected()`; classes of the same
/// package that it uses are introspected too. Immutable classes are created
/// through their constructor (`final` fields, `required` and default
/// values); a class with its own `fromJson` / `toJson` (e.g. from
/// `json_serializable` or `freezed`) is converted with those.
///
/// ```dart
/// @Introspected()
/// class Book {
///   const Book({required this.isbn, required this.title, this.tags = const []});
///   final String isbn;
///   final String title;
///   final List<String> tags;
/// }
///
/// final mapper = context.getBean<ObjectMapper>(); // or ObjectMapper(...)
/// final json = mapper.writeValueAsString(book);   // {"isbn":"1","tags":[],"title":"Dune"}
/// final again = mapper.readValue<Book>(json);
/// final books = mapper.readList<Book>('[{"isbn":"1","title":"Dune"}]');
/// ```
///
/// Built-in conversions: `String`, `int`, `double`, `num` (`NaN` and
/// infinities as the strings `"NaN"`, `"Infinity"`, `"-Infinity"`, like
/// Jackson), `bool`, `DateTime` (ISO-8601 like Jackson writes an
/// `OffsetDateTime`: `2026-01-01T12:00:00.000+02:00` for a local time, `Z`
/// for UTC, converted to [timeZone] when set; or epoch milliseconds with
/// [writeDatesAsTimestamps]), `Duration` (ISO-8601 such as `PT1M30S`; also
/// reads `90s` or milliseconds), `Uri`, `BigInt` (as a string), enums (by
/// name or `@JsonValue`), `List`, `Set`, `Map`, nullable types and nested
/// objects. `Map<String, dynamic>`, `List<dynamic>` and `Object?` read
/// without a type are the plain decoded JSON. Anything else: a [JsonSerializer] / [JsonDeserializer].
///
/// Spring (Java):
/// ```java
/// ObjectMapper mapper = new ObjectMapper();
/// String json = mapper.writeValueAsString(book);
/// Book again = mapper.readValue(json, Book.class);
/// List<Book> books = mapper.readValue(json, new TypeReference<List<Book>>() {});
/// ```
class ObjectMapper {
  /// A mapper reading class metadata from [introspector] (the context's one
  /// in an application; [BeanIntrospector.shared] by default).
  ///
  /// [namingStrategy] turns Dart names into JSON names; [inclusion] decides
  /// which values are written; [failOnUnknownProperties] rejects JSON
  /// properties a class does not have (off, like Spring Boot);
  /// [writeDatesAsTimestamps] writes `DateTime` / `Duration` as
  /// milliseconds; [timeZone] (`UTC`, `Z` or a fixed offset such as
  /// `+02:00` or `GMT+2`) is the offset dates are written in;
  /// [indentOutput] pretty-prints; [sortPropertiesAlphabetically] writes the
  /// properties of an object sorted by JSON name (Jackson 3's default,
  /// `MapperFeature.SORT_PROPERTIES_ALPHABETICALLY`; a class's constructor
  /// parameters come first, like `SORT_CREATOR_PROPERTIES_FIRST`), `false`
  /// writes them in declaration order (Jackson 2's, superclass first);
  /// `@JsonPropertyOrder` wins either way. The serializers and deserializers of
  /// [modules] come after [serializers] / [deserializers].
  ObjectMapper({
    BeanIntrospector? introspector,
    this.namingStrategy = PropertyNamingStrategy.lowerCamelCase,
    this.inclusion = JsonInclusion.always,
    this.failOnUnknownProperties = false,
    this.writeDatesAsTimestamps = false,
    this.timeZone,
    this.indentOutput = false,
    this.sortPropertiesAlphabetically = true,
    Iterable<JsonSerializer<Object>> serializers = const [],
    Iterable<JsonDeserializer<Object>> deserializers = const [],
    Iterable<JsonModule> modules = const [],
  }) : introspector = introspector ?? BeanIntrospector.shared,
       _offset = timeZone == null ? null : _parseTimeZone(timeZone),
       serializers = List.unmodifiable([
         ...serializers,
         for (final module in modules) ...module.serializers,
       ]),
       deserializers = List.unmodifiable([
         ...deserializers,
         for (final module in modules) ...module.deserializers,
       ]);

  /// Where class metadata comes from.
  final BeanIntrospector introspector;

  /// Dart property name → JSON name (unless `@JsonProperty` says).
  final PropertyNamingStrategy namingStrategy;

  /// Which property values are written (unless `@JsonInclude` says).
  final JsonInclusion inclusion;

  /// Whether JSON properties a class does not have are an error.
  final bool failOnUnknownProperties;

  /// Whether `DateTime` and `Duration` are written as milliseconds.
  final bool writeDatesAsTimestamps;

  /// The time zone dates are written in (Jackson's `setTimeZone`,
  /// `spring.jackson.time-zone`): `UTC`, `Z` or a fixed offset; `null`
  /// writes each `DateTime` in its own zone (local or UTC).
  final String? timeZone;

  final Duration? _offset;

  /// Whether [writeValueAsString] pretty-prints.
  final bool indentOutput;

  /// Whether the properties of an object are written sorted by JSON name
  /// (constructor parameters first), instead of in declaration order;
  /// `spring.jackson.mapper.sort-properties-alphabetically`.
  final bool sortPropertiesAlphabetically;

  /// Custom writers, tried before the built-in conversions.
  final List<JsonSerializer<Object>> serializers;

  /// Custom readers, tried before the built-in conversions.
  final List<JsonDeserializer<Object>> deserializers;

  static final _conversion = DefaultConversionService();
  final _classes = <BeanIntrospection<Object>, _ClassInfo>{};

  // -------------------------------------------------------------------
  // Writing
  // -------------------------------------------------------------------

  /// [value] as a JSON string.
  ///
  /// ```dart
  /// mapper.writeValueAsString(Book(isbn: '1', title: 'Dune')); // {"isbn":"1",...}
  /// ```
  String writeValueAsString(Object? value) {
    final tree = valueToTree(value);
    return indentOutput
        ? const JsonEncoder.withIndent('  ').convert(tree)
        : jsonEncode(tree);
  }

  /// [value] as decoded JSON: `null`, bools, numbers, strings, lists and
  /// maps (what `jsonDecode` returns). [type] helps with enums that use
  /// `@JsonValue`.
  Object? valueToTree(Object? value, [TypeInfo<Object?>? type]) =>
      _write(value, _Path.root, Set.identity(), type);

  // -------------------------------------------------------------------
  // Reading
  // -------------------------------------------------------------------

  /// A [T] from the JSON string [json]. Pass [type] for generic types:
  /// `readValue(json, const ListType<Book>(ClassType<Book>()))` (or use
  /// [readList] / [readMap]).
  ///
  /// ```dart
  /// final book = mapper.readValue<Book>('{"isbn":"1","title":"Dune"}');
  /// ```
  T readValue<T>(String json, [TypeInfo<T>? type]) {
    final Object? tree;
    try {
      tree = jsonDecode(json);
    } on FormatException catch (error) {
      throw JsonMappingException(
        'invalid JSON: ${error.message}',
        cause: error,
      );
    }
    return treeToValue<T>(tree, type);
  }

  /// A [T] from decoded JSON [tree] (e.g. what an HTTP client decoded).
  T treeToValue<T>(Object? tree, [TypeInfo<T>? type]) =>
      _read(tree, type ?? _classType<T>(), _Path.root) as T;

  /// A `List<E>` from the JSON array [json].
  ///
  /// ```dart
  /// final books = mapper.readList<Book>('[{"isbn":"1","title":"Dune"}]');
  /// ```
  List<E> readList<E>(String json, [TypeInfo<E>? element]) =>
      readValue(json, ListType<E>(element ?? _classType<E>()));

  /// A `Map<String, V>` from the JSON object [json].
  Map<String, V> readMap<V>(String json, [TypeInfo<V>? value]) => readValue(
    json,
    MapType<String, V>(const ClassType<String>(), value ?? _classType<V>()),
  );

  /// [value] converted to [T] through JSON, like Jackson's `convertValue`
  /// (e.g. a `Map` into an object, or an object into another class with the
  /// same properties).
  T convertValue<T>(Object? value, [TypeInfo<T>? type]) =>
      treeToValue<T>(valueToTree(value), type);

  // -------------------------------------------------------------------
  // Implementation
  // -------------------------------------------------------------------

  static ClassType<T> _classType<T>() => ClassType<T>(nullable: null is T);

  // [S] is [B] or `B?`.
  static bool _is<S, B>() => S == B || (<S>[] is List<B?> && <B?>[] is List<S>);

  _ClassInfo _info(BeanIntrospection<Object> introspection) =>
      _classes[introspection] ??= _ClassInfo(introspection, this);

  Object? _write(
    Object? value,
    _Path path,
    Set<Object> seen, [
    TypeInfo<Object?>? type,
  ]) {
    if (value == null) {
      return null;
    }
    for (final serializer in serializers) {
      if (serializer.handles(value)) {
        final result = serializer.write(value, this);
        return result is Map || result is Iterable
            ? _write(result, path, seen)
            : result;
      }
    }
    switch (value) {
      case String() || bool() || int():
        return value;
      case double():
        // Jackson's WRITE_NAN_AS_STRINGS: "NaN", "Infinity", "-Infinity".
        return value.isFinite ? value : value.toString();
      case DateTime():
        return writeDatesAsTimestamps
            ? value.millisecondsSinceEpoch
            : _writeDate(value);
      case Duration():
        return writeDatesAsTimestamps
            ? value.inMilliseconds
            : _isoDuration(value);
      case Uri() || BigInt():
        return value.toString();
      case Enum():
        return switch (type) {
          final EnumType<Enum> enumType => enumType.toJsonValue(value),
          _ => value.name,
        };
    }
    if (!seen.add(value)) {
      throw JsonMappingException(
        'cycle: ${value.runtimeType} refers back to itself',
        path: '$path',
      );
    }
    try {
      if (value case final Map<Object?, Object?> map) {
        final valueType = type is MapType ? type.value : null;
        return {
          for (final MapEntry(:key, value: item) in map.entries)
            _writeKey(key, path): _write(
              item,
              path.key(_writeKey(key, path)),
              seen,
              valueType,
            ),
        };
      }
      if (value case final Iterable<Object?> items) {
        final elementType = switch (type) {
          ListType(:final element) || SetType(:final element) => element,
          _ => null,
        };
        var index = 0;
        return [
          for (final item in items)
            _write(item, path.index(index++), seen, elementType),
        ];
      }
      final introspection = introspector.findIntrospection(value);
      if (introspection != null) {
        if (introspection.hasToJson) {
          return _write(introspection.toJson(value), path, seen);
        }
        return _info(introspection).write(value, path, seen);
      }
      return _write(_dynamicToJson(value, path), path, seen);
    } finally {
      seen.remove(value);
    }
  }

  // Objects that are not introspected may still have a `toJson()` (the
  // convention `jsonEncode` relies on too).
  Object? _dynamicToJson(Object value, _Path path) {
    try {
      // ignore: avoid_dynamic_calls
      return (value as dynamic).toJson();
    } on NoSuchMethodError {
      throw JsonMappingException(
        '${value.runtimeType} cannot be written as JSON: mark it '
        '@Introspected(), give it a toJson() method, or register a '
        'JsonSerializer',
        path: '$path',
      );
    }
  }

  String _writeKey(Object? key, _Path path) => switch (key) {
    final String key => key,
    final Enum key => key.name,
    final DateTime key => _writeDate(key),
    null => throw JsonMappingException(
      'null map keys cannot be written as JSON',
      path: '$path',
    ),
    final Object key => key.toString(),
  };

  // ISO-8601 with the offset, like Jackson's OffsetDateTime: in [timeZone]
  // when set, otherwise in the value's own zone (`Z` for UTC).
  String _writeDate(DateTime value) {
    final offset = _offset ?? (value.isUtc ? null : value.timeZoneOffset);
    if (offset == null || (_offset != null && offset == Duration.zero)) {
      return value.toUtc().toIso8601String();
    }
    final text = (_offset == null ? value : value.toUtc().add(offset))
        .toIso8601String();
    final local = text.endsWith('Z')
        ? text.substring(0, text.length - 1)
        : text;
    final minutes = offset.inMinutes.abs();
    return '$local${offset.isNegative ? '-' : '+'}'
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
  }

  // `UTC`, `GMT`, `Z`, or an offset such as `+02:00`, `-0530`, `GMT+2`,
  // `UTC+02:00`. Named zones (`Europe/Berlin`) need a tz database.
  static Duration _parseTimeZone(String timeZone) {
    final match = RegExp(
      r'^(?:UTC|GMT|UT|Z)?(?:([+-])(\d{1,2})(?::?(\d{2}))?)?$',
    ).firstMatch(timeZone.trim());
    if (timeZone.trim().isEmpty || match == null) {
      throw ArgumentError.value(
        timeZone,
        'timeZone',
        'use UTC or a fixed offset such as +02:00 (named time zones are not '
            'supported: Dart has no time zone database)',
      );
    }
    if (match[1] == null) {
      return Duration.zero;
    }
    final offset = Duration(
      hours: int.parse(match[2]!),
      minutes: int.parse(match[3] ?? '0'),
    );
    if (offset > const Duration(hours: 18)) {
      throw ArgumentError.value(timeZone, 'timeZone', 'offset out of range');
    }
    return match[1] == '-' ? -offset : offset;
  }

  static String _isoDuration(Duration duration) {
    final negative = duration.isNegative;
    var micros = duration.inMicroseconds.abs();
    final hours = micros ~/ Duration.microsecondsPerHour;
    micros -= hours * Duration.microsecondsPerHour;
    final minutes = micros ~/ Duration.microsecondsPerMinute;
    micros -= minutes * Duration.microsecondsPerMinute;
    final seconds = micros / Duration.microsecondsPerSecond;
    final text = StringBuffer(negative ? '-PT' : 'PT');
    if (hours > 0) {
      text.write('${hours}H');
    }
    if (minutes > 0) {
      text.write('${minutes}M');
    }
    if (seconds > 0 || (hours == 0 && minutes == 0)) {
      text
        ..write(
          seconds == seconds.truncateToDouble()
              ? seconds.toInt()
              : seconds.toString(),
        )
        ..write('S');
    }
    return text.toString();
  }

  Object? _read(Object? json, TypeInfo<Object?> type, _Path path) {
    if (json == null) {
      if (type.nullable) {
        return null;
      }
      throw JsonMappingException(
        'null is not allowed here (expected $type)',
        path: '$path',
      );
    }
    return type.accept(_Reader(this, json, path));
  }

  Object _readClass<T>(Object json, _Path path) {
    for (final deserializer in deserializers) {
      if (deserializer.handles<T>()) {
        try {
          return deserializer.deserialize(json, this);
        } on JsonMappingException {
          rethrow;
        } on Object catch (error) {
          throw JsonMappingException(
            'cannot read $T: $error',
            path: '$path',
            cause: error,
          );
        }
      }
    }
    if (_is<T, String>()) {
      return switch (json) {
        final String text => text,
        num() || bool() => json.toString(),
        _ => throw _expected('a string', json, path),
      };
    }
    if (_is<T, int>()) {
      return switch (json) {
        final int value => value,
        final double value when value == value.truncateToDouble() =>
          value.toInt(),
        final String text when int.tryParse(text) != null => int.parse(text),
        _ => throw _expected('an integer', json, path),
      };
    }
    if (_is<T, double>()) {
      return switch (json) {
        final num value => value.toDouble(),
        final String text when double.tryParse(text) != null => double.parse(
          text,
        ),
        _ => throw _expected('a number', json, path),
      };
    }
    if (_is<T, num>()) {
      return switch (json) {
        final num value => value,
        final String text when num.tryParse(text) != null => num.parse(text),
        _ => throw _expected('a number', json, path),
      };
    }
    if (_is<T, bool>()) {
      return switch (json) {
        final bool value => value,
        'true' => true,
        'false' => false,
        _ => throw _expected('true or false', json, path),
      };
    }
    if (_is<T, DateTime>()) {
      return switch (json) {
        final String text when DateTime.tryParse(text) != null =>
          DateTime.parse(text),
        final int millis => DateTime.fromMillisecondsSinceEpoch(
          millis,
          isUtc: true,
        ),
        _ => throw _expected('an ISO-8601 date-time', json, path),
      };
    }
    if (_is<T, Duration>()) {
      if (json is int) {
        return Duration(milliseconds: json);
      }
      if (json is String) {
        try {
          return _conversion.convert<Duration>(json);
        } on Object {
          // reported below
        }
      }
      throw _expected('a duration such as "PT1M30S"', json, path);
    }
    if (_is<T, Uri>()) {
      return switch (json) {
        final String text when Uri.tryParse(text) != null => Uri.parse(text),
        _ => throw _expected('a URI', json, path),
      };
    }
    if (_is<T, BigInt>()) {
      return switch (json) {
        final int value => BigInt.from(value),
        final String text when BigInt.tryParse(text) != null => BigInt.parse(
          text,
        ),
        _ => throw _expected('an integer', json, path),
      };
    }
    if (_is<T, Object>()) {
      return json;
    }
    final introspection = introspector.forTypeArgument<T>();
    if (introspection != null) {
      return _info(introspection).read(json, path);
    }
    if (<T>[] is List<Iterable<Object?>?> ||
        <T>[] is List<Map<Object?, Object?>?>) {
      // Map<String, dynamic>, List<dynamic> (Jackson's raw Map / List):
      // the decoded JSON as it is.
      if (json is T) {
        return json;
      }
      throw JsonMappingException(
        'cannot read $T without its element types: pass a type, e.g. '
        'readValue(json, const ListType<Book>(ClassType<Book>())), or use '
        'readList / readMap',
        path: '$path',
      );
    }
    throw JsonMappingException(
      'cannot read $T: mark it @Introspected() (and register its module) or '
      'register a JsonDeserializer',
      path: '$path',
    );
  }

  Object _readEnum<E extends Enum>(EnumType<E> type, Object json, _Path path) {
    for (final value in type.values) {
      if (type.toJsonValue(value) == json) {
        return value;
      }
    }
    // The name is accepted too (also when @JsonValue gives another form).
    for (final value in type.values) {
      if (value.name == json) {
        return value;
      }
    }
    throw _expected(
      'one of ${[for (final v in type.values) jsonEncode(type.toJsonValue(v))].join(', ')}',
      json,
      path,
    );
  }

  Object? _readKey(String key, TypeInfo<Object?> type, _Path path) {
    final Object json = switch (type) {
      ClassType<int>() || ClassType<int?>() => int.tryParse(key) ?? key,
      ClassType<double>() || ClassType<num>() => num.tryParse(key) ?? key,
      _ => key,
    };
    return _read(json, type, path);
  }

  JsonMappingException _expected(String what, Object? json, _Path path) =>
      JsonMappingException(
        'expected $what, got ${_describe(json)}',
        path: '$path',
      );

  static String _describe(Object? json) => switch (json) {
    null => 'null',
    final String text => jsonEncode(
      text.length > 40 ? '${text.substring(0, 40)}...' : text,
    ),
    List() => 'a list',
    Map() => 'an object',
    _ => '$json',
  };
}

/// Builds a value of the visited type from decoded [json].
final class _Reader implements TypeInfoVisitor<Object?> {
  _Reader(this.mapper, this.json, this.path);

  final ObjectMapper mapper;
  final Object json;
  final _Path path;

  @override
  Object? visitDynamic(DynamicType type) => json;

  @override
  Object? visitClass<T>(ClassType<T> type) => mapper._readClass<T>(json, path);

  @override
  Object? visitEnum<E extends Enum>(EnumType<E> type) =>
      mapper._readEnum<E>(type, json, path);

  // Generic classes are read by a JsonDeserializer or their own fromJson;
  // generic introspected classes are not supported yet.
  @override
  Object? visitGeneric<T>(GenericType<T> type) =>
      mapper._readClass<T>(json, path);

  @override
  Object? visitList<E>(ListType<E> type) => type.create(_items(type.element));

  @override
  Object? visitSet<E>(SetType<E> type) => type.create(_items(type.element));

  List<Object?> _items(TypeInfo<Object?> element) {
    final list = json;
    if (list is! List<Object?>) {
      throw mapper._expected('a list', json, path);
    }
    return [
      for (var i = 0; i < list.length; i++)
        mapper._read(list[i], element, path.index(i)),
    ];
  }

  @override
  Object? visitMap<K, V>(MapType<K, V> type) {
    final map = json;
    if (map is! Map<Object?, Object?>) {
      throw mapper._expected('an object', json, path);
    }
    return type.create([
      for (final MapEntry(:key, :value) in map.entries)
        MapEntry(
          mapper._readKey('$key', type.key, path.key('$key')),
          mapper._read(value, type.value, path.key('$key')),
        ),
    ]);
  }
}

/// JSON names, ignored and included properties of one class (cached).
final class _ClassInfo {
  _ClassInfo(this.introspection, this.mapper) {
    final classAnnotations = introspection.annotations;
    final ignoreProperties = classAnnotations
        .whereType<JsonIgnoreProperties>()
        .firstOrNull;
    ignoreUnknown = ignoreProperties?.ignoreUnknown ?? false;
    ignoredNames.addAll(ignoreProperties?.value ?? const []);
    classInclusion = classAnnotations
        .whereType<JsonInclude>()
        .firstOrNull
        ?.value;
    for (final property in introspection.properties) {
      final name = _name(property.name, property.annotations);
      jsonNames[property.name] = name;
      if (property.annotations.whereType<JsonIgnore>().isNotEmpty ||
          ignoredNames.contains(name)) {
        ignoredNames.add(name);
      }
    }
    for (final parameter
        in introspection.constructor?.parameters ?? const <BeanParameter>[]) {
      final name =
          _explicitName(parameter.annotations) ??
          jsonNames[parameter.name] ??
          mapper.namingStrategy.translate(parameter.name);
      parameterNames[parameter.name] = name;
      if (parameter.annotations.whereType<JsonIgnore>().isNotEmpty) {
        ignoredNames.add(name);
      }
    }
    known
      ..addAll(jsonNames.values)
      ..addAll(parameterNames.values);
    writeOrder = _writeOrder(
      classAnnotations.whereType<JsonPropertyOrder>().firstOrNull,
    );
  }

  final BeanIntrospection<Object> introspection;
  final ObjectMapper mapper;
  late final bool ignoreUnknown;
  late final JsonInclusion? classInclusion;

  /// Dart property name → JSON name.
  final jsonNames = <String, String>{};

  /// Dart constructor parameter name → JSON name.
  final parameterNames = <String, String>{};

  /// JSON names left out in both directions.
  final ignoredNames = <String>{};

  /// Every JSON name the class reads.
  final known = <String>{};

  /// The properties in the order they are written.
  late final List<BeanProperty<Object>> writeOrder;

  // Jackson's POJOPropertiesCollector._sortProperties: the names of
  // `@JsonPropertyOrder` first, then (when sorting) the constructor
  // parameters, then the rest; sorted by JSON name when [sorting], else in
  // declaration order.
  List<BeanProperty<Object>> _writeOrder(JsonPropertyOrder? order) {
    final properties = introspection.properties.toList();
    final sorting =
        (order?.alphabetic ?? false) || mapper.sortPropertiesAlphabetically;
    if (!sorting && (order == null || order.value.isEmpty)) {
      return properties;
    }
    int byName(BeanProperty<Object> a, BeanProperty<Object> b) =>
        jsonNames[a.name]!.compareTo(jsonNames[b.name]!);
    if (sorting) {
      properties.sort(byName);
    }
    final ordered = <BeanProperty<Object>>[];
    for (final name in order?.value ?? const <String>[]) {
      // A JSON name, or the Dart name of a property.
      var index = properties.indexWhere((p) => jsonNames[p.name] == name);
      if (index < 0) {
        index = properties.indexWhere((p) => p.name == name);
      }
      if (index >= 0) {
        ordered.add(properties.removeAt(index));
      }
    }
    if (sorting) {
      final creator = {
        for (final parameter
            in introspection.constructor?.parameters ?? const <BeanParameter>[])
          parameter.name,
      };
      ordered.addAll(properties.where((p) => creator.contains(p.name)));
      properties.removeWhere((p) => creator.contains(p.name));
    }
    return ordered..addAll(properties);
  }

  String _name(String dartName, List<Object> annotations) =>
      _explicitName(annotations) ?? mapper.namingStrategy.translate(dartName);

  static String? _explicitName(List<Object> annotations) =>
      annotations.whereType<JsonProperty>().firstOrNull?.name;

  Map<String, Object?> write(Object bean, _Path path, Set<Object> seen) {
    final result = <String, Object?>{};
    for (final property in writeOrder) {
      final name = jsonNames[property.name]!;
      if (ignoredNames.contains(name)) {
        continue;
      }
      final value = property.getValue(bean);
      final rule =
          property.annotations.whereType<JsonInclude>().firstOrNull?.value ??
          classInclusion ??
          mapper.inclusion;
      if (!_included(value, rule)) {
        continue;
      }
      result[name] = mapper._write(
        value,
        path.key(name),
        seen,
        property.typeInfo,
      );
    }
    return result;
  }

  static bool _included(Object? value, JsonInclusion rule) => switch (rule) {
    JsonInclusion.always => true,
    JsonInclusion.nonNull => value != null,
    JsonInclusion.nonEmpty =>
      value != null &&
          !(value is String && value.isEmpty) &&
          !(value is Iterable && value.isEmpty) &&
          !(value is Map && value.isEmpty),
  };

  Object read(Object json, _Path path) {
    if (introspection.hasFromJson) {
      try {
        return introspection.fromJson(json);
      } on JsonMappingException {
        rethrow;
      } on Object catch (error) {
        throw JsonMappingException(
          'fromJson of ${introspection.beanType} failed: $error',
          path: '$path',
          cause: error,
        );
      }
    }
    if (json is! Map<Object?, Object?>) {
      throw mapper._expected('an object', json, path);
    }
    final used = <String>{};
    final Object bean;
    final constructor = introspection.constructor;
    if (constructor != null) {
      bean = _construct(constructor, json, path, used);
    } else if (introspection.isInstantiable) {
      bean = introspection.instantiate();
    } else {
      throw JsonMappingException(
        '${introspection.beanType} has no public constructor to create it '
        'from JSON (add one, or mark one @JsonCreator())',
        path: '$path',
      );
    }
    for (final property in introspection.properties) {
      final name = jsonNames[property.name]!;
      if (used.contains(name) ||
          ignoredNames.contains(name) ||
          !json.containsKey(name)) {
        continue;
      }
      used.add(name);
      if (!property.isWritable) {
        continue; // final and not a constructor parameter: nothing to set
      }
      final value = mapper._read(
        json[name],
        property.typeInfo ?? const DynamicType(),
        path.key(name),
      );
      if (value == null && !property.nullable) {
        throw JsonMappingException(
          'null is not allowed here',
          path: '${path.key(name)}',
        );
      }
      try {
        property.setValue(bean, value);
      } on Object catch (error) {
        throw JsonMappingException(
          'cannot set ${property.name}: $error',
          path: '${path.key(name)}',
          cause: error,
        );
      }
    }
    if (mapper.failOnUnknownProperties && !ignoreUnknown) {
      for (final key in json.keys) {
        if (!used.contains(key) &&
            !known.contains(key) &&
            !ignoredNames.contains(key)) {
          throw JsonMappingException(
            'unknown property "$key" of ${introspection.beanType} (known: '
            '${known.join(', ')})',
            path: '$path',
          );
        }
      }
    }
    return bean;
  }

  Object _construct(
    BeanConstructor<Object> constructor,
    Map<Object?, Object?> json,
    _Path path,
    Set<String> used,
  ) {
    final positional = <(BeanParameter, Object?, bool)>[];
    final named = <Symbol, Object?>{};
    for (final parameter in constructor.parameters) {
      final name = parameterNames[parameter.name]!;
      final present = json.containsKey(name) && !ignoredNames.contains(name);
      Object? value;
      if (present) {
        used.add(name);
        value = mapper._read(json[name], parameter.type, path.key(name));
      } else if (parameter.isRequired) {
        if (!parameter.type.nullable) {
          throw JsonMappingException(
            'missing property "$name" (required by '
            '${introspection.beanType})',
            path: '$path',
          );
        }
      }
      if (parameter.isNamed) {
        if (present || parameter.isRequired) {
          named[parameter.symbol!] = value;
        }
      } else {
        positional.add((parameter, value, present || parameter.isRequired));
      }
    }
    // Trailing optional positional parameters that are absent keep their
    // defaults; an absent one before a present one can only be null.
    while (positional.isNotEmpty && !positional.last.$3) {
      positional.removeLast();
    }
    for (final (parameter, _, given) in positional) {
      if (!given && !parameter.type.nullable) {
        throw JsonMappingException(
          'missing property "${parameterNames[parameter.name]}": a later '
          'positional parameter is given, so this one cannot keep its default',
          path: '$path',
        );
      }
    }
    try {
      return constructor.newInstance([
        for (final (_, value, _) in positional) value,
      ], named);
    } on JsonMappingException {
      rethrow;
    } on Object catch (error) {
      throw JsonMappingException(
        'cannot create ${introspection.beanType}: $error',
        path: '$path',
        cause: error,
      );
    }
  }
}

/// A position in a JSON document: `items[2].price`.
final class _Path {
  const _Path._(this._parent, this._segment);

  static const root = _Path._(null, '');
  static final _identifier = RegExp(r'^[A-Za-z_$][\w$-]*$');

  final _Path? _parent;
  final String _segment;

  _Path key(String key) => _Path._(
    this,
    _identifier.hasMatch(key) ? '.$key' : '[${jsonEncode(key)}]',
  );

  _Path index(int index) => _Path._(this, '[$index]');

  @override
  String toString() {
    final segments = <String>[];
    for (_Path? path = this; path != null; path = path._parent) {
      segments.add(path._segment);
    }
    final text = segments.reversed.join();
    return text.startsWith('.') ? text.substring(1) : text;
  }
}
