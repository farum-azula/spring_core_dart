import 'package:spring_boot_dart/src/annotations.dart';
import 'package:spring_boot_dart/src/banner.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

// The settings `SpringApplication` and the auto-configurations read. The
// generator writes their binding (`bindBootProperties` in `properties.dart`
// binds them from an environment before the context exists; inside the
// context they are beans), and the editor metadata
// (`spring_gen/spring_metadata.json`) comes from the same classes, so the
// description and the reading cannot drift apart.

/// The behaviour of `SpringApplication`: `spring.main.*`.
@ConfigurationProperties('spring.main')
class MainProperties {
  /// A second bean with the same name replaces the first instead of
  /// failing the start.
  bool allowBeanDefinitionOverriding = false;

  /// Where the banner is printed. `false` is the same as `off`.
  BannerMode bannerMode = BannerMode.console;

  /// Creates every bean on first use instead of at the start: a faster
  /// start, but a broken bean fails later.
  bool lazyInitialization = false;

  /// Logs the "Starting …", active profiles and "Started … in N seconds"
  /// lines.
  bool logStartupInfo = true;

  /// Closes the context on SIGINT or SIGTERM, so `@PreDestroy` methods run
  /// (VM only). Off by default, unlike in Spring Boot.
  bool registerShutdownHook = false;
}

/// The auto-configuration switches: `spring.autoconfigure.*`.
@ConfigurationProperties('spring.autoconfigure')
class AutoconfigureProperties {
  /// The auto-configurations to leave out, by class or module name.
  List<String>? exclude;
}

/// The application's identity: `spring.application.*`.
@ConfigurationProperties('spring.application')
class ApplicationProperties {
  /// Properties as one JSON object (see `SPRING_APPLICATION_JSON`).
  String? json;

  /// The application's name: the context's id, and the name in the startup
  /// lines (`application` when not set).
  String? name;
}

/// The banner file: `spring.banner.*`.
@ConfigurationProperties('spring.banner')
class BannerProperties {
  /// The banner file. `${spring-boot.version}`,
  /// `${spring-boot.formatted-version}` and other `${...}` in it are
  /// replaced.
  String location = 'resources:banner.txt';
}

/// The development tools: `spring.devtools.restart.*`.
@ConfigurationProperties('spring.devtools.restart')
class DevtoolsRestartProperties {
  /// Whether a hot reload restarts the context when the generated code
  /// changed.
  bool enabled = true;
}

/// The shutdown: `spring.lifecycle.*`.
@ConfigurationProperties('spring.lifecycle')
class LifecycleProperties {
  /// How long the context waits for the beans of one shutdown phase to
  /// stop.
  Duration timeoutPerShutdownPhase = const Duration(seconds: 30);
}

/// The debug switches, which are keys without a prefix.
@ConfigurationProperties('')
class DebugProperties {
  /// Any value but `false` (for example `--debug`) logs the condition
  /// evaluation report: which auto-configured beans were created, and why
  /// the others were not.
  String? debug;

  /// Any value but `false` (for example `--trace`) sets the framework
  /// loggers to trace.
  String? trace;
}

/// The message source: `spring.messages.*`.
@ConfigurationProperties('spring.messages')
class MessagesProperties {
  /// Formats messages without arguments too, so `''` becomes `'`.
  bool alwaysUseMessageFormat = false;

  /// The base names of the files. `i18n/errors` (or `i18n.errors`) reads
  /// `i18n/errors_{locale}.properties`.
  List<String> basename = ['messages'];

  /// How long a loaded file is kept before it is read again. Default: kept
  /// forever. A number without a unit is in seconds.
  @DurationUnit(ChronoUnit.seconds)
  Duration? cacheDuration;

  /// Texts shared by every locale; a later file wins.
  List<String>? commonMessages;

  /// A locale tried before the system's (not in Spring Boot).
  String? defaultLocale;

  /// The files' encoding; an unknown one fails the start. Default: UTF-8.
  String? encoding;

  /// Tries the system's locale before the file without a locale.
  bool fallbackToSystemLocale = true;

  /// A missing key returns the key itself instead of failing.
  bool useCodeAsDefaultMessage = false;
}

/// The JSON mapper: `spring.json.*`.
@ConfigurationProperties('spring.json')
class JsonProperties {
  /// How field names become JSON names.
  @PropertyValues([
    'SNAKE_CASE',
    'UPPER_SNAKE_CASE',
    'UPPER_CAMEL_CASE',
    'LOWER_CAMEL_CASE',
    'LOWER_CASE',
    'KEBAB_CASE',
    'LOWER_DOT_CASE',
  ])
  String propertyNamingStrategy = 'LOWER_CAMEL_CASE';

