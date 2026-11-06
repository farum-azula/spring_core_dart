import 'dart:async';

import 'package:spring_boot_actuator/src/endpoint/annotations.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The id of an actuator endpoint (`health`, `info`), compared without
/// case, dots and dashes as Spring Boot does.
///
/// ```dart
/// EndpointId.of('health') == EndpointId.of('Health'); // true
/// ```
///
/// Spring Boot (Java): `EndpointId`.
final class EndpointId {
  EndpointId._(this.value, this._key);

  /// The id [value]: letters, digits, dots and dashes, starting with a
  /// letter. Throws an [ArgumentError] for another text.
  factory EndpointId.of(String value) {
    if (!_valid.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'An endpoint id has letters, digits, dots and dashes and starts '
            'with a letter',
      );
    }
    return EndpointId._(value, toLowerCaseKey(value));
  }

  static final _valid = RegExp(r'^[a-zA-Z][a-zA-Z0-9.\-]*$');

  /// The id as written.
  final String value;

  final String _key;

  /// The id in lower case without dots and dashes: the form of the
  /// property keys (`management.endpoint.<id>.enabled`) and comparisons.
  String toLowerCaseString() => _key;

  /// [value] in lower case without dots and dashes.
  static String toLowerCaseKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[.\-]'), '');

  @override
  bool operator ==(Object other) => other is EndpointId && other._key == _key;

  @override
  int get hashCode => _key.hashCode;

  @override
  String toString() => value;
}

/// The version of the actuator's JSON a client asked for, by its media
/// type: `application/vnd.spring-boot.actuator.v3+json` (and plain
/// `application/json`) or `...v2+json`.
///
/// It only changes the health endpoint: version 2 puts the components of a
/// composite health under `details`, version 3 under `components`.
///
/// Spring Boot (Java): `ApiVersion`.
enum ApiVersion {
  /// `application/vnd.spring-boot.actuator.v2+json`.
  v2,

  /// `application/vnd.spring-boot.actuator.v3+json`; the default.
  v3;

  /// The version a client gets when it names none.
  static const ApiVersion latest = ApiVersion.v3;

  /// The media type of the version.
  String get mediaType => 'application/vnd.spring-boot.actuator.$name+json';
}

/// The user of an operation's request, for an operation that shows more
/// to some users (the health endpoint's `show-details=when-authorized`).
///
/// A parameter of this type in a [ReadOperation] method receives it.
/// Without the security starter (or for an anonymous request) the
/// [principal] is `null`.
///
/// ```dart
/// @ReadOperation()
/// Report report(SecurityContext user) =>
///     user.isUserInRole('ADMIN') ? full : summary;
/// ```
///
/// Spring Boot (Java): `org.springframework.boot.actuate.endpoint.
/// SecurityContext`.
abstract interface class SecurityContext {
  /// A context of [principal] whose roles [roles] tells; without it, the
  /// user has no role.
  factory SecurityContext.of(
    Principal? principal, {
    PrincipalRoleChecker? roles,
  }) = _SecurityContext;

  /// No user: the context of a request without a login, and of calls that
  /// do not come over HTTP.
  static const SecurityContext none = _SecurityContext(null);

  /// The logged-in user, or `null`.
  Principal? get principal;

  /// Whether the user has [role] (`ADMIN` or `ROLE_ADMIN`).
  bool isUserInRole(String role);
}

final class _SecurityContext implements SecurityContext {
  const _SecurityContext(this.principal, {this.roles});

  @override
  final Principal? principal;

  final PrincipalRoleChecker? roles;

  @override
  bool isUserInRole(String role) {
    final user = principal;
    return user != null && (roles?.isUserInRole(user, role) ?? false);
  }
}

