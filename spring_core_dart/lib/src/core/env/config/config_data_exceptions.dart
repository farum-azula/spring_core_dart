/// A non-optional config location does not exist, like Spring Boot's
/// `ConfigDataResourceNotFoundException`.
///
/// ```dart
/// // application.properties: spring.config.import=file:./missing.properties
/// try {
///   await ConfigDataEnvironment(environment).processAndApply();
/// } on ConfigDataResourceNotFoundException catch (error) {
///   print(error.location); // file:./missing.properties
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
  /// Creates the exception for [location], resolved to the resource
  /// described by [description].
  ConfigDataResourceNotFoundException(this.location, this.description);

  /// The config location as written (without `optional:`).
  final String location;

  /// Description of the resource that was looked up.
  final String description;

  @override
  String toString() =>
      'ConfigDataResourceNotFoundException: Config data resource '
      "'$description' via location '$location' cannot be found. Prefix the "
      "location with 'optional:' to ignore it.";
}

/// A non-optional config location produced nothing, like Spring Boot's
/// `ConfigDataLocationNotFoundException`: a directory location
/// (`file:./config/`) that does not exist, whether from
/// `spring.config.location`, `spring.config.import` or a file's own import.
/// An existing directory without config files is fine.
///
/// ```dart
/// // --spring.config.import=file:./missing/
/// try {
///   ConfigDataEnvironment(environment).processAndApplySync();
/// } on ConfigDataLocationNotFoundException catch (error) {
///   print(error.location); // file:./missing/
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
  /// Creates the exception for [location].
  ConfigDataLocationNotFoundException(this.location);

  /// The config location as written (without `optional:`).
  final String location;

  @override
  String toString() =>
      "ConfigDataLocationNotFoundException: Config data location '$location' "
      "cannot be found. Prefix the location with 'optional:' to ignore it.";
}

/// A property is not allowed where it was found, like Spring Boot's
/// `InvalidConfigDataPropertyException`.
///
/// For example `spring.profiles.active` inside `application-dev.properties`
/// or inside a document guarded by `spring.config.activate.on-profile`.
///
/// ```dart
/// try {
///   ConfigDataEnvironment(environment).processAndApplySync();
/// } on InvalidConfigDataPropertyException catch (error) {
///   print('${error.property} in ${error.source}: ${error.reason}');
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
  /// Creates the exception for [property] found in [source].
  InvalidConfigDataPropertyException(this.property, this.source, this.reason);

  /// The offending property key.
  final String property;

  /// Name of the property source that contains it.
  final String source;

  /// Why the property is not allowed there.
  final String reason;

  @override
  String toString() =>
      "InvalidConfigDataPropertyException: Property '$property' imported "
      "from location '$source' is invalid: $reason";
}

/// A config location cannot be loaded (no loader, async-only resource in a
/// synchronous load, ...).
///
/// ```dart
/// try {
///   ConfigDataEnvironment(environment).processAndApplySync();
/// } on ConfigDataLoadException catch (error) {
///   // e.g. an asset resource: use processAndApply() instead
///   print(error.message);
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
  /// Creates the exception for [location] with the failure [message].
  ConfigDataLoadException(this.location, this.message);

  /// The config location that could not be loaded.
  final String location;

  /// Why loading failed.
  final String message;

  @override
  String toString() =>
      "ConfigDataLoadException: Unable to load config data from '$location': "
      '$message';
}
