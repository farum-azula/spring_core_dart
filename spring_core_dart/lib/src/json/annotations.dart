import 'package:spring_core_dart/src/json/naming.dart';

/// The JSON name of a property, constructor parameter or enum constant,
/// like Jackson's `@JsonProperty`. Wins over the naming strategy.
///
/// [access] limits the property to one direction: [JsonPropertyAccess.readOnly]
/// is written but ignored when read, [JsonPropertyAccess.writeOnly] is read
/// but not written.
///
/// Jackson's `required` is the Dart parameter: a constructor parameter
/// that is neither nullable nor has a default value must be in the JSON; a
/// nullable one may be missing (`null`).
///
/// ```dart
/// @Introspected()
/// class Book {
///   const Book(this.isbn, this.publishedAt, {this.password});
///   final String isbn; // required: not nullable, no default
///   @JsonProperty('published_at')
///   final DateTime publishedAt;
///   @JsonProperty('', access: JsonPropertyAccess.writeOnly)
///   final String? password;
/// }
/// // {"isbn": "978-0", "published_at": "2026-01-01T00:00:00.000"}
///
/// enum Color {
///   @JsonProperty('RED')
///   red,
///   green, // "green"
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonProperty(required = true) String isbn;  // Dart: String isbn
/// @JsonProperty("published_at") Instant publishedAt;
/// @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String password;
/// enum Color { @JsonProperty("RED") RED, GREEN }
/// ```
class JsonProperty {
  /// The property is called [name] in JSON (`''`: its own name, after
  /// the naming strategy, e.g. `@JsonProperty('', access: ...)`).
  const JsonProperty(this.name, {this.access = JsonPropertyAccess.auto});

  /// The JSON name; empty for the default one.
  final String name;

  /// In which directions the property is used.
  final JsonPropertyAccess access;
}

/// The directions a property is used in (Jackson's
/// `JsonProperty.Access`).
enum JsonPropertyAccess {
  /// Both, as far as the property can be read and set (`AUTO`).
  auto,

  /// Only written to JSON; a value in the JSON is ignored (`READ_ONLY`:
  /// the property is only read from the object).
  readOnly,

  /// Only read from JSON, never written (`WRITE_ONLY`: the property is only
  /// set on the object).
  writeOnly,

  /// Both (`READ_WRITE`); like [auto], as Dart has no visibility levels
  /// between public and private.
  readWrite,
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

  /// Properties that are not `null` (`NON_ABSENT`; Dart has no `Optional`,
  /// so it is [nonNull]).
  nonAbsent,

  /// Properties that are not `null`, an empty string, list, set or map
  /// (`NON_EMPTY`).
  nonEmpty,

  /// Properties that do not have their default value (`NON_DEFAULT`): on a
  /// class (`@JsonInclude(JsonInclusion.nonDefault)` on the class) the
  /// values of an instance created with the no-argument constructor;
  /// elsewhere, or when the class has none, the defaults of the type —
  /// `null`, `0`, `false` and what [nonEmpty] leaves out.
  nonDefault,
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
/// Money(
///     @JsonProperty("amount") int amount,
///     @JsonProperty("currency") String currency) { ... }
/// ```
class JsonCreator {
  /// Marks the constructor.
  const JsonCreator();
}

/// The value an object is written as, like Jackson's `@JsonValue`: on a
/// field or getter of an enum, the JSON form of each enum value (default:
/// the value's name); on a property (field or getter) or a method without
/// parameters of an `@Introspected` class, the whole object is written as
/// that value and read back through a constructor with one parameter
/// (Jackson's delegating creator) or its `fromJson`. One per class.
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
///
/// @Introspected()
/// class Isbn {
///   const Isbn(this.value);
///   @JsonValue()
///   final String value;
/// }
/// // Isbn('978-0')  ↔  "978-0"
/// ```
///
/// Spring (Java):
/// ```java
/// enum Stock {
///   IN_STOCK("in_stock");
///   @JsonValue final String json;
/// }
/// record Isbn(@JsonValue String value) {}
/// ```
class JsonValue {
  /// Marks the field, getter or method.
  const JsonValue();
}

/// More JSON names a property (or constructor parameter) is read from,
/// like Jackson's `@JsonAlias`. It is still written with its own name.
///
/// ```dart
/// @JsonAlias(['fullName', 'n'])
/// final String name; // reads "name", "fullName" or "n"
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonAlias({"fullName", "n"}) String name;
/// ```
class JsonAlias {
  /// Reads the property from the JSON names [value] too.
  const JsonAlias(this.value);

