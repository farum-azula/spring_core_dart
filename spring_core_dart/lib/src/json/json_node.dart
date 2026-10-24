import 'dart:collection';
import 'dart:convert';

import 'package:spring_core_dart/src/json/json_exception.dart';

/// A node of a JSON tree, like Jackson 3's `JsonNode`: what
/// `ObjectMapper.readTree` returns, to navigate JSON without a class.
///
/// ```dart
/// final root = mapper.readTree('{"book": {"title": "Dune", "tags": ["sf"]}}');
/// root.get('book')?.get('title')?.asString();   // Dune
/// root.path('book').path('price').asInt(10);    // 10 (missing → default)
/// root.at('/book/tags/0').stringValue();        // sf
/// (root as ObjectNode).put('read', true);
/// mapper.treeToValue<Shelf>(root);              // into a class
/// ```
///
/// Spring (Java):
/// ```java
/// JsonNode root = mapper.readTree(json);
/// root.get("book").get("title").asString();
/// root.at("/book/tags/0").stringValue();
/// ```
sealed class JsonNode {
  const JsonNode();

  /// The node of decoded JSON [json] (what `jsonDecode` returns); a
  /// [JsonNode] is returned as it is.
  factory JsonNode.from(Object? json) => switch (json) {
    null => NullNode.instance,
    final JsonNode node => node,
    final bool value => BooleanNode(value),
    final num value => NumericNode(value),
    final String value => StringNode(value),
    final Iterable<Object?> items => ArrayNode([
      for (final item in items) JsonNode.from(item),
    ]),
    final Map<Object?, Object?> map => ObjectNode({
      for (final MapEntry(:key, :value) in map.entries)
        '$key': JsonNode.from(value),
    }),
    _ => throw ArgumentError.value(json, 'json', 'not decoded JSON'),
  };

  /// The decoded JSON of this node: `null`, a bool, number, string, list or
  /// map ([MissingNode] gives `null`).
  Object? toJson();

  /// The property [nameOrIndex] of an object, or the element at index
  /// [nameOrIndex] of an array; `null` when there is none.
  JsonNode? get(Object nameOrIndex) => null;

  /// Like [get], but a [MissingNode] instead of `null`, so paths can be
  /// chained: `root.path('a').path('b')`.
  JsonNode path(Object nameOrIndex) => get(nameOrIndex) ?? MissingNode.instance;

  /// The node at the JSON Pointer [pointer] (`/book/tags/0`; `~1` is `/`,
  /// `~0` is `~`); a [MissingNode] when there is none.
  JsonNode at(String pointer) {
    if (pointer.isEmpty) {
      return this;
    }
    if (!pointer.startsWith('/')) {
      throw ArgumentError.value(pointer, 'pointer', 'must start with /');
    }
    JsonNode node = this;
    for (final raw in pointer.substring(1).split('/')) {
      final segment = raw.replaceAll('~1', '/').replaceAll('~0', '~');
      node =
          switch (node) {
            ArrayNode() => node.get(int.tryParse(segment) ?? -1),
            _ => node.get(segment),
          } ??
          MissingNode.instance;
      if (node is MissingNode) {
        break;
      }
    }
    return node;
  }

  /// Whether [get] finds a node.
  bool has(Object nameOrIndex) => get(nameOrIndex) != null;

  /// The number of properties or elements (0 for other nodes).
  int get size => 0;

  /// Whether the object or array has no children (`true` for other nodes).
  bool get isEmpty => size == 0;

  /// Whether this is an [ObjectNode].
  bool get isObject => false;

  /// Whether this is an [ArrayNode].
  bool get isArray => false;

  /// Whether this is an object or an array.
  bool get isContainer => isObject || isArray;

  /// Whether this is a [StringNode].
  bool get isString => false;

  /// Whether this is a [NumericNode].
  bool get isNumber => false;

  /// Whether this is a number without a fraction.
  bool get isIntegralNumber => false;

  /// Whether this is a [BooleanNode].
  bool get isBoolean => false;

  /// Whether this is the [NullNode].
  bool get isNull => false;

  /// Whether this is the [MissingNode].
  bool get isMissingNode => false;

  /// Whether this is a string, number, boolean or `null`.
  bool get isValueNode => !isContainer && !isMissingNode;

  /// The value as a string: the text of a string, number or boolean;
  /// [defaultValue] for others.
  String asString([String defaultValue = '']) => defaultValue;

  /// The value as an int: a number (truncated), a numeric string or a
  /// boolean (1 / 0); [defaultValue] otherwise.
  int asInt([int defaultValue = 0]) => defaultValue;

