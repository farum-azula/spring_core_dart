import 'package:spring_boot_actuator/src/endpoint/operation.dart';

/// The state of a part of the application in a health report: `UP`,
/// `DOWN`, `OUT_OF_SERVICE`, `UNKNOWN`, or a code of the application's own.
///
/// Statuses are compared by [code]; [description] says more and is shown
/// next to it.
///
/// ```dart
/// const fatal = Status('FATAL', 'The disk is gone');
/// ```
///
/// Spring Boot (Java): `Status`.
final class Status {
  /// A status of [code] with an optional [description].
  const Status(this.code, [this.description = '']);

  /// The state is not known.
  static const unknown = Status('UNKNOWN');

  /// The part works.
  static const up = Status('UP');

  /// The part does not work.
  static const down = Status('DOWN');

  /// The part works but was taken out of service on purpose.
  static const outOfService = Status('OUT_OF_SERVICE');

  /// The code: `UP`, `DOWN`, ...
  final String code;

  /// What the status means here; empty for none.
  final String description;

  @override
  bool operator ==(Object other) => other is Status && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// A node of a health report: a [Health] of one indicator, or a composite
/// of several ([CompositeHealthDescriptor]).
///
/// Spring Boot (Java): `HealthDescriptor` (Spring Boot 4; `HealthComponent`
/// in Spring Boot 2.2 to 3).
sealed class HealthDescriptor implements OperationResponseBody {
  const HealthDescriptor();

  /// The status of this node.
  Status get status;

  /// The status as JSON: `status`, and `description` when there is one.
  Map<String, Object?> statusJson() => {
    'status': status.code,
    if (status.description.isNotEmpty) 'description': status.description,
  };
}

/// The health of one part of the application: a [status] and the
/// [details] that explain it (sizes, versions, the error).
///
/// A `HealthIndicator` returns one, built with [Health.up],
/// [Health.down] and the other starting points:
///
/// ```dart
/// return Health.up().withDetail('queue', queue.length).build();
/// return Health.down().withException(error).build();
/// ```
///
/// Spring Boot (Java): `Health` and `Health.Builder`.
final class Health extends HealthDescriptor {
  /// A health of [status] with [details].
  Health(this.status, [Map<String, Object?> details = const {}])
    : details = Map.unmodifiable(details);

  @override
  final Status status;

  /// What explains the status, written as JSON under `details`; empty
  /// for none.
  final Map<String, Object?> details;

  /// A builder with the status `UP`.
  static HealthBuilder up() => HealthBuilder().up();

  /// A builder with the status `DOWN`.
  static HealthBuilder down() => HealthBuilder().down();

  /// A builder with the status `OUT_OF_SERVICE`.
  static HealthBuilder outOfService() => HealthBuilder().outOfService();

  /// A builder with the status `UNKNOWN`.
  static HealthBuilder unknown() => HealthBuilder().unknown();

  /// A builder with [status] (Spring Boot's `Health.status(...)`).
  static HealthBuilder withStatus(Status status) => HealthBuilder(status);

  /// The same health without its details (what `show-details=never`
  /// shows).
  Health withoutDetails() => details.isEmpty ? this : Health(status);

  @override
  Map<String, Object?> toJson() => {
    ...statusJson(),
    if (details.isNotEmpty) 'details': details,
  };

  @override
  String toString() => '$status $details';
}

/// Builds a [Health]: a status and details added one by one.
///
/// Spring Boot (Java): `Health.Builder`.
final class HealthBuilder {
  /// A builder with [status], `UNKNOWN` by default.
  HealthBuilder([this._status = Status.unknown]);

  Status _status;
  final _details = <String, Object?>{};

  /// Sets the status `UP`.
  HealthBuilder up() => status(Status.up);

  /// Sets the status `DOWN`.
  HealthBuilder down([Object? error]) {
    if (error != null) {
      withException(error);
    }
    return status(Status.down);
  }

  /// Sets the status `OUT_OF_SERVICE`.
  HealthBuilder outOfService() => status(Status.outOfService);

  /// Sets the status `UNKNOWN`.
  HealthBuilder unknown() => status(Status.unknown);

  /// Sets [status].
  HealthBuilder status(Status status) {
    _status = status;
    return this;
  }

  /// Sets the status of [code], such as `FATAL`.
  HealthBuilder statusCode(String code) => status(Status(code));

  /// Adds the detail [key] with [value].
  HealthBuilder withDetail(String key, Object? value) {
    _details[key] = value;
    return this;
  }

  /// Adds every entry of [details].
  HealthBuilder withDetails(Map<String, Object?> details) {
    _details.addAll(details);
    return this;
  }

  /// Adds the detail `error`: the type of [error] and its message, as
  /// Spring Boot writes `ClassName: message`.
  HealthBuilder withException(Object error) =>
      withDetail('error', '${error.runtimeType}: $error');

  /// The health built so far.
  Health build() => Health(_status, _details);
}

/// The health of several parts together: the aggregated [status] and,
/// when shown, each part's health under its name.
///
/// Written as `{"status": "UP", "components": {...}}` (under `details`
/// instead for clients of the version 2 JSON).
///
/// Spring Boot (Java): `CompositeHealthDescriptor` (Spring Boot 4;
/// `CompositeHealth` before).
class CompositeHealthDescriptor extends HealthDescriptor {
  /// A composite of [status] with [components] (`null` when hidden).
  CompositeHealthDescriptor(
    this.status,
    Map<String, HealthDescriptor>? components, {
    this.apiVersion = ApiVersion.latest,
  }) : components = components == null
           ? null
           : Map.unmodifiable({
               for (final name in components.keys.toList()..sort())
                 name: ?components[name],
             });

  @override
  final Status status;

  /// The parts by name, sorted by name (as Spring Boot's `TreeMap`);
  /// `null` when hidden
  /// (`show-components=never`).
  final Map<String, HealthDescriptor>? components;

  /// The JSON version: version 2 writes the parts under `details`.
  final ApiVersion apiVersion;

  @override
  Map<String, Object?> toJson() => {
    ...statusJson(),
    if (components case final parts? when parts.isNotEmpty)
      apiVersion == ApiVersion.v2 ? 'details' : 'components': {
        for (final MapEntry(:key, :value) in parts.entries) key: value.toJson(),
      },
  };
}

/// The health of the whole application, the root of `/actuator/health`:
/// a composite that also lists the names of the health [groups].
///
/// Spring Boot (Java): `SystemHealthDescriptor` (Spring Boot 4;
/// `SystemHealth` before).
final class SystemHealthDescriptor extends CompositeHealthDescriptor {
  /// The application's health of [status] with [components] and the
  /// [groups]' names.
  SystemHealthDescriptor(
    super.status,
    super.components, {
    List<String> groups = const [],
    super.apiVersion,
  }) : groups = List.unmodifiable([...groups]..sort());

  /// The names of the health groups, sorted; not written when empty.
  final List<String> groups;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    if (groups.isNotEmpty) 'groups': groups,
  };
}
