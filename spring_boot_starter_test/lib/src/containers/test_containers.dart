import 'dart:io';

import 'package:spring_boot_starter_test/src/containers/docker_endpoint.dart';
import 'package:spring_boot_starter_test/src/containers/generic_container.dart';
import 'package:spring_boot_starter_test/src/dynamic_property_registry.dart';

/// The containers of a test class: what the generated code of a class with
/// `@Container()` fields calls.
///
/// [start] starts the containers one after the other, in the order of the
/// fields, before the class's context (and stops those already started
/// when one fails); [stop] removes them in reverse order after the context
/// closed. [registerConnections] adds the properties of the
/// `@ServiceConnection()` containers to the context's dynamic properties,
/// which win over every other source. [skipReason] decides whether the
/// class runs at all.
///
/// A test written as functions uses it the same way, or starts its
/// `GenericContainer` in `setUpAll` by hand:
///
/// ```dart
/// void main() {
///   final postgres = PostgresContainer();
///   final containers = TestContainers({'postgres': postgres},
///       serviceConnections: {'postgres'});
///   setUpAll(containers.start);
///   tearDownAll(containers.stop);
///   final app = springBootTest(springApplication,
///       dynamicProperties: containers.registerConnections);
///   // ...
/// }
/// ```
///
/// Spring: `TestcontainersExtension` of `@Testcontainers`, and the
/// `ContainerConnectionDetailsFactory`s behind `@ServiceConnection`.
final class TestContainers {
  /// The containers by name (`Class.field`, for the error messages), and
  /// the names of those that are service connections.
  const TestContainers(
    this.containers, {
    this.serviceConnections = const {},
  });

  /// The containers to start, by name, in order.
  final Map<String, Object?> containers;

  /// The names of the [containers] whose connection properties are put
  /// into the context.
  final Set<String> serviceConnections;

  /// Whether `CONTAINERS_REQUIRED=true` is set: a missing Docker fails the
  /// tests instead of skipping them. Set it in CI.
  static bool get required =>
      (Platform.environment['CONTAINERS_REQUIRED'] ?? '').toLowerCase() ==
      'true';

  /// Why tests that need containers cannot run here, or `null` when they
  /// can: no Docker socket found.
  ///
  /// It is `null` when `CONTAINERS_REQUIRED=true` (the tests then fail with
  /// the real error) or [skipWithoutDocker] is `false`. It only looks for
  /// the daemon's socket, so a daemon that is down behind a stale socket
  /// fails the start of the containers. Pass it as `skip:` of a `group` or
  /// `test`.
  static String? skipReason({bool skipWithoutDocker = true}) {
    if (required || !skipWithoutDocker) {
      return null;
    }
    final reason = DockerEndpoint.unavailableReason();
    return reason == null
        ? null
        : 'Docker is not available ($reason); set CONTAINERS_REQUIRED=true '
              'to fail instead of skipping';
  }

  GenericContainer _container(String name) => switch (containers[name]) {
    final GenericContainer container => container,
    final other => throw StateError(
      '@Container field $name must hold a GenericContainer (or a module '
      'such as PostgresContainer), not ${other?.runtimeType}',
    ),
  };

  /// Starts every container, in order. When one fails, the ones started
  /// are stopped and the error is rethrown.
  Future<void> start() async {
    final started = <GenericContainer>[];
    try {
      for (final name in containers.keys) {
        final container = _container(name);
        await container.start();
        started.add(container);
      }
    } on Object {
      for (final container in started.reversed) {
        await container.stop();
      }
      rethrow;
    }
  }

  /// Removes every container, in reverse order; all are tried, and the
  /// first error is rethrown at the end.
  Future<void> stop() async {
    Object? first;
    StackTrace? trace;
    for (final name in containers.keys.toList().reversed) {
      try {
        await _container(name).stop();
      } on Object catch (error, stackTrace) {
        first ??= error;
        trace ??= stackTrace;
      }
    }
    if (first != null) {
      Error.throwWithStackTrace(first, trace!);
    }
  }

  /// Adds the connection properties of the service connections to
  /// [registry]: each is read when the application asks for it, so it sees
  /// the mapped ports of the running container.
  void registerConnections(DynamicPropertyRegistry registry) {
    for (final name in serviceConnections) {
      final container = _container(name);
      if (container is! ServiceConnectionProperties) {
        throw StateError(
          '@ServiceConnection on $name: ${container.runtimeType} cannot say '
          'how to connect to it (PostgresContainer and KeycloakContainer '
          'can). Implement ServiceConnectionProperties, or set the '
          'properties in a @DynamicPropertySource method.',
        );
      }
      final source = container as ServiceConnectionProperties;
      for (final property in source.connectionProperties.keys) {
        registry.add(property, () => source.connectionProperties[property]);
      }
    }
  }
}
