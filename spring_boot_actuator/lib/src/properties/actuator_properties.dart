import 'package:spring_boot_actuator/src/endpoint/endpoint_access.dart';
import 'package:spring_boot_actuator/src/health/groups.dart';
import 'package:spring_boot_actuator/src/info/contributors.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The `management.endpoints.*` properties of every endpoint.
///
/// Spring Boot (Java): the `enabled-by-default` key of
/// `EndpointProperties`, and `management.endpoints.access.default`.
@ConfigurationProperties('management.endpoints')
class EndpointsProperties {
  /// Whether the endpoints are enabled when their own
  /// `management.endpoint.<id>.enabled` is not set. Default: each
  /// endpoint's own default (on for the built-in ones).
  bool? enabledByDefault;

  /// The access of the endpoints (Spring Boot 3.4 and later).
  EndpointsAccessProperties access = EndpointsAccessProperties();
}

/// The `management.endpoints.access.*` properties.
@Introspected()
class EndpointsAccessProperties {
  /// The access of an endpoint whose `management.endpoint.<id>.access`
  /// is not set: `none` disables it, `read-only` and `unrestricted`
  /// enable it. Default: the endpoint's own default.
  @Name('default')
  EndpointAccess? defaultAccess;
}

/// The `management.endpoint.health.*` properties.
///
/// Spring Boot (Java): `HealthEndpointProperties`.
@ConfigurationProperties('management.endpoint.health')
class HealthEndpointProperties {
  /// Whether the endpoint is enabled. Default: on.
  bool? enabled;

  /// The endpoint's access (`none` disables it). Default: on.
  EndpointAccess? access;

  /// Who sees the details of each indicator (sizes, versions, errors).
  Show showDetails = Show.never;

  /// Who sees the components (the parts by name). Default: the same as
  /// `show-details`.
  Show? showComponents;

  /// The roles `when-authorized` asks for (any one); empty: any logged-in
  /// user.
  List<String> roles = [];

  /// How the statuses aggregate and which HTTP status they answer.
  HealthStatusProperties status = HealthStatusProperties();

  /// Named groups of indicators, each at `/actuator/health/<name>`.
  Map<String, HealthGroupProperties> group = {};

  /// The `liveness` and `readiness` groups of Kubernetes probes.
  HealthProbesProperties probes = HealthProbesProperties();

  /// The logging of slow indicators.
  HealthLoggingProperties logging = HealthLoggingProperties();

  /// Whether a group that includes or excludes a contributor that does
  /// not exist stops the start.
  bool validateGroupMembership = true;
}

/// The `management.endpoint.health.status.*` properties (also of each
/// group).
@Introspected()
class HealthStatusProperties {
  /// The status codes from the most to the least severe; the first status
  /// of the parts in this order is the aggregate. Default: `DOWN`,
  /// `OUT_OF_SERVICE`, `UP`, `UNKNOWN`.
  List<String> order = [];

  /// The HTTP status of each health status
  /// (`http-mapping.down=503`). Default: `DOWN` and `OUT_OF_SERVICE` are
  /// `503`, the others `200`.
  Map<String, int> httpMapping = {};
}

/// One health group: `management.endpoint.health.group.<name>.*`.
@Introspected()
class HealthGroupProperties {
  /// The contributors of the group (`*` for all, `db/primary` for one
  /// inside a composite). Default: all.
  List<String> include = [];

  /// The contributors left out of the group.
  List<String> exclude = [];

  /// Who sees the details. Default:
  /// `management.endpoint.health.show-details`.
  Show? showDetails;

  /// Who sees the components. Default: `show-details` of the group.
  Show? showComponents;

  /// The roles of `when-authorized`. Default:
  /// `management.endpoint.health.roles`.
  List<String>? roles;

  /// The status order and HTTP mapping of the group. Default: those of
  /// the endpoint.
  HealthStatusProperties status = HealthStatusProperties();

  /// An extra path of the group on the main server (`server:/healthz`).
  String? additionalPath;
}

/// The `management.endpoint.health.probes.*` properties.
@Introspected()
class HealthProbesProperties {
  /// Whether the `liveness` and `readiness` groups (with the
  /// `livenessState` and `readinessState` indicators) exist. On by
  /// default on Kubernetes and Cloud Foundry, as in Spring Boot.
  bool? enabled;

  /// Whether the probes are also at `/livez` and `/readyz` on the main
  /// server.
  bool addAdditionalPaths = false;
}

/// The `management.endpoint.health.logging.*` properties.
@Introspected()
class HealthLoggingProperties {
  /// An indicator slower than this is logged as a warning.
  Duration slowIndicatorThreshold = const Duration(seconds: 10);
}

/// The `management.endpoint.info.*` properties.
@ConfigurationProperties('management.endpoint.info')
class InfoEndpointProperties {
  /// Whether the endpoint is enabled. Default: on.
  bool? enabled;

  /// The endpoint's access (`none` disables it). Default: on.
  EndpointAccess? access;
}

/// The `management.endpoint.mappings.*` properties.
@ConfigurationProperties('management.endpoint.mappings')
class MappingsEndpointProperties {
  /// Whether the endpoint is enabled. Default: on.
  bool? enabled;

  /// The endpoint's access (`none` disables it). Default: on.
  EndpointAccess? access;
}

