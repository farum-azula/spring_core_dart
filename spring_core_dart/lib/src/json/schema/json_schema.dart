import 'dart:collection';
import 'dart:convert';

import 'package:spring_core_dart/src/json/json_exception.dart';

/// A JSON Schema document (draft 2020-12) that checks decoded JSON.
///
/// Use it to check JSON you receive before you use it: a request body, a
/// file, a message. [validate] takes the decoded JSON (what `jsonDecode`
/// returns) and lists every place that does not fit, with its JSON
/// pointer. `ObjectMapper` uses it for classes marked with
/// `@JsonSchemaSource` when it has a `schemaResolver`.
///
/// Supported keywords: `type` (also a list, and `integer`), `enum`,
/// `const`, `properties`, `required`, `additionalProperties`,
/// `patternProperties`, `propertyNames`, `minProperties`,
/// `maxProperties`, `dependentRequired`, `dependentSchemas`, `items`,
/// `prefixItems`, `minItems`, `maxItems`, `uniqueItems`, `contains`,
/// `minContains`, `maxContains`, `minLength` and `maxLength` (in Unicode
/// code points), `pattern` (a Dart `RegExp` in Unicode mode, not
/// anchored), `minimum`, `maximum`, `exclusiveMinimum`,
/// `exclusiveMaximum`, `multipleOf`, `format`, `allOf`, `anyOf`, `oneOf`,
/// `not`, `if` / `then` / `else`, `$ref`, `$defs` / `definitions`, `$id`,
/// `$anchor`, and the schemas `true` and `false`. Other keywords (`title`,
/// `description`, `default`, `examples`, ...) are ignored.
/// `unevaluatedProperties`, `unevaluatedItems` and `$dynamicRef` are not
/// supported (ignored).
///
/// `format` is checked for `date-time`, `date`, `time` (RFC 3339; a time
/// needs its offset), `email` (something `@` a domain, no spaces), `uri`
/// (with a scheme), `uri-reference`, `uuid`, `ipv4` and `ipv6`; other
/// formats are ignored.
///
/// A `$ref` is resolved against the base URI (the `$id`s around it): a
/// fragment (`#/$defs/item`, `#anchor`) in the same document, another
/// document through the [registry] by its absolute URI. A `$ref` that
/// loops without reaching a value is reported, not followed forever.
///
/// ```dart
/// final schema = JsonSchema.parse('''
///   {"type": "object", "required": ["id"],
///    "properties": {"id": {"type": "integer", "minimum": 1}}}
/// ''');
/// final result = schema.validate(jsonDecode('{"id": 0}'));
/// result.isValid;                  // false
/// result.violations.first.path;    // /id
/// result.violations.first.message; // must be at least 1
/// ```
///
/// Spring (Java): Spring has no counterpart; Java applications use a
/// library such as networknt's `json-schema-validator`.
final class JsonSchema {
  /// The schema [document], with the URI [id] it is known by (its `$id`
  /// is resolved against it) and the [registry] that holds the documents
  /// its `$ref`s point to.
  JsonSchema(this.document, {Uri? id, this.registry})
    : _given = id == null ? null : _withoutFragment(id),
      id = _idOf(document, id),
      _root = document {
    _index(document, _given ?? Uri());
  }

  JsonSchema._rejecting({Uri? id, this.registry})
    : document = const {'not': <String, Object?>{}},
      _given = id == null ? null : _withoutFragment(id),
      id = id == null ? null : _withoutFragment(id),
      _root = false;

  /// The schema written as JSON [text]; `true` and `false` are the schemas
  /// that accept everything and nothing. Throws a [FormatException] for
  /// text that is not JSON or not a schema.
  factory JsonSchema.parse(
    String text, {
    Uri? id,
    JsonSchemaRegistry? registry,
  }) {
    final decoded = jsonDecode(text);
    return switch (decoded) {
      final Map<String, Object?> map => JsonSchema(
        map,
        id: id,
        registry: registry,
      ),
      true => JsonSchema(const {}, id: id, registry: registry),
      false => JsonSchema._rejecting(id: id, registry: registry),
      _ => throw const FormatException(
        'a JSON Schema is an object, true or false',
      ),
    };
  }

  /// The decoded schema document.
  final Map<String, Object?> document;

  /// The URI of the document: its `$id` (resolved against the URI it was
  /// given), else that URI; `null` when it has neither.
  final Uri? id;

  /// The documents other documents' `$ref`s are looked up in; `null` when
  /// the schema refers only to itself.
  final JsonSchemaRegistry? registry;

