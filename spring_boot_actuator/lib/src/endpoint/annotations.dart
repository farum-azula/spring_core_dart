import 'package:spring_boot_actuator/src/endpoint/operation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Marks a bean as an actuator endpoint: something the running application
/// tells about itself (its health, its version, its mappings), under the
/// endpoint's [id].
///
/// The endpoint's methods marked [ReadOperation] are its operations. The
/// actuator starter makes each endpoint that is enabled
/// (`management.endpoint.<id>.enabled`) and exposed
/// (`management.endpoints.web.exposure.include`) answer
/// `GET /actuator/<id>`; a parameter marked [Selector] becomes a path
/// segment after it, the other parameters query parameters. Like
/// [Component], it declares the bean: the class must be under a scanned
/// directory.
///
/// ```dart
/// // GET /actuator/features and GET /actuator/features/{name}
/// @Endpoint(id: 'features')
/// class FeaturesEndpoint {
///   FeaturesEndpoint(this.flags);
///   final FeatureFlags flags;
///
///   @ReadOperation()
///   Map<String, bool> features() => flags.all;
///
///   @ReadOperation()
///   bool? feature(@Selector() String name) => flags.all[name];
/// }
/// ```
///
/// Spring Boot (Java):
/// ```java
/// @Component
/// @Endpoint(id = "features")
/// class FeaturesEndpoint {
///   @ReadOperation
///   Map<String, Boolean> features() { ... }
///
///   @ReadOperation
///   Boolean feature(@Selector String name) { ... }
/// }
/// ```
class Endpoint extends Component {
  /// Declares the endpoint [id]; [name] replaces the bean name.
  const Endpoint({required this.id, this.enableByDefault = true, String? name})
    : super(name);

  /// The endpoint's id, its path segment under the base path: letters and
  /// digits, starting with a letter (`health`, `features`).
  final String id;

  /// Whether the endpoint is enabled when neither
  /// `management.endpoint.<id>.enabled` nor
  /// `management.endpoints.enabled-by-default` is set.
  final bool enableByDefault;
}

/// Marks a bean that replaces the operations of an endpoint over HTTP,
/// with what only HTTP has: a status code ([WebEndpointResponse]) and the
/// user of the request ([SecurityContext]).
///
/// Its [ReadOperation] methods replace the endpoint's methods of the same
/// shape (the same selectors); the endpoint's other methods stay. The
/// health endpoint has one: `HealthEndpointWebExtension` answers `503`
/// when the application is down.
///
/// ```dart
/// @EndpointWebExtension(endpoint: FeaturesEndpoint)
/// class FeaturesWebExtension {
///   @ReadOperation()
///   WebEndpointResponse<Map<String, bool>> features(SecurityContext user) =>
///       user.principal == null
///           ? const WebEndpointResponse(status: 404)
///           : WebEndpointResponse(body: flags.all);
/// }
/// ```
///
/// Spring Boot (Java): `@EndpointWebExtension(endpoint = ...)`.
class EndpointWebExtension extends Component {
  /// Declares the extension of [endpoint], the class of an [Endpoint]
  /// bean; [name] replaces the bean name.
  const EndpointWebExtension({required this.endpoint, String? name})
    : super(name);

  /// The class of the extended endpoint bean.
  final Type endpoint;
}

/// Marks a method of an [Endpoint] (or [EndpointWebExtension]) bean as a
/// read operation: `GET` over HTTP.
///
/// Its parameters are filled from the request: a [Selector] parameter from
/// the path, a [SecurityContext] or [ApiVersion] parameter from the
/// request itself, any other parameter from the query parameter of its
/// name (converted to its type; a missing one is `null` when the
/// parameter allows it, else the request is answered `400`). The result is
/// written as JSON; `null` answers `404`.
///
/// ```dart
/// @ReadOperation()
/// Future<Report> report({String? since}) => reports.since(since);
/// ```
///
/// Spring Boot (Java): `@ReadOperation`.
@BeanMethodAnnotation()
class ReadOperation {
  /// Marks a read operation; [produces] replaces the media types it
  /// answers with (by default the actuator's JSON types).
  const ReadOperation({this.produces = const []});

  /// The media types of the answer; empty for the actuator's JSON types.
  final List<String> produces;
}

/// How many path segments a [Selector] parameter takes.
///
/// Spring Boot (Java): `Selector.Match`.
enum SelectorMatch {
  /// One segment: `/actuator/caches/{name}`.
  single,

  /// Every remaining segment, as a `List<String>`:
  /// `/actuator/health/{*path}`.
  allRemaining,
}

/// Marks a parameter of an operation as a path segment: the operation of a
/// method with a `@Selector() String name` answers
/// `/actuator/<id>/{name}`.
///
/// ```dart
/// @ReadOperation()
/// Health? component(@Selector(match: SelectorMatch.allRemaining)
///     List<String> path) => ...;
/// ```
///
/// Spring Boot (Java): `@Selector`.
class Selector {
  /// Marks the parameter; [match] says how many segments it takes.
  const Selector({this.match = SelectorMatch.single});

  /// One segment, or all the remaining ones.
  final SelectorMatch match;
}
