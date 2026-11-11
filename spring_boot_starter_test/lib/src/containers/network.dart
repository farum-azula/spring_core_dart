import 'dart:math';

import 'package:spring_boot_starter_test/src/containers/container_runtime.dart';
import 'package:spring_boot_starter_test/src/containers/docker_client.dart';

/// A Docker network of the test run: containers put on it with
/// `GenericContainer.withNetwork` reach each other by the names given
/// with `withNetworkAliases`, on the ports they listen on (not the ports
/// published to the host).
///
/// ```dart
/// static final network = Network.newNetwork();
///
/// @Container()
/// static final database = PostgresContainer('postgres:17-alpine')
///     .withNetwork(network)
///     .withNetworkAliases(['db']);
///
/// @Container()
/// static final api = GenericContainer('postgrest/postgrest:v12.2.3')
///     .withNetwork(network)
///     .withEnv('PGRST_DB_URI', 'postgres://test:test@db:5432/test')
///     .withExposedPorts([3000]);
/// ```
///
/// The network is created when its first container starts and carries
/// the run's label, so the reaper removes it with the run's containers
/// (also when the process is killed). [close] removes it sooner, once its
/// containers have stopped.
///
/// Testcontainers (Java): `Network.newNetwork()`.
final class Network {
  Network._(this.name);

  /// A network with a name of its own; nothing happens until a container
  /// on it starts.
  factory Network.newNetwork() {
    final random = Random.secure();
    final suffix = [
      for (var i = 0; i < 8; i++) random.nextInt(16).toRadixString(16),
    ].join();
    return Network._('spring-test-$suffix');
  }

  /// The network's name, as containers are created on it.
  final String name;

  Future<String>? _id;
  DockerClient? _docker;

  /// The network's id, creating it on the daemon of [docker] at the first
  /// call.
  ///
  /// A creation that fails is not remembered: who asked gets the daemon's
  /// error, and the next call tries again. One refusal of the daemon
  /// would otherwise fail every later container of the network with it.
  Future<String> create(DockerClient docker) {
    if (_id case final known?) {
      return known;
    }
    late final Future<String> creating;
    Future<String> run() async {
      try {
        return await docker.createNetwork(
          name,
          labels: ContainerRuntime.instance.labels,
        );
      } on Object {
        // Unless the network was closed and asked for again meanwhile.
        if (identical(_id, creating)) {
          _id = null;
        }
        rethrow;
      }
    }

    _docker = docker;
    return _id = creating = run();
  }

  /// Whether the network was created (and not closed since).
  bool get isCreated => _id != null;

  /// Removes the network; its containers must have stopped. A network
  /// that was never created, could not be created, or is gone, is no
  /// error.
  Future<void> close() async {
    final pending = _id;
    final docker = _docker;
    _id = null;
    if (pending == null || docker == null) {
      return;
    }
    final String id;
    try {
      id = await pending;
    } on Object {
      // Its creation was under way and failed: there is nothing to
      // remove, and who asked for the network has the error.
      return;
    }
    await docker.removeNetwork(id);
  }

  @override
  String toString() => 'Network($name)';
}
