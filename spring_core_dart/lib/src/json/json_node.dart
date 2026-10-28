import 'dart:collection';
import 'dart:convert';

import 'package:spring_core_dart/src/json/json_exception.dart';

/// One value of a JSON document held as a tree: an object, array, string,
/// number, boolean or `null`, with typed accessors for navigating it.
///
/// Use it when JSON has no fixed shape worth a class: a webhook payload
/// where two fields matter, a document to patch before passing it on, or
/// a property whose content varies. `ObjectMapper.readTree` parses text
/// into one; a property or a value typed `JsonNode` (or a subtype) is read
/// as a tree too, and a node is written back as its JSON. Compared with
/// the plain maps and lists of `jsonDecode`, it adds safe paths
/// ([path], [at]) and conversions ([asInt], [stringValue], ...). Nodes are
/// equal when their JSON is.
///
/// ```dart
/// // Read a few fields of a document without a model class.
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

  /// Wraps decoded JSON [json] (what `jsonDecode` returns) in nodes; a
  /// [JsonNode] is returned as it is. Map keys become strings.
  ///
  /// Throws an [ArgumentError] for a value that is not decoded JSON, such
  /// as a `DateTime`; convert objects with `ObjectMapper.valueToTree`
  /// first.
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

  /// Returns this node as plain decoded JSON: `null`, a bool, number,
  /// string, list or map, as `jsonEncode` takes it ([MissingNode] gives
  /// `null`).
  Object? toJson();

  /// The property [nameOrIndex] of an object, or the element at index
  /// [nameOrIndex] of an array; `null` when there is none.
  JsonNode? get(Object nameOrIndex) => null;

  /// Like [get], but a [MissingNode] instead of `null`, so paths can be
  /// chained: `root.path('a').path('b')`.
  JsonNode path(Object nameOrIndex) => get(nameOrIndex) ?? MissingNode.instance;

  /// Returns the node at the JSON Pointer [pointer] (`/book/tags/0`;
  /// `~1` stands for `/`, `~0` for `~`), or a [MissingNode] when there is
  /// none. An empty pointer gives this node; one not starting with `/`
  /// throws an [ArgumentError].
  JsonNode at(String pointer) {
    if (pointer.isEmpty) {
      return this;
    }
    if (!pointer.startsWith('/')) {
      throw ArgumentError.value(pointer, 'pointer', 'must start with /');
    }
    var node = this;
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

  /// Whether [get] finds a node for [nameOrIndex].
  bool has(Object nameOrIndex) => get(nameOrIndex) != null;

  /// The number of properties of an object or elements of an array; 0
  /// for other nodes.
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

  /// The value as a string (Jackson 3): the text of a string, number or
  /// boolean, `''` for `null` and a missing node. An object or array gives
  /// [defaultValue], or throws a [JsonNodeException] without one; `null`
  /// and a missing node give [defaultValue] when there is one.
  String asString([String? defaultValue]) =>
      defaultValue ?? (throw _cannotCoerce('asString()', 'String'));

  /// The value as an int (Jackson 3): a finite number (truncated), a
  /// string of an integer (`"42"`), a boolean (1 / 0), 0 for `null` and a
  /// missing node. Anything else gives [defaultValue], or throws a
  /// [JsonNodeException] without one; `null` and a missing node give
  /// [defaultValue] when there is one.
  int asInt([int? defaultValue]) =>
      defaultValue ?? (throw _cannotCoerce('asInt()', 'int'));

  /// The value as a double, converted like [asInt] (a string may be any
  /// number, `"1.5"`).
  double asDouble([double? defaultValue]) =>
      defaultValue ?? (throw _cannotCoerce('asDouble()', 'double'));

  /// The value as a bool: a boolean, `"true"` / `"false"`, a number (not
  /// 0), `false` for `null` and a missing node; anything else gives
  /// [defaultValue], or throws a [JsonNodeException] without one.
  bool asBoolean([bool? defaultValue]) =>
      defaultValue ?? (throw _cannotCoerce('asBoolean()', 'boolean'));

  JsonNodeException _cannotCoerce(String method, String type) =>
      JsonNodeException(
        // Subclasses show their own name.
        // ignore: no_runtimetype_tostring
        '$method: $runtimeType value cannot be converted to '
        '$type',
      );

  /// Returns the text of a [StringNode]; throws a [JsonNodeException] for
  /// other nodes. Use [asString] to convert instead.
  String stringValue() => throw _wrong('a string');

  /// The value of a [NumericNode] as an int, when it is one exactly;
  /// throws a [JsonNodeException] for a fraction (`1.5`), NaN, infinity
  /// and other nodes.
  int intValue() => throw _wrong('a number');

  /// Returns the value of a [NumericNode] as a double; throws a
  /// [JsonNodeException] for other nodes.
  double doubleValue() => throw _wrong('a number');

  /// Returns the value of a [NumericNode]; throws a [JsonNodeException]
  /// for other nodes.
  num numberValue() => throw _wrong('a number');

  /// Returns the value of a [BooleanNode]; throws a [JsonNodeException]
  /// for other nodes.
  bool booleanValue() => throw _wrong('a boolean');

  JsonNodeException _wrong(String expected) =>
      // Subclasses show their own name.
      // ignore: no_runtimetype_tostring
      JsonNodeException('expected $expected node, got $runtimeType');

  /// The elements of an array or the property values of an object; empty
  /// for other nodes.
  Iterable<JsonNode> values() => const [];

  /// The property names of an object, in order; empty for other nodes.
  Iterable<String> propertyNames() => const [];

  /// The properties of an object as name/node entries, in order; empty
  /// for other nodes.
  Iterable<MapEntry<String, JsonNode>> properties() => const [];

  /// Returns a copy that shares no objects or arrays with this node, so
  /// it can be changed independently.
  JsonNode deepCopy() => JsonNode.from(_copy(toJson()));

  static Object? _copy(Object? json) => switch (json) {
    final List<Object?> list => [for (final item in list) _copy(item)],
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries) key: _copy(value),
    },
    _ => json,
  };

  /// This node as compact JSON text.
  @override
  String toString() => jsonEncode(toJson());

  /// This node as JSON text indented by two spaces, for people to read.
  String toPrettyString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  // A missing node equals only itself (its JSON is `null` too).
  @override
  bool operator ==(Object other) =>
      other is JsonNode &&
      other.isMissingNode == isMissingNode &&
      _deepEquals(toJson(), other.toJson());

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