  /// The value as a double, converted like [asInt].
  double asDouble([double defaultValue = 0]) => defaultValue;

  /// The value as a bool: a boolean, `"true"` / `"false"` or a number (not
  /// 0); [defaultValue] otherwise.
  bool asBoolean([bool defaultValue = false]) => defaultValue;

  /// The text of a [StringNode]; throws a [JsonNodeException] for others.
  String stringValue() => throw _wrong('a string');

  /// The value of a [NumericNode] as an int; throws a [JsonNodeException]
  /// for others.
  int intValue() => throw _wrong('a number');

  /// The value of a [NumericNode] as a double; throws for others.
  double doubleValue() => throw _wrong('a number');

  /// The value of a [NumericNode]; throws for others.
  num numberValue() => throw _wrong('a number');

  /// The value of a [BooleanNode]; throws for others.
  bool booleanValue() => throw _wrong('a boolean');

  JsonNodeException _wrong(String expected) => JsonNodeException(
    'expected $expected node, got ${runtimeType.toString()}',
  );

  /// The elements of an array or the property values of an object.
  Iterable<JsonNode> values() => const [];

  /// The property names of an object.
  Iterable<String> propertyNames() => const [];

  /// The properties of an object.
  Iterable<MapEntry<String, JsonNode>> properties() => const [];

  /// A copy that shares no containers with this node.
  JsonNode deepCopy() => JsonNode.from(_copy(toJson()));

  static Object? _copy(Object? json) => switch (json) {
    final List<Object?> list => [for (final item in list) _copy(item)],
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries) key: _copy(value),
    },
    _ => json,
  };

  /// Compact JSON.
  @override
  String toString() => jsonEncode(toJson());

  /// Indented JSON.
  String toPrettyString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  @override
  bool operator ==(Object other) =>
      other is JsonNode && _deepEquals(toJson(), other.toJson());

  // Consistent with ==: object properties in any order hash alike, and
  // numbers equal by value (`1` and `1.0`) hash alike.
  @override
  int get hashCode => _deepHash(toJson());

  static int _deepHash(Object? value) => switch (value) {
    final List<Object?> list => Object.hashAll(list.map(_deepHash)),
    final Map<Object?, Object?> map => Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in map.entries)
        Object.hash(key, _deepHash(value)),
    ]),
    _ => value.hashCode,
  };

  static bool _deepEquals(Object? a, Object? b) {
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
    if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _deepEquals(a[k], b[k]));
    }
    return a == b;
  }
}

/// A JSON object: properties in insertion order.
final class ObjectNode extends JsonNode {
  /// An object with [children] (empty by default).
  ObjectNode([Map<String, JsonNode>? children])
    : _children = LinkedHashMap.of(children ?? const {});

  final LinkedHashMap<String, JsonNode> _children;

  @override
  JsonNode? get(Object nameOrIndex) =>
      nameOrIndex is String ? _children[nameOrIndex] : null;

  /// Sets property [name] to [value] (decoded JSON or a [JsonNode]).
  ObjectNode put(String name, Object? value) {
    _children[name] = JsonNode.from(value);
    return this;
  }

  /// Sets property [name] to [node].
  ObjectNode set(String name, JsonNode node) {
    _children[name] = node;
    return this;
  }

  /// Sets property [name] to `null`.
  ObjectNode putNull(String name) => set(name, NullNode.instance);

  /// Adds an empty object under [name] and returns it.
  ObjectNode putObject(String name) {
    final child = ObjectNode();
    _children[name] = child;
    return child;
  }

  /// Adds an empty array under [name] and returns it.
  ArrayNode putArray(String name) {
    final child = ArrayNode();
    _children[name] = child;
    return child;
  }

  /// Removes property [name]; returns its node.
  JsonNode? remove(String name) => _children.remove(name);

  /// Removes every property.
  ObjectNode removeAll() {
    _children.clear();
    return this;
  }

  @override
  int get size => _children.length;

  @override
  bool get isObject => true;

  @override
  Iterable<JsonNode> values() => _children.values;

  @override
  Iterable<String> propertyNames() => _children.keys;

  @override
  Iterable<MapEntry<String, JsonNode>> properties() => _children.entries;

  @override
  Map<String, Object?> toJson() => {
    for (final MapEntry(:key, :value) in _children.entries) key: value.toJson(),
  };
}

/// A JSON array.
final class ArrayNode extends JsonNode {
  /// An array of [elements] (empty by default).
  ArrayNode([List<JsonNode>? elements]) : _elements = [...?elements];