  final Uri? _given;

  // What is evaluated: the document, or `false` for the schema `false`.
  final Object? _root;

  // Subschemas by the absolute URI their `$id` or `$anchor` gives.
  final _resources = <Uri, Object?>{};

  static final _patterns = <String, RegExp?>{};

  static Uri _withoutFragment(Uri uri) =>
      uri.hasFragment ? uri.removeFragment() : uri;

  static Uri? _idOf(Map<String, Object?> document, Uri? given) {
    final own = document[r'$id'];
    if (own is String) {
      return _withoutFragment((given ?? Uri()).resolve(own));
    }
    return given == null ? null : _withoutFragment(given);
  }

  static const _schemaMaps = [
    'properties',
    'patternProperties',
    r'$defs',
    'definitions',
    'dependentSchemas',
  ];

  static const _schemaValues = [
    'additionalProperties',
    'propertyNames',
    'items',
    'additionalItems',
    'contains',
    'not',
    'if',
    'then',
    'else',
    'unevaluatedItems',
    'unevaluatedProperties',
  ];

  static const _schemaLists = ['allOf', 'anyOf', 'oneOf', 'prefixItems'];

  void _index(Object? schema, Uri base) {
    if (schema is List<Object?>) {
      for (final item in schema) {
        _index(item, base);
      }
      return;
    }
    if (schema is! Map<String, Object?>) {
      return;
    }
    var scope = base;
    if (schema[r'$id'] case final String id) {
      scope = _withoutFragment(base.resolve(id));
      _resources[scope] = schema;
    }
    if (schema[r'$anchor'] case final String anchor) {
      _resources[scope.replace(fragment: anchor)] = schema;
    }
    for (final keyword in _schemaMaps) {
      if (schema[keyword] case final Map<String, Object?> map) {
        for (final value in map.values) {
          _index(value, scope);
        }
      }
    }
    for (final keyword in [..._schemaValues, ..._schemaLists]) {
      _index(schema[keyword], scope);
    }
  }

  /// Checks [instance], decoded JSON (`Map<String, Object?>`, `List`,
  /// `num`, `String`, `bool` or `null`), and returns every violation.
  JsonSchemaResult validate(Object? instance) {
    final violations = <JsonSchemaViolation>[];
    _Evaluator(registry).evaluate(
      _root,
      instance,
      '',
      _Scope(this, _given ?? Uri(), _given ?? Uri()),
      violations,
    );
    return JsonSchemaResult(List.unmodifiable(violations));
  }

  @override
  String toString() => 'JsonSchema(${id ?? 'no id'})';
}

/// Finds the [JsonSchema] of a `@JsonSchemaSource` location, for
/// `ObjectMapper.schemaResolver`; `null` when there is none.
///
/// Spring (Java): Spring has no counterpart.
typedef JsonSchemaResolver = JsonSchema? Function(String location);

/// The outcome of [JsonSchema.validate]: valid, or the violations.
///
/// Spring (Java): Spring has no counterpart.
final class JsonSchemaResult {
  /// A result with [violations]; none means valid.
  const JsonSchemaResult(this.violations);

  /// Every place where the instance does not fit, in document order.
  final List<JsonSchemaViolation> violations;

  /// Whether the instance fits the schema.
  bool get isValid => violations.isEmpty;

  @override
  String toString() =>
      isValid ? 'valid' : 'invalid:\n  ${violations.join('\n  ')}';
}

/// One place where a JSON value does not fit a [JsonSchema].
///
/// Spring (Java): Spring has no counterpart.
final class JsonSchemaViolation {
  /// The violation of [keyword] at [path], described by [message].
  const JsonSchemaViolation(this.path, this.keyword, this.message);

  /// The JSON pointer of the value, such as `/items/2/price`; `''` for
  /// the whole document. A missing property's path names the property.
  final String path;

  /// The schema keyword that failed, such as `minimum` or `required`.
  final String keyword;

  /// What is wrong, in plain English: `must be at least 1`, `is
  /// required`, `must be one of: a, b`.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is JsonSchemaViolation &&
      other.path == path &&
      other.keyword == keyword &&
      other.message == message;

  @override
  int get hashCode => Object.hash(path, keyword, message);

  @override
  String toString() => '${path.isEmpty ? '(root)' : path}: $message';
}

