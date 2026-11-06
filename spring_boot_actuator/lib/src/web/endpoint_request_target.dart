import 'package:spring_boot_actuator/src/endpoint/operation.dart';

/// The actuator endpoint a web request is for, recorded on the request by
/// the actuator starter before the security filters run, so a request
/// matcher can tell an endpoint request from the others without knowing
/// the base path or the exposed endpoints.
///
/// The security starter's `EndpointRequest.toAnyEndpoint()` reads it:
///
/// ```dart
/// final target = EndpointRequestTarget.of(request.attributes);
/// if (target?.endpointId == EndpointId.of('health')) { ... }
/// ```
///
/// Spring Boot's `EndpointRequest` asks the application context for the
/// exposed endpoints' paths instead; this attribute is how the same
/// answer reaches a matcher here.
final class EndpointRequestTarget {
  /// A request for the endpoint [endpointId].
  const EndpointRequestTarget.endpoint(EndpointId this.endpointId);

  /// A request for the discovery page (`/actuator`).
  const EndpointRequestTarget.links() : endpointId = null;

  /// The request attribute holding the target.
  static const attribute = 'spring.boot.actuate.endpoint.target';

  /// The endpoint, or `null` for the discovery page.
  final EndpointId? endpointId;

  /// Whether the request is for the discovery page.
  bool get isLinks => endpointId == null;

  /// The target recorded in [attributes], or `null` for a request that is
  /// not for an exposed endpoint.
  static EndpointRequestTarget? of(Map<String, Object?> attributes) =>
      switch (attributes[attribute]) {
        final EndpointRequestTarget target => target,
        _ => null,
      };

  @override
  String toString() => isLinks ? 'links' : 'endpoint $endpointId';
}
