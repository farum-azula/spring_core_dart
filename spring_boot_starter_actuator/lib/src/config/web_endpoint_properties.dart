import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The `management.endpoints.web.*` properties: where the endpoints are
/// and which of them HTTP exposes.
///
/// Spring Boot (Java): `WebEndpointProperties`.
@ConfigurationProperties('management.endpoints.web')
class WebEndpointProperties {
  /// The path under which the endpoints are (`/actuator/health`); `/`
  /// puts them at the root (`/health`), without the discovery page.
  String basePath = '/actuator';

  /// Which endpoints are exposed.
  WebEndpointExposure exposure = WebEndpointExposure();

  /// The discovery page at the base path.
  WebEndpointDiscovery discovery = WebEndpointDiscovery();

  /// Another path for an endpoint, by id
  /// (`path-mapping.health=healthcheck`).
  Map<String, String> pathMapping = {};

  /// [basePath] as the endpoints use it: with a leading `/`, without a
  /// trailing one, empty for the root.
  String get cleanBasePath {
    var path = basePath.trim();
    if (path.isNotEmpty && !path.startsWith('/')) {
      path = '/$path';
    }
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }
}

/// The `management.endpoints.web.exposure.*` properties.
@Introspected()
class WebEndpointExposure {
  /// The ids of the exposed endpoints, or `*` for all. Default: `health`.
  List<String> include = [];

  /// The ids of the endpoints not exposed (wins over [include]), or `*`.
  List<String> exclude = [];
}

/// The `management.endpoints.web.discovery.*` properties.
@Introspected()
class WebEndpointDiscovery {
  /// Whether the base path answers the links to the exposed endpoints.
  bool enabled = true;
}
