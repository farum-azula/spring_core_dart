import 'package:spring_core_dart/src/context/property_annotations.dart';
import 'package:spring_core_dart/src/core/env/cloud_platform.dart';

// The settings the core reads while it builds the environment, before any
// bean or binder exists (so the code reads them by name, see
// `ConfigDataEnvironment`). These classes describe them in code: the editor
// metadata (`spring_gen/spring_metadata.json`) is generated from them. They
// are not beans and nothing binds them in this package: the Binder lives in
// spring_boot_dart, which needs the environment this code builds.
// test/core/env/core_properties_drift_test.dart keeps the classes and the
// readers together (same keys, same defaults).

/// How a missing configuration file is treated.
enum OnNotFound {
  /// A missing location that is not `optional:` stops the start.
  fail,

  /// Every location is optional.
  ignore,
}

/// The document-level conditions of `spring.config.activate.*`.
class ConfigActivateProperties {
  /// The document applies when this profile expression matches.
  String? onProfile;

  /// The document applies on this platform, or on `none` (no platform).
  CloudPlatform? onCloudPlatform;
}

/// Which configuration files are read: `spring.config.*`.
@ConfigurationProperties('spring.config')
class ConfigProperties {
  /// Document conditions, set inside a multi-document file.
  ConfigActivateProperties activate = ConfigActivateProperties();

  /// Groups searched after the locations, so they win over them, also where
  /// a location is named in both: `file:./config/` puts
  /// `./config/application.properties` above `./config/*/`.
  String? additionalLocation;

  /// More configuration to read: `resources:other.yml`,
  /// `optional:file:./local.yml`, `configtree:/run/secrets/`.
  @Name('import')
  List<String>? imports;

  /// Replaces the default locations. `,` separates groups; `;` joins
  /// locations into one group. Default: the two default groups.
  String? location;

  /// The base names of the files. `application,shop` reads
  /// `application*.*` and `shop*.*`; a later name wins.
  List<String> name = ['application'];

  /// What to do with a location that does not exist.
  OnNotFound onNotFound = OnNotFound.fail;
}

/// The profile settings: `spring.profiles.*`.
@ConfigurationProperties('spring.profiles')
class ProfilesProperties {
  /// The active profiles. The first source that has the key wins, so the
  /// command line beats a file.
  @PropertyValues.provider('profiles')
  List<String>? active;

  /// The profiles used while none is active; `default` when not set.
  @Name('default')
  @PropertyValues.provider('profiles')
  List<String>? defaults;

  /// Profiles added to the active ones, from every source.
  @PropertyValues.provider('profiles')
  List<String>? include;

  /// Activating `<name>` activates these too; groups can contain groups.
  Map<String, List<String>> group = {};

  /// Whether the names are checked: letters, digits and `-_.+@`, starting
  /// and ending with a letter or digit.
  bool validate = true;
}

/// The cloud platform setting: `spring.main.cloud-platform`.
@ConfigurationProperties('spring.main')
class CloudPlatformProperties {
  /// Forces the cloud platform instead of detecting it; `none` turns
  /// detection off.
  CloudPlatform? cloudPlatform;
}