/// The JSON Schema documents a `$ref` to another document is resolved
/// in, by their absolute URI.
///
/// ```dart
/// final registry = JsonSchemaRegistry()
///   ..add(JsonSchema.parse(addressJson)); // its $id: https://x.org/address.json
/// final order = JsonSchema.parse(
///   '{"\$id": "https://x.org/order.json",'
///   ' "properties": {"to": {"\$ref": "address.json"}}}',
///   registry: registry,
/// );
/// ```
///
/// Spring (Java): Spring has no counterpart.
final class JsonSchemaRegistry {
  /// A registry holding [schemas] (each by its [JsonSchema.id]).
  JsonSchemaRegistry([Iterable<JsonSchema> schemas = const []]) {
    schemas.forEach(add);
  }

  final _schemas = <Uri, JsonSchema>{};

  /// The schemas added, by the URI each is known by (read only).
  Map<Uri, JsonSchema> get schemas => Map.unmodifiable(_schemas);

  /// Adds [schema] by [uri], else by its [JsonSchema.id]; throws an
  /// [ArgumentError] when it has neither. A later schema for the same URI
  /// replaces the earlier one.
  void add(JsonSchema schema, {Uri? uri}) {
    final key =
        uri ??
        schema.id ??
        (throw ArgumentError.value(
          schema,
          'schema',
          r'has no $id: pass the uri it is known by',
        ));
    _schemas[JsonSchema._withoutFragment(key)] = schema;
  }

  /// The schema known by [uri] (its fragment is ignored): one added by
  /// that URI, else a subschema with that `$id` in one of them; `null`
  /// when there is none.
  JsonSchema? resolve(Uri uri) {
    final found = _locate(uri);
    if (found == null) {
      return null;
    }
    final (owner, resource) = found;
    if (identical(resource, owner.document)) {
      return owner;
    }
    return resource is Map<String, Object?>
        ? JsonSchema(resource, id: uri, registry: this)
        : null;
  }

  (JsonSchema, Object?)? _locate(Uri uri) {
    final key = JsonSchema._withoutFragment(uri);
    if (_schemas[key] case final schema?) {
      return (schema, schema.document);
    }
    for (final schema in _schemas.values) {
      if (schema._resources.containsKey(key)) {
        return (schema, schema._resources[key]);
      }
    }
    return null;
  }
}

/// The error `ObjectMapper` throws when JSON read into a class marked
/// `@JsonSchemaSource` does not fit its schema.
///
/// [path] is where the checked value is in the document being read (empty
/// for the whole document); each violation's path is a JSON pointer
/// inside that value. The message lists them all.
///
/// ```dart
/// try {
///   mapper.readValue<Order>(json);
/// } on JsonSchemaValidationException catch (error) {
///   for (final violation in error.violations) {
///     print('${violation.path}: ${violation.message}');
///   }
/// }
/// ```
///
/// Spring (Java): Spring has no counterpart.
class JsonSchemaValidationException extends JsonMappingException {
  /// The [violations] of the schema at [location], for the value at
  /// [path].
  JsonSchemaValidationException(
    this.violations, {
    required this.location,
    super.path,
  }) : super(_describe(violations, location));

  /// Every place where the value does not fit the schema.
  final List<JsonSchemaViolation> violations;

  /// The `@JsonSchemaSource` location of the schema that failed.
  final String location;

  static String _describe(
    List<JsonSchemaViolation> violations,
    String location,
  ) =>
      'does not match the JSON Schema $location: '
      '${violations.map((v) => '$v').join('; ')}';
}

final class _Scope {
  const _Scope(this.owner, this.base, this.root);

  // The document being evaluated.
  final JsonSchema owner;

  // The base URI of relative `$ref`s.
  final Uri base;

  // The URI the owner's root document was entered by.
  final Uri root;

  _Scope at(Uri base) => _Scope(owner, base, root);
}

final class _Evaluator {
  _Evaluator(this.registry);

  final JsonSchemaRegistry? registry;
  final _active = <(Object?, String)>{};
  var _depth = 0;

  static const _maxDepth = 512;

  bool evaluate(
    Object? schema,
    Object? instance,
    String path,
    _Scope scope,
    List<JsonSchemaViolation> out,
  ) {
    if (schema == false) {
      out.add(JsonSchemaViolation(path, 'false', 'is not allowed'));
      return false;
    }
    if (schema is! Map<String, Object?>) {
      return true;
    }
    var current = scope;
    if (schema[r'$id'] case final String id) {
      current = scope.at(JsonSchema._withoutFragment(scope.base.resolve(id)));
    }
    final start = out.length;
    if (schema[r'$ref'] case final String ref) {
      _ref(ref, instance, path, current, out);
    }
    _type(schema, instance, path, out);
    _values(schema, instance, path, out);
    switch (instance) {
      case final num number:
        _number(schema, number, path, out);
      case final String text:
        _string(schema, text, path, out);
      case final List<Object?> items:
        _array(schema, items, path, current, out);
      case final Map<Object?, Object?> object:
        _object(schema, object, path, current, out);
    }
    _combinators(schema, instance, path, current, out);
    return out.length == start;
  }

