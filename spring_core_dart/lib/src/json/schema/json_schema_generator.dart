import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/type_info.dart';
import 'package:spring_core_dart/src/json/annotations.dart';
import 'package:spring_core_dart/src/json/json_node.dart';
import 'package:spring_core_dart/src/json/naming.dart';
import 'package:spring_core_dart/src/validation/constraints.dart';

/// Writes the JSON Schema (draft 2020-12) of `@Introspected` classes from
/// their introspection, without reflection.
///
/// Use it to publish the shape of your JSON: an API's request bodies, a
/// configuration file, a message format. The schema describes the JSON
/// `ObjectMapper` writes and reads with its default settings and the
/// given [namingStrategy]: JSON names (`@JsonProperty`, `@JsonNaming`),
/// left-out properties (`@JsonIgnore`, `@JsonIgnoreProperties`,
/// `@JsonAnyGetter` / `@JsonAnySetter`), `@JsonProperty(access:)` as
/// `readOnly` / `writeOnly`, `@JsonFormat` shapes, and the validation
/// constraints as keywords.
///
/// What a type becomes:
/// - `String` → `string`; `int` → `integer`; `double`, `num` →
///   `number`; `bool` → `boolean`;
/// - `DateTime` → `string` with format `date-time`; `Duration` →
///   `string` with format `duration`; `Uri` → `string` with format
///   `uri-reference`; `BigInt` → a string of digits or an integer;
/// - an enum → its JSON values (`@JsonValue` too) in `enum`;
/// - `List` → `array` with `items`; `Set` → the same, `uniqueItems`;
///   `Map` → `object` with `additionalProperties`;
/// - an introspected class → a `$ref` to `#/$defs/<ClassName>` (the root
///   class is `#`, so cycles work);
/// - a nullable type also allows `null`; `dynamic`, `Object` and
///   `JsonNode` allow anything.
///
/// `required` lists the constructor parameters the mapper needs (required,
/// not nullable, not read-only) and the properties marked `@NotNull`.
/// Constraints become keywords whatever their groups: `@NotEmpty`,
/// `@NotBlank` (also the pattern `\S`), `@Size`, `@Min`, `@Max`,
/// `@DecimalMin`, `@DecimalMax`, `@Positive`, `@PositiveOrZero`,
/// `@Negative`, `@NegativeOrZero`, `@Matches` (anchored, without its
/// flags), `@Email` and `@Each` (for the elements).
///
/// Not described: polymorphism (`@JsonTypeInfo`), `@JsonUnwrapped`
/// properties, classes with their own `fromJson` / `toJson` (any JSON),
/// and the mapper settings that write dates and durations as numbers.
///
/// ```dart
/// final schema = JsonSchemaGenerator().schemaOf(Order);
/// // {$schema: https://json-schema.org/draft/2020-12/schema, title: Order,
/// //  type: object, properties: {...}, required: [...], $defs: {...}}
/// ```
///
/// Spring (Java): Spring has no counterpart; Java applications use
/// Jackson's `jsonSchema` module or victools' `jsonschema-generator`.
final class JsonSchemaGenerator {
  /// A generator reading classes from [introspector]
  /// ([BeanIntrospector.shared] by default) and naming properties with
  /// [namingStrategy], as the `ObjectMapper` it describes does.
  JsonSchemaGenerator({
    BeanIntrospector? introspector,
    this.namingStrategy = PropertyNamingStrategy.lowerCamelCase,
  }) : introspector = introspector ?? BeanIntrospector.shared;

  /// The `$schema` of every generated schema: draft 2020-12.
  static const draft = 'https://json-schema.org/draft/2020-12/schema';

  /// Where the classes are described.
  final BeanIntrospector introspector;

  /// How Dart property names become JSON names, for classes without
  /// `@JsonNaming`.
  final PropertyNamingStrategy namingStrategy;