  /// Which properties are written.
  JsonInclusion defaultPropertyInclusion = JsonInclusion.always;

  /// `UTC`, `Z` or a fixed offset (`+02:00`); named zones such as
  /// `Europe/Berlin` fail, as Dart has no time zone database.
  String? timeZone;

  /// Reading.
  JsonDeserializationProperties deserialization =
      JsonDeserializationProperties();

  /// Writing.
  JsonSerializationProperties serialization = JsonSerializationProperties();

  /// The mapper's general behaviour.
  JsonMapperProperties mapper = JsonMapperProperties();

  /// Settings of the date and time module.
  JsonDatatypeProperties datatype = JsonDatatypeProperties();

  /// The JSON Schemas of the app: the build writes a class for each of
  /// their objects (`lib/spring_gen/json_schemas.spring.dart`) and keeps a
  /// remote one as a resource; the `jsonSchemaRegistry` bean has them.
  List<JsonSchemaProperties> schemas = [];

  /// What the `jsonSchemaRegistry` bean is given.
  JsonSchemasRegistryProperties schemasRegistry =
      JsonSchemasRegistryProperties();
}

/// `spring.json.schemas[n].*`: a JSON Schema of the app.
class JsonSchemaProperties {
  /// Where it is: `resources:schemas/order.json`, an `https://` address
  /// or `github:owner/repo/path@ref`; the build downloads a remote one.
  String? location;

  /// The SHA-256 of a remote schema (hex): the build refuses another.
  String? sha256;

  /// What the names of its classes start with (`Api`: `ApiOrder`).
  String? prefix;

  /// The name of its root class, instead of its `title`.
  String? name;
}

/// `spring.json.schemas-registry.*`.
class JsonSchemasRegistryProperties {
  /// The schemas of `spring.json.schemas` and of `@JsonSchemaSource` go
  /// into the registry bean, the app's own too.
  bool properties = true;
}

/// `spring.json.deserialization.*`.
class JsonDeserializationProperties {
  /// `1.0` can be read into an `int`.
  bool acceptFloatAsInt = true;

  /// `null` for a non-nullable number or `bool` fails the read.
  bool failOnNullForPrimitives = true;

  /// An unknown JSON property fails the read.
  bool failOnUnknownProperties = false;

  /// Reads timestamps with a fraction.
  bool readDateTimestampsAsNanoseconds = true;
}

/// `spring.json.serialization.*`.
class JsonSerializationProperties {
  /// Pretty-printed JSON.
  bool indentOutput = false;

  /// Timestamps with a fraction.
  bool writeDateTimestampsAsNanoseconds = true;

  /// Dates as numbers.
  /// `spring.json.datatype.datetime.write-dates-as-timestamps` does the same
  /// and wins.
  bool writeDatesAsTimestamps = false;

  /// Durations as numbers.
  bool writeDurationsAsTimestamps = false;
}

/// `spring.json.mapper.*`.
class JsonMapperProperties {
  /// Properties without `@JsonView` appear in every view.
  bool defaultViewInclusion = false;

  /// Writes properties in alphabetical order.
  bool sortPropertiesAlphabetically = true;
}

/// `spring.json.datatype.*`.
class JsonDatatypeProperties {
  /// The date and time settings, which win over the same ones in
  /// `serialization` and `deserialization`.
  JsonDatetimeProperties datetime = JsonDatetimeProperties();
}

/// `spring.json.datatype.datetime.*`.
class JsonDatetimeProperties {
  /// Reads timestamps with a fraction. Default: the value of
  /// `spring.json.deserialization.read-date-timestamps-as-nanoseconds`.
  bool? readDateTimestampsAsNanoseconds;

  /// Timestamps with a fraction. Default: the value of
  /// `spring.json.serialization.write-date-timestamps-as-nanoseconds`.
  bool? writeDateTimestampsAsNanoseconds;

  /// Dates as numbers. Default: the value of
  /// `spring.json.serialization.write-dates-as-timestamps`.
  bool? writeDatesAsTimestamps;

  /// Durations as numbers. Default: the value of
  /// `spring.json.serialization.write-durations-as-timestamps`.
  bool? writeDurationsAsTimestamps;
}