  bool _check(Object? schema, Object? instance, String path, _Scope scope) =>
      evaluate(schema, instance, path, scope, []);

  // ------------------------------------------------------------------
  // $ref
  // ------------------------------------------------------------------

  void _ref(
    String ref,
    Object? instance,
    String path,
    _Scope scope,
    List<JsonSchemaViolation> out,
  ) {
    final target = _resolve(ref, scope);
    if (target == null) {
      out.add(
        JsonSchemaViolation(path, r'$ref', 'cannot resolve the \$ref "$ref"'),
      );
      return;
    }
    final (schema, targetScope) = target;
    final key = (schema, path);
    if (_depth >= _maxDepth || !_active.add(key)) {
      out.add(
        JsonSchemaViolation(
          path,
          r'$ref',
          'the \$ref "$ref" refers back to itself without reaching a value',
        ),
      );
      return;
    }
    _depth++;
    try {
      evaluate(schema, instance, path, targetScope, out);
    } finally {
      _depth--;
      _active.remove(key);
    }
  }

  (Object?, _Scope)? _resolve(String ref, _Scope scope) {
    final Uri uri;
    try {
      uri = scope.base.resolve(ref);
    } on FormatException {
      return null;
    }
    final document = JsonSchema._withoutFragment(uri);
    final fragment = uri.hasFragment ? uri.fragment : '';
    JsonSchema owner;
    Object? resource;
    var root = scope.root;
    if (document == scope.root) {
      owner = scope.owner;
      resource = owner.document;
    } else if (scope.owner._resources.containsKey(document)) {
      owner = scope.owner;
      resource = owner._resources[document];
    } else {
      final found =
          registry?._locate(document) ??
          scope.owner.registry?._locate(document);
      if (found == null) {
        return null;
      }
      (owner, resource) = found;
      root = identical(resource, owner.document)
          ? document
          : (owner._given ?? Uri());
    }
    var base = document;
    if (fragment.isEmpty) {
      return (resource, _Scope(owner, base, root));
    }
    if (!fragment.startsWith('/')) {
      final anchored = owner._resources[document.replace(fragment: fragment)];
      return anchored == null ? null : (anchored, _Scope(owner, base, root));
    }
    var node = resource;
    for (final raw in fragment.substring(1).split('/')) {
      final segment = Uri.decodeComponent(
        raw,
      ).replaceAll('~1', '/').replaceAll('~0', '~');
      switch (node) {
        case final Map<String, Object?> map when map.containsKey(segment):
          node = map[segment];
        case final List<Object?> list:
          final index = int.tryParse(segment);
          if (index == null || index < 0 || index >= list.length) {
            return null;
          }
          node = list[index];
        default:
          return null;
      }
      if (node case {r'$id': final String id}) {
        base = JsonSchema._withoutFragment(base.resolve(id));
      }
    }
    return (node, _Scope(owner, base, root));
  }

  // ------------------------------------------------------------------
  // Any type
  // ------------------------------------------------------------------

  void _type(
    Map<String, Object?> schema,
    Object? instance,
    String path,
    List<JsonSchemaViolation> out,
  ) {
    final types = switch (schema['type']) {
      final String type => [type],
      final List<Object?> list => list.whereType<String>().toList(),
      _ => null,
    };
    if (types == null || types.any((t) => _isType(instance, t))) {
      return;
    }
    out.add(
      JsonSchemaViolation(
        path,
        'type',
        'must be ${_words(types.map(_article))}, '
            'got ${_article(_typeOf(instance))}',
      ),
    );
  }

  void _values(
    Map<String, Object?> schema,
    Object? instance,
    String path,
    List<JsonSchemaViolation> out,
  ) {
    if (schema['enum'] case final List<Object?> values
        when !values.any((v) => _equal(v, instance))) {
      out.add(
        JsonSchemaViolation(
          path,
          'enum',
          'must be one of: ${values.map(_show).join(', ')}',
        ),
      );
    }
    if (schema.containsKey('const') && !_equal(schema['const'], instance)) {
      out.add(
        JsonSchemaViolation(
          path,
          'const',
          'must be ${jsonEncode(schema['const'])}',
        ),
      );
    }
  }

