import 'dart:convert';

import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/type_info.dart';
import 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';
import 'package:spring_core_dart/src/json/annotations.dart';
import 'package:spring_core_dart/src/json/date_format.dart';
import 'package:spring_core_dart/src/json/json_exception.dart';
import 'package:spring_core_dart/src/json/json_mapper.dart';
import 'package:spring_core_dart/src/json/json_node.dart';
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
/// `json_serializable` or `freezed`) is converted with those. Generic
/// classes (`Page<T>`) are read with their type arguments:
/// `readValue(json, GenericType<Page<Book>>([ClassType<Book>()]))`.
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
/// final mapper = context.getBean<ObjectMapper>(); // or JsonMapper.builder()...build()
/// final json = mapper.writeValueAsString(book);   // {"isbn":"1","tags":[],"title":"Dune"}
/// final again = mapper.readValue<Book>(json);
/// final books = mapper.readList<Book>('[{"isbn":"1","title":"Dune"}]');
/// final tree = mapper.readTree(json);             // JsonNode
/// ```
///
/// Built-in conversions: `String`, `int` (a number with a fraction is
/// truncated, like Jackson's `ACCEPT_FLOAT_AS_INT`; out of range fails),
/// `double`, `num` (`NaN` and infinities as the strings `"NaN"`,
/// `"Infinity"`, `"-Infinity"`, like Jackson), `bool`, `DateTime`
/// (ISO-8601 like Jackson writes an `OffsetDateTime`:
/// `2026-01-01T12:00:00.000+02:00` for a local time, `Z` for UTC, converted
/// to [timeZone] when set; read strictly, text without an offset in
/// [timeZone] or UTC; or a timestamp with [writeDatesAsTimestamps]: seconds
/// with the fraction (`1767268800.5`) like Jackson 3, or milliseconds
/// without [writeDateTimestampsAsNanoseconds]), `Duration` (ISO-8601 such
/// as `PT1M30S`, also read from `90s`; or seconds / milliseconds the same
/// way with [writeDurationsAsTimestamps]), `Uri`, `BigInt` (as a string),
/// enums (by name or `@JsonValue`; read also by index), `List`, `Set`,
/// `Map`, nullable types (`""` reads as `null` for nullable numbers,
/// booleans, dates and durations), [JsonNode] trees and nested objects.
/// `Map<String, dynamic>`, `List<dynamic>` and `Object?` read without a
/// type are the plain decoded JSON. Anything else: a [JsonSerializer] /
/// [JsonDeserializer].
///
/// Annotations: `@JsonProperty`, `@JsonAlias`, `@JsonIgnore`,
/// `@JsonIgnoreProperties`, `@JsonInclude`, `@JsonPropertyOrder`,
/// `@JsonCreator`, `@JsonValue`, `@JsonFormat`, `@JsonNaming`,
/// `@JsonView`, `@JsonUnwrapped`, `@JsonAnyGetter` / `@JsonAnySetter` and
/// polymorphism with `@JsonTypeInfo` / `@JsonSubTypes` / `@JsonTypeName`.
///
/// Spring (Java):
/// ```java
/// JsonMapper mapper = JsonMapper.builder().build();
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
  /// [acceptFloatAsInt] truncates numbers with a fraction read into an
  /// `int` (on, like Jackson); [writeDatesAsTimestamps] /
  /// [writeDurationsAsTimestamps] write `DateTime` / `Duration` as numbers
  /// (off, like Jackson 3), in seconds with the fraction
  /// ([writeDateTimestampsAsNanoseconds], on) or milliseconds; numbers are
  /// read as seconds when [readDateTimestampsAsNanoseconds] (on), else as
  /// milliseconds (a number with a fraction is always seconds); [timeZone]
  /// (`UTC`, `Z` or a fixed offset such as `+02:00` or `GMT+2`) is the
  /// offset dates are written in and dates without an offset are read in;
  /// [indentOutput] pretty-prints; [sortPropertiesAlphabetically] writes
  /// the properties of an object sorted by JSON name (Jackson 3's default,
  /// `MapperFeature.SORT_PROPERTIES_ALPHABETICALLY`; a class's constructor
  /// parameters come first, like `SORT_CREATOR_PROPERTIES_FIRST`), `false`
  /// writes them in declaration order (Jackson 2's, superclass first);
  /// `@JsonPropertyOrder` wins either way; [defaultViewInclusion] includes
  /// properties without `@JsonView` when a view is active (off, like
  /// Jackson 3). The serializers and deserializers of [modules] come after
  /// [serializers] / [deserializers].
  ObjectMapper({
    BeanIntrospector? introspector,
    this.namingStrategy = PropertyNamingStrategy.lowerCamelCase,
    this.inclusion = JsonInclusion.always,
    this.failOnUnknownProperties = false,
    this.acceptFloatAsInt = true,
    this.writeDatesAsTimestamps = false,
    this.writeDurationsAsTimestamps = false,
    this.writeDateTimestampsAsNanoseconds = true,
    this.readDateTimestampsAsNanoseconds = true,
    this.timeZone,
    this.indentOutput = false,
    this.sortPropertiesAlphabetically = true,
    this.defaultViewInclusion = false,
    Iterable<JsonSerializer<Object>> serializers = const [],
    Iterable<JsonDeserializer<Object>> deserializers = const [],
    Iterable<JsonModule> modules = const [],
  }) : introspector = introspector ?? BeanIntrospector.shared,
       _offset = timeZone == null ? null : parseTimeZone(timeZone),
       _view = null,
       serializers = List.unmodifiable([
         ...serializers,
         for (final module in modules) ...module.serializers,
       ]),
       deserializers = List.unmodifiable([
         ...deserializers,
         for (final module in modules) ...module.deserializers,
       ]);

  ObjectMapper._withView(ObjectMapper other, this._view)
    : introspector = other.introspector,
      namingStrategy = other.namingStrategy,
      inclusion = other.inclusion,
      failOnUnknownProperties = other.failOnUnknownProperties,
      acceptFloatAsInt = other.acceptFloatAsInt,
      writeDatesAsTimestamps = other.writeDatesAsTimestamps,
      writeDurationsAsTimestamps = other.writeDurationsAsTimestamps,
      writeDateTimestampsAsNanoseconds = other.writeDateTimestampsAsNanoseconds,
      readDateTimestampsAsNanoseconds = other.readDateTimestampsAsNanoseconds,
      timeZone = other.timeZone,
      _offset = other._offset,
      indentOutput = other.indentOutput,
      sortPropertiesAlphabetically = other.sortPropertiesAlphabetically,
      defaultViewInclusion = other.defaultViewInclusion,
      serializers = other.serializers,
      deserializers = other.deserializers;

  /// Where class metadata comes from.
  final BeanIntrospector introspector;

  /// Dart property name → JSON name (unless `@JsonProperty` or `@JsonNaming`
  /// says).
  final PropertyNamingStrategy namingStrategy;

  /// Which property values are written (unless `@JsonInclude` says).
  final JsonInclusion inclusion;

  /// Whether JSON properties a class does not have are an error.
  final bool failOnUnknownProperties;

  /// Whether a number with a fraction read into an `int` is truncated
  /// (Jackson's `ACCEPT_FLOAT_AS_INT`); otherwise it is an error.
  final bool acceptFloatAsInt;

  /// Whether `DateTime` is written as a timestamp.
  final bool writeDatesAsTimestamps;

  /// Whether `Duration` is written as a number.
  final bool writeDurationsAsTimestamps;

  /// Whether timestamps are written as seconds with the fraction (Jackson
  /// 3's `WRITE_DATE_TIMESTAMPS_AS_NANOSECONDS`), not milliseconds.
  final bool writeDateTimestampsAsNanoseconds;

  /// Whether integer timestamps are read as seconds (Jackson 3's
  /// `READ_DATE_TIMESTAMPS_AS_NANOSECONDS`), not milliseconds.
  final bool readDateTimestampsAsNanoseconds;

  /// The time zone dates are written in and dates without an offset are
  /// read in (Jackson's `setTimeZone`, `spring.jackson.time-zone`): `UTC`,
  /// `Z` or a fixed offset; `null` writes each `DateTime` in its own zone
  /// (local or UTC) and reads in UTC.
  final String? timeZone;

  final Duration? _offset;

  /// Whether [writeValueAsString] pretty-prints.
  final bool indentOutput;

  /// Whether the properties of an object are written sorted by JSON name
  /// (constructor parameters first), instead of in declaration order;
  /// `spring.jackson.mapper.sort-properties-alphabetically`.
  final bool sortPropertiesAlphabetically;

  /// Whether properties without `@JsonView` are included when a view is
  /// active (Jackson's `DEFAULT_VIEW_INCLUSION`).
  final bool defaultViewInclusion;

  /// Custom writers, tried before the built-in conversions.
  final List<JsonSerializer<Object>> serializers;

  /// Custom readers, tried before the built-in conversions.
  final List<JsonDeserializer<Object>> deserializers;

  final Type? _view;

  static final _conversion = DefaultConversionService();
  static final _patterns = <String, DatePattern>{};
  final _classes = <BeanIntrospection<Object>, _ClassInfo>{};
  final _polymorphisms = <BeanIntrospection<Object>, _Polymorphism>{};

  // dart2js: every number is a double, `int` is exact up to 2^53.
  static const _web = identical(0, 0.0);
  static const double _intLimit = _web
      ? 9007199254740992.0
      : 9223372036854775808.0;

  /// Whether [feature] is on in this mapper.
  bool isEnabled(JsonFeature feature) => switch (feature) {
    SerializationFeature.indentOutput => indentOutput,
    DeserializationFeature.failOnUnknownProperties => failOnUnknownProperties,
    DeserializationFeature.acceptFloatAsInt => acceptFloatAsInt,
    DateTimeFeature.writeDatesAsTimestamps => writeDatesAsTimestamps,
    DateTimeFeature.writeDurationsAsTimestamps => writeDurationsAsTimestamps,
    DateTimeFeature.writeDateTimestampsAsNanoseconds =>
      writeDateTimestampsAsNanoseconds,
    DateTimeFeature.readDateTimestampsAsNanoseconds =>
      readDateTimestampsAsNanoseconds,
    MapperFeature.sortPropertiesAlphabetically => sortPropertiesAlphabetically,
    MapperFeature.defaultViewInclusion => defaultViewInclusion,
    _ => feature.enabledByDefault,
  };

  /// A builder with this mapper's configuration, to derive another mapper
  /// (Jackson 3's `rebuild()`; mappers are immutable).
  ///
  /// ```dart
  /// final strict = mapper.rebuild()
  ///     .enable(DeserializationFeature.failOnUnknownProperties)
  ///     .build();
  /// ```
  JsonMapperBuilder rebuild() => JsonMapperBuilder()
      .introspector(introspector)
      .propertyNamingStrategy(namingStrategy)
      .defaultPropertyInclusion(inclusion)
      .defaultTimeZone(timeZone)
      .configure(SerializationFeature.indentOutput, indentOutput)
      .configure(
        DeserializationFeature.failOnUnknownProperties,
        failOnUnknownProperties,
      )
      .configure(DeserializationFeature.acceptFloatAsInt, acceptFloatAsInt)
      .configure(DateTimeFeature.writeDatesAsTimestamps, writeDatesAsTimestamps)
      .configure(
        DateTimeFeature.writeDurationsAsTimestamps,
        writeDurationsAsTimestamps,
      )
      .configure(
        DateTimeFeature.writeDateTimestampsAsNanoseconds,
        writeDateTimestampsAsNanoseconds,
      )
      .configure(
        DateTimeFeature.readDateTimestampsAsNanoseconds,
        readDateTimestampsAsNanoseconds,
      )
      .configure(
        MapperFeature.sortPropertiesAlphabetically,
        sortPropertiesAlphabetically,
      )
      .configure(MapperFeature.defaultViewInclusion, defaultViewInclusion)
      .addSerializers(serializers)
      .addDeserializers(deserializers);

  /// A writer that writes only the properties of [view] (see `@JsonView`).
  ///
  /// ```dart
  /// mapper.writerWithView(Public).writeValueAsString(user);
  /// ```
  ObjectWriter writerWithView(Type view) =>
      ObjectWriter._(ObjectMapper._withView(this, view));

  /// A reader that reads only the properties of [view]; the others in the
  /// JSON are skipped.
  ObjectReader readerWithView(Type view) =>
      ObjectReader._(ObjectMapper._withView(this, view));

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
  /// `@JsonValue`. Use `JsonNode.from(mapper.valueToTree(value))` for a
  /// [JsonNode].
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
  T readValue<T>(String json, [TypeInfo<T>? type]) =>
      treeToValue<T>(_decode(json), type);

  static Object? _decode(String json) {
    try {
      return jsonDecode(json);
    } on FormatException catch (error) {
      throw JsonMappingException(
        'invalid JSON: ${error.message}',
        cause: error,
      );
    }
  }

  /// The JSON string [json] as a tree of [JsonNode]s (Jackson's
  /// `readTree`).
  ///
  /// ```dart
  /// mapper.readTree('{"a":[1,2]}').at('/a/1').intValue(); // 2
  /// ```
  JsonNode readTree(String json) => JsonNode.from(_decode(json));

  /// An empty [ObjectNode].
  ObjectNode createObjectNode() => ObjectNode();

  /// An empty [ArrayNode].
  ArrayNode createArrayNode() => ArrayNode();

  /// A [T] from decoded JSON [tree] (e.g. what an HTTP client decoded) or a
  /// [JsonNode].
  T treeToValue<T>(Object? tree, [TypeInfo<T>? type]) => _read(
    tree is JsonNode && !_isNodeType<T>() ? tree.toJson() : tree,
    type ?? _classType<T>(),
    _Path.root,
  ) as T;

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
  /// (e.g. a `Map` into an object, an object into another class with the
  /// same properties, or anything into a [JsonNode]).
  T convertValue<T>(Object? value, [TypeInfo<T>? type]) =>
      treeToValue<T>(valueToTree(value), type);

  // -------------------------------------------------------------------
  // Implementation: writing
  // -------------------------------------------------------------------

  static ClassType<T> _classType<T>() => ClassType<T>(nullable: null is T);

  // [S] is [B] or `B?`.
  static bool _is<S, B>() => S == B || (<S>[] is List<B?> && <B?>[] is List<S>);

  static bool _isNodeType<T>() => <T>[] is List<JsonNode?>;

  _ClassInfo _info(BeanIntrospection<Object> introspection) =>
      _classes[introspection] ??= _ClassInfo(introspection, this);

  _Polymorphism _polymorphism(BeanIntrospection<Object> base) =>
      _polymorphisms[base] ??= _Polymorphism(this, base);

  // Whether the view class [active] extends [view] (both introspected).
  bool _extendsView(Type active, Type view) {
    final a = introspector.forType(active);
    final b = introspector.forType(view);
    return a != null && b != null && a.isSubtypeOf(b);
  }

  Object? _write(
    Object? value,
    _Path path,
    Set<Object> seen, [
    TypeInfo<Object?>? type,
    JsonFormat? format,
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
    final asString = format?.shape == JsonFormatShape.string;
    switch (value) {
      case String():
        return value;
      // Before `int`: on the web, infinities are ints too.
      case double() when !value.isFinite:
        // Jackson's WRITE_NAN_AS_STRINGS: "NaN", "Infinity", "-Infinity".
        return value.toString();
      case bool() || int():
        return asString ? '$value' : value;
      case double():
        return asString ? value.toString() : value;
      case DateTime():
        return _writeDateTime(value, format);
      case Duration():
        return _writeDuration(value, format);
      case Uri() || BigInt():
        return value.toString();
      case Enum():
        if (format?.shape == JsonFormatShape.number) {
          return value.index;
        }
        return switch (type) {
          final EnumType<Enum> enumType => enumType.toJsonValue(value),
          _ => value.name,
        };
      case JsonNode():
        return value.toJson();
    }
    if (!seen.add(value)) {
      throw JsonMappingException(
        'cycle: ${value.runtimeType} refers back to itself',
        path: '$path',
      );
    }
    try {
      if (value case final Map<Object?, Object?> map) {
        final (keyType, valueType) = type is MapType
            ? (type.key, type.value)
            : (null, null);
        return {
          for (final MapEntry(:key, value: item) in map.entries)
            _writeKey(key, path, keyType): _write(
              item,
              path.key(_writeKey(key, path, keyType)),
              seen,
              valueType,
              format,
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
            _write(item, path.index(index++), seen, elementType, format),
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

  String _writeKey(Object? key, _Path path, [TypeInfo<Object?>? keyType]) =>
      switch (key) {
        final String key => key,
        final Enum key => switch (keyType) {
          final EnumType<Enum> enumType => '${enumType.toJsonValue(key)}',
          _ => key.name,
        },
        final DateTime key => _writeDate(key),
        null => throw JsonMappingException(
          'null map keys cannot be written as JSON',
          path: '$path',
        ),
        final Object key => key.toString(),
      };

  Duration? _formatOffset(JsonFormat? format) =>
      format == null || format.timezone.isEmpty
      ? null
      : parseTimeZone(format.timezone, 'JsonFormat.timezone');

  static DatePattern _pattern(String pattern) =>
      _patterns[pattern] ??= DatePattern(pattern);

  Object _writeDateTime(DateTime value, JsonFormat? format) {
    final shape = format?.shape ?? JsonFormatShape.any;
    final pattern = format?.pattern ?? '';
    if (shape == JsonFormatShape.number ||
        (shape == JsonFormatShape.any &&
            pattern.isEmpty &&
            writeDatesAsTimestamps)) {
      return _timestamp(value.microsecondsSinceEpoch);
    }
    final offset = _formatOffset(format);
    if (pattern.isNotEmpty) {
      return _pattern(pattern).format(
        value,
        offset ??
            _offset ??
            (value.isUtc ? Duration.zero : value.timeZoneOffset),
      );
    }
    return _writeDate(value, offset);
  }

  // Jackson 3: seconds with the fraction (`1767268800.5`), or epoch
  // milliseconds without WRITE_DATE_TIMESTAMPS_AS_NANOSECONDS.
  num _timestamp(int micros) => writeDateTimestampsAsNanoseconds
      ? micros / Duration.microsecondsPerSecond
      : (micros / Duration.microsecondsPerMillisecond).floor();

  Object _writeDuration(Duration value, JsonFormat? format) {
    final shape = format?.shape ?? JsonFormatShape.any;
    if (shape == JsonFormatShape.number ||
        (shape == JsonFormatShape.any && writeDurationsAsTimestamps)) {
      return writeDateTimestampsAsNanoseconds
          ? value.inMicroseconds / Duration.microsecondsPerSecond
          : value.inMilliseconds;
    }
    return _isoDuration(value);
  }

  // ISO-8601 with the offset, like Jackson's OffsetDateTime: in [override]
  // or [timeZone] when set, otherwise in the value's own zone (`Z` for UTC).
  String _writeDate(DateTime value, [Duration? override]) {
    final zone = override ?? _offset;
    final offset = zone ?? (value.isUtc ? null : value.timeZoneOffset);
    if (offset == null || (zone != null && offset == Duration.zero)) {
      return value.toUtc().toIso8601String();
    }
    final text = (zone == null ? value : value.toUtc().add(offset))
        .toIso8601String();
    final local = text.endsWith('Z')
        ? text.substring(0, text.length - 1)
        : text;
    final minutes = offset.inMinutes.abs();
    return '$local${offset.isNegative ? '-' : '+'}'
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
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

  // -------------------------------------------------------------------
  // Implementation: reading
  // -------------------------------------------------------------------

  Object? _read(
    Object? json,
    TypeInfo<Object?> type,
    _Path path, [
    JsonFormat? format,
  ]) {
    if (json == null) {
      if (type.nullable) {
        return null;
      }
      throw JsonMappingException(
        'null is not allowed here (expected $type)',
        path: '$path',
      );
    }
    return type.accept(_Reader(this, json, path, format));
  }

  // Jackson's coercion of "" for scalars (CoercionAction.AsNull): numbers,
  // booleans, dates and durations.
  static bool _emptyIsNull<T>() =>
      _is<T, int>() ||
      _is<T, double>() ||
      _is<T, num>() ||
      _is<T, bool>() ||
      _is<T, BigInt>() ||
      _is<T, DateTime>() ||
      _is<T, Duration>();

  Object _readClass<T>(
    Object json,
    _Path path, {
    JsonFormat? format,
    List<TypeInfo<Object?>>? arguments,
  }) {
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
      return _readInt(json, path);
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
      return _readDateTime(json, path, format);
    }
    if (_is<T, Duration>()) {
      return _readDuration(json, path);
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
        final double value
            when value.isFinite && value == value.truncateToDouble() =>
          BigInt.from(value),
        final String text when BigInt.tryParse(text) != null => BigInt.parse(
          text,
        ),
        _ => throw _expected('an integer', json, path),
      };
    }
    if (_isNodeType<T>()) {
      final node = JsonNode.from(json);
      return node is T ? node : throw _expected('a $T', json, path);
    }
    if (_is<T, Object>()) {
      return json;
    }
    if (arguments != null) {
      final generic = introspector.forGenericType<T>(arguments);
      if (generic != null) {
        return _info(generic).read(json, path);
      }
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
    if (introspector.introspections.any(
      (i) => i.isGeneric && i.isRawTypeOf<T>(),
    )) {
      throw JsonMappingException(
        'cannot read the generic $T without its type arguments: pass a '
        'GenericType, e.g. readValue(json, GenericType<Page<Book>>(const '
        '[ClassType<Book>()]))',
        path: '$path',
      );
    }
    throw JsonMappingException(
      'cannot read $T: mark it @Introspected() (and register its module) or '
      'register a JsonDeserializer',
      path: '$path',
    );
  }

  // Jackson: a number with a fraction is truncated (ACCEPT_FLOAT_AS_INT),
  // one out of range fails (no saturation: `1e20` is not
  // 9223372036854775807).
  int _readInt(Object json, _Path path) {
    if (json is String) {
      return int.tryParse(json.trim()) ??
          (throw _expected('an integer', json, path));
    }
    if (json is! num || !json.isFinite) {
      throw _expected('an integer', json, path);
    }
    final isFloat = _web ? json != json.truncateToDouble() : json is double;
    if (isFloat && !acceptFloatAsInt) {
      throw JsonMappingException(
        'cannot coerce floating-point value ($json) to int '
        '(acceptFloatAsInt is off)',
        path: '$path',
      );
    }
    if (json is int && !_web) {
      return json;
    }
    if (json.abs() >= _intLimit) {
      throw JsonMappingException(
        'numeric value ($json) out of range of int',
        path: '$path',
      );
    }
    return json.truncate();
  }

  static final _numeric = RegExp(r'^-?\d+(\.\d+)?$');

  // A timestamp: an integer is seconds (or milliseconds without
  // readDateTimestampsAsNanoseconds), a decimal is seconds with the
  // fraction; in microseconds.
  int _timestampMicros(Object number) {
    if (number is String) {
      final negative = number.startsWith('-');
      final [whole, ...fraction] = number.replaceFirst('-', '').split('.');
      if (fraction.isEmpty) {
        return _timestampMicros(int.parse(number));
      }
      final micros =
          int.parse(whole) * Duration.microsecondsPerSecond +
          int.parse(fraction.single.padRight(6, '0').substring(0, 6));
      return negative ? -micros : micros;
    }
    final value = number as num;
    final integral = _web ? value == value.truncateToDouble() : value is int;
    if (integral) {
      return readDateTimestampsAsNanoseconds
          ? value.toInt() * Duration.microsecondsPerSecond
          : value.toInt() * Duration.microsecondsPerMillisecond;
    }
    return (value * Duration.microsecondsPerSecond).round();
  }

  DateTime _readDateTime(Object json, _Path path, JsonFormat? format) {
    if (json is num && json.isFinite) {
      return DateTime.fromMicrosecondsSinceEpoch(
        _timestampMicros(json),
        isUtc: true,
      );
    }
    if (json is! String) {
      throw _expected('an ISO-8601 date-time', json, path);
    }
    final text = json.trim();
    final offset = _formatOffset(format) ?? _offset ?? Duration.zero;
    final pattern = format?.pattern ?? '';
    if (pattern.isNotEmpty) {
      try {
        return _pattern(pattern).parse(text, offset);
      } on FormatException {
        throw _expected('a date-time like "$pattern"', json, path);
      }
    }
    if (_numeric.hasMatch(text)) {
      return DateTime.fromMicrosecondsSinceEpoch(
        _timestampMicros(text),
        isUtc: true,
      );
    }
    return parseIsoDateTime(text, offset) ??
        (throw _expected('an ISO-8601 date-time', json, path));
  }

  Duration _readDuration(Object json, _Path path) {
    if (json is num && json.isFinite) {
      return Duration(microseconds: _timestampMicros(json));
    }
    if (json is String) {
      final text = json.trim();
      if (_numeric.hasMatch(text)) {
        return Duration(microseconds: _timestampMicros(text));
      }
      try {
        return _conversion.convert<Duration>(text);
      } on Object {
        // reported below
      }
    }
    throw _expected('a duration such as "PT1M30S"', json, path);
  }

  Object _readEnum<E extends Enum>(EnumType<E> type, Object json, _Path path) {
    for (final value in type.values) {
      if (type.toJsonValue(value) == json) {
        return value;
      }
    }
    // The name is accepted too (also when @JsonValue gives another form),
    // and an index (Jackson, unless FAIL_ON_NUMBERS_FOR_ENUMS).
    for (final value in type.values) {
      if (value.name == json) {
        return value;
      }
    }
    if (json is int && json >= 0 && json < type.values.length) {
      return type.values[json];
    }
    throw _expected(
      'one of ${[for (final v in type.values) jsonEncode(type.toJsonValue(v))].join(', ')}',
      json,
      path,
    );
  }

  Object? _readKey(String key, TypeInfo<Object?> type, _Path path) {
    if (type case final EnumType<Enum> enumType) {
      for (final value in enumType.values) {
        if ('${enumType.toJsonValue(value)}' == key) {
          return value;
        }
      }
    }
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

/// Writes with the configuration of a mapper and a `@JsonView` (Jackson's
/// `ObjectWriter`, from `ObjectMapper.writerWithView`).
final class ObjectWriter {
  ObjectWriter._(this._mapper);

  final ObjectMapper _mapper;

  /// [value] as a JSON string.
  String writeValueAsString(Object? value) => _mapper.writeValueAsString(value);

  /// [value] as decoded JSON.
  Object? valueToTree(Object? value, [TypeInfo<Object?>? type]) =>
      _mapper.valueToTree(value, type);
}

/// Reads with the configuration of a mapper and a `@JsonView` (Jackson's
/// `ObjectReader`, from `ObjectMapper.readerWithView`).
final class ObjectReader {
  ObjectReader._(this._mapper);

  final ObjectMapper _mapper;

  /// A [T] from the JSON string [json].
  T readValue<T>(String json, [TypeInfo<T>? type]) =>
      _mapper.readValue<T>(json, type);

  /// A [T] from decoded JSON or a [JsonNode].
  T treeToValue<T>(Object? tree, [TypeInfo<T>? type]) =>
      _mapper.treeToValue<T>(tree, type);

  /// A `List<E>` from the JSON array [json].
  List<E> readList<E>(String json, [TypeInfo<E>? element]) =>
      _mapper.readList<E>(json, element);
}

/// Builds a value of the visited type from decoded [json].
final class _Reader implements TypeInfoVisitor<Object?> {
  _Reader(this.mapper, this.json, this.path, this.format);

  final ObjectMapper mapper;
  final Object json;
  final _Path path;
  final JsonFormat? format;

  @override
  Object? visitDynamic(DynamicType type) => json;

  @override
  Object? visitClass<T>(ClassType<T> type) {
    if (json == '' && type.nullable && ObjectMapper._emptyIsNull<T>()) {
      return null;
    }
    return mapper._readClass<T>(json, path, format: format);
  }

  @override
  Object? visitEnum<E extends Enum>(EnumType<E> type) =>
      mapper._readEnum<E>(type, json, path);

  // Generic classes: a JsonDeserializer, their own fromJson, or the generic
  // introspection specialized with the type arguments.
  @override
  Object? visitGeneric<T>(GenericType<T> type) => mapper._readClass<T>(
    json,
    path,
    format: format,
    arguments: type.arguments,
  );

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
        mapper._read(list[i], element, path.index(i), format),
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
          mapper._read(value, type.value, path.key('$key'), format),
        ),
    ]);
  }
}

/// The introspection of a class type (or generic type), if any.
final class _IntrospectionOf
    implements TypeInfoVisitor<BeanIntrospection<Object>?> {
  _IntrospectionOf(this.introspector);

  final BeanIntrospector introspector;

  @override
  BeanIntrospection<Object>? visitClass<T>(ClassType<T> type) =>
      introspector.forTypeArgument<T>();

  @override
  BeanIntrospection<Object>? visitGeneric<T>(GenericType<T> type) =>
      introspector.forGenericType<T>(type.arguments);

  @override
  BeanIntrospection<Object>? visitDynamic(DynamicType type) => null;

  @override
  BeanIntrospection<Object>? visitEnum<E extends Enum>(EnumType<E> type) =>
      null;

  @override
  BeanIntrospection<Object>? visitList<E>(ListType<E> type) => null;

  @override
  BeanIntrospection<Object>? visitMap<K, V>(MapType<K, V> type) => null;

  @override
  BeanIntrospection<Object>? visitSet<E>(SetType<E> type) => null;
}

bool _deepEquals(Object? a, Object? b) {
  if (a is List<Object?> && b is List<Object?>) {
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
  if (a is Set<Object?> && b is Set<Object?>) {
    return a.length == b.length && a.containsAll(b);
  }
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _deepEquals(a[k], b[k]));
  }
  return a == b;
}

/// JSON names, ignored and included properties, formats, views, unwrapped
/// and "any" properties of one class (cached per mapper).
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
    classFormat = classAnnotations.whereType<JsonFormat>().firstOrNull;
    final classViews = classAnnotations.whereType<JsonView>().firstOrNull;
    final naming =
        classAnnotations.whereType<JsonNaming>().firstOrNull?.value ??
        mapper.namingStrategy;
    final parameters = {
      for (final parameter
          in introspection.constructor?.parameters ?? const <BeanParameter>[])
        parameter.name: parameter,
    };
    final names = {
      for (final property in introspection.properties) property.name,
      ...parameters.keys,
    };
    for (final name in names) {
      // A constructor parameter's annotations first (`@JsonProperty` on a
      // parameter wins), then those of the field it initializes.
      final annotations = [
        ...?parameters[name]?.annotations,
        ...?introspection.getProperty(name)?.annotations,
      ];
      A? find<A>() => annotations.whereType<A>().firstOrNull;
      final jsonName = find<JsonProperty>()?.name ?? naming.translate(name);
      jsonNames[name] = jsonName;
      if (find<JsonIgnore>() != null || ignoredNames.contains(jsonName)) {
        ignoredNames.add(jsonName);
      }
      aliases[name] = find<JsonAlias>()?.value ?? const [];
      if (find<JsonFormat>() case final format?) {
        formats[name] = format;
      }
      if (find<JsonView>() ?? classViews case final view?) {
        views[name] = view.value;
      }
      if (find<JsonInclude>() case final include?) {
        inclusions[name] = include.value;
      }
      if (find<JsonUnwrapped>() case final unwrap? when unwrap.enabled) {
        unwrapped[name] = unwrap;
      }
      if (find<JsonAnyGetter>() != null) {
        anyGetter ??= introspection.getProperty(name);
        anyNames.add(name);
      }
      if (find<JsonAnySetter>() != null) {
        anySetterName ??= name;
        anyNames.add(name);
      }
    }
    for (final method in introspection.methods) {
      if (method.annotations.whereType<JsonAnyGetter>().isNotEmpty) {
        anyGetterMethod ??= method;
      }
      if (method.annotations.whereType<JsonAnySetter>().isNotEmpty) {
        anySetterMethod ??= method;
      }
    }
    writeOrder = _writeOrder(
      classAnnotations.whereType<JsonPropertyOrder>().firstOrNull,
    );
  }

  final BeanIntrospection<Object> introspection;
  final ObjectMapper mapper;
  late final bool ignoreUnknown;
  late final JsonInclusion? classInclusion;
  late final JsonFormat? classFormat;

  /// Dart property / constructor parameter name → JSON name.
  final jsonNames = <String, String>{};

  /// Dart name → `@JsonAlias` names.
  final aliases = <String, List<String>>{};

  /// Dart name → `@JsonFormat`.
  final formats = <String, JsonFormat>{};

  /// Dart name → `@JsonView` classes (its own or the class's).
  final views = <String, List<Type>>{};

  /// Dart name → `@JsonInclude` of the property.
  final inclusions = <String, JsonInclusion>{};

  /// Dart name → `@JsonUnwrapped`.
  final unwrapped = <String, JsonUnwrapped>{};

  /// JSON names left out in both directions.
  final ignoredNames = <String>{};

  /// Dart names of `@JsonAnyGetter` / `@JsonAnySetter` properties.
  final anyNames = <String>{};
  BeanProperty<Object>? anyGetter;
  BeanMethod<Object>? anyGetterMethod;
  String? anySetterName;
  BeanMethod<Object>? anySetterMethod;

  bool get hasAnySetter => anySetterName != null || anySetterMethod != null;

  /// The properties in the order they are written.
  late final List<BeanProperty<Object>> writeOrder;

  /// The polymorphic base this class belongs to (`@JsonTypeInfo` on it or
  /// on an introspected supertype), if any.
  late final _Polymorphism? polymorphism = _findPolymorphism();

  _Polymorphism? _findPolymorphism() {
    bool hasTypeInfo(BeanIntrospection<Object> i) =>
        i.annotations.whereType<JsonTypeInfo>().isNotEmpty;
    if (hasTypeInfo(introspection)) {
      return mapper._polymorphism(introspection);
    }
    BeanIntrospection<Object>? best;
    for (final other in mapper.introspector.introspections) {
      if (other != introspection &&
          hasTypeInfo(other) &&
          introspection.isSubtypeOf(other) &&
          (best == null || other.isSubtypeOf(best))) {
        best = other;
      }
    }
    return best == null ? null : mapper._polymorphism(best);
  }

  /// Every JSON name the class reads (aliases and unwrapped names too).
  late final Set<String> known = _known();

  Set<String> _known() {
    final names = <String>{};
    for (final MapEntry(key: name, value: json) in jsonNames.entries) {
      if (anyNames.contains(name)) {
        continue;
      }
      if (unwrapped[name] case final unwrap?) {
        final child = _childInfo(name);
        if (child != null) {
          names.addAll([
            for (final n in child.known) '${unwrap.prefix}$n${unwrap.suffix}',
          ]);
          continue;
        }
      }
      names
        ..add(json)
        ..addAll(aliases[name]!);
    }
    if (polymorphism case final poly?) {
      names.add(poly.property);
    }
    return names;
  }

  /// The values a class-level `@JsonInclude(JsonInclusion.nonDefault)`
  /// compares with: those of an instance made by the no-argument
  /// constructor.
  late final Map<String, Object?>? defaults = _defaults();

  Map<String, Object?>? _defaults() {
    try {
      final constructor = introspection.constructor;
      final Object instance;
      if (introspection.isInstantiable) {
        instance = introspection.instantiate();
      } else if (constructor != null &&
          !constructor.parameters.any((p) => p.isRequired)) {
        instance = constructor.newInstance(const []);
      } else {
        return null;
      }
      return {
        for (final property in introspection.properties)
          property.name: property.getValue(instance),
      };
    } on Object {
      return null;
    }
  }

  TypeInfo<Object?> _typeOf(String name) =>
      introspection.constructor?.parameters
          .where((p) => p.name == name)
          .firstOrNull
          ?.type ??
      introspection.getProperty(name)?.typeInfo ??
      const DynamicType();

  _ClassInfo? _childInfo(String name) {
    final child = _typeOf(name).accept(_IntrospectionOf(mapper.introspector));
    return child == null ? null : mapper._info(child);
  }

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

  bool _inView(String name) {
    final view = mapper._view;
    if (view == null) {
      return true;
    }
    final propertyViews = views[name];
    if (propertyViews == null) {
      return mapper.defaultViewInclusion;
    }
    return propertyViews.any((v) => v == view || mapper._extendsView(view, v));
  }

  // Whether property [name] takes part in reading and writing as a
  // regular property.
  bool _regular(String name) =>
      !ignoredNames.contains(jsonNames[name]) &&
      !anyNames.contains(name) &&
      _inView(name);

  // -------------------------------------------------------------------
  // Writing
  // -------------------------------------------------------------------

  Object? write(Object bean, _Path path, Set<Object> seen) {
    if (classFormat?.shape == JsonFormatShape.array) {
      return [
        for (final property in writeOrder)
          if (_regular(property.name))
            mapper._write(
              property.getValue(bean),
              path.key(jsonNames[property.name]!),
              seen,
              property.typeInfo,
              formats[property.name],
            ),
      ];
    }
    final properties = writeProperties(bean, path, seen);
    final poly = polymorphism;
    if (poly == null || poly.info.use == JsonTypeId.deduction) {
      return properties;
    }
    final id = poly.idOf(introspection);
    return switch (poly.info.include) {
      // The type id first, like Jackson.
      JsonTypeInclusion.property => {poly.property: id, ...properties},
      JsonTypeInclusion.existingProperty => properties,
      JsonTypeInclusion.wrapperObject => {id: properties},
      JsonTypeInclusion.wrapperArray => [id, properties],
    };
  }

  Map<String, Object?> writeProperties(
    Object bean,
    _Path path,
    Set<Object> seen, {
    String prefix = '',
    String suffix = '',
  }) {
    final result = <String, Object?>{};
    for (final property in writeOrder) {
      final name = property.name;
      if (!_regular(name)) {
        continue;
      }
      final json = jsonNames[name]!;
      final value = property.getValue(bean);
      if (unwrapped[name] case final unwrap?) {
        final child = value == null
            ? null
            : mapper.introspector.findIntrospection(value);
        if (value == null) {
          continue;
        }
        if (child != null && !child.hasToJson) {
          if (!seen.add(value)) {
            throw JsonMappingException(
              'cycle: ${value.runtimeType} refers back to itself',
              path: '$path',
            );
          }
          try {
            result.addAll(
              mapper
                  ._info(child)
                  .writeProperties(
                    value,
                    path,
                    seen,
                    prefix: '$prefix${unwrap.prefix}',
                    suffix: '${unwrap.suffix}$suffix',
                  ),
            );
          } finally {
            seen.remove(value);
          }
          continue;
        }
      }
      final rule = inclusions[name] ?? classInclusion ?? mapper.inclusion;
      if (!_included(name, value, rule)) {
        continue;
      }
      result['$prefix$json$suffix'] = mapper._write(
        value,
        path.key(json),
        seen,
        property.typeInfo,
        formats[name],
      );
    }
    final any = anyGetter != null
        ? anyGetter!.getValue(bean)
        : anyGetterMethod?.invoke(bean, const []);
    if (any is Map<Object?, Object?>) {
      final valueType = switch (anyGetter?.typeInfo) {
        MapType(:final value) => value,
        _ => null,
      };
      for (final MapEntry(:key, :value) in any.entries) {
        result['$prefix$key$suffix'] = mapper._write(
          value,
          path.key('$key'),
          seen,
          valueType,
        );
      }
    }
    return result;
  }

  bool _included(String name, Object? value, JsonInclusion rule) =>
      switch (rule) {
        JsonInclusion.always => true,
        JsonInclusion.nonNull || JsonInclusion.nonAbsent => value != null,
        JsonInclusion.nonEmpty => !_isEmpty(value),
        JsonInclusion.nonDefault =>
          inclusions[name] == null && defaults != null
              // Class-level: the value of a default instance.
              ? !_deepEquals(value, defaults![name])
              // Otherwise the default of the type.
              : !_isEmpty(value) && value != 0 && value != false,
      };

  static bool _isEmpty(Object? value) =>
      value == null ||
      (value is String && value.isEmpty) ||
      (value is Iterable && value.isEmpty) ||
      (value is Map && value.isEmpty);

  // -------------------------------------------------------------------
  // Reading
  // -------------------------------------------------------------------

  Object read(Object json, _Path path) {
    if (polymorphism case final poly?) {
      return poly.read(this, json, path);
    }
    return readPlain(json, path);
  }

  // Without type ids: the class's own fromJson, or its properties.
  Object readPlain(Object json, _Path path, {bool nested = false}) {
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
    var object = json;
    if (classFormat?.shape == JsonFormatShape.array && object is List) {
      final order = [
        for (final property in writeOrder)
          if (_regular(property.name)) jsonNames[property.name]!,
      ];
      object = <String, Object?>{
        for (var i = 0; i < object.length && i < order.length; i++)
          order[i]: object[i],
      };
    }
    if (object is! Map<Object?, Object?>) {
      throw mapper._expected('an object', json, path);
    }
    return _readObject(object, path, nested: nested);
  }

  String? _presentKey(String name, Map<Object?, Object?> json) {
    for (final key in [jsonNames[name]!, ...aliases[name]!]) {
      if (json.containsKey(key) && !ignoredNames.contains(key)) {
        return key;
      }
    }
    return null;
  }

  Object _readObject(
    Map<Object?, Object?> json,
    _Path path, {
    required bool nested,
  }) {
    final used = <String>{};
    final values = <String, Object?>{};
    final constructor = introspection.constructor;
    final parameterNames = {
      for (final parameter
          in constructor?.parameters ?? const <BeanParameter>[])
        parameter.name,
    };
    // Every regular property and parameter that is present.
    for (final name in jsonNames.keys) {
      if (!_regular(name)) {
        continue;
      }
      final property = introspection.getProperty(name);
      final settable =
          parameterNames.contains(name) || (property?.isWritable ?? false);
      if (unwrapped[name] case final unwrap?) {
        final child = _childInfo(name);
        if (child != null) {
          final sub = <String, Object?>{};
          for (final MapEntry(:key, :value) in json.entries) {
            final text = '$key';
            if (text.length >= unwrap.prefix.length + unwrap.suffix.length &&
                text.startsWith(unwrap.prefix) &&
                text.endsWith(unwrap.suffix)) {
              final stripped = text.substring(
                unwrap.prefix.length,
                text.length - unwrap.suffix.length,
              );
              if (child.known.contains(stripped)) {
                sub[stripped] = value;
                used.add(text);
              }
            }
          }
          if (settable && (sub.isNotEmpty || !_typeOf(name).nullable)) {
            values[name] = child.readPlain(sub, path, nested: true);
          }
          continue;
        }
      }
      final key = _presentKey(name, json);
      if (key == null) {
        continue;
      }
      used.add(key);
      if (!settable) {
        continue; // read-only and not a constructor parameter
      }
      values[name] = mapper._read(
        json[key],
        _typeOf(name),
        path.key(key),
        formats[name],
      );
    }
    // `@JsonAnySetter`: what no property takes.
    final any = <String, Object?>{};
    if (hasAnySetter) {
      final valueType = switch (anySetterName == null
          ? null
          : _typeOf(anySetterName!)) {
        MapType(:final value) => value,
        _ => const DynamicType(),
      };
      for (final MapEntry(:key, :value) in json.entries) {
        final text = '$key';
        if (!used.contains(text) &&
            !known.contains(text) &&
            !ignoredNames.contains(text)) {
          used.add(text);
          any[text] = mapper._read(value, valueType, path.key(text));
        }
      }
      if (anySetterName case final name? when parameterNames.contains(name)) {
        values[name] = _typeOf(name) is MapType
            ? (_typeOf(name) as MapType<Object?, Object?>).create(any.entries)
            : any;
      }
    }
    final Object bean;
    if (constructor != null) {
      bean = _construct(constructor, values, path);
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
      final name = property.name;
      if (parameterNames.contains(name) ||
          !values.containsKey(name) ||
          !property.isWritable) {
        continue;
      }
      final value = values[name];
      final key = jsonNames[name]!;
      if (value == null && !property.nullable) {
        throw JsonMappingException(
          'null is not allowed here',
          path: '${path.key(key)}',
        );
      }
      try {
        property.setValue(bean, value);
      } on Object catch (error) {
        throw JsonMappingException(
          'cannot set $name: $error',
          path: '${path.key(key)}',
          cause: error,
        );
      }
    }
    if (any.isNotEmpty) {
      _setAny(bean, any, parameterNames, path);
    }
    if (mapper.failOnUnknownProperties &&
        !ignoreUnknown &&
        !nested &&
        !hasAnySetter) {
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

  void _setAny(
    Object bean,
    Map<String, Object?> any,
    Set<String> parameterNames,
    _Path path,
  ) {
    try {
      if (anySetterMethod case final method?) {
        for (final MapEntry(:key, :value) in any.entries) {
          method.invoke(bean, [key, value]);
        }
        return;
      }
      final name = anySetterName!;
      if (parameterNames.contains(name)) {
        return; // passed to the constructor
      }
      final property = introspection.getProperty(name)!;
      var map = property.getValue(bean) as Map<Object?, Object?>?;
      if (map == null) {
        final type = _typeOf(name);
        map = type is MapType
            ? (type as MapType<Object?, Object?>).create(const [])
            : <String, Object?>{};
        property.setValue(bean, map);
      }
      map.addAll(any);
    } on JsonMappingException {
      rethrow;
    } on Object catch (error) {
      throw JsonMappingException(
        'the @JsonAnySetter of ${introspection.beanType} failed: $error',
        path: '$path',
        cause: error,
      );
    }
  }

  Object _construct(
    BeanConstructor<Object> constructor,
    Map<String, Object?> values,
    _Path path,
  ) {
    final positional = <(BeanParameter, Object?, bool)>[];
    final named = <Symbol, Object?>{};
    for (final parameter in constructor.parameters) {
      final name = jsonNames[parameter.name]!;
      final present = values.containsKey(parameter.name);
      final value = values[parameter.name];
      if (!present && parameter.isRequired && !parameter.type.nullable) {
        throw JsonMappingException(
          'missing property "$name" (required by '
          '${introspection.beanType})',
          path: '$path',
        );
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
          'missing property "${jsonNames[parameter.name]}": a later '
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

/// The type ids of a `@JsonTypeInfo` class and its subtypes.
final class _Polymorphism {
  _Polymorphism(this.mapper, this.base)
    : info = base.annotations.whereType<JsonTypeInfo>().first;

  final ObjectMapper mapper;
  final BeanIntrospection<Object> base;
  final JsonTypeInfo info;

  /// The type id property (`@type` by default, like Jackson's `Id.NAME`).
  String get property => info.property.isEmpty ? '@type' : info.property;

  // Ids from `@JsonSubTypes` names.
  final _names = <BeanIntrospection<Object>, String>{};

  /// Type id → class: the base, the `@JsonSubTypes` of the base and,
  /// transitively, of the listed classes.
  late final Map<String, BeanIntrospection<Object>> byId = _collect();

  Map<String, BeanIntrospection<Object>> _collect() {
    final ids = <String, BeanIntrospection<Object>>{};
    final seen = <BeanIntrospection<Object>>[];
    final queue = [base];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (seen.contains(current)) {
        continue;
      }
      seen.add(current);
      for (final subTypes in current.annotations.whereType<JsonSubTypes>()) {
        for (final sub in subTypes.value) {
          final target =
              mapper.introspector.forType(sub.value) ??
              (throw JsonMappingException(
                'subtype ${sub.value} of ${base.beanType} is not '
                '@Introspected',
              ));
          if (sub.name.isNotEmpty) {
            _names[target] ??= sub.name;
            ids[sub.name] = target;
          }
          for (final name in sub.names) {
            ids[name] = target;
          }
          queue.add(target);
        }
      }
    }
    for (final introspection in seen) {
      ids.putIfAbsent(_idOf(introspection), () => introspection);
    }
    return ids;
  }

  String _idOf(BeanIntrospection<Object> introspection) =>
      _names[introspection] ??
      introspection.annotations.whereType<JsonTypeName>().firstOrNull?.value ??
      introspection.className;

  /// The type id written for [introspection].
  String idOf(BeanIntrospection<Object> introspection) {
    byId; // collects the @JsonSubTypes names
    return _idOf(introspection);
  }

  Object read(_ClassInfo requested, Object json, _Path path) {
    String? id;
    Object? body = json;
    BeanIntrospection<Object>? target;
    switch (info.include) {
      case _ when info.use == JsonTypeId.deduction:
        target = _deduce(json, path);
      case JsonTypeInclusion.property || JsonTypeInclusion.existingProperty:
        if (json is! Map<Object?, Object?>) {
          throw mapper._expected('an object', json, path);
        }
        final raw = json[property];
        if (raw != null && raw is! String) {
          throw JsonMappingException(
            'type id property "$property" must be a string, got '
            '${ObjectMapper._describe(raw)}',
            path: '$path',
          );
        }
        id = raw as String?;
        body = info.visible ? json : ({...json}..remove(property));
      case JsonTypeInclusion.wrapperObject:
        if (json is! Map<Object?, Object?> || json.length != 1) {
          throw mapper._expected(
            'an object wrapping the value of ${base.beanType} with its type '
            'id as the only property',
            json,
            path,
          );
        }
        id = '${json.keys.single}';
        body = json.values.single;
        path = path.key(id);
      case JsonTypeInclusion.wrapperArray:
        if (json is! List<Object?> ||
            json.length != 2 ||
            json.first is! String) {
          throw mapper._expected(
            'an array [type id, value] for ${base.beanType}',
            json,
            path,
          );
        }
        id = json.first! as String;
        body = json[1];
        path = path.index(1);
    }
    if (target == null && id == null) {
      target = _defaultImpl(
        info.include == JsonTypeInclusion.property ||
                info.include == JsonTypeInclusion.existingProperty
            ? 'missing type id property "$property" (for '
                  '${requested.introspection.beanType})'
            : 'missing type id (for ${requested.introspection.beanType})',
        path,
      );
    }
    target ??=
        byId[id] ??
        (throw JsonMappingException(
          'could not resolve type id "$id" as a subtype of '
          '${requested.introspection.beanType}: known type ids = '
          '[${(byId.keys.toList()..sort()).join(', ')}]',
          path: '$path',
        ));
    if (target != requested.introspection &&
        !target.isSubtypeOf(requested.introspection)) {
      throw JsonMappingException(
        'type id "${id ?? _idOf(target)}" (${target.beanType}) is not a '
        'subtype of ${requested.introspection.beanType}',
        path: '$path',
      );
    }
    if (body == null) {
      throw JsonMappingException(
        'null is not allowed here (expected ${target.beanType})',
        path: '$path',
      );
    }
    return mapper._info(target).readPlain(body, path);
  }

  BeanIntrospection<Object> _defaultImpl(String message, _Path path) {
    final type = info.defaultImpl;
    if (type == null) {
      throw JsonMappingException(message, path: '$path');
    }
    return mapper.introspector.forType(type) ??
        (throw JsonMappingException(
          'defaultImpl $type of ${base.beanType} is not @Introspected',
          path: '$path',
        ));
  }

  // Jackson's AsDeductionTypeDeserializer: every property known to some
  // candidate removes the candidates without it; one left wins.
  BeanIntrospection<Object> _deduce(Object json, _Path path) {
    if (json is! Map<Object?, Object?>) {
      throw mapper._expected('an object', json, path);
    }
    var candidates = {
      for (final introspection in byId.values)
        if (introspection.hasFromJson ||
            introspection.isInstantiable ||
            introspection.constructor != null)
          introspection,
    }.toList();
    final everyKnown = {
      for (final candidate in candidates) ...mapper._info(candidate).known,
    };
    for (final key in json.keys) {
      if (!everyKnown.contains(key)) {
        continue;
      }
      candidates = [
        for (final candidate in candidates)
          if (mapper._info(candidate).known.contains(key)) candidate,
      ];
      if (candidates.length == 1) {
        return candidates.single;
      }
    }
    return _defaultImpl(
      'cannot deduce unique subtype of ${base.beanType} '
      '(${candidates.length} candidates match)',
      path,
    );
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