/// Tells whether a principal has a role, for [SecurityContext.isUserInRole].
///
/// The security starter declares one that reads the authorities of an
/// `Authentication` (`ROLE_ADMIN` for the role `ADMIN`, or the authority
/// itself); declare one to read the roles of another kind of principal.
///
/// ```dart
/// @Component()
/// class TokenRoles implements PrincipalRoleChecker {
///   @override
///   bool isUserInRole(Principal principal, String role) =>
///       principal is ApiToken && principal.scopes.contains(role);
/// }
/// ```
///
/// Spring Boot reads the roles through the request (`isUserInRole` of the
/// servlet request, the authorities in WebFlux); this interface is that
/// question without a dependency on the security starter.
abstract interface class PrincipalRoleChecker {
  /// Whether [principal] has [role].
  bool isUserInRole(Principal principal, String role);
}

/// The kind of an endpoint operation: what it does and the HTTP method it
/// answers.
///
/// Spring Boot (Java): `OperationType`.
enum OperationType {
  /// Reads: `GET`.
  read,
}

/// One parameter of an endpoint operation.
///
/// Spring Boot (Java): `OperationParameter`.
final class OperationParameter {
  /// The parameter [name] of [type]; [selector] when it is a path segment.
  const OperationParameter(
    this.name, {
    required this.type,
    this.selector,
    this.symbol,
    this.isMandatory = true,
  });

  /// The parameter's name: the query parameter it is read from.
  final String name;

  /// Its declared type.
  final TypeInfo<Object?> type;

  /// How many path segments it takes, or `null` when it is not a
  /// [Selector].
  final SelectorMatch? selector;

  /// `#name` for a named parameter; `null` for a positional one.
  final Symbol? symbol;

  /// Whether a request must give it: not nullable and without a default.
  final bool isMandatory;

  /// Whether the parameter is filled from the request itself (the user or
  /// the API version) rather than from the path or the query.
  bool get isImplicit =>
      type.type == SecurityContext || type.type == ApiVersion;
}

/// What an operation is called with: the request's user, the API version
/// and the arguments read from its path and query.
///
/// The actuator starter creates one per request; tests create one to call
/// an operation directly.
///
/// ```dart
/// final result = await operation.invoke(
///   InvocationContext(arguments: {'path': ['db']}),
/// );
/// ```
///
/// Spring Boot (Java): `InvocationContext`.
final class InvocationContext {
  /// A context for [securityContext], [apiVersion] and [arguments]
  /// (by parameter name: a `String` or `List<String>` from the request, or
  /// a value of the parameter's type).
  InvocationContext({
    this.securityContext = SecurityContext.none,
    this.apiVersion = ApiVersion.latest,
    Map<String, Object?> arguments = const {},
  }) : arguments = Map.unmodifiable(arguments);

  /// The user of the request.
  final SecurityContext securityContext;

  /// The JSON version the client asked for.
  final ApiVersion apiVersion;

  /// The arguments by parameter name.
  final Map<String, Object?> arguments;
}

/// An answer of an operation over HTTP with its own [status] (and media
/// type), for an [EndpointWebExtension] that answers more than `200`.
///
/// ```dart
/// return WebEndpointResponse(body: health, status: 503);
/// ```
///
/// Spring Boot (Java): `WebEndpointResponse<T>`.
final class WebEndpointResponse<T> {
  /// An answer of [body] with [status] (`200` by default; `404` without a
  /// body).
  const WebEndpointResponse({this.body, int? status, this.contentType})
    : status = status ?? (body == null ? notFound : ok);

  /// `200`.
  static const ok = 200;

  /// `404`.
  static const notFound = 404;

  /// `400`.
  static const badRequest = 400;

  /// `503`.
  static const serviceUnavailable = 503;

  /// The body, written as JSON; `null` for none.
  final T? body;

  /// The HTTP status.
  final int status;

  /// The media type of the answer; `null` for the one the client asked
  /// for.
  final String? contentType;
}