  // ------------------------------------------------------------------
  // Numbers
  // ------------------------------------------------------------------

  void _number(
    Map<String, Object?> schema,
    num value,
    String path,
    List<JsonSchemaViolation> out,
  ) {
    void fail(String keyword, String message) =>
        out.add(JsonSchemaViolation(path, keyword, message));
    if (schema['minimum'] case final num limit when value < limit) {
      fail('minimum', 'must be at least $limit');
    }
    if (schema['maximum'] case final num limit when value > limit) {
      fail('maximum', 'must be at most $limit');
    }
    if (schema['exclusiveMinimum'] case final num limit when value <= limit) {
      fail('exclusiveMinimum', 'must be greater than $limit');
    }
    if (schema['exclusiveMaximum'] case final num limit when value >= limit) {
      fail('exclusiveMaximum', 'must be less than $limit');
    }
    if (schema['multipleOf'] case final num divisor
        when divisor > 0 && !_isMultiple(value, divisor)) {
      fail('multipleOf', 'must be a multiple of $divisor');
    }
  }

  static bool _isMultiple(num value, num divisor) {
    if (value is int && divisor is int) {
      return value % divisor == 0;
    }
    final quotient = value / divisor;
    if (!quotient.isFinite) {
      return false;
    }
    return (quotient - quotient.roundToDouble()).abs() < 1e-9;
  }

  // ------------------------------------------------------------------
  // Strings
  // ------------------------------------------------------------------

  void _string(
    Map<String, Object?> schema,
    String value,
    String path,
    List<JsonSchemaViolation> out,
  ) {
    void fail(String keyword, String message) =>
        out.add(JsonSchemaViolation(path, keyword, message));
    final length = value.runes.length;
    if (_count(schema['minLength']) case final limit? when length < limit) {
      fail('minLength', 'must be at least ${_n(limit, 'character')} long');
    }
    if (_count(schema['maxLength']) case final limit? when length > limit) {
      fail('maxLength', 'must be at most ${_n(limit, 'character')} long');
    }
    if (schema['pattern'] case final String pattern) {
      final regexp = _regexp(pattern);
      if (regexp == null) {
        fail('pattern', 'cannot be checked: "$pattern" is not a valid pattern');
      } else if (!regexp.hasMatch(value)) {
        fail('pattern', 'must match the pattern $pattern');
      }
    }
    if (schema['format'] case final String format
        when !JsonSchemaFormats.isValid(format, value)) {
      fail('format', 'must be a valid $format');
    }
  }

  static RegExp? _regexp(String pattern) =>
      JsonSchema._patterns.putIfAbsent(pattern, () {
        try {
          return RegExp(pattern, unicode: true);
        } on FormatException {
          try {
            return RegExp(pattern);
          } on FormatException {
            return null;
          }
        }
      });

  // ------------------------------------------------------------------
  // Arrays
  // ------------------------------------------------------------------

  void _array(
    Map<String, Object?> schema,
    List<Object?> items,
    String path,
    _Scope scope,
    List<JsonSchemaViolation> out,
  ) {
    void fail(String keyword, String message) =>
        out.add(JsonSchemaViolation(path, keyword, message));
    final itemsKeyword = schema['items'];
    // `items` as a list: the tuple form of drafts before 2020-12.
    final prefix = switch ((schema['prefixItems'], itemsKeyword)) {
      (final List<Object?> list, _) => list,
      (_, final List<Object?> list) => list,
      _ => const <Object?>[],
    };
    final rest = itemsKeyword is List
        ? schema['additionalItems']
        : itemsKeyword;
    for (var i = 0; i < items.length; i++) {
      final itemPath = '$path/$i';
      if (i < prefix.length) {
        evaluate(prefix[i], items[i], itemPath, scope, out);
      } else if (rest == false) {
        out.add(JsonSchemaViolation(itemPath, 'items', 'is not allowed'));
      } else if (rest != null) {
        evaluate(rest, items[i], itemPath, scope, out);
      }
    }
    if (_count(schema['minItems']) case final limit?
        when items.length < limit) {
      fail('minItems', 'must have at least ${_n(limit, 'item')}');
    }
    if (_count(schema['maxItems']) case final limit?
        when items.length > limit) {
      fail('maxItems', 'must have at most ${_n(limit, 'item')}');
    }
    if (schema['uniqueItems'] == true) {
      if (_duplicate(items) case (final i, final j)) {
        fail(
          'uniqueItems',
          'must not have duplicate items (items $i and $j are equal)',
        );
      }
    }
    if (schema.containsKey('contains')) {
      final contains = schema['contains'];
      var matches = 0;
      for (var i = 0; i < items.length; i++) {
        if (_check(contains, items[i], '$path/$i', scope)) {
          matches++;
        }
      }
      final min = _count(schema['minContains']) ?? 1;
      if (matches < min) {
        fail(
          min == 1 && !schema.containsKey('minContains')
              ? 'contains'
              : 'minContains',
          'must contain at least ${_n(min, 'item')} matching the "contains" '
          'schema',
        );
      }
      if (_count(schema['maxContains']) case final max? when matches > max) {
        fail(
          'maxContains',
          'must contain at most ${_n(max, 'item')} matching the "contains" '
              'schema',
        );
      }
    }
  }

