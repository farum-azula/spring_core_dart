/// Type conversion, like Spring's `ConversionService`.
///
/// Dart cannot inspect type arguments at runtime, so targets are matched by
/// exact [Type]: `List<int>` is a different target from `List<String>`.
///
/// ```dart
/// final ConversionService service = DefaultConversionService();
/// final port = service.convert<int>('8080'); // 8080
/// final timeout = service.convert<Duration>('10s');
/// final ids = service.convert<List<int>>('1, 2, 3'); // [1, 2, 3]
/// ```
///
/// Spring (Java):
/// ```java
/// ConversionService service = new DefaultConversionService();
/// Integer port = service.convert("8080", Integer.class);
/// // Generic targets need a TypeDescriptor in Spring:
/// Object ids = service.convert("1, 2, 3",
///     TypeDescriptor.valueOf(String.class),
///     TypeDescriptor.collection(List.class,
///         TypeDescriptor.valueOf(Integer.class)));
/// ```
abstract interface class ConversionService {
  /// Whether [source] can be converted to [targetType].
  ///
  /// Unlike Spring, which checks source and target *types*, this checks a
  /// source *value*; a `null` source is always convertible.
  ///
  /// ```dart
  /// service.canConvert('42', int); // true
  /// ```
  bool canConvert(Object? source, Type targetType);

  /// Whether values of type [S] can be converted to [targetType] (Spring's
  /// `canConvert(Class, Class)`): [S] is one, or a converter accepts [S]
  /// (or a supertype of it, such as `num` for `int`).
  ///
  /// ```dart
  /// service.canConvertType<String>(Duration); // true
  /// service.canConvertType<Uri>(Duration); // false
  /// ```
  bool canConvertType<S>(Type targetType);

  /// Converts [source] to [T].
  ///
  /// Returns [source] unchanged when it already is a [T]. A `null` source
  /// (or a converter result of `null`, e.g. for an empty string) is allowed
  /// only when [T] is nullable; otherwise a `ConversionFailedException` is
  /// thrown.
  ///
  /// ```dart
  /// final enabled = service.convert<bool>('yes'); // true
  /// final maybe = service.convert<int?>(''); // null
  /// ```
  T convert<T>(Object? source);

  /// Converts [source] to [targetType], for callers that only know the
  /// target at runtime. Returns `null` for a `null` source.
  ///
  /// ```dart
  /// final Object? value = service.convertTo('2.5', double); // 2.5
  /// ```
  Object? convertTo(Object? source, Type targetType);
}

/// Registration of converters, like Spring's `ConverterRegistry`.
///
/// Converters are plain functions; there is no `Converter` interface.
///
/// ```dart
/// final registry = DefaultConversionService()
///   ..addConverter<String, Money>(Money.parse)
///   ..addEnum(Level.values)
///   ..addCollectionConverters<Money>();
/// ```
///
/// Spring (Java):
/// ```java
/// DefaultConversionService registry = new DefaultConversionService();
/// registry.addConverter(String.class, Money.class, Money::parse);
/// // Enums and collections are handled generically by Spring's defaults.
/// ```
abstract interface class ConverterRegistry {
  /// Adds a converter from [S] (checked with `is`) to exactly [T].
  ///
  /// Later registrations take precedence over earlier ones. The converter is
  /// also used for the nullable target `T?`. A converter may return `null`
  /// (e.g. for a blank string), which is only accepted for nullable targets.
  ///
  /// ```dart
  /// registry.addConverter<String, Money>(Money.parse);
  /// ```
  void addConverter<S, T>(T? Function(S source) converter);

  /// Adds `String` → [E], [E] → `String` and the collection converters of
  /// [E] (`List<E>` / `Set<E>`, see [addCollectionConverters]). Names
  /// match leniently, like
  /// Boot's `LenientObjectToEnumConverterFactory`: `my-value`, `MY_VALUE`
  /// and `myValue` all find `myValue`.
  ///
  /// Spring converts enums generically (`StringToEnumConverterFactory`);
  /// without reflection Dart needs the [values] list.
  ///
  /// ```dart
  /// registry.addEnum(Level.values);
  /// service.convert<Level>('warn'); // Level.warn
  /// ```
  void addEnum<E extends Enum>(List<E> values);

  /// Adds `String` (comma-separated), `Iterable` and any other object (a
  /// one-element collection, Spring's `ObjectToCollectionConverter`) →
  /// `List<E>` / `Set<E>`; elements are converted with this service.
  ///
  /// ```dart
  /// registry.addCollectionConverters<Level>();
  /// service.convert<Set<Level>>('info,warn'); // {Level.info, Level.warn}
  /// service.convert<List<int>>(5); // [5]
  /// ```
  void addCollectionConverters<E>();

  /// Adds `Map` → `Map<K, V>`, keys and values converted with this service
  /// (Spring's `MapToMapConverter`).
  ///
  /// ```dart
  /// registry.addMapConverters<String, Level>();
  /// service.convert<Map<String, Level>>({'a': 'warn'}); // {a: Level.warn}
  /// ```
  void addMapConverters<K, V>();

  /// Removes every converter targeting [T] (and `T?`).
  ///
  /// Spring's `removeConvertible(Class, Class)` also takes the source type.
  void removeConvertible<T>();
}