  /// The schema of the introspected class [type], the classes it uses in
  /// its `$defs`. Throws an [ArgumentError] when [type] is not
  /// introspected.
  Map<String, Object?> schemaOf(Type type) {
    final introspection =
        introspector.forType(type) ??
        (throw ArgumentError.value(
          type,
          'type',
          'is not introspected: mark it @Introspected()',
        ));
    return _Run(this, introspection).root();
  }

  /// The schemas of [types], by class name.
  Map<String, Map<String, Object?>> schemasOf(Iterable<Type> types) => {
    for (final type in types) _nameOf(type): schemaOf(type),
  };

  /// The schemas of every class of the [introspector], by class name;
  /// enums and generic classes are left out, and of two classes with the
  /// same name the first.
  Map<String, Map<String, Object?>> all() {
    final result = <String, Map<String, Object?>>{};
    for (final introspection in introspector.introspections) {
      if (introspection.isGeneric ||
          introspector.enumTypeFor(introspection.beanType) != null ||
          result.containsKey(introspection.className)) {
        continue;
      }
      result[introspection.className] = _Run(this, introspection).root();
    }
    return result;
  }

  String _nameOf(Type type) => introspector.forType(type)?.className ?? '$type';
}

enum _Kind { string, number, array, object, other }

final class _Run {
  _Run(this.generator, this.rootIntrospection);

  final JsonSchemaGenerator generator;
  final BeanIntrospection<Object> rootIntrospection;
  final _names = <BeanIntrospection<Object>, String>{};
  final _defs = <String, Map<String, Object?>>{};

  BeanIntrospector get introspector => generator.introspector;

  Map<String, Object?> root() {
    final body = objectSchema(rootIntrospection);
    return {
      r'$schema': JsonSchemaGenerator.draft,
      'title': rootIntrospection.className,
      ...body,
      if (_defs.isNotEmpty) r'$defs': _defs,
    };
  }

  Map<String, Object?> refTo(
    BeanIntrospection<Object> introspection, [
    String? name,
  ]) {
    if (identical(introspection, rootIntrospection)) {
      return {r'$ref': '#'};
    }
    var defName = _names[introspection];
    if (defName == null) {
      defName = _uniqueName(name ?? introspection.className);
      _names[introspection] = defName;
      _defs[defName] = const {};
      _defs[defName] = {
        'title': introspection.className,
        ...objectSchema(introspection),
      };
    }
    return {r'$ref': '#/\$defs/$defName'};
  }