  // ------------------------------------------------------------------
  // Objects
  // ------------------------------------------------------------------

  void _object(
    Map<String, Object?> schema,
    Map<Object?, Object?> object,
    String path,
    _Scope scope,
    List<JsonSchemaViolation> out,
  ) {
    void fail(String keyword, String message) =>
        out.add(JsonSchemaViolation(path, keyword, message));
    if (schema['required'] case final List<Object?> required) {
      for (final name in required.whereType<String>()) {
        if (!object.containsKey(name)) {
          out.add(
            JsonSchemaViolation(_child(path, name), 'required', 'is required'),
          );
        }
      }
    }
    final properties = switch (schema['properties']) {
      final Map<String, Object?> map => map,
      _ => const <String, Object?>{},
    };
    final patterns = switch (schema['patternProperties']) {
      final Map<String, Object?> map => map,
      _ => const <String, Object?>{},
    };
    final additional = schema['additionalProperties'];
    final names = schema['propertyNames'];
    for (final MapEntry(:key, :value) in object.entries) {
      final name = '$key';
      final childPath = _child(path, name);
      var matched = false;
      if (properties.containsKey(name)) {
        matched = true;
        evaluate(properties[name], value, childPath, scope, out);
      }
      for (final MapEntry(key: pattern, value: sub) in patterns.entries) {
        if (_regexp(pattern)?.hasMatch(name) ?? false) {
          matched = true;
          evaluate(sub, value, childPath, scope, out);
        }
      }
      if (!matched && additional != null) {
        if (additional == false) {
          out.add(
            JsonSchemaViolation(
              childPath,
              'additionalProperties',
              'is not allowed',
            ),
          );
        } else {
          evaluate(additional, value, childPath, scope, out);
        }
      }
      if (names != null) {
        final problems = <JsonSchemaViolation>[];
        if (!evaluate(names, name, childPath, scope, problems)) {
          out.add(
            JsonSchemaViolation(
              childPath,
              'propertyNames',
              'is not a valid property name: '
                  '${problems.map((p) => p.message).join('; ')}',
            ),
          );
        }
      }
    }
    if (_count(schema['minProperties']) case final limit?
        when object.length < limit) {
      fail('minProperties', 'must have at least ${_n(limit, 'property')}');
    }
    if (_count(schema['maxProperties']) case final limit?
        when object.length > limit) {
      fail('maxProperties', 'must have at most ${_n(limit, 'property')}');
    }
    if (schema['dependentRequired'] case final Map<String, Object?> rules) {
      for (final MapEntry(key: name, value: needed) in rules.entries) {
        if (!object.containsKey(name) || needed is! List) {
          continue;
        }
        for (final other in needed.whereType<String>()) {
          if (!object.containsKey(other)) {
            out.add(
              JsonSchemaViolation(
                _child(path, other),
                'dependentRequired',
                'is required when "$name" is present',
              ),
            );
          }
        }
      }
    }
    if (schema['dependentSchemas'] case final Map<String, Object?> rules) {
      for (final MapEntry(key: name, value: sub) in rules.entries) {
        if (object.containsKey(name)) {
          evaluate(sub, object, path, scope, out);
        }
      }
    }
  }

  // ------------------------------------------------------------------
  // allOf, anyOf, oneOf, not, if / then / else
  // ------------------------------------------------------------------

