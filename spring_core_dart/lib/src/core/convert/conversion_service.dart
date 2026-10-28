/// Turns a value into a value of another type, such as the text `'10s'`
/// from a config file into a `Duration`.
///
/// Configuration values and `@Value` arguments arrive as strings (or YAML
/// lists and maps), while beans want `int`, `Duration`, `Uri`, enums or
/// lists. The framework calls a conversion service whenever it fills a
/// typed value: `PropertyResolver.getPropertyAs`, `@Value` injection and
/// `@ConfigurationProperties` binding. An application mostly receives its
/// results. It uses one directly to convert in its own code, and it
/// provides one, as a `conversionService` bean, only to teach `@Value` a
/// type of its own.
///
/// Dart cannot inspect type arguments at run time, so targets are matched
/// by exact [Type]: `List<int>` is a different target from `List<String>`,
/// and each needs its own converter.
///
/// ```dart
/// // The environment carries the service it converts properties with.
/// final ConversionService service = environment.conversionService;
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
  /// Whether [source] can be converted to [targetType]: it already is one,
  /// or a converter for [targetType] accepts it. A `null` source is always
  /// convertible.
  ///
  /// It tells whether a converter exists, not whether this value parses:
  /// `canConvert('abc', int)` is `true` and the conversion still fails.
  /// Unlike Spring, which checks source and target *types*, this checks a
  /// source *value*.
  ///
  /// ```dart
  /// service.canConvert('42', int); // true
  /// ```
  bool canConvert(Object? source, Type targetType);

  /// Whether values of type [S] can be converted to [targetType], checked
  /// before any value exists (for example when wiring code is generated).
  ///
  /// True when [S] is [targetType], when [targetType] is `Object`,
  /// `Object?` or `dynamic`, when [S] is a subtype of a registered
  /// [targetType], or when a converter for [targetType] accepts [S] or a
  /// supertype of it (a `num` converter accepts `int`). This is Spring's
  /// `canConvert(Class, Class)`.
  ///
  /// ```dart
  /// service.canConvertType<String>(Duration); // true
  /// service.canConvertType<Uri>(Duration); // false
  /// ```
  bool canConvertType<S>(Type targetType);

  /// Converts [source] to [T], the usual call.
  ///
  /// Returns [source] unchanged when it already is a [T]. A `null` source,
  /// or a converter result of `null` (the default converters return `null`
  /// for a blank string), is allowed only when [T] is nullable; otherwise
  /// a `ConversionFailedException` is thrown. It is also thrown, with the
  /// parser's error as its cause, when the converter fails. When no
  /// converter targets [T], a `ConverterNotFoundException` is thrown.
  ///
  /// ```dart
  /// final enabled = service.convert<bool>('yes'); // true
  /// final maybe = service.convert<int?>(''); // null
  /// ```
  T convert<T>(Object? source);

  /// Converts [source] to [targetType], for callers that know the target
  /// only as a [Type] value at run time, such as a binder walking fields.
  ///
  /// Returns `null` for a `null` source and may return `null` for a blank
  /// string; throws like [convert] otherwise.
  ///
  /// ```dart
  /// final Object? value = service.convertTo('2.5', double); // 2.5
  /// ```
  Object? convertTo(Object? source, Type targetType);
}

/// The part of a conversion service that accepts new converters.
///
/// The default converters cover numbers, booleans, durations, sizes,
/// URIs, dates and their lists and maps. Anything else, a value type of
/// the application or an enum, must be registered before it can be
/// converted. An application writes these calls when it builds its own
/// `conversionService` bean, or in tests; converters are plain functions,
/// there is no `Converter` interface to implement.
///
/// ```dart
/// @Configuration()
/// class ConversionConfig {
///   // The context uses this bean to convert `@Value` arguments, so
///   // `@Value(r'${shop.price}') Money price` works.
///   @Bean()
///   ConversionService conversionService() => DefaultConversionService()
///     ..addConverter<String, Money>(Money.parse)
///     ..addEnum(Level.values)
///     ..addCollectionConverters<Money>();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// ConversionService conversionService() {
///   DefaultConversionService registry = new DefaultConversionService();
///   registry.addConverter(String.class, Money.class, Money::parse);
///   // Enums and collections are handled generically by Spring's defaults.
///   return registry;
/// }
/// ```
abstract interface class ConverterRegistry {
  /// Adds [converter] from [S] to exactly [T]; it also serves the nullable
  /// target `T?`.
  ///
  /// A source is accepted when it `is` an [S], so a converter from `num`
  /// also takes `int` values. A later registration for the same target
  /// wins over an earlier one. The converter may return `null` (for a
  /// blank string, for example); that is accepted only for nullable
  /// targets. An error it throws reaches the caller wrapped in a
  /// `ConversionFailedException`.
  ///
  /// ```dart
  /// registry.addConverter<String, Money>(Money.parse);
  /// ```
  void addConverter<S, T>(T? Function(S source) converter);

  /// Makes the enum [E] convertible: from `String`, back to `String` (its
  /// name), and as `List<E>` or `Set<E>` (see [addCollectionConverters]).
  ///
  /// Names match leniently, as in Spring Boot: the exact name first, then
  /// ignoring case and separators, so `my-value`, `MY_VALUE` and `myValue`
  /// all find `myValue`. A blank string converts to `null`; an unknown
  /// name fails the conversion.
  ///
  /// Spring converts every enum without registration
  /// (`StringToEnumConverterFactory`); without reflection Dart needs the
  /// [values] list.
  ///
  /// ```dart
  /// registry.addEnum(Level.values);
  /// service.convert<Level>('warn'); // Level.warn
  /// ```
  void addEnum<E extends Enum>(List<E> values);

  /// Makes `List<E>` and `Set<E>` convertible, each element converted to
  /// [E] with this service.
  ///
  /// The sources are a comma-separated string (parts trimmed; a blank
  /// string is an empty collection), any iterable, and any other single
  /// value, which becomes a one-element collection (Spring's
  /// `ObjectToCollectionConverter`). Needed for each element type, since
  /// `List<E>` is its own target; [addEnum] calls it for you.
  ///
  /// ```dart
  /// registry.addCollectionConverters<Level>();
  /// service.convert<Set<Level>>('info,warn'); // {Level.info, Level.warn}
  /// service.convert<List<int>>(5); // [5]
  /// ```
  void addCollectionConverters<E>();

  /// Makes `Map<K, V>` convertible from any map, each key converted to [K]
  /// and each value to [V] with this service (Spring's
  /// `MapToMapConverter`).
  ///
  /// ```dart
  /// registry.addMapConverters<String, Level>();
  /// service.convert<Map<String, Level>>({'a': 'warn'}); // {a: Level.warn}
  /// ```
  void addMapConverters<K, V>();

  /// Removes every converter targeting [T] and `T?`, whatever its source,
  /// for example to replace a default converter. A value that already is a
  /// [T] still converts to itself.
  ///
  /// Spring's `removeConvertible(Class, Class)` also takes the source type.
  void removeConvertible<T>();
}