/// A JSON object: named child nodes, kept in insertion order.
///
/// Besides reading, it is the node to build or change JSON with: [put],
/// [set], [remove] and the `put...` helpers change it in place and most
/// return it, so calls chain.
///
/// ```dart
/// // Build a request body by hand.
/// final body = ObjectNode()
///   ..put('query', 'dune')
///   ..putArray('tags').add('sf');
/// ```
final class ObjectNode extends JsonNode {
  /// An object with the properties [children]; empty by default.
  ObjectNode([Map<String, JsonNode>? children])
    : _children = LinkedHashMap.of(children ?? const {});

  final LinkedHashMap<String, JsonNode> _children;

  @override
  JsonNode? get(Object nameOrIndex) =>
      nameOrIndex is String ? _children[nameOrIndex] : null;

  /// Sets property [name] to [value], decoded JSON or a [JsonNode], and
  /// returns this object.
  ObjectNode put(String name, Object? value) {
    _children[name] = JsonNode.from(value);
    return this;
  }

  /// Sets property [name] to [node] and returns this object.
  ObjectNode set(String name, JsonNode node) {
    _children[name] = node;
    return this;
  }

  /// Sets property [name] to JSON `null` and returns this object.
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

  /// Removes property [name] and returns its node, or `null` when there
  /// was none.
  JsonNode? remove(String name) => _children.remove(name);

  /// Removes every property and returns this object.
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

/// A JSON array: an ordered list of child nodes, which can be changed in
/// place.
final class ArrayNode extends JsonNode {
  /// An array of [elements]; empty by default.
  ArrayNode([List<JsonNode>? elements]) : _elements = [...?elements];

  final List<JsonNode> _elements;

  @override
  JsonNode? get(Object nameOrIndex) =>
      nameOrIndex is int && nameOrIndex >= 0 && nameOrIndex < _elements.length
      ? _elements[nameOrIndex]
      : null;

  /// Appends [value], decoded JSON or a [JsonNode], and returns this
  /// array.
  ArrayNode add(Object? value) {
    _elements.add(JsonNode.from(value));
    return this;
  }

  /// Inserts [value] at [index] and returns this array.
  ArrayNode insert(int index, Object? value) {
    _elements.insert(index, JsonNode.from(value));
    return this;
  }

  /// Replaces the element at [index] with [value] and returns the old
  /// one.
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

  /// Removes the element at [index] and returns it.
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

/// A JSON string. [asInt], [asDouble] and [asBoolean] convert numeric and
/// `"true"` / `"false"` text.
final class StringNode extends JsonNode {
  /// The string [value].
  const StringNode(this.value);

  /// The string's text.
  final String value;

  @override
  bool get isString => true;