  void _combinators(
    Map<String, Object?> schema,
    Object? instance,
    String path,
    _Scope scope,
    List<JsonSchemaViolation> out,
  ) {
    if (schema['allOf'] case final List<Object?> all) {
      for (final sub in all) {
        evaluate(sub, instance, path, scope, out);
      }
    }
    if (schema['anyOf'] case final List<Object?> any) {
      final branches = _branches(any, instance, path, scope);
      if (!branches.any((b) => b.isEmpty)) {
        _reportBranches(
          branches,
          path,
          'anyOf',
          'must match at least one of the schemas',
          out,
        );
      }
    }
    if (schema['oneOf'] case final List<Object?> one) {
      final branches = _branches(one, instance, path, scope);
      final matching = [
        for (var i = 0; i < branches.length; i++)
          if (branches[i].isEmpty) i,
      ];
      if (matching.isEmpty) {
        _reportBranches(
          branches,
          path,
          'oneOf',
          'must match exactly one of the schemas',
          out,
        );
      } else if (matching.length > 1) {
        out.add(
          JsonSchemaViolation(
            path,
            'oneOf',
            'must match exactly one of the schemas, but matches '
                '${matching.length} (${matching.join(', ')})',
          ),
        );
      }
    }
    if (schema.containsKey('not') &&
        _check(schema['not'], instance, path, scope)) {
      out.add(JsonSchemaViolation(path, 'not', 'must not match the schema'));
    }
    if (schema.containsKey('if')) {
      if (_check(schema['if'], instance, path, scope)) {
        if (schema.containsKey('then')) {
          evaluate(schema['then'], instance, path, scope, out);
        }
      } else if (schema.containsKey('else')) {
        evaluate(schema['else'], instance, path, scope, out);
      }
    }
  }

  List<List<JsonSchemaViolation>> _branches(
    List<Object?> schemas,
    Object? instance,
    String path,
    _Scope scope,
  ) {
    final branches = <List<JsonSchemaViolation>>[];
    for (final sub in schemas) {
      final violations = <JsonSchemaViolation>[];
      evaluate(sub, instance, path, scope, violations);
      branches.add(violations);
    }
    return branches;
  }

  // When one branch alone accepts the value's type (as in `anyOf` of a
  // `$ref` and `{"type": "null"}`), its violations say more than "must
  // match one of the schemas".
  void _reportBranches(
    List<List<JsonSchemaViolation>> branches,
    String path,
    String keyword,
    String message,
    List<JsonSchemaViolation> out,
  ) {
    bool typeFits(List<JsonSchemaViolation> violations) => !violations.any(
      (v) =>
          v.path == path &&
          (v.keyword == 'type' ||
              v.keyword == 'false' ||
              v.keyword == 'enum' ||
              v.keyword == 'const'),
    );
    final candidates = branches.where(typeFits).toList();
    if (candidates.length == 1) {
      out.addAll(candidates.single);
    } else {
      out.add(JsonSchemaViolation(path, keyword, message));
    }
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  static String _child(String path, String name) =>
      '$path/${name.replaceAll('~', '~0').replaceAll('/', '~1')}';

  static int? _count(Object? value) => switch (value) {
    final int count => count,
    final double count when count == count.truncateToDouble() => count.toInt(),
    _ => null,
  };

  static String _n(int count, String noun) {
    if (count == 1) {
      return '1 $noun';
    }
    final plural = noun.endsWith('y')
        ? '${noun.substring(0, noun.length - 1)}ies'
        : '${noun}s';
    return '$count $plural';
  }

  static bool _isInteger(num value) =>
      value is int || (value.isFinite && value == value.truncateToDouble());

  static bool _isType(Object? value, String type) => switch (type) {
    'null' => value == null,
    'boolean' => value is bool,
    'string' => value is String,
    'number' => value is num,
    'integer' => value is num && _isInteger(value),
    'array' => value is List,
    'object' => value is Map,
    _ => false,
  };

  static String _typeOf(Object? value) => switch (value) {
    null => 'null',
    bool() => 'boolean',
    final num number => _isInteger(number) ? 'integer' : 'number',
    String() => 'string',
    List() => 'array',
    Map() => 'object',
    _ => value.runtimeType.toString(),
  };

  static String _article(String type) => switch (type) {
    'null' => 'null',
    'integer' || 'object' || 'array' => 'an $type',
    _ => 'a $type',
  };

  static String _words(Iterable<String> words) {
    final list = words.toList();
    if (list.length <= 1) {
      return list.join();
    }
    return '${list.sublist(0, list.length - 1).join(', ')} or ${list.last}';
  }

  static String _show(Object? value) =>
      value is String ? value : jsonEncode(value);

  // The first two equal items of [items], or `null` when all differ: the
  // pair that comparing every item with every later one finds first.
  //
  // One pass over a hash table of the items, so the time grows with the
  // size of the array and not with its square: the array is a request's,
  // and 20,000 items compared in pairs keep the isolate for a second.
  static (int, int)? _duplicate(List<Object?> items) {
    final seen = HashMap<Object?, int>(equals: _equal, hashCode: _hash);
    (int, int)? found;
    for (var j = 0; j < items.length; j++) {
      final i = seen.putIfAbsent(items[j], () => j);
      if (i != j && (found == null || i < found.$1)) {
        found = (i, j);
      }
    }
    return found;
  }

  // A hash that is the same for what [_equal] calls equal: 1 and 1.0, and
  // objects with their keys in any order.
  static int _hash(Object? value) => switch (value) {
    final List<Object?> items => Object.hashAll(items.map(_hash)),
    final Map<Object?, Object?> members => Object.hashAllUnordered(
      members.entries.map((e) => Object.hash(e.key, _hash(e.value))),
    ),
    _ => value.hashCode,
  };

  static bool _equal(Object? a, Object? b) {
    if (a is List<Object?> && b is List<Object?>) {
      if (a.length != b.length) {
        return false;
      }
      for (var i = 0; i < a.length; i++) {
        if (!_equal(a[i], b[i])) {
          return false;
        }
      }
      return true;
    }
    if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
    }
    if (a is bool || b is bool) {
      return identical(a, b);
    }
    return a == b;
  }
}

