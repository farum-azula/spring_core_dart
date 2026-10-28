import 'package:spring_core_dart/src/json/naming.dart';

/// Gives a property, constructor parameter or enum constant another name in
/// JSON, or limits it to one direction.
///
/// Use it when the JSON name differs from the Dart one (`published_at`
/// for `publishedAt`), for a single property where a naming strategy would
/// be too broad. The name wins over the mapper's and the class's naming
/// strategy. [access] makes a property one-way: a
/// [JsonPropertyAccess.readOnly] property is written but ignored when
/// read, a [JsonPropertyAccess.writeOnly] one (a password in a sign-up
/// request) is read but never written.
///
/// There is no `required` flag: whether a property must be present comes
/// from the Dart constructor. A parameter that is neither nullable nor has
/// a default value must be in the JSON; a nullable one may be missing and
/// reads as `null`.
///
/// ```dart
/// // A REST model: snake_case date, password accepted but never echoed.
/// @Introspected()
/// class Book {
///   const Book(this.isbn, this.publishedAt, {this.password});
///   final String isbn; // must be present: not nullable, no default
///   @JsonProperty('published_at')
///   final DateTime publishedAt;
///   @JsonProperty('', access: JsonPropertyAccess.writeOnly)
///   final String? password;
/// }
/// // {"isbn": "978-0", "published_at": "2026-01-01T00:00:00.000Z"}
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
  /// Names the property [name] in JSON; `''` keeps its own name (after the
  /// naming strategy), for setting only [access].
  const JsonProperty(this.name, {this.access = JsonPropertyAccess.auto});

  /// The JSON name; empty for the name the naming strategy gives.
  final String name;

  /// In which directions the property is used; [JsonPropertyAccess.auto] by
  /// default.
  final JsonPropertyAccess access;
}

/// The directions a property takes part in, for [JsonProperty.access]
/// (Jackson's `JsonProperty.Access`).
enum JsonPropertyAccess {
  /// Both directions, as far as the property can be read and set (`AUTO`).
  /// The default.
  auto,

  /// Only written to JSON; a value for it in the JSON is ignored. Use it for
  /// values the server computes, such as an id or a total (`READ_ONLY`:
  /// the property is only read from the object).
  readOnly,

  /// Only read from JSON, never written. Use it for secrets a client sends,
  /// such as a password (`WRITE_ONLY`: the property is only set on the
  /// object).
  writeOnly,

  /// Both directions (`READ_WRITE`); the same as [auto], as Dart has no
  /// visibility levels between public and private.
  readWrite,
}

/// Leaves a property out of JSON in both directions.
///
/// Use it for data that must never leave the server or come from a
/// client, such as a password hash or an internal flag. The property is
/// not written, and a JSON property of that name is skipped when reading.
///
/// ```dart
/// // Stored, but never part of an API response.
/// @JsonIgnore()
/// String? passwordHash;
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonIgnore String passwordHash;
/// ```
class JsonIgnore {
  /// Leaves the annotated property out of JSON.
  const JsonIgnore();
}

/// Decides which values of a property, or of every property of a class,
/// are written: for example, leave out `null`s.
///
/// Use it to keep responses small or to send partial updates, where a
/// missing property means "unchanged". It wins over the mapper's
/// `inclusion` (`spring.jackson.default-property-inclusion` in Spring
/// Boot); on a property it wins over the class's.
///
/// ```dart
/// // A partial update: only the fields that were set are sent.
/// @Introspected()
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
  /// Writes the values [value] lets through.
  const JsonInclude(this.value);

  /// Which values are written.
  final JsonInclusion value;
}

/// Which property values are written, for [JsonInclude] and the mapper's
/// `inclusion` (Jackson's `JsonInclude.Include`).
enum JsonInclusion {
  /// Every value, `null` included (`ALWAYS`). The mapper's default.
  always,

  /// Every value except `null` (`NON_NULL`).
  nonNull,

  /// Every value except `null` (`NON_ABSENT`); the same as [nonNull], as
  /// Dart has no `Optional`.
  nonAbsent,

  /// Every value except `null` and an empty string, list, set or map
  /// (`NON_EMPTY`).
  nonEmpty,

  /// Every value that differs from its default (`NON_DEFAULT`). On a class
  /// (`@JsonInclude(JsonInclusion.nonDefault)` on the class), the default
  /// is the value in an instance created with the no-argument constructor.
  /// Elsewhere, or when the class has no such constructor, it is the
  /// default of the type: `null`, `0`, `false` and what [nonEmpty] leaves
  /// out.
  nonDefault,
}