  final List<JsonNode> _elements;

  @override
  JsonNode? get(Object nameOrIndex) =>
      nameOrIndex is int && nameOrIndex >= 0 && nameOrIndex < _elements.length
      ? _elements[nameOrIndex]
      : null;

  /// Appends [value] (decoded JSON or a [JsonNode]).
  ArrayNode add(Object? value) {
    _elements.add(JsonNode.from(value));
    return this;
  }

  /// Inserts [value] at [index].
  ArrayNode insert(int index, Object? value) {
    _elements.insert(index, JsonNode.from(value));
    return this;
  }

  /// Replaces the element at [index]; returns the old one.
  JsonNode set(int index, Object? value) {
    final old = _elements[index];
    _elements[index] = JsonNode.from(value);
    return old;
  }

  /// Appends an empty object and returns it.
  ObjectNode addObject() {
    final child = ObjectNode();
    _elements.add(child);
    return child;
  }

  /// Appends an empty array and returns it.
  ArrayNode addArray() {
    final child = ArrayNode();
    _elements.add(child);
    return child;
  }

  /// Removes the element at [index]; returns it.
  JsonNode remove(int index) => _elements.removeAt(index);

  @override
  int get size => _elements.length;

  @override
  bool get isArray => true;

  @override
  Iterable<JsonNode> values() => _elements;

  @override
  List<Object?> toJson() => [for (final element in _elements) element.toJson()];
}

/// A JSON string (Jackson 3's `StringNode`).
final class StringNode extends JsonNode {
  /// The string [value].
  const StringNode(this.value);

  /// The text.
  final String value;

  @override
  bool get isString => true;

  @override
  String stringValue() => value;

  @override
  String asString([String defaultValue = '']) => value;

  @override
  int asInt([int defaultValue = 0]) =>
      int.tryParse(value.trim()) ??
      double.tryParse(value.trim())?.truncate() ??
      defaultValue;

  @override
  double asDouble([double defaultValue = 0]) =>
      double.tryParse(value.trim()) ?? defaultValue;

  @override
  bool asBoolean([bool defaultValue = false]) =>
      switch (value.trim().toLowerCase()) {
        'true' => true,
        'false' => false,
        _ => defaultValue,
      };

  @override
  String toJson() => value;
}

/// A JSON number.
final class NumericNode extends JsonNode {
  /// The number [value].
  const NumericNode(this.value);

  /// The number.
  final num value;

  @override
  bool get isNumber => true;

  @override
  bool get isIntegralNumber => value is int;

  @override
  num numberValue() => value;

  @override
  int intValue() => value.truncate();

  @override
  double doubleValue() => value.toDouble();

  @override
  String asString([String defaultValue = '']) => '$value';

  @override
  int asInt([int defaultValue = 0]) => value.truncate();

  @override
  double asDouble([double defaultValue = 0]) => value.toDouble();

  @override
  bool asBoolean([bool defaultValue = false]) => value != 0;

  @override
  num toJson() => value;
}

/// `true` or `false`.
final class BooleanNode extends JsonNode {
  /// The boolean [value].
  const BooleanNode(this.value);

  /// The value.
  final bool value;

  @override
  bool get isBoolean => true;

  @override
  bool booleanValue() => value;

  @override
  String asString([String defaultValue = '']) => '$value';

  @override
  int asInt([int defaultValue = 0]) => value ? 1 : 0;

  @override
  double asDouble([double defaultValue = 0]) => value ? 1 : 0;

  @override
  bool asBoolean([bool defaultValue = false]) => value;

  @override
  bool toJson() => value;
}

/// JSON `null`.
final class NullNode extends JsonNode {
  const NullNode._();

  /// The only instance.
  static const instance = NullNode._();

  @override
  bool get isNull => true;

  @override
  String asString([String defaultValue = '']) => 'null';

  @override
  Object? toJson() => null;
}

/// What [JsonNode.path] and [JsonNode.at] return when there is no node.
final class MissingNode extends JsonNode {
  const MissingNode._();

  /// The only instance.
  static const instance = MissingNode._();

  @override
  bool get isMissingNode => true;

  @override
  Object? toJson() => null;

  @override
  String toString() => '';
}

/// A [JsonNode] accessor called on the wrong kind of node (Jackson 3's
/// `JsonNodeException`), e.g. `stringValue()` on a number.
class JsonNodeException extends JsonMappingException {
  /// The failure [message].
  JsonNodeException(super.message);
}