  /// The other JSON names.
  final List<String> value;
}

/// How a value is written and read, like Jackson's `@JsonFormat`: on a
/// `DateTime` a [pattern] (the letters of Java's `DateTimeFormatter`:
/// `y M d H h m s S a E X x Z` and `'quoted'` text) and a [timezone]; a
/// [shape] for dates, durations, enums, numbers and booleans;
/// [JsonFormatShape.array] on a class writes its objects as arrays of
/// property values. On a list, set or map property it applies to the
/// elements (values).
///
/// ```dart
/// @JsonFormat(pattern: 'dd.MM.yyyy', timezone: '+01:00')
/// final DateTime due;          // "24.12.2026"
/// @JsonFormat(shape: JsonFormatShape.number)
/// final Genre genre;           // 0 (the index)
/// @JsonFormat(shape: JsonFormatShape.string)
/// final int count;             // "42"
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonFormat(pattern = "dd.MM.yyyy", timezone = "GMT+1") OffsetDateTime due;
/// @JsonFormat(shape = JsonFormat.Shape.NUMBER) Genre genre;
/// ```
class JsonFormat {
  /// The format; every part is optional.
  const JsonFormat({
    this.shape = JsonFormatShape.any,
    this.pattern = '',
    this.timezone = '',
  });

  /// The JSON shape.
  final JsonFormatShape shape;

  /// The date pattern (empty: ISO-8601).
  final String pattern;

  /// The offset dates are written in and read in when the text has none:
  /// `UTC`, `Z` or a fixed offset such as `+02:00` (empty: the mapper's).
  final String timezone;
}

/// The JSON shape of [JsonFormat] (Jackson's `JsonFormat.Shape`).
enum JsonFormatShape {
  /// The type's default (`ANY` / `NATURAL`).
  any,

  /// A string: numbers and booleans as text, dates as ISO-8601 (or the
  /// pattern) even when timestamps are on, enums by name.
  string,

  /// A number: dates and durations as timestamps, enums by index.
  number,

  /// On a class: an object is written as the array of its property values,
  /// in property order, and read back from one.
  array,
}

/// Marks a `Map<String, ...>` property (or a method returning one) whose
/// entries are written as properties of the object, like Jackson's
/// `@JsonAnyGetter`. They come after the other properties.
///
/// ```dart
/// @JsonAnyGetter()
/// @JsonAnySetter()
/// final Map<String, Object?> extra = {};
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonAnyGetter @JsonAnySetter Map<String, Object> extra = new HashMap<>();
/// ```
class JsonAnyGetter {
  /// Marks the property or method.
  const JsonAnyGetter();
}

/// Marks a `Map<String, ...>` property (or a method `(String name, value)`)
/// that receives the JSON properties the class does not have, like
/// Jackson's `@JsonAnySetter`; unknown properties then never fail. A map
/// property that is a constructor parameter receives them as its argument;
/// otherwise its map is filled (or created when it is `null`). Values are
/// read as the map's value type.
///
/// ```dart
/// @JsonAnySetter()
/// void set(String name, Object? value) => extra[name] = value;
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonAnySetter
/// void set(String name, Object value) { extra.put(name, value); }
/// ```
class JsonAnySetter {
  /// Marks the property or method.
  const JsonAnySetter();
}

/// Writes the properties of an object-valued property inline, in the
/// enclosing object, like Jackson's `@JsonUnwrapped`; [prefix] and
/// [suffix] are added to their names. Reading collects them back.
///
/// ```dart
/// @JsonUnwrapped(prefix: 'home_')
/// final Address address; // {"name": "Ann", "home_city": "Lyon"}
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonUnwrapped(prefix = "home_") Address address;
/// ```
class JsonUnwrapped {
  /// Unwraps the property; [enabled] `false` turns it off.
  const JsonUnwrapped({
    this.prefix = '',
    this.suffix = '',
    this.enabled = true,
  });

  /// Added before each property name.
  final String prefix;

  /// Added after each property name.
  final String suffix;

  /// Whether the property is unwrapped.
  final bool enabled;
}

/// Class-level: the naming strategy of this class's properties, like
/// Jackson's `@JsonNaming`; wins over the mapper's.
///
/// ```dart
/// @Introspected()
/// @JsonNaming(PropertyNamingStrategy.snakeCase)
/// class Row { ... } // publishedAt → published_at
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
/// class Row { ... }
/// ```
class JsonNaming {
  /// Names the properties with [value].
  const JsonNaming(this.value);

