import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/property_resolver.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/env/system_environment_property_source.dart';

/// A cloud platform an application can run on (Kubernetes, Heroku, Cloud
/// Foundry, ...), recognised from the environment variables the platform
/// sets.
///
/// It lets one build behave differently in the cloud without a profile per
/// platform. Applications mostly name a value: in a config file document
/// guarded by `spring.config.activate.on-cloud-platform: kubernetes`, or
/// in `@ConditionalOnCloudPlatform(CloudPlatform.kubernetes)` on a bean.
/// Code asks [getActive] only when it needs the answer itself.
///
/// The property `spring.main.cloud-platform` ([propertyName]) overrides
/// the detection: a platform name (`kubernetes`, `cloud-foundry`,
/// `CLOUD_FOUNDRY`; case and separators are ignored) forces it, and
/// `none` turns detection off.
///
/// ```dart
/// // Health probes only make sense where Kubernetes calls them.
/// @Bean()
/// @ConditionalOnCloudPlatform(CloudPlatform.kubernetes)
/// ProbesController probes() => ProbesController();
///
/// // The same question in code.
/// final onKubernetes =
///     CloudPlatform.getActive(environment) == CloudPlatform.kubernetes;
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// @ConditionalOnCloudPlatform(CloudPlatform.KUBERNETES)
/// ProbesController probes() { return new ProbesController(); }
///
/// boolean onKubernetes =
///     CloudPlatform.getActive(environment) == CloudPlatform.KUBERNETES;
/// ```
enum CloudPlatform {
  /// No cloud platform. Never detected; set
  /// `spring.main.cloud-platform=none` to turn detection off.
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
  /// are set, or any `<NAME>_SERVICE_HOST` with its `<NAME>_SERVICE_PORT`.
  /// Only the real environment variables count (the `systemEnvironment`
  /// source), not properties of the same name from elsewhere.
  kubernetes,

  /// Azure App Service: `WEBSITE_SITE_NAME`, `WEBSITE_INSTANCE_ID`,
  /// `WEBSITE_RESOURCE_GROUP` and `WEBSITE_SKU` are set.
  azureAppService,

  /// Amazon ECS: `ECS_CONTAINER_METADATA_URI` or
  /// `ECS_CONTAINER_METADATA_URI_V4` is set.
  amazonEcs;

  /// The property that forces a platform, or turns detection off with
  /// `none`: `spring.main.cloud-platform`, as in Spring Boot.
  static const propertyName = 'spring.main.cloud-platform';

  /// Whether this platform is active in [environment]: forced by
  /// [propertyName], or detected when that property is not set at all.
  bool isActive(PropertyResolver environment) {
    final property = environment.getProperty(propertyName);
    return isEnforced(property) ||
        (property == null && isDetected(environment));
  }

  /// Whether [value], a value of [propertyName], names this platform, case
  /// and separators ignored.
  bool isEnforced(String? value) =>
      value != null && _lenient(value) == _lenient(name);

  /// Whether the variables this platform sets are present in
  /// [environment], ignoring [propertyName].
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

  /// The platform the application runs on: the first, in declaration
  /// order, that is forced or detected in [environment].
  ///
  /// `null` when there is none, when [environment] is `null`, or when
  /// [propertyName] names no known platform. [none] when the property is
  /// `none`.
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

  /// The platform [value] names (`kubernetes`, `cloud-foundry`), case and
  /// separators ignored, or `null` for an unknown name.
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