  String _uniqueName(String raw) {
    final base = raw
        .replaceAll(RegExp('[^A-Za-z0-9_]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    var name = base.isEmpty ? 'Type' : base;
    for (var i = 2; _defs.containsKey(name); i++) {
      name = '$base$i';
    }
    return name;
  }

  Map<String, Object?> objectSchema(BeanIntrospection<Object> introspection) {
    if (introspection.hasFromJson || introspection.hasToJson) {
      return {};
    }
    final classAnnotations = introspection.annotations;
    final naming =
        classAnnotations.whereType<JsonNaming>().firstOrNull?.value ??
        generator.namingStrategy;
    final ignored = {
      ...?classAnnotations.whereType<JsonIgnoreProperties>().firstOrNull?.value,
    };
    final parameters = {
      for (final parameter
          in introspection.constructor?.parameters ?? const <BeanParameter>[])
        parameter.name: parameter,
    };
    final names = {
      for (final property in introspection.properties) property.name,
      ...parameters.keys,
    };
    // `@JsonValue`: the class is written as that value.
    for (final name in names) {
      final property = introspection.getProperty(name);
      if (property != null &&
          property.annotations.whereType<JsonValue>().isNotEmpty) {
        return propertySchema(
          property.typeInfo,
          property.type,
          property.nullable,
          property.annotations,
        );
      }
    }
    final describesRead = introspection.describesPart(IntrospectionPart.read);
    final describesWrite = introspection.describesPart(
      IntrospectionPart.write,
    );
    final properties = <String, Object?>{};
    final required = <String>[];
    for (final name in names) {
      final parameter = parameters[name];
      final property = introspection.getProperty(name);
      final annotations = [
        ...?parameter?.annotations,
        ...?property?.annotations,
      ];
      A? find<A>() => annotations.whereType<A>().firstOrNull;
      final jsonProperty = find<JsonProperty>();
      final jsonName = jsonProperty != null && jsonProperty.name.isNotEmpty
          ? jsonProperty.name
          : naming.translate(name);
      if (find<JsonIgnore>() != null ||
          ignored.contains(jsonName) ||
          find<JsonAnyGetter>() != null ||
          find<JsonAnySetter>() != null ||
          (find<JsonUnwrapped>()?.enabled ?? false)) {
        continue;
      }
      final type = parameter?.type ?? property?.typeInfo;
      final nullable = type?.nullable ?? property?.nullable ?? false;
      final notNull = find<NotNull>() != null;
      final schema = propertySchema(
        type,
        property?.type ?? type?.type,
        nullable && !notNull,
        annotations,
      );
      final access = jsonProperty?.access ?? JsonPropertyAccess.auto;
      final settable = parameter != null || (property?.isWritable ?? false);
      final readable = property?.isReadable ?? false;
      final readOnly =
          access == JsonPropertyAccess.readOnly ||
          (describesWrite && !settable && readable);
      final writeOnly =
          access == JsonPropertyAccess.writeOnly ||
          (describesRead && !readable && settable);
      if (readOnly) {
        schema['readOnly'] = true;
      } else if (writeOnly) {
        schema['writeOnly'] = true;
      }
      properties[jsonName] = schema;
      final requiredByConstructor =
          parameter != null &&
          parameter.isRequired &&
          !parameter.hasDefaultValue &&
          !parameter.type.nullable &&
          !readOnly;
      if (requiredByConstructor || notNull) {
        required.add(jsonName);
      }
    }
    return {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    };
  }

  Map<String, Object?> propertySchema(
    TypeInfo<Object?>? type,
    Type? rawType,
    bool nullable,
    List<Object> annotations,
  ) {
    final format = annotations.whereType<JsonFormat>().firstOrNull;
    var schema = type != null
        ? type.accept(_TypeSchema(this))
        : _rawSchema(rawType);
    schema = _shaped(schema, format);
    _constrain(schema, annotations, type, rawType);
    return nullable ? _nullable(schema) : schema;
  }

  Map<String, Object?> _rawSchema(Type? type) {
    if (type == null) {
      return {};
    }
    if (_scalar(type) case final scalar?) {
      return scalar;
    }
    if (introspector.enumTypeFor(type) case final enumType?) {
      return _enumSchema(enumType);
    }
    if (introspector.forType(type) case final introspection?) {
      return refTo(introspection);
    }
    return {};
  }

  // `@JsonFormat(shape:)` and a date pattern change what is written.
  static Map<String, Object?> _shaped(
    Map<String, Object?> schema,
    JsonFormat? format,
  ) {
    if (format == null) {
      return schema;
    }
    switch (format.shape) {
      case JsonFormatShape.string:
        return {'type': 'string'};
      case JsonFormatShape.number:
        if (schema['enum'] != null) {
          return {'type': 'integer', 'minimum': 0};
        }
        if (schema['format'] == 'date-time' || schema['format'] == 'duration') {
          return {'type': 'number'};
        }
        return schema;
      case JsonFormatShape.any || JsonFormatShape.array:
        if (format.pattern.isNotEmpty && schema['format'] == 'date-time') {
          return {'type': 'string'};
        }
        return schema;
    }
  }

  static Map<String, Object?> _nullable(Map<String, Object?> schema) {
    if (schema.isEmpty) {
      return schema;
    }
    if (schema.containsKey(r'$ref') || schema.containsKey('anyOf')) {
      return {
        'anyOf': [
          schema,
          {'type': 'null'},
        ],
      };
    }
    final result = {...schema};
    switch (schema['type']) {
      case final String type:
        result['type'] = [type, 'null'];
      case final List<Object?> types when !types.contains('null'):
        result['type'] = [...types, 'null'];
    }
    if (schema['enum'] case final List<Object?> values
        when !values.contains(null)) {
      result['enum'] = [...values, null];
    }
    return result;
  }

  // Compares the exact runtime Type, as ObjectMapper does.
  // ignore: switch_on_type
  static Map<String, Object?>? _scalar(Type type) => switch (type) {
    const (String) => {'type': 'string'},
    const (int) => {'type': 'integer'},
    const (double) || const (num) => {'type': 'number'},
    const (bool) => {'type': 'boolean'},
    const (DateTime) => {'type': 'string', 'format': 'date-time'},
    const (Duration) => {'type': 'string', 'format': 'duration'},
    const (Uri) => {'type': 'string', 'format': 'uri-reference'},
    const (BigInt) => {
      'type': ['string', 'integer'],
      'pattern': r'^-?\d+$',
    },
    _ => null,
  };

  static Map<String, Object?> _enumSchema(EnumType<Enum> type) {
    final values = [for (final value in type.values) type.toJsonValue(value)];
    final kind = values.every((v) => v is String)
        ? 'string'
        : values.every((v) => v is int)
        ? 'integer'
        : null;
    return {'type': ?kind, 'enum': values};
  }

  _Kind _kindOf(TypeInfo<Object?>? type, Type? rawType) => switch (type) {
    ListType() || SetType() => _Kind.array,
    MapType() => _Kind.object,
    ClassType(type: final classType) => _kindOfType(classType),
    null => _kindOfType(rawType),
    _ => _Kind.other,
  };

  static _Kind _kindOfType(Type? type) => switch (type) {
    const (String) => _Kind.string,
    const (int) || const (double) || const (num) => _Kind.number,
    _ => _Kind.other,
  };

  void _constrain(
    Map<String, Object?> schema,
    List<Object> annotations,
    TypeInfo<Object?>? type,
    Type? rawType,
  ) {
    final kind = _kindOf(type, rawType);
    void length(int? min, int? max) {
      final (minKey, maxKey) = switch (kind) {
        _Kind.string => ('minLength', 'maxLength'),
        _Kind.array => ('minItems', 'maxItems'),
        _Kind.object => ('minProperties', 'maxProperties'),
        _ => (null, null),
      };
      if (minKey != null && min != null && min > 0) {
        schema[minKey] = min;
      }
      if (maxKey != null && max != null) {
        schema[maxKey] = max;
      }
    }

    void pattern(String regexp) {
      if (kind != _Kind.string) {
        return;
      }
      if (schema.containsKey('pattern')) {
        ((schema['allOf'] ??= <Object?>[]) as List<Object?>).add({
          'pattern': regexp,
        });
      } else {
        schema['pattern'] = regexp;
      }
    }

    for (final annotation in annotations) {
      switch (annotation) {
        case NotEmpty():
          length(1, null);
        case NotBlank():
          length(1, null);
          pattern(r'\S');
        case Size(:final min, :final max):
          length(min, max == 0x7FFFFFFF ? null : max);
        case Min(:final value) when kind == _Kind.number:
          schema['minimum'] = value;
        case Max(:final value) when kind == _Kind.number:
          schema['maximum'] = value;
        case DecimalMin(:final value, :final inclusive)
            when kind == _Kind.number && num.tryParse(value) != null:
          schema[inclusive ? 'minimum' : 'exclusiveMinimum'] = num.parse(
            value,
          );
        case DecimalMax(:final value, :final inclusive)
            when kind == _Kind.number && num.tryParse(value) != null:
          schema[inclusive ? 'maximum' : 'exclusiveMaximum'] = num.parse(
            value,
          );
        case Positive() when kind == _Kind.number:
          schema['exclusiveMinimum'] = 0;
        case PositiveOrZero() when kind == _Kind.number:
          schema['minimum'] = 0;
        case Negative() when kind == _Kind.number:
          schema['exclusiveMaximum'] = 0;
        case NegativeOrZero() when kind == _Kind.number:
          schema['maximum'] = 0;
        case Matches(:final regexp):
          pattern('^(?:$regexp)\$');
        case Email(:final regexp) when kind == _Kind.string:
          schema['format'] = 'email';
          if (regexp != '.*') {
            pattern('^(?:$regexp)\$');
          }
        case Each(:final constraints):
          final (element, target) = switch (type) {
            ListType(:final element) || SetType(:final element) => (
              element,
              schema['items'],
            ),
            MapType(:final value) => (value, schema['additionalProperties']),
            _ => (null, null),
          };
          if (element != null && target is Map<String, Object?>) {
            _constrain(target, constraints, element, null);
          }
      }
    }
  }
}

/// The schema of a [TypeInfo].
final class _TypeSchema implements TypeInfoVisitor<Map<String, Object?>> {
  _TypeSchema(this.run);

  final _Run run;

  BeanIntrospector get introspector => run.introspector;

  Map<String, Object?> _of(TypeInfo<Object?> type) {
    final schema = type.accept(this);
    return type.nullable ? _Run._nullable(schema) : schema;
  }

  static bool _is<S, B>() => S == B || (<S>[] is List<B?> && <B?>[] is List<S>);

  @override
  Map<String, Object?> visitClass<T>(ClassType<T> type) {
    if (_Run._scalar(type.type) case final scalar?) {
      return scalar;
    }
    if (_is<T, Object>() || <T>[] is List<JsonNode?>) {
      return {};
    }
    if (introspector.forTypeArgument<T>() case final introspection?) {
      return run.refTo(introspection);
    }
    // A type test on the type argument T, not a constant.
    // ignore: literal_only_boolean_expressions
    if (<T>[] is List<Enum?>) {
      if (introspector.enumTypeOf<T>() case final enumType?) {
        return _Run._enumSchema(enumType);
      }
      return {'type': 'string'};
    }
    // A type test on the type argument T, not a constant.
    // ignore: literal_only_boolean_expressions
    if (<T>[] is List<Iterable<Object?>?>) {
      return {'type': 'array'};
    }
    // A type test on the type argument T, not a constant.
    // ignore: literal_only_boolean_expressions
    if (<T>[] is List<Map<Object?, Object?>?>) {
      return {'type': 'object'};
    }
    return {};
  }

  @override
  Map<String, Object?> visitList<E>(ListType<E> type) => {
    'type': 'array',
    'items': _of(type.element),
  };

  @override
  Map<String, Object?> visitSet<E>(SetType<E> type) => {
    'type': 'array',
    'items': _of(type.element),
    'uniqueItems': true,
  };

  @override
  Map<String, Object?> visitMap<K, V>(MapType<K, V> type) {
    final keys = switch (type.key) {
      final EnumType<Enum> enumType => {
        'enum': [for (final v in enumType.values) '${enumType.toJsonValue(v)}'],
      },
      ClassType<int>() => {'pattern': r'^-?\d+$'},
      ClassType() => type.key.capture(
        <X>() => <X>[] is List<Enum?>
            ? switch (introspector.enumTypeOf<X>()) {
                final enumType? => {
                  'enum': [
                    for (final v in enumType.values)
                      '${enumType.toJsonValue(v)}',
                  ],
                },
                null => null,
              }
            : null,
      ),
      _ => null,
    };
    return {
      'type': 'object',
      'propertyNames': ?keys,
      'additionalProperties': _of(type.value),
    };
  }

  @override
  Map<String, Object?> visitEnum<E extends Enum>(EnumType<E> type) =>
      _Run._enumSchema(type);

  @override
  Map<String, Object?> visitGeneric<T>(GenericType<T> type) {
    final introspection = introspector.forGenericType<T>(type.arguments);
    return introspection == null ? {} : run.refTo(introspection, '$T');
  }

  @override
  Map<String, Object?> visitDynamic(DynamicType type) => {};
}