  /// The strategy.
  final PropertyNamingStrategy value;
}

/// The views a property belongs to, like Jackson's `@JsonView`; on a class,
/// the default of its properties. `mapper.writerWithView(Public)` writes
/// (and `readerWithView` reads) only the properties of that view or of a
/// view it extends, and those without a view only when
/// `defaultViewInclusion` is on (off by default, like Jackson 3 and Spring
/// Boot). Views extending other views are recognised through the
/// introspector: the view classes named in `@JsonView` are introspected.
///
/// ```dart
/// class Public {}
/// class Internal extends Public {}
///
/// @JsonView([Public]) final String name;
/// @JsonView([Internal]) final String email;
///
/// mapper.writerWithView(Public).writeValueAsString(user); // {"name": ...}
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonView(Views.Public.class) String name;
/// mapper.writerWithView(Views.Public.class).writeValueAsString(user);
/// ```
class JsonView {
  /// The property belongs to the views [value].
  const JsonView(this.value);

  /// The view classes.
  final List<Type> value;
}

/// Class-level: objects of this class and its subclasses carry a type id,
/// so a value of the base type is read back as the right subclass, like
/// Jackson's `@JsonTypeInfo`. The ids come from `@JsonSubTypes` (or
/// `@JsonTypeName`, else the simple class name); only the subtypes listed
/// by `@JsonSubTypes` (also those of the listed classes) are read.
///
/// ```dart
/// @Introspected()
/// @JsonTypeInfo(property: 'kind')
/// @JsonSubTypes([
///   JsonSubType(Dog, name: 'dog'),
///   JsonSubType(Cat, name: 'cat'),
/// ])
/// abstract class Animal { ... }
/// // Dog(...)  ↔  {"kind": "dog", "name": "Rex"}
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "kind")
/// @JsonSubTypes({@JsonSubTypes.Type(value = Dog.class, name = "dog"), ...})
/// abstract class Animal { ... }
/// ```
class JsonTypeInfo {
  /// Type ids by [use], included as [include]; [property] is the id's
  /// property name (default `@type`); [defaultImpl] is read when the id is
  /// missing or unknown; [visible] also passes the id property on to the
  /// class.
  const JsonTypeInfo({
    this.use = JsonTypeId.name,
    this.include = JsonTypeInclusion.property,
    this.property = '',
    this.defaultImpl,
    this.visible = false,
  });

  /// What the type id is.
  final JsonTypeId use;

  /// Where the type id goes.
  final JsonTypeInclusion include;

  /// The type id's property name; empty for `@type`.
  final String property;

  /// The class read when the JSON has no type id or an unknown one.
  final Type? defaultImpl;

  /// Whether the type id property is also read into the class.
  final bool visible;
}

/// What a type id is (Jackson's `JsonTypeInfo.Id`).
enum JsonTypeId {
  /// A logical name: `@JsonSubTypes` / `@JsonTypeName`, else the simple
  /// class name (`NAME`).
  name,

  /// The same as [name]: Dart has no nested classes (`SIMPLE_NAME`).
  simpleName,

  /// No type id: the subtype is the one whose properties include all those
  /// present (`DEDUCTION`).
  deduction,
}

/// Where a type id is written (Jackson's `JsonTypeInfo.As`).
enum JsonTypeInclusion {
  /// A property of the object, written first (`PROPERTY`).
  property,

  /// A property the class has itself; not added when writing
  /// (`EXISTING_PROPERTY`).
  existingProperty,

  /// An object wrapping the value: `{"dog": {...}}` (`WRAPPER_OBJECT`).
  wrapperObject,

  /// An array: `["dog", {...}]` (`WRAPPER_ARRAY`).
  wrapperArray,
}

/// Class-level: the subclasses of a `@JsonTypeInfo` class and their type
/// ids, like Jackson's `@JsonSubTypes`. The listed classes are introspected.
class JsonSubTypes {
  /// The subtypes [value].
  const JsonSubTypes(this.value);

  /// The subtypes.
  final List<JsonSubType> value;
}

/// A subtype of [JsonSubTypes] (Jackson's `@JsonSubTypes.Type`): the class
/// [value] with type id [name] (empty: its `@JsonTypeName` or class name)
/// and more ids [names] it is read from.
class JsonSubType {
  /// Subtype [value] with id [name].
  const JsonSubType(this.value, {this.name = '', this.names = const []});

  /// The subclass.
  final Type value;

  /// Its type id.
  final String name;

  /// More type ids read as this subclass.
  final List<String> names;
}

/// Class-level: the type id of this class, like Jackson's `@JsonTypeName`.
///
/// ```dart
/// @Introspected()
/// @JsonTypeName('dog')
/// class Dog extends Animal { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonTypeName("dog") class Dog extends Animal { ... }
/// ```
class JsonTypeName {
  /// The id [value].
  const JsonTypeName(this.value);

  /// The type id.
  final String value;
}
