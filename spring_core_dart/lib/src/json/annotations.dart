/// The JSON name of a property or constructor parameter, like Jackson's
/// `@JsonProperty`. Wins over the naming strategy.
///
/// ```dart
/// @Introspected()
/// class Book {
///   const Book(this.isbn, this.publishedAt);
///   final String isbn;
///   @JsonProperty('published_at')
///   final DateTime publishedAt;
/// }
/// // {"isbn": "978-0", "published_at": "2026-01-01T00:00:00.000"}
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonProperty("published_at") Instant publishedAt;
/// ```
class JsonProperty {
  /// The property is called [name] in JSON.
  const JsonProperty(this.name);

  /// The JSON name.
  final String name;
}

/// Leaves a property out of JSON in both directions, like Jackson's
/// `@JsonIgnore`.
///
/// ```dart
/// @JsonIgnore()
/// String? passwordHash;
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonIgnore String passwordHash;
/// ```
class JsonIgnore {
  /// Marks the property.
  const JsonIgnore();
}

/// When a property is written, like Jackson's `@JsonInclude`; on a class it
/// applies to all its properties. Wins over
/// `spring.jackson.default-property-inclusion`.
///
/// ```dart
/// @JsonInclude(JsonInclusion.nonNull)
/// class Patch { String? title; String? note; }
/// // Patch()..title = 'x'  →  {"title": "x"}
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonInclude(JsonInclude.Include.NON_NULL)
/// class Patch { ... }
/// ```
class JsonInclude {
  /// Writes properties as [value] says.
  const JsonInclude(this.value);

  /// The rule.
  final JsonInclusion value;
}

/// Which property values are written (Jackson's `JsonInclude.Include`).
enum JsonInclusion {
  /// Every property, `null` included (`ALWAYS`).
  always,

  /// Properties that are not `null` (`NON_NULL`).
  nonNull,

  /// Properties that are not `null`, an empty string, list, set or map
  /// (`NON_EMPTY`).
  nonEmpty,
}

/// Class-level: the order in which properties are written, like Jackson's
/// `@JsonPropertyOrder`. The listed JSON names (or Dart names) come first,
/// in that order; the others follow in the mapper's order (sorted
/// alphabetically unless `ObjectMapper.sortPropertiesAlphabetically` is
/// off). [JsonPropertyOrder.alphabetic] sorts the unlisted ones
/// alphabetically even when the mapper does not (Jackson's `alphabetic =
/// true`).
///
/// ```dart
/// @Introspected()
/// @JsonPropertyOrder(['id', 'title'])
/// class Book { ... } // {"id":..., "title":..., then the rest}
///
/// @Introspected()
/// @JsonPropertyOrder.alphabetic()
/// class Tag { ... } // sorted, whatever the mapper says
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonPropertyOrder({"id", "title"})
/// class Book { ... }
///
/// @JsonPropertyOrder(alphabetic = true)
/// class Tag { ... }
/// ```
class JsonPropertyOrder {
  /// Writes [value] first.
  const JsonPropertyOrder(this.value) : alphabetic = false;

  /// Sorts the properties alphabetically, after the names in [value] (none
  /// by default).
  const JsonPropertyOrder.alphabetic({this.value = const []})
    : alphabetic = true;

  /// JSON property names written first, in this order.
  final List<String> value;

  /// Whether the properties that are not listed are sorted alphabetically.
  final bool alphabetic;
}

/// Class-level: JSON properties to ignore, and whether unknown properties
/// are fine while reading, like Jackson's `@JsonIgnoreProperties`.
///
/// ```dart
/// @Introspected()
/// @JsonIgnoreProperties(ignoreUnknown: true)
/// class Book { ... } // extra fields of the server are skipped
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonIgnoreProperties(ignoreUnknown = true)
/// class Book { ... }
/// ```
class JsonIgnoreProperties {
  /// Ignores the JSON properties [value]; [ignoreUnknown] accepts unknown
  /// ones even when `failOnUnknownProperties` is on.
  const JsonIgnoreProperties({
    this.value = const [],
    this.ignoreUnknown = false,
  });

  /// JSON property names to ignore in both directions.
  final List<String> value;

  /// Whether unknown properties are skipped while reading.
  final bool ignoreUnknown;
}

/// Marks the constructor (or factory) to create instances from JSON, like
/// Jackson's `@JsonCreator`. Without it the unnamed constructor is used.
///
/// ```dart
/// @Introspected()
/// class Money {
///   Money(this.cents);
///   @JsonCreator()
///   Money.of({required int amount, required String currency}) : ...;
///   ...
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonCreator
/// Money(@JsonProperty("amount") int amount, @JsonProperty("currency") String currency) { ... }
/// ```
class JsonCreator {
  /// Marks the constructor.
  const JsonCreator();
}

/// On a field of an enum: the field's value is the JSON form of each enum
/// value (default: the value's name), like Jackson's `@JsonValue`.
///
/// ```dart
/// enum Stock {
///   inStock('in_stock'),
///   soldOut('sold_out');
///
///   const Stock(this.json);
///   @JsonValue()
///   final String json;
/// }
/// // Stock.inStock  ↔  "in_stock"
/// ```
///
/// Spring (Java):
/// ```java
/// enum Stock {
///   IN_STOCK("in_stock");
///   @JsonValue final String json;
/// }
/// ```
class JsonValue {
  /// Marks the field.
  const JsonValue();
}
