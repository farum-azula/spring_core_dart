import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart' hide Resource;
import 'package:dart_style/dart_style.dart';
import 'package:spring_core_dart/core.dart';
import 'package:spring_core_dart/json.dart' show JsonSchemaLocations;
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/spring_key_files.dart';
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart'
    show readPlatformEnvironment;
import 'package:spring_core_dart_generator/src/web_loader_download.dart';

/// One schema of `spring.json.schemas`: where it is, its pin, and how its
/// classes are named.
typedef JsonSchemaEntry = ({
  String location,
  String? sha256,
  String prefix,
  String? name,
});

/// A schema of `spring.json.schemas` read: its entry, its text, and the
/// resource it is kept under in the app (`JsonSchemaLocations.resourceOf`).
typedef LoadedJsonSchema = ({
  JsonSchemaEntry entry,
  String text,
  Map<String, Object?> document,
  String resource,
});

/// The classes of the JSON Schemas an app lists in `spring.json.schemas`,
/// written at build time to `lib/spring_gen/json_schemas.spring.dart`, a
/// part of the app's `.spring.dart` (as the theme's typed keys are):
///
/// ```yaml
/// spring:
///   json:
///     schemas:
///       - location: resources:schemas/order.json
///       - location: https://example.com/schemas/user.json
///         sha256: 3f1c...        # the download is refused with another
///       - location: github:acme/contracts/schemas/invoice.json@v2
///         prefix: Api            # ApiInvoice, ApiInvoiceLine
///         name: Invoice          # the root class, instead of its title
/// ```
///
/// A schema of `resources:` is read from `lib/resources/`; one of
/// `https://` or `github:` is downloaded at every build and kept in
/// `.dart_tool/spring/json_schemas/`, whose copy an offline build uses.
/// Each class is `@Introspected` (the build writes its introspection into
/// the module), its root carries `@JsonSchemaSource` with the location,
/// and the schema's text is a resource of the app, so the `ObjectMapper`
/// checks a JSON against it when it reads one and the actuator shows it.
///
/// What a schema becomes:
///
/// - an object with `properties`: a class, each property a final field
///   (`required` and not nullable: a required named parameter; else
///   nullable); `$defs` and inline objects are classes of their own
///   (`OrderLine`, or the parent's name and the property's);
/// - `string` → `String` (`format: date-time` → `DateTime`), `integer` →
///   `int`, `number` → `double`, `boolean` → `bool`, `array` → `List`,
///   an object of `additionalProperties` only → `Map<String, ...>`;
/// - a string `enum` → a Dart enum whose values keep their JSON text;
/// - `type: [x, "null"]` and `anyOf`/`oneOf` of a type and `null` →
///   nullable; `allOf` of objects → their properties together; any other
///   `anyOf`/`oneOf`, and a `$ref` outside the schema not listed →
///   `Object?` (a warning names it);
/// - `minLength`/`maxLength`, `minItems`/`maxItems` → `@Size`, `minimum`/
///   `maximum` → `@Min`/`@Max` (`@DecimalMin`/`@DecimalMax` for numbers),
///   `pattern` → `@Matches`, `format: email` → `@Email`; `description` →
///   the field's or class's doc comment.
///
/// Spring has no counterpart; jsonschema2pojo does the same for Java.
abstract final class JsonSchemaClasses {
  /// The file the classes are written to.
  static const file = 'lib/spring_gen/json_schemas.spring.dart';

  /// The name of the list of the classes' introspections in the part.
  static const introspections = r'_$jsonSchemaIntrospections';

  /// The prefix the part uses for the core's library.
  static const prefix = '_sj';

  /// The import of the parent library the part needs.
  static const import = 'package:spring_core_dart/spring_core_dart.dart';

  static final _memo = <String, Future<List<LoadedJsonSchema>>>{};