/// Puts chosen properties of a class first when it is written, for JSON
/// that people read or that a fixed format expects.
///
/// Put it on the class. The listed names (JSON or Dart names) come first,
/// in that order; the others follow in the mapper's order, sorted
/// alphabetically unless `ObjectMapper.sortPropertiesAlphabetically` is
/// off. [JsonPropertyOrder.alphabetic] sorts the unlisted ones
/// alphabetically even when the mapper does not (Jackson's
/// `alphabetic = true`). Reading does not depend on the order.
///
/// ```dart
/// // The id and title lead, whatever else the book has.
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
  /// Writes the properties [value] first, in that order.
  const JsonPropertyOrder(this.value) : alphabetic = false;

  /// Writes the properties [value] first (none by default), then the others
  /// sorted alphabetically.
  const JsonPropertyOrder.alphabetic({this.value = const []})
    : alphabetic = true;

  /// The property names written first, in this order.
  final List<String> value;

  /// Whether the properties that are not listed are sorted alphabetically
  /// regardless of the mapper's setting.
  final bool alphabetic;
}

/// Lists JSON properties a class ignores, and can make it accept unknown
/// ones when reading.
///
/// Put it on the class. Use [ignoreUnknown] for a model of an outside API
/// that may add fields, so reading keeps working when the mapper is
/// strict (`failOnUnknownProperties` on). Use [value] to drop properties
/// by JSON name in both directions, such as an inherited one this class
/// should not expose.
///
/// ```dart
/// // The server may add fields; skip them.
/// @Introspected()
/// @JsonIgnoreProperties(ignoreUnknown: true)
/// class Book { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonIgnoreProperties(ignoreUnknown = true)
/// class Book { ... }
/// ```
class JsonIgnoreProperties {
  /// Ignores the JSON properties [value]; with [ignoreUnknown], unknown
  /// properties are skipped even when `failOnUnknownProperties` is on.
  const JsonIgnoreProperties({
    this.value = const [],
    this.ignoreUnknown = false,
  });

  /// The JSON property names to ignore in both directions; none by
  /// default.
  final List<String> value;

  /// Whether unknown properties are skipped while reading, whatever the
  /// mapper says; `false` by default.
  final bool ignoreUnknown;
}

/// Marks the constructor (or factory constructor) the mapper creates
/// objects with when reading JSON.
///
/// Without it the unnamed constructor is used. Use it when that one does
/// not fit the JSON: the class is built from other values than it stores,
/// or the unnamed constructor is for code, not for JSON. The parameters
/// are matched to JSON properties by name.
///
/// ```dart
/// // JSON has amount and currency; the object stores cents.
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
  /// Marks the annotated constructor for reading JSON.
  const JsonCreator();
}

/// Makes one value stand for the whole object in JSON: an enum constant's
/// JSON form, or a small value class written as a plain string or number.
///
/// On a field or getter of an enum, its value is each constant's JSON form
/// instead of the constant's name (also as a map key; an `int` one is
/// matched by value, never as an index). On a property (field or getter)
/// or a method without parameters of an `@Introspected` class, the object
/// is written as that value and read back through a constructor with one
/// parameter (Jackson's delegating creator) or its `fromJson`. One per
/// class; a second one fails the build.
///
/// ```dart
/// // The API says "in_stock"; Dart says inStock.
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
/// // A typed id that is a plain string in JSON.
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
  /// Marks the field, getter or method whose value stands for the object.
  const JsonValue();
}

/// Other JSON names a property (or constructor parameter) is read from,
/// besides its own.
///
/// Use it when clients send the same field under several names, such as
/// an old and a new name during a migration. The property is still
/// written with its own name only.
///
/// ```dart
/// // Accepts the old names while clients move to "name".
/// @JsonAlias(['fullName', 'n'])
/// final String name; // reads "name", "fullName" or "n"
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonAlias({"fullName", "n"}) String name;
/// ```
class JsonAlias {
  /// Also reads the property from the JSON names [value].
  const JsonAlias(this.value);

  /// The other JSON names accepted when reading.
  final List<String> value;
}

