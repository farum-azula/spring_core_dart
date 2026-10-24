import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/property_resolver.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/env/system_environment_property_source.dart';

/// The cloud platform the application runs on, detected from environment
/// variables, like Spring Boot's `CloudPlatform`.
///
/// `spring.main.cloud-platform` ([propertyName]) overrides the detection:
/// a platform name (`kubernetes`, `cloud-foundry`, `CLOUD_FOUNDRY`; case
/// and separators are ignored) enforces it, `none` turns detection off.
/// Used by `spring.config.activate.on-cloud-platform` documents and
/// `@ConditionalOnCloudPlatform`.
///
/// ```dart
/// final platform = CloudPlatform.getActive(environment);
/// if (platform == CloudPlatform.kubernetes) {
///   // ...
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// CloudPlatform platform = CloudPlatform.getActive(environment);
/// if (platform == CloudPlatform.KUBERNETES) { ... }
/// ```
enum CloudPlatform {
  /// No cloud platform; enforce it to turn detection off.
  none,

  /// Cloud Foundry: `VCAP_APPLICATION` or `VCAP_SERVICES` is set.
  cloudFoundry,

  /// Heroku: `DYNO` is set.
  heroku,

  /// SAP Cloud Platform: `HC_LANDSCAPE` is set.
  sap,

  /// HashiCorp Nomad: `NOMAD_ALLOC_ID` is set.
  nomad,

  /// Kubernetes: `KUBERNETES_SERVICE_HOST` and `KUBERNETES_SERVICE_PORT`
  /// are set, or any `<NAME>_SERVICE_HOST` with its `<NAME>_SERVICE_PORT`
  /// (in the system environment property source).
  kubernetes,

  /// Azure App Service: `WEBSITE_SITE_NAME`, `WEBSITE_INSTANCE_ID`,
  /// `WEBSITE_RESOURCE_GROUP` and `WEBSITE_SKU` are set.
  azureAppService,

  /// Amazon ECS: `ECS_CONTAINER_METADATA_URI` or
  /// `ECS_CONTAINER_METADATA_URI_V4` is set.
  amazonEcs;

  /// Property that enforces a platform (Boot's
  /// `spring.main.cloud-platform`).
  static const propertyName = 'spring.main.cloud-platform';

  /// Whether this platform is active in [environment]: enforced by
  /// [propertyName], or detected when that property is not set.
  bool isActive(PropertyResolver environment) {
    final property = environment.getProperty(propertyName);
    return isEnforced(property) ||
        (property == null && isDetected(environment));
  }

  /// Whether [value] (a [propertyName] value) names this platform.
  bool isEnforced(String? value) =>
      value != null && _lenient(value) == _lenient(name);

  /// Whether the environment variables of this platform are present.
  bool isDetected(PropertyResolver environment) => switch (this) {
    none => false,
    cloudFoundry =>
      environment.containsProperty('VCAP_APPLICATION') ||
          environment.containsProperty('VCAP_SERVICES'),
    heroku => environment.containsProperty('DYNO'),
    sap => environment.containsProperty('HC_LANDSCAPE'),
    nomad => environment.containsProperty('NOMAD_ALLOC_ID'),
    kubernetes => _isKubernetes(environment),
    azureAppService => const [
      'WEBSITE_SITE_NAME',
      'WEBSITE_INSTANCE_ID',
      'WEBSITE_RESOURCE_GROUP',
      'WEBSITE_SKU',
    ].every(environment.containsProperty),
    amazonEcs =>
      environment.containsProperty('ECS_CONTAINER_METADATA_URI') ||
          environment.containsProperty('ECS_CONTAINER_METADATA_URI_V4'),
  };

  /// The active platform of [environment] (the first one, in declaration
  /// order, that is enforced or detected), or `null`. [none] when
  /// `spring.main.cloud-platform=none`.
  static CloudPlatform? getActive(PropertyResolver? environment) {
    if (environment == null) {
      return null;
    }
    for (final platform in values) {
      if (platform.isActive(environment)) {
        return platform;
      }
    }
    return null;
  }

  /// The platform [value] names (case and separators ignored), or `null`.
  static CloudPlatform? parse(String value) {
    for (final platform in values) {
      if (platform.isEnforced(value)) {
        return platform;
      }
    }
    return null;
  }

  // Kubernetes is only detected from the system environment source, like
  // Boot's KUBERNETES.isDetected.
  static bool _isKubernetes(PropertyResolver environment) {
    if (environment is! ConfigurableEnvironment) {
      return false;
    }
    final source = environment.propertySources.get(
      SystemEnvironmentPropertySource.defaultName,
    );
    if (source == null) {
      return false;
    }
    if (source.containsProperty('KUBERNETES_SERVICE_HOST') &&
        source.containsProperty('KUBERNETES_SERVICE_PORT')) {
      return true;
    }
    if (source is EnumerablePropertySource<Object>) {
      const suffix = '_SERVICE_HOST';
      for (final name in source.propertyNames) {
        if (name.endsWith(suffix)) {
          final service = name.substring(0, name.length - suffix.length);
          if (source.getProperty('${service}_SERVICE_PORT') != null) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static String _lenient(String text) =>
      text.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
}