  /// The entries of `spring.json.schemas` in the configuration [texts]
  /// (paths below `lib/resources/`).
  static List<JsonSchemaEntry> entries(Map<String, String> texts) {
    if (!texts.values.any((text) => text.contains('schemas'))) {
      return const [];
    }
    final PropertyResolver environment;
    try {
      environment = readPlatformEnvironment(texts, profiles: const []);
    } on Object {
      return const [];
    }
    String? value(String key) {
      final text = environment.getProperty(key)?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    return [
      for (var i = 0; value('spring.json.schemas[$i].location') != null; i++)
        (
          location: value('spring.json.schemas[$i].location')!,
          sha256: value('spring.json.schemas[$i].sha256')?.toLowerCase(),
          prefix: value('spring.json.schemas[$i].prefix') ?? '',
          name: value('spring.json.schemas[$i].name'),
        ),
    ];
  }

  /// The schemas of [entries], read once a build for every builder that
  /// asks (the classes builder and the module's builder decide the same).
  /// Problems are logged; a schema that cannot be read is left out.
  static Future<List<LoadedJsonSchema>> load(
    BuildStep buildStep,
    List<JsonSchemaEntry> entries, {
    WebLoaderFetch? fetch,
  }) {
    final package = buildStep.inputId.package;
    final key = '$package\n${[for (final e in entries) '$e'].join('\n')}';
    return _memo[key] ??= _load(buildStep, package, entries, fetch);
  }

  static Future<List<LoadedJsonSchema>> _load(
    BuildStep buildStep,
    String package,
    List<JsonSchemaEntry> entries,
    WebLoaderFetch? fetch,
  ) async {
    final loaded = <LoadedJsonSchema>[];
    for (final entry in entries) {
      final location = entry.location;
      String? text;
      if (location.startsWith('resources:')) {
        final id = AssetId(
          package,
          'lib/resources/${location.substring('resources:'.length)}',
        );
        if (await buildStep.canRead(id)) {
          text = await buildStep.readAsString(id);
        } else {
          log.severe(
            'spring.json.schemas: $location is not in lib/resources/; its '
            'classes are not written.',
          );
          continue;
        }
      } else {
        final RemoteAddress address;
        try {
          address = const RemoteAddresses().parse(
            location,
            property: 'spring.json.schemas[].location',
          );
        } on ArgumentError catch (error) {
          log.severe('spring.json.schemas: ${error.message} ($location).');
          continue;
        }
        final directory =
            PackageDirectories.current
                .file(AssetId(package, 'pubspec.yaml'))
                ?.parent
                .path ??
            Directory.current.path;
        final read = await WebLoaderDownload(
          cache: Directory('$directory/.dart_tool/spring/json_schemas'),
          fetch: fetch,
          extension: '.json',
          pinProperty: 'spring.json.schemas[].sha256',
        ).read(address.uri, entry.sha256);
        if (read.problem != null) {
          (read.text == null ? log.severe : log.warning)(
            'spring.json.schemas: ${read.problem}.',
          );
        }
        text = read.text;
        if (text == null) {
          continue;
        }
      }
      final Object? document;
      try {
        document = jsonDecode(text);
      } on FormatException catch (error) {
        log.severe('spring.json.schemas: $location is no JSON ($error).');
        continue;
      }
      if (document is! Map<String, Object?>) {
        log.severe('spring.json.schemas: $location is no JSON object.');
        continue;
      }
      loaded.add((
        entry: entry,
        text: text,
        document: document,
        resource: JsonSchemaLocations.resourceOf(location),
      ));
    }
    return loaded;
  }

  /// The part's code for [schemas] (its `part of` is written by the
  /// caller), or `null` when no class comes of them.
  static String? code(List<LoadedJsonSchema> schemas, {bool report = true}) {
    if (schemas.isEmpty) {
      return null;
    }
    final model = _Model(schemas)..build();
    for (final name in [
      for (final c in model.classes) c.name,
      for (final e in model.enums) e.name,
    ]) {
      if (_springNames.contains(name)) {
        model.warnings.add(
          'spring.json.schemas: the class $name has the name of a class of '
          'Spring for Dart (an app that imports both must hide one); a '
          'prefix: changes it.',
        );
      }
    }
    if (report) {
      model.warnings.forEach(log.warning);
    }
    return model.classes.isEmpty && model.enums.isEmpty ? null : model.code();
  }
}

/// The part of `spring.json.schemas` as both builders decide it: the
/// library it belongs to, its code, and what that library's module needs
/// for it (the part, its import, its introspections, the downloaded
/// schemas as resources).
final class JsonSchemaPart {
  const JsonSchemaPart._({
    this.parent,
    this.parentPath = '',
    this.code = '',
    this.parts = const [],
    this.imports = const [],
    this.introspections = const [],
    this.resources = const {},
  });