/// Changes the JSON form of one property's value: a date pattern and time
/// zone, or a shape (a number as a string, an enum by index, ...).
///
/// Use it when an API expects a format other than the mapper's default,
/// such as `24.12.2026` instead of ISO-8601. On a `DateTime`, [pattern]
/// takes the letters of Java's `DateTimeFormatter` (`y M d H h m s S a E
/// X x Z` and `'quoted'` text) and [timezone] the offset. [shape] applies
/// to dates, durations, enums, numbers and booleans; [JsonFormatShape.array]
/// on a class writes its objects as arrays of property values. On a list,
/// set or map property it applies to the elements (the values of a map).
///
/// ```dart
/// // Fields of a model for an API with its own conventions.
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
  /// A format with a [shape], a date [pattern] and a [timezone]; each is
  /// optional and the defaults change nothing.
  const JsonFormat({
    this.shape = JsonFormatShape.any,
    this.pattern = '',
    this.timezone = '',
  });

  /// The JSON shape; [JsonFormatShape.any] keeps the type's usual one.
  final JsonFormatShape shape;

  /// The date pattern, such as `dd.MM.yyyy`; empty for ISO-8601. An
  /// unsupported letter is an error.
  final String pattern;

  /// The offset dates are written in, and read in when the text has none:
  /// `UTC`, `Z` or a fixed offset such as `+02:00`; empty for the mapper's
  /// `timeZone`.
  final String timezone;
}

/// The JSON shapes [JsonFormat.shape] can ask for (Jackson's
/// `JsonFormat.Shape`).
enum JsonFormatShape {
  /// The type's usual shape (`ANY` / `NATURAL`). The default.
  any,

  /// A string: numbers and booleans as text, dates as ISO-8601 (or the
  /// pattern) even when timestamps are on, enums by name.
  string,

  /// A number: dates and durations as timestamps, enums by index.
  number,

  /// On a class: each object is written as the array of its property
  /// values, in property order, and read back from one. It makes compact
  /// JSON for long lists of small records.
  array,
}

/// Writes the entries of a map property as extra properties of the
/// object, after the declared ones.
///
/// Put it on a `Map<String, ...>` property or a method returning one. Use
/// it for open-ended objects: known fields as properties, anything else
/// kept in a map and written back flat. Pair it with [JsonAnySetter] to
/// collect the unknown properties into the same map when reading, so they
/// survive a read-modify-write round trip.
///
/// ```dart
/// // Unknown properties are kept and written back.
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
  /// Marks the map property or method.
  const JsonAnyGetter();
}

/// Collects the JSON properties a class does not have, instead of
/// skipping them or failing.
///
/// Put it on a `Map<String, ...>` property or on a method taking
/// `(String name, value)`. With it, unknown properties never fail, even
/// with `failOnUnknownProperties` on. A map property that is a constructor
/// parameter receives them as its argument; otherwise its map is filled
/// (or created when it is `null`). Values are read as the map's value
/// type.
///
/// ```dart
/// // Every unknown property ends up in `extra`.
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
  /// Marks the map property or method.
  const JsonAnySetter();
}

/// Writes the properties of a nested object inline, in the enclosing
/// object, instead of under its own key.
///
/// Use it to keep a Dart model structured (an `Address` object) while the
/// JSON is flat (`home_city`). [prefix] and [suffix] are added to the
/// nested names; reading collects the properties back into the nested
/// object.
///
/// ```dart
/// // The address fields sit next to the name, prefixed.
/// @JsonUnwrapped(prefix: 'home_')
/// final Address address; // {"name": "Ann", "home_city": "Lyon"}
/// ```
///
/// Spring (Java):
/// ```java
/// @JsonUnwrapped(prefix = "home_") Address address;
/// ```
class JsonUnwrapped {
  /// Unwraps the property, adding [prefix] and [suffix] to the nested names;
  /// [enabled] `false` turns it off.
  const JsonUnwrapped({
    this.prefix = '',
    this.suffix = '',
    this.enabled = true,
  });

  /// Added before each nested property name; empty by default.
  final String prefix;

  /// Added after each nested property name; empty by default.
  final String suffix;

  /// Whether the property is unwrapped; `true` by default.
  final bool enabled;
}

/// Sets the naming strategy of one class's properties, overriding the
/// mapper's.
///
/// Put it on the class when one model talks to an API with another
/// convention than the rest of the application. `@JsonProperty` on a
/// property still wins.
///
/// ```dart
/// // Rows of a snake_case export; other classes keep their names.
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
  /// Names the class's properties with [value].
  const JsonNaming(this.value);

  /// The naming strategy of the class's properties.
  final PropertyNamingStrategy value;
}

/// Puts a property into one or more views, so the same class can be
/// written with fewer or more properties depending on who reads it.
///
/// Use it to serve a public and an internal form of a model without two
/// classes. A view is any class; a view class that extends another
/// includes it. `mapper.writerWithView(Public)` writes (and
/// `readerWithView` reads) only the properties of that view or of a view
/// it extends; properties without a view only when `defaultViewInclusion`
/// is on (off by default, like Jackson 3 and Spring Boot). On a class it is
/// the default view of its properties. The view classes named here are
/// introspected, which is how the mapper knows which extends which.
///
/// ```dart
/// // Public callers get the name; internal ones also the email.
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
  /// Puts the property into the views [value].
  const JsonView(this.value);

  /// The view classes the property belongs to.
  final List<Type> value;
}