/// The `format` values [JsonSchema] checks, and how.
///
/// Spring (Java): Spring has no counterpart.
abstract final class JsonSchemaFormats {
  /// The formats that are checked; any other format is accepted as it is.
  static const checked = {
    'date-time',
    'date',
    'time',
    'email',
    'uri',
    'uri-reference',
    'uuid',
    'ipv4',
    'ipv6',
  };

  static final _date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final _time = RegExp(
    r'^(\d{2}):(\d{2}):(\d{2})(\.\d+)?([Zz]|[+-](\d{2}):(\d{2}))$',
  );
  static final _email = RegExp(r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)*$');
  static final _uuid = RegExp(
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );
  static final _ipv4 = RegExp(
    r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$',
  );

  /// Whether [value] is a valid [format]; `true` for a format that is not
  /// [checked].
  ///
  /// - `date-time`: RFC 3339, `2026-01-31T12:00:00.5+02:00` (`T`, an
  ///   offset or `Z`);
  /// - `date`: `2026-01-31`, a real calendar day;
  /// - `time`: `12:00:00Z`, with its offset;
  /// - `email`: a local part, `@` and a domain, no spaces (not every rule
  ///   of RFC 5321);
  /// - `uri`: a URI with a scheme; `uri-reference`: any URI, also relative;
  /// - `uuid`: 8-4-4-4-12 hexadecimal digits;
  /// - `ipv4`: four numbers from 0 to 255 without leading zeros;
  /// - `ipv6`: what `Uri.parseIPv6Address` accepts.
  static bool isValid(String format, String value) => switch (format) {
    'date-time' => _dateTime(value),
    'date' => _isDate(value),
    'time' => _isTime(value),
    'email' => _email.hasMatch(value),
    'uri' => !value.contains(' ') && (Uri.tryParse(value)?.hasScheme ?? false),
    'uri-reference' => !value.contains(' ') && Uri.tryParse(value) != null,
    'uuid' => _uuid.hasMatch(value),
    'ipv4' => _ipv4.hasMatch(value),
    'ipv6' => _isIpv6(value),
    _ => true,
  };

  static bool _dateTime(String value) {
    final t = value.indexOf(RegExp('[Tt]'));
    return t > 0 &&
        _isDate(value.substring(0, t)) &&
        _isTime(value.substring(t + 1));
  }

  static bool _isDate(String value) {
    final match = _date.firstMatch(value);
    if (match == null) {
      return false;
    }
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    if (month < 1 || month > 12 || day < 1) {
      return false;
    }
    final date = DateTime.utc(year, month, day);
    return date.month == month && date.day == day;
  }

  static bool _isTime(String value) {
    final match = _time.firstMatch(value);
    if (match == null) {
      return false;
    }
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    final second = int.parse(match[3]!);
    final offsetHour = match[6] == null ? 0 : int.parse(match[6]!);
    final offsetMinute = match[7] == null ? 0 : int.parse(match[7]!);
    return hour < 24 &&
        minute < 60 &&
        second <= 60 &&
        offsetHour < 24 &&
        offsetMinute < 60;
  }

  static bool _isIpv6(String value) {
    if (!value.contains(':') || value.contains('%')) {
      return false;
    }
    try {
      Uri.parseIPv6Address(value);
      return true;
    } on FormatException {
      return false;
    }
  }
}