  /// No part.
  static const none = JsonSchemaPart._();

  /// The library the part belongs to (`lib/main.dart`).
  final AssetId? parent;

  /// The path of the parent's generated file seen from the part.
  final String parentPath;

  /// The part's code, without its header and `part of`.
  final String code;

  /// The part as the parent names it.
  final List<String> parts;

  /// The imports the parent needs for the part (`url as prefix`).
  final List<String> imports;

  /// The lists of introspections the parent's module spreads.
  final List<String> introspections;

  /// The downloaded schemas, by their resource path.
  final Map<String, ({String? text, String? base64})> resources;

  /// The part of [buildStep]'s package; `null` without schemas or classes.
  /// [report] logs the problems (the classes builder does; the module's
  /// builder decides the same silently).
  static Future<JsonSchemaPart?> of(
    BuildStep buildStep, {
    bool report = false,
    WebLoaderFetch? fetch,
  }) async {
    final all = await SpringBuilder.resources(buildStep, warn: false);
    final texts = {
      for (final MapEntry(:key, value: (:text, base64: _)) in all.entries)
        key: ?text,
    };
    final entries = JsonSchemaClasses.entries(texts);
    if (entries.isEmpty) {
      return null;
    }
    final loaded = await JsonSchemaClasses.load(
      buildStep,
      entries,
      fetch: fetch,
    );
    final code = JsonSchemaClasses.code(loaded, report: report);
    if (code == null) {
      return null;
    }
    final scans = await SpringKeyFiles.scanLibraries(buildStep);
    final choice = SpringKeyFiles.parentLibrary(scans);
    final parentId = choice.parent;
    if (parentId == null) {
      if (report) {
        log.warning(
          choice.error ??
              'No library of ${buildStep.inputId.package} has a '
                  '@ComponentScan or @SpringBootApplication, so the classes of '
                  'spring.json.schemas have no library to be a part of: '
                  '${JsonSchemaClasses.file} is not written.',
        );
      }
      return null;
    }
    final parent = SpringKeyFiles.parentOf(parentId);
    return JsonSchemaPart._(
      parent: parentId,
      parentPath: SpringKeyFiles.parentPath(parent),
      code: code,
      parts: [SpringKeyFiles.partPath(parent, JsonSchemaClasses.file)],
      imports: [
        '${JsonSchemaClasses.import} as ${JsonSchemaClasses.prefix}',
      ],
      introspections: const [JsonSchemaClasses.introspections],
      resources: {
        for (final schema in loaded)
          if (JsonSchemaLocations.isRemote(schema.entry.location))
            schema.resource: (text: schema.text, base64: null),
      },
    );
  }
}

/// Writes `lib/spring_gen/json_schemas.spring.dart`, the classes of the
/// JSON Schemas of `spring.json.schemas` ([JsonSchemaClasses]): a part of
/// the package's `@SpringBootApplication` library (else its outermost
/// `@ComponentScan`), whose module the main builder gives their
/// introspections.
final class JsonSchemasBuilder implements Builder {
  /// The builder; [fetch] downloads (the network by default).
  JsonSchemasBuilder({this.fetch});