/// A value an operation answers that writes itself as JSON, like the
/// health and the mappings: [toJson] gives maps, lists and plain values.
///
/// Other answers are written by the application's `ObjectMapper`.
///
/// Spring Boot (Java): `OperationResponseBody`, a marker that makes
/// Jackson write the value with the actuator's own `ObjectMapper`; here the
/// value writes itself.
abstract interface class OperationResponseBody {
  /// The value as JSON: maps, lists, strings, numbers, booleans, `null`.
  Object? toJson();
}

/// Thrown when a request to an operation lacks a mandatory parameter;
/// answered `400`.
///
/// Spring Boot (Java): `MissingParametersException`.
class MissingParametersException implements Exception {
  /// The exception for the missing [parameters].
  MissingParametersException(Iterable<String> parameters)
    : parameters = List.unmodifiable(parameters);

  /// The names of the missing parameters.
  final List<String> parameters;

  @override
  String toString() =>
      'Failed to invoke operation because the following required '
      'parameters were missing: ${parameters.join(', ')}';
}

/// Thrown when an argument of a request cannot be converted to its
/// parameter's type; answered `400`.
///
/// Spring Boot (Java): `InvalidEndpointRequestException`.
class InvalidEndpointRequestException implements Exception {
  /// The exception with [message] and the short [reason] sent to the
  /// client.
  InvalidEndpointRequestException(this.message, this.reason);

  /// What went wrong, for the log.
  final String message;

  /// The reason given to the client.
  final String reason;

  @override
  String toString() => message;
}

/// One operation of an endpoint: a method that reads (or later changes)
/// something, with its parameters.
///
/// Spring Boot (Java): `Operation` (`DiscoveredOperation`).
final class EndpointOperation {
  /// An operation of [type] with [parameters], calling its invoker.
  EndpointOperation({
    required this.endpointId,
    required this.type,
    required this.name,
    required this._invoker,
    List<OperationParameter> parameters = const [],
    List<String> produces = const [],
    this.className,
  }) : parameters = List.unmodifiable(parameters),
       produces = List.unmodifiable(produces);

  /// The endpoint the operation belongs to.
  final EndpointId endpointId;

  /// What the operation does.
  final OperationType type;

  /// The method's name, for the mappings and the log.
  final String name;

  /// The name of the class whose method it is (`HealthEndpoint`), for the
  /// mappings; `null` when unknown.
  final String? className;

  /// The parameters, in declaration order.
  final List<OperationParameter> parameters;

  /// The media types it answers with; empty for the actuator's JSON.
  final List<String> produces;

  final FutureOr<Object?> Function(InvocationContext context) _invoker;

  /// The [Selector] parameters, in order: the path segments after the
  /// endpoint's path.
  List<OperationParameter> get selectors => [
    for (final parameter in parameters)
      if (parameter.selector != null) parameter,
  ];

  /// Calls the operation with the arguments of [context]. Throws a
  /// [MissingParametersException] for a missing mandatory argument and an
  /// [InvalidEndpointRequestException] for one that cannot be converted.
  Future<Object?> invoke(InvocationContext context) async =>
      await _invoker(context);

  @override
  String toString() => 'Actuator ${type.name} operation $endpointId.$name';
}

/// An endpoint with the operations it has, as the discoverer found it.
///
/// Spring Boot (Java): `ExposableEndpoint` (`ExposableWebEndpoint`).
final class ExposableEndpoint {
  /// The endpoint [id] with its [operations].
  ExposableEndpoint({
    required this.id,
    required List<EndpointOperation> operations,
    this.enableByDefault = true,
    this.beanName,
  }) : operations = List.unmodifiable(operations);

  /// The endpoint's id.
  final EndpointId id;

  /// Whether it is enabled when no property says.
  final bool enableByDefault;

  /// The operations.
  final List<EndpointOperation> operations;

  /// The name of the endpoint bean; `null` for one built in code.
  final String? beanName;

  @override
  String toString() => 'Endpoint $id';
}