/// The `management.health.*` properties: which health indicators exist.
///
/// Spring Boot (Java): the `management.health.<name>.enabled` keys and
/// `DiskSpaceHealthIndicatorProperties`.
@ConfigurationProperties('management.health')
class ManagementHealthProperties {
  /// The default of every indicator's `enabled`.
  HealthIndicatorDefaults defaults = HealthIndicatorDefaults();

  /// The `ping` indicator, always `UP`.
  HealthIndicatorProperties ping = HealthIndicatorProperties();

  /// The `db` indicator of the data starter's data sources.
  HealthIndicatorProperties db = HealthIndicatorProperties();

  /// The `diskSpace` indicator.
  DiskSpaceHealthIndicatorProperties diskspace =
      DiskSpaceHealthIndicatorProperties();

  /// The `livenessState` indicator.
  AvailabilityStateIndicatorProperties livenessstate =
      AvailabilityStateIndicatorProperties();

  /// The `readinessState` indicator.
  AvailabilityStateIndicatorProperties readinessstate =
      AvailabilityStateIndicatorProperties();
}

/// The `management.health.defaults.*` properties.
@Introspected()
class HealthIndicatorDefaults {
  /// Whether the indicators whose own `enabled` is not set exist.
  bool enabled = true;
}

/// The `management.health.<name>.*` properties of one indicator.
@Introspected()
class HealthIndicatorProperties {
  /// Whether the indicator exists. Default:
  /// `management.health.defaults.enabled`.
  bool? enabled;
}

/// The `management.health.livenessstate.*` and `readinessstate.*`
/// properties.
@Introspected()
class AvailabilityStateIndicatorProperties {
  /// Whether the indicator exists without the probes (which add it).
  bool enabled = false;
}

/// The `management.health.diskspace.*` properties.
@Introspected()
class DiskSpaceHealthIndicatorProperties {
  /// Whether the indicator exists. Default:
  /// `management.health.defaults.enabled`.
  bool? enabled;

  /// The path whose file system is checked. Default: the working
  /// directory.
  String path = '.';

  /// The least free space that is `UP`.
  DataSize threshold = DataSize.ofMegabytes(10);
}

/// The `management.info.*` properties: which info contributors exist.
///
/// Spring Boot (Java): the `management.info.<id>.enabled` keys and
/// `InfoContributorProperties`.
@ConfigurationProperties('management.info')
class ManagementInfoProperties {
  /// The default of the `build` and `git` contributors' `enabled`.
  InfoContributorDefaults defaults = InfoContributorDefaults();

  /// The `build` contributor (`build-info.properties`).
  InfoContributorProperties build = InfoContributorProperties();

  /// The `git` contributor (`git.properties`).
  GitInfoContributorProperties git = GitInfoContributorProperties();

  /// The `env` contributor (the `info.*` properties).
  OptInInfoContributorProperties env = OptInInfoContributorProperties();

  /// The `os` contributor.
  OptInInfoContributorProperties os = OptInInfoContributorProperties();

  /// The `dart` contributor (Spring Boot's `java`).
  OptInInfoContributorProperties dart = OptInInfoContributorProperties();
}

/// The `management.info.defaults.*` properties.
@Introspected()
class InfoContributorDefaults {
  /// Whether `build` and `git` exist when their own `enabled` is not set.
  bool enabled = true;
}

/// The `management.info.build.*` properties.
@Introspected()
class InfoContributorProperties {
  /// Whether the contributor exists. Default:
  /// `management.info.defaults.enabled`.
  bool? enabled;
}

/// The `management.info.git.*` properties.
@Introspected()
class GitInfoContributorProperties {
  /// Whether the contributor exists. Default:
  /// `management.info.defaults.enabled`.
  bool? enabled;

  /// `simple` (branch, short commit id and time) or `full` (every key).
  InfoPropertiesMode mode = InfoPropertiesMode.simple;
}

/// The properties of a contributor that is off by default (`env`, `os`,
/// `dart`).
@Introspected()
class OptInInfoContributorProperties {
  /// Whether the contributor exists.
  bool enabled = false;
}

/// The `spring.info.*` properties: where the build and git information
/// is read from.
///
/// Spring Boot (Java): `ProjectInfoProperties`.
@ConfigurationProperties('spring.info')
class ProjectInfoProperties {
  /// The build information.
  BuildInfoLocation build = BuildInfoLocation();

  /// The git information.
  GitInfoLocation git = GitInfoLocation();
}

/// Where a properties file of project information is.
abstract interface class ProjectInfoLocation {
  /// Where the properties file is (`resources:`, `file:`).
  String get location;

  /// The file's encoding: `UTF-8` or `ISO-8859-1`.
  String get encoding;
}

/// The `spring.info.build.*` properties.
@Introspected()
class BuildInfoLocation implements ProjectInfoLocation {
  /// Where `build-info.properties` is (`resources:`, `file:`).
  @override
  String location = 'resources:build-info.properties';

  /// The file's encoding: `UTF-8` or `ISO-8859-1`.
  @override
  String encoding = 'UTF-8';
}

/// The `spring.info.git.*` properties.
@Introspected()
class GitInfoLocation implements ProjectInfoLocation {
  /// Where `git.properties` is (`resources:`, `file:`).
  @override
  String location = 'resources:git.properties';

  /// The file's encoding: `UTF-8` or `ISO-8859-1`.
  @override
  String encoding = 'UTF-8';
}