  @override
  String stringValue() => value;

  @override
  String asString([String? defaultValue]) => value;

  // Like Jackson's NumberInput.looksLikeValidNumber: no blanks, hex, `NaN`.
  static final _integer = RegExp(r'^[+-]?\d+$');
  static final _number = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');

  @override
  int asInt([int? defaultValue]) =>
      (_integer.hasMatch(value) ? int.tryParse(value) : null) ??
      super.asInt(defaultValue);

  @override
  double asDouble([double? defaultValue]) =>
      (_number.hasMatch(value) ? double.tryParse(value) : null) ??
      super.asDouble(defaultValue);

  @override
  bool asBoolean([bool? defaultValue]) => switch (value) {
    'true' => true,
    'false' => false,
    _ => super.asBoolean(defaultValue),
  };

  @override
  String toJson() => value;
}

/// A JSON number: an `int` when the JSON had no fraction, else a
/// `double`.
final class NumericNode extends JsonNode {
  /// The number [value].
  const NumericNode(this.value);

  /// The number, as decoded.
  final num value;

  @override
  bool get isNumber => true;

  @override
  bool get isIntegralNumber => value is int;

  @override
  num numberValue() => value;

  @override
  int intValue() {
    final value = this.value;
    if (value is int) {
      return value;
    }
    if (!value.isFinite) {
      throw JsonNodeException('intValue(): $value cannot be converted to int');
    }
    if (value != value.truncateToDouble()) {
      throw JsonNodeException(
        'intValue(): $value has a fractional part, it cannot be converted to '
        'int exactly',
      );
    }
    return value.toInt();
  }

  @override
  double doubleValue() => value.toDouble();

  @override
  String asString([String? defaultValue]) => '$value';

  @override
  int asInt([int? defaultValue]) =>
      value.isFinite ? value.truncate() : super.asInt(defaultValue);

  @override
  double asDouble([double? defaultValue]) => value.toDouble();

  @override
  bool asBoolean([bool? defaultValue]) => value != 0;

  @override
  num toJson() => value;
}

/// A JSON `true` or `false`.
final class BooleanNode extends JsonNode {
  /// The boolean [value].
  const BooleanNode(this.value);

  /// The boolean.
  final bool value;

  @override
  bool get isBoolean => true;

  @override
  bool booleanValue() => value;

  @override
  String asString([String? defaultValue]) => '$value';

  @override
  int asInt([int? defaultValue]) => value ? 1 : 0;

  @override
  double asDouble([double? defaultValue]) => value ? 1 : 0;

  @override
  bool asBoolean([bool? defaultValue]) => value;

  @override
  bool toJson() => value;
}

/// A JSON `null` value, which is present (unlike a [MissingNode]).
final class NullNode extends JsonNode {
  const NullNode._();

  /// The one JSON `null` node.
  static const instance = NullNode._();

  @override
  bool get isNull => true;

  @override
  String asString([String? defaultValue]) => defaultValue ?? '';

  @override
  int asInt([int? defaultValue]) => defaultValue ?? 0;

  @override
  double asDouble([double? defaultValue]) => defaultValue ?? 0;

  @override
  bool asBoolean([bool? defaultValue]) => defaultValue ?? false;

  @override
  Object? toJson() => null;
}

/// The stand-in that [JsonNode.path] and [JsonNode.at] return where the
/// document has no node, so navigation can go on without `null` checks.
///
/// Its `as...` accessors return their default (`0`, `''`, `false`, or
/// the one given), so `root.path('a').path('b').asInt(10)` reads a value
/// or falls back. It differs from a [NullNode]: the property is absent,
/// not `null`, and it equals only itself.
final class MissingNode extends JsonNode {
  const MissingNode._();

  /// The one missing node.
  static const instance = MissingNode._();

  @override
  bool get isMissingNode => true;

  @override
  String asString([String? defaultValue]) => defaultValue ?? '';

  @override
  int asInt([int? defaultValue]) => defaultValue ?? 0;

  @override
  double asDouble([double? defaultValue]) => defaultValue ?? 0;

  @override
  bool asBoolean([bool? defaultValue]) => defaultValue ?? false;

  @override
  Object? toJson() => null;

  @override
  String toString() => '';
}

/// The error a [JsonNode] accessor throws when the node has the wrong
/// kind, such as `stringValue()` on a number, or cannot be converted.
///
/// It is a [JsonMappingException], so code that handles mapping errors
/// handles it too. Avoid it with the `as...` accessors and a default.
class JsonNodeException extends JsonMappingException {
  /// An error described by [message].
  JsonNodeException(super.message);
}
