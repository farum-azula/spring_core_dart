/// The startup error for a config file that must exist and does not, such
/// as `spring.config.import=file:./secrets.yml` when there is no
/// `secrets.yml`.
///
/// A location is required unless it starts with `optional:`; the default
/// locations, profile variants (`application-dev.yml`) and imports marked
/// `optional:` never fail. The message names the location and suggests the
/// prefix. Applications meet it as a failed start and fix the location or
/// add `optional:`; `spring.config.on-not-found=ignore` makes every
/// location optional. A missing `configtree:` directory fails the same
/// way.
///
/// ```dart
/// // application.properties: spring.config.import=file:./missing.properties
/// try {
///   await ConfigDataEnvironment(environment).processAndApply();
/// } on ConfigDataResourceNotFoundException catch (error) {
///   log.error(error.location); // file:./missing.properties
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// // Thrown by SpringApplication.run for a missing non-optional
/// // spring.config.import / spring.config.location.
/// try {
///   SpringApplication.run(App.class, args);
/// } catch (ConfigDataResourceNotFoundException ex) {
///   log.error(ex.getMessage());
/// }
/// ```
final class ConfigDataResourceNotFoundException implements Exception {
  /// Creates the exception for [location], which was looked up as the
  /// resource described by [description].
  ConfigDataResourceNotFoundException(this.location, this.description);

  /// The location as it was written, such as `file:./secrets.yml`.
  final String location;

  /// The resource that was looked for, such as
  /// `file [/srv/shop/secrets.yml]`.
  final String description;

  @override
  String toString() =>
      'ConfigDataResourceNotFoundException: Config data resource '
      "'$description' via location '$location' cannot be found. Prefix the "
      "location with 'optional:' to ignore it.";
}

/// The startup error for a required directory location that does not
/// exist, such as `spring.config.import=file:./config/` without a
/// `./config/` directory.
///
/// It applies to directories named in `spring.config.location`,
/// `spring.config.additional-location` or `spring.config.import`. An
/// existing directory without config files is fine, but a wildcard
/// location needs at least one subdirectory (`file:./config/*/`,
/// `configtree:/etc/config/*/`), or one match when it names a file
/// (`file:./config/*/app.yml`), as in Boot. Prefix the location with
/// `optional:` when it may be missing. Applications meet it as a failed
/// start; a missing single file gives
/// [ConfigDataResourceNotFoundException] instead.
///
/// ```dart
/// // --spring.config.import=file:./missing/
/// try {
///   ConfigDataEnvironment(environment).processAndApplySync();
/// } on ConfigDataLocationNotFoundException catch (error) {
///   log.error(error.location); // file:./missing/
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// // Thrown by SpringApplication.run for a missing non-optional directory.
/// try {
///   SpringApplication.run(App.class, args);
/// } catch (ConfigDataLocationNotFoundException ex) {
///   log.error(ex.getMessage());
/// }
/// ```
final class ConfigDataLocationNotFoundException implements Exception {
  /// Creates the exception for [location], with a [reason] when it is more
  /// specific than "cannot be found".
  ConfigDataLocationNotFoundException(this.location, {this.reason});

  /// The location as it was written, such as `file:./config/`.
  final String location;

  /// Why it counts as not found when the directory exists, such as
  /// `contains no subdirectories` for a wildcard directory location;
  /// `null` for a directory that does not exist and for a wildcard
  /// location that finds nothing (Boot's "cannot be found").
  final String? reason;

  @override
  String toString() =>
      "ConfigDataLocationNotFoundException: Config data location '$location' "
      "${reason ?? 'cannot be found'}. Prefix the location with 'optional:' "
      'to ignore it.';
}

/// The startup error for a property written in a config file where it is
/// not allowed.
///
/// Profile switches decide which files are read, so they may not appear in
/// files that are only read because of a profile: `spring.profiles.active`,
/// `spring.profiles.default`, `spring.profiles.include` and
/// `spring.profiles.group.*` fail the start inside
/// `application-dev.properties` or inside a document guarded by
/// `spring.config.activate.on-profile`. The pre-2.4 key `spring.profiles`
/// is rejected anywhere: write `spring.config.activate.on-profile`.
/// Applications meet it as a failed start and move the property.
///
/// ```dart
/// try {
///   ConfigDataEnvironment(environment).processAndApplySync();
/// } on InvalidConfigDataPropertyException catch (error) {
///   log.error('${error.property} in ${error.source}: ${error.reason}');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring Boot throws the same exception from SpringApplication.run:
/// // "Property 'spring.profiles.active' imported from location
/// //  'class path resource [application-dev.properties]' is invalid in a
/// //  profile specific resource"
/// ```
final class InvalidConfigDataPropertyException implements Exception {
  /// Creates the exception for [property], found in the property source
  /// called [source], with the [reason] it is not allowed there.
  InvalidConfigDataPropertyException(this.property, this.source, this.reason);

  /// The key that is not allowed, such as `spring.profiles.active`.
  final String property;

  /// The name of the property source (file or document) that contains
  /// it.
  final String source;

  /// Why the property is not allowed there, such as `not allowed in a
  /// profile-specific document`.
  final String reason;

  @override
  String toString() =>
      "InvalidConfigDataPropertyException: Property '$property' imported "
      "from location '$source' is invalid: $reason";
}

/// The startup error for config data that exists but cannot be used.
///
/// Thrown, with the location and the reason, for a file that is not valid
/// `.properties` or YAML, a file extension no loader handles, a location
/// form that is not supported (a `classpath:` wildcard, more than one
/// `*`), an invalid `spring.config.activate.on-cloud-platform` or
/// `spring.config.on-not-found` value, and a resource that can only be
/// read asynchronously (a Flutter asset, a URL) during a synchronous load.
/// Applications meet it as a failed start and fix the file or location.
///
/// ```dart
/// try {
///   ConfigDataEnvironment(environment).processAndApplySync();
/// } on ConfigDataLoadException catch (error) {
///   // e.g. an asset resource: use processAndApply() instead
///   log.error(error.message);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// // Closest: Spring Boot's ConfigDataLocationNotFoundException /
/// // UnsupportedConfigDataLocationException, thrown from
/// // SpringApplication.run.
/// ```
final class ConfigDataLoadException implements Exception {
  /// Creates the exception for [location], with the reason in [message].
  ConfigDataLoadException(this.location, this.message);

  /// The location (or, for a bad setting, the property) that could not be
  /// used.
  final String location;

  /// Why it could not be used, such as the parser's error with its line.
  final String message;

  @override
  String toString() =>
      "ConfigDataLoadException: Unable to load config data from '$location': "
      '$message';
}