  /// How a remote schema is downloaded; tests give their own.
  final WebLoaderFetch? fetch;

  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': [JsonSchemaClasses.file],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final part = await JsonSchemaPart.of(
      buildStep,
      report: true,
      fetch: fetch,
    );
    if (part == null) {
      return;
    }
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, JsonSchemaClasses.file),
      DartFormatter(
        languageVersion: DartFormatter.latestLanguageVersion,
      ).format(
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
        '// Generated by spring_core_dart_generator from the JSON Schemas of '
        'spring.json.schemas.\n\n'
        '// ignore_for_file: type=lint\n'
        "part of '${part.parentPath}';\n\n"
        '${part.code}',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The model: classes, enums and the Dart type of each schema.

sealed class _Type {
  const _Type();
  // The Dart type, without `?`.
  String get dart;
  // The TypeInfo expression, nullable when [nullable].
  String typeInfo(String p, [bool nullable = false]);
}

String _n(bool nullable, {bool first = true}) =>
    nullable ? '${first ? '' : ', '}nullable: true' : '';

final class _Plain extends _Type {
  const _Plain(this.dart);
  @override
  final String dart;
  @override
  String typeInfo(String p, [bool nullable = false]) =>
      '$p.ClassType<$dart>(${_n(nullable)})';
}

final class _Any extends _Type {
  const _Any();
  @override
  String get dart => 'Object';
  @override
  String typeInfo(String p, [bool nullable = false]) =>
      '$p.ClassType<Object>(${_n(nullable)})';
}

final class _ListOf extends _Type {
  const _ListOf(this.element, this.nullableElement);
  final _Type element;
  final bool nullableElement;
  @override
  String get dart => 'List<${element.dart}${nullableElement ? '?' : ''}>';
  @override
  String typeInfo(String p, [bool nullable = false]) =>
      '$p.ListType<${element.dart}${nullableElement ? '?' : ''}>('
      '${element.typeInfo(p, nullableElement)}${_n(nullable, first: false)})';
}

final class _MapOf extends _Type {
  const _MapOf(this.value, this.nullableValue);
  final _Type value;
  final bool nullableValue;
  @override
  String get dart => 'Map<String, ${value.dart}${nullableValue ? '?' : ''}>';
  @override
  String typeInfo(String p, [bool nullable = false]) =>
      '$p.MapType<String, ${value.dart}${nullableValue ? '?' : ''}>('
      '$p.ClassType<String>(), ${value.typeInfo(p, nullableValue)}'
      '${_n(nullable, first: false)})';
}

final class _ClassRef extends _Type {
  _ClassRef(this.target);
  final _Class target;
  @override
  String get dart => target.name;
  @override
  String typeInfo(String p, [bool nullable = false]) =>
      '$p.ClassType<$dart>(${_n(nullable)})';
}

final class _EnumRef extends _Type {
  _EnumRef(this.target);
  final _Enum target;
  @override
  String get dart => target.name;
  @override
  String typeInfo(String p, [bool nullable = false]) =>
      '$p.EnumType<$dart>($dart.values, jsonValue: _\$${dart}Json'
      '${_n(nullable, first: false)})';
}

final class _Field {
  _Field({
    required this.name,
    required this.json,
    required this.type,
    required this.nullable,
    required this.required,
    required this.constraints,
    this.description,
  });
  final String name;
  final String json;
  final _Type type;
  final bool nullable;
  final bool required;
  final List<String> constraints;
  final String? description;
}

final class _Class {
  _Class(this.name, {this.description, this.source});
  final String name;
  final String? description;
  // The location of the schema it is the root of; `null` for the others.
  final String? source;
  final fields = <_Field>[];
}

final class _Enum {
  _Enum(this.name, this.values, {this.description});
  final String name;
  // (dart name, JSON text)
  final List<(String, String)> values;
  final String? description;
}

final class _Model {
  _Model(this.schemas);

  final List<LoadedJsonSchema> schemas;
  final warnings = <String>[];
  final classes = <_Class>[];
  final enums = <_Enum>[];
  final _names = <String>{};
  // The type of each schema by its document and JSON pointer.
  final _byPointer = <String, _Type>{};

  void build() {
    for (final schema in schemas) {
      final document = schema.document;
      final title =
          schema.entry.name ??
          (document['title'] is String ? document['title']! as String : null) ??
          _fileName(schema.entry.location);
      _typeOf(
        document,
        schema,
        '#',
        schema.entry.prefix + _pascal(title),
        root: true,
      );
    }
  }

  static String _fileName(String location) {
    var last = location.split('/').last.split('@').first;
    if (last.contains('.')) {
      last = last.substring(0, last.indexOf('.'));
    }
    return last.isEmpty ? 'Schema' : last;
  }

  String _unique(String name) {
    var unique = name;
    for (var n = 2; !_names.add(unique); n++) {
      unique = '$name$n';
    }
    return unique;
  }

  // The schema at [pointer] of [schema]'s document.
  Object? _at(LoadedJsonSchema schema, String pointer) {
    Object? node = schema.document;
    if (pointer == '#') {
      return node;
    }
    for (final raw in pointer.substring(2).split('/')) {
      final part = Uri.decodeComponent(
        raw,
      ).replaceAll('~1', '/').replaceAll('~0', '~');
      node = switch (node) {
        final Map<String, Object?> map => map[part],
        final List<Object?> list =>
          int.tryParse(part) is int
              ? list.elementAtOrNull(int.parse(part))
              : null,
        _ => null,
      };
    }
    return node;
  }

  // The type of [node] (at [pointer] of [schema]) and whether it allows
  // null. [name] is the class or enum name if it becomes one.
  (_Type, bool) _typeOfNullable(
    Object? node,
    LoadedJsonSchema schema,
    String pointer,
    String name,
  ) {
    if (node is! Map<String, Object?>) {
      return (const _Any(), true);
    }
    final ref = node[r'$ref'];
    if (ref is String) {
      return _ref(ref, schema, name);
    }
    final type = node['type'];
    if (type is List) {
      final kinds = type.whereType<String>().toList();
      final nullable = kinds.remove('null');
      if (kinds.length == 1) {
        final (t, _) = _typeOfNullable(
          {...node, 'type': kinds.single},
          schema,
          pointer,
          name,
        );
        return (t, nullable);
      }
      warnings.add(
        '${schema.entry.location} $pointer: a type of ${type.join(', ')} is '
        'Object?.',
      );
      return (const _Any(), true);
    }
    for (final union in const ['anyOf', 'oneOf']) {
      if (node[union] case final List<Object?> options) {
        final others = [
          for (final (i, o) in options.indexed)
            if (!(o is Map && o['type'] == 'null')) (i, o),
        ];
        final nullable = others.length < options.length;
        if (others.length == 1) {
          final (i, option) = others.single;
          final (t, n) = _typeOfNullable(
            option,
            schema,
            '$pointer/$union/$i',
            name,
          );
          return (t, nullable || n);
        }
        warnings.add(
          '${schema.entry.location} $pointer: $union of ${others.length} '
          'kinds is Object? (a JSON value of any of them).',
        );
        return (const _Any(), true);
      }
    }
    return (_typeOf(node, schema, pointer, name), type == 'null');
  }

  (_Type, bool) _ref(String ref, LoadedJsonSchema schema, String name) {
    if (ref.startsWith('#')) {
      final key = '${schema.entry.location}$ref';
      if (_byPointer[key] case final known?) {
        return (known, false);
      }
      final target = _at(schema, ref);
      final defName = ref.split('/').last;
      return _typeOfNullable(
        target,
        schema,
        ref,
        schema.entry.prefix + _pascal(defName),
      );
    }
    // Another document: one of the listed schemas, by its location or $id.
    final uri = _base(schema)?.resolve(ref) ?? Uri.tryParse(ref);
    for (final other in schemas) {
      final id = _base(other);
      if (other.entry.location == ref ||
          (id != null &&
              uri != null &&
              id.removeFragment() == uri.removeFragment())) {
        final fragment = uri?.fragment ?? '';
        final pointer = fragment.isEmpty ? '#' : '#$fragment';
        final key = '${other.entry.location}$pointer';
        if (_byPointer[key] case final known?) {
          return (known, false);
        }
        return _typeOfNullable(
          _at(other, pointer),
          other,
          pointer,
          other.entry.prefix +
              _pascal(
                pointer == '#'
                    ? _fileName(other.entry.location)
                    : pointer.split('/').last,
              ),
        );
      }
    }
    warnings.add(
      '${schema.entry.location}: \$ref $ref is not a schema of '
      'spring.json.schemas: Object?.',
    );
    return (const _Any(), true);
  }

  static Uri? _base(LoadedJsonSchema schema) {
    final id = schema.document[r'$id'];
    if (id is String) {
      return Uri.tryParse(id);
    }
    return Uri.tryParse(schema.entry.location);
  }

  _Type _typeOf(
    Map<String, Object?> node,
    LoadedJsonSchema schema,
    String pointer,
    String name, {
    bool root = false,
  }) {
    final key = '${schema.entry.location}$pointer';
    if (_byPointer[key] case final known?) {
      return known;
    }
    final description = node['description'] is String
        ? node['description']! as String
        : null;
    final enumValues = node['enum'];
    if (enumValues is List &&
        enumValues.isNotEmpty &&
        enumValues.every((v) => v is String)) {
      final values = <(String, String)>[];
      final used = <String>{};
      for (final value in enumValues.cast<String>()) {
        var dart = _camel(value);
        if (dart.isEmpty || _keywords.contains(dart) || dart == 'values') {
          dart = 'value${_pascal(dart)}';
        }
        var unique = dart;
        for (var n = 2; !used.add(unique); n++) {
          unique = '$dart$n';
        }
        values.add((unique, value));
      }
      final e = _Enum(_unique(name), values, description: description);
      enums.add(e);
      return _byPointer[key] = _EnumRef(e);
    }
    var type = node['type'];
    final allOf = node['allOf'];
    if (type == null && (node['properties'] != null || allOf is List)) {
      type = 'object';
    }
    switch (type) {
      case 'string':
        return switch (node['format']) {
          'date-time' => const _Plain('DateTime'),
          _ => const _Plain('String'),
        };
      case 'integer':
        return const _Plain('int');
      case 'number':
        return const _Plain('double');
      case 'boolean':
        return const _Plain('bool');
      case 'array':
        final items = node['items'];
        if (items == null) {
          return const _ListOf(_Any(), true);
        }
        final (element, nullable) = _typeOfNullable(
          items,
          schema,
          '$pointer/items',
          '${name}Item',
        );
        return _ListOf(element, nullable || element is _Any);
      case 'object':
        final properties = <String, Object?>{};
        final required = <String>{};
        void merge(Map<String, Object?> part) {
          if (part['properties'] case final Map<String, Object?> p) {
            properties.addAll(p);
          }
          if (part['required'] case final List<Object?> r) {
            required.addAll(r.whereType<String>());
          }
        }

        merge(node);
        if (allOf is List) {
          for (final part in allOf) {
            final resolved =
                part is Map<String, Object?> &&
                    part[r'$ref'] is String &&
                    (part[r'$ref']! as String).startsWith('#')
                ? _at(schema, part[r'$ref']! as String)
                : part;
            if (resolved is Map<String, Object?>) {
              merge(resolved);
            }
          }
        }
        if (properties.isEmpty) {
          final extra = node['additionalProperties'];
          if (extra is Map<String, Object?>) {
            final (value, nullable) = _typeOfNullable(
              extra,
              schema,
              '$pointer/additionalProperties',
              '${name}Value',
            );
            return _MapOf(value, nullable || value is _Any);
          }
          return const _MapOf(_Any(), true);
        }
        final c = _Class(
          _unique(name),
          description: description,
          source: root ? schema.entry.location : null,
        );
        _byPointer[key] = _ClassRef(c);
        classes.add(c);
        final usedNames = <String>{};
        for (final MapEntry(key: json, value: property) in properties.entries) {
          var dart = _camel(json);
          if (dart.isEmpty || _keywords.contains(dart)) {
            dart = '${dart}Value';
          }
          var unique = dart;
          for (var n = 2; !usedNames.add(unique); n++) {
            unique = '$dart$n';
          }
          final (t, allowsNull) = _typeOfNullable(
            property,
            schema,
            '$pointer/properties/${_escape(json)}',
            '${c.name}${_pascal(json)}',
          );
          final isRequired = required.contains(json) && !allowsNull;
          c.fields.add(
            _Field(
              name: unique,
              json: json,
              type: t,
              nullable: !isRequired || t is _Any,
              required: isRequired && t is! _Any,
              constraints: property is Map<String, Object?>
                  ? _constraints(property, t)
                  : const [],
              description:
                  property is Map<String, Object?> &&
                      property['description'] is String
                  ? property['description']! as String
                  : null,
            ),
          );
        }
        return c.fields.isEmpty ? const _MapOf(_Any(), true) : _ClassRef(c);
      default:
        return const _Any();
    }
  }

  static String _escape(String part) =>
      part.replaceAll('~', '~0').replaceAll('/', '~1');

  // The constraint annotations of a property (prefix added at emission).
  static List<String> _constraints(Map<String, Object?> node, _Type type) {
    final result = <String>[];
    num? n(String key) => node[key] is num ? node[key]! as num : null;
    final isList = type is _ListOf;
    final (minSize, maxSize) = isList
        ? (n('minItems'), n('maxItems'))
        : (n('minLength'), n('maxLength'));
    if (minSize != null || maxSize != null) {
      final bounds = [
        if (minSize != null) 'min: ${minSize.toInt()}',
        if (maxSize != null) 'max: ${maxSize.toInt()}',
      ];
      result.add('Size(${bounds.join(', ')})');
    }
    final integer = type is _Plain && type.dart == 'int';
    for (final (key, exclusive, min) in const [
      ('minimum', false, true),
      ('exclusiveMinimum', true, true),
      ('maximum', false, false),
      ('exclusiveMaximum', true, false),
    ]) {
      final value = n(key);
      if (value == null) {
        continue;
      }
      if (integer && !exclusive && value == value.roundToDouble()) {
        result.add('${min ? 'Min' : 'Max'}(${value.toInt()})');
      } else {
        result.add(
          "${min ? 'DecimalMin' : 'DecimalMax'}('$value'"
          "${exclusive ? ', inclusive: false' : ''})",
        );
      }
    }
    if (node['pattern'] case final String pattern) {
      result.add('Matches(${_raw(pattern)})');
    }
    if (node['format'] == 'email') {
      result.add('Email()');
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // The code.

  String code() {
    const p = JsonSchemaClasses.prefix;
    final out = StringBuffer();
    void w(String line) => out.writeln(line);
    for (final e in enums) {
      _doc(out, e.description, '');
      w('enum ${e.name} {');
      for (final (dart, json) in e.values) {
        w('  /// `${json.replaceAll('`', "'")}`.');
        w('  $dart,');
      }
      w('}\n');
      w(
        'Object? _\$${e.name}Json(${e.name} value) => switch (value) {',
      );
      for (final (dart, json) in e.values) {
        w('  ${e.name}.$dart => ${_raw(json)},');
      }
      w('};\n');
    }
    for (final c in classes) {
      _doc(out, c.description, '');
      if (c.source case final source?) {
        w('@$p.JsonSchemaSource(${_raw(source)})');
      }
      // A property left out stays out: `null` is no value of its schema.
      w('@$p.JsonInclude($p.JsonInclusion.nonNull)');
      w('class ${c.name} {');
      w('  /// The ${c.name} of these values.');
      w('  const ${c.name}({');
      for (final f in c.fields) {
        w('    ${f.required ? 'required ' : ''}this.${f.name},');
      }
      w('  });\n');
      for (final f in c.fields) {
        _doc(out, f.description ?? 'JSON `${f.json}`.', '  ');
        for (final constraint in f.constraints) {
          w('  @$p.$constraint');
        }
        if (f.name != f.json) {
          w('  @$p.JsonProperty(${_raw(f.json)})');
        }
        w(
          '  final ${f.type.dart}${f.nullable ? '?' : ''} ${f.name};\n',
        );
      }
      w('  @override');
      w(
        "  String toString() => '${c.name}("
        "${[for (final f in c.fields) '${f.name}: \$${f.name}'].join(', ')})';",
      );
      w('}\n');
    }
    w(
      'final List<$p.BeanIntrospection<Object>> '
      '${JsonSchemaClasses.introspections} = [',
    );
    for (final c in classes) {
      w('  $p.BeanIntrospection<${c.name}>(');
      w('    className: ${_raw(c.name)},');
      final classAnnotations = [
        '$p.JsonInclude($p.JsonInclusion.nonNull)',
        if (c.source case final source?) '$p.JsonSchemaSource(${_raw(source)})',
      ];
      w('    annotations: const [${classAnnotations.join(', ')}],');
      w('    properties: [');
      for (final f in c.fields) {
        final info = f.type.typeInfo(p, f.nullable);
        final annotations = [
          for (final constraint in f.constraints) '$p.$constraint',
          if (f.name != f.json) '$p.JsonProperty(${_raw(f.json)})',
        ];
        w('      $p.BeanProperty<${c.name}>(');
        w('        ${_raw(f.name)},');
        w('        typeInfo: $info,');
        if (f.nullable) {
          w('        nullable: true,');
        }
        w('        get: (bean) => bean.${f.name},');
        if (annotations.isNotEmpty) {
          w(
            '        annotations: const [${annotations.join(', ')}],',
          );
        }
        w('      ),');
      }
      w('    ],');
      w('    constructor: $p.BeanConstructor<${c.name}>(');
      w('      parameters: [');
      for (final f in c.fields) {
        final info = f.type.typeInfo(p, f.nullable);
        w('        $p.BeanParameter(');
        w('          ${_raw(f.name)},');
        w('          type: $info,');
        w('          symbol: #${f.name},');
        if (f.required) {
          w('          isRequired: true,');
        }
        if (f.name != f.json) {
          w(
            '          annotations: const [$p.JsonProperty(${_raw(f.json)})],',
          );
        }
        w('        ),');
      }
      w('      ],');
      w('      create: (positional, named) => ${c.name}(');
      for (final f in c.fields) {
        final cast = '${f.type.dart}${f.nullable ? '?' : ''}';
        w(
          cast == 'Object?'
              ? '        ${f.name}: named[#${f.name}],'
              : '        ${f.name}: named[#${f.name}] as $cast,',
        );
      }
      w('      ),');
      w('    ),');
      w('  ),');
    }
    w('];');
    return out.toString();
  }

  static void _doc(StringBuffer out, String? text, String indent) {
    if (text == null || text.trim().isEmpty) {
      return;
    }
    for (final line in const LineSplitter().convert(text.trim())) {
      out.writeln('$indent/// ${line.trimRight()}'.trimRight());
    }
  }
}

// A Dart raw string of [text].
String _raw(String text) {
  if (!text.contains("'") && !text.contains('\n')) {
    return "r'$text'";
  }
  if (!text.contains('"') && !text.contains('\n')) {
    return 'r"$text"';
  }
  return jsonEncode(text).replaceAll(r'$', r'\$');
}

String _pascal(String text) {
  final words = RegExp('[A-Za-z0-9]+')
      .allMatches(text)
      .map((m) => m[0]!)
      .expand(_splitCamel)
      .toList();
  var result = [
    for (final w in words) w[0].toUpperCase() + w.substring(1),
  ].join();
  if (result.isEmpty) {
    result = 'Schema';
  }
  if (RegExp('^[0-9]').hasMatch(result)) {
    result = 'S$result';
  }
  return result;
}

String _camel(String text) {
  final pascal = _pascal(text);
  if (pascal == 'Schema' && !text.toLowerCase().contains('schema')) {
    return '';
  }
  // Keep a leading run of capitals as one word: URL → url, URLPath → urlPath.
  final lead = RegExp(r'^[A-Z]+(?=[A-Z][a-z]|[0-9]|$)').firstMatch(pascal);
  if (lead != null) {
    return pascal.replaceRange(0, lead.end, lead[0]!.toLowerCase());
  }
  return pascal[0].toLowerCase() + pascal.substring(1);
}

// `orderId` → [order, Id]; `ORDER` stays one word.
Iterable<String> _splitCamel(String word) => word == word.toUpperCase()
    ? [word.toLowerCase()]
    : RegExp('[A-Z]?[a-z0-9]+|[A-Z]+(?![a-z])')
          .allMatches(word)
          .map((m) => m[0]!);

const _keywords = {
  'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case', //
  'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
  'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
  'external', 'factory', 'false', 'final', 'finally', 'for', 'Function',
  'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
  'late', 'library', 'mixin', 'new', 'null', 'of', 'on', 'operator', 'part',
  'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
  'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'type',
  'typedef', 'var', 'void', 'when', 'while', 'with', 'yield', 'hashCode',
  'toString', 'runtimeType', 'noSuchMethod',
};

// Names an app imports with Spring for Dart, which a class of a schema
// would make ambiguous.
const _springNames = {
  'Order', 'Component', 'Service', 'Repository', 'Value', 'Bean', //
  'Configuration', 'Resource', 'Environment', 'Profile', 'Lazy', 'Primary',
  'Qualifier', 'Scope', 'Valid', 'Size', 'Min', 'Max', 'Email', 'Matches',
  'NotNull', 'NotBlank', 'NotEmpty', 'Positive', 'Negative', 'Past',
  'Event', 'Introspected', 'JsonProperty', 'JsonIgnore', 'JsonInclude',
  'ObjectMapper', 'JsonNode', 'Errors', 'Validator', 'Conditional',
};