/// Makes a class hierarchy polymorphic in JSON: each object carries a type
/// id, so a value of the base type is read back as the right subclass.
///
/// Put it on the base class when a property or a list holds several
/// subclasses, such as `List<Animal>` with dogs and cats. The ids come
/// from `@JsonSubTypes`, else `@JsonTypeName`, else the simple class name.
/// Only the subtypes listed by `@JsonSubTypes` (and those the listed
/// classes list) are read; an unknown id fails unless [defaultImpl] is
/// set.
///
/// ```dart
/// // A list of animals keeps each one's class.
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
  /// Writes type ids of the kind [use], placed as [include]. [property] is
  /// the id's property name (default `@type`); [defaultImpl] is the class
  /// read when the id is missing or unknown; [visible] also passes the id
  /// property on to the class.
  const JsonTypeInfo({
    this.use = JsonTypeId.name,
    this.include = JsonTypeInclusion.property,
    this.property = '',
    this.defaultImpl,
    this.visible = false,
  });

  /// What the type id is: a name (the default) or nothing, deduced from the
  /// properties.
  final JsonTypeId use;

  /// Where the type id goes; a property of the object by default.
  final JsonTypeInclusion include;

  /// The name of the type id property; empty for `@type`.
  final String property;

  /// The class read when the JSON has no type id or an unknown one; `null`
  /// makes that an error.
  final Type? defaultImpl;

  /// Whether the type id property is also read into the class, for a class
  /// that keeps its kind as a property; `false` by default.
  final bool visible;
}

/// What identifies the subclass in JSON, for [JsonTypeInfo.use]
/// (Jackson's `JsonTypeInfo.Id`).
enum JsonTypeId {
  /// A logical name: from `@JsonSubTypes` or `@JsonTypeName`, else the
  /// simple class name (`NAME`). The default.
  name,

  /// The same as [name], as Dart has no nested classes (`SIMPLE_NAME`).
  simpleName,

  /// No type id: the subclass is the one whose properties include all those
  /// present in the JSON (`DEDUCTION`). Use it for JSON you do not control.
  deduction,
}

/// Where the type id is placed, for [JsonTypeInfo.include] (Jackson's
/// `JsonTypeInfo.As`).
enum JsonTypeInclusion {
  /// A property of the object, written first (`PROPERTY`). The default.
  property,

  /// A property the class has itself, which is read as the id; nothing is
  /// added when writing (`EXISTING_PROPERTY`).
  existingProperty,

  /// An object wrapping the value: `{"dog": {...}}` (`WRAPPER_OBJECT`).
  wrapperObject,

  /// An array of the id and the value: `["dog", {...}]` (`WRAPPER_ARRAY`).
  wrapperArray,
}

/// Lists the subclasses of a `@JsonTypeInfo` class and their type ids.
///
/// Put it on the base class next to `@JsonTypeInfo`; only listed
/// subclasses can be read. The listed classes are introspected, so they
/// need no `@Introspected()` of their own. See [JsonTypeInfo] for an
/// example.
///
/// Spring (Java):
/// ```java
/// @JsonSubTypes({@JsonSubTypes.Type(value = Dog.class, name = "dog")})
/// ```
class JsonSubTypes {
  /// Lists the subclasses [value].
  const JsonSubTypes(this.value);

  /// The subclasses and their ids.
  final List<JsonSubType> value;
}

/// One entry of [JsonSubTypes]: a subclass and the type ids it is written
/// and read with (Jackson's `@JsonSubTypes.Type`).
class JsonSubType {
  /// The subclass [value] with the id [name] (empty: its `@JsonTypeName` or
  /// class name), also read from the ids [names].
  const JsonSubType(this.value, {this.name = '', this.names = const []});

  /// The subclass.
  final Type value;

  /// Its type id, written and read; empty for its `@JsonTypeName` or class
  /// name.
  final String name;

  /// More type ids read as this subclass, never written; for old ids.
  final List<String> names;
}

/// Sets the type id of a subclass in a `@JsonTypeInfo` hierarchy.
///
/// Put it on the subclass to keep the id next to the class instead of in
/// the base class's `@JsonSubTypes`. Without it, and without a name in
/// `@JsonSubTypes`, the id is the simple class name.
///
/// ```dart
/// // Dogs are "dog" in JSON.
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
  /// Gives the class the type id [value].
  const JsonTypeName(this.value);

  /// The type id written and read for the class.
  final String value;
}
