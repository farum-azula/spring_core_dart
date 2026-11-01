import 'dart:io';

/// Where the Docker daemon listens: a Unix socket or a TCP address.
///
/// [resolve] finds it the way the `docker` command does: `DOCKER_HOST`
/// (`unix:///path/docker.sock` or `tcp://host:2375`) when set, else the
/// first of the usual sockets that exists: `/var/run/docker.sock`, Docker
/// Desktop's `~/.docker/run/docker.sock`, Colima's
/// `~/.colima/default/docker.sock`, Rancher Desktop's `~/.rd/docker.sock`
/// and the rootless daemon's `$XDG_RUNTIME_DIR/docker.sock`. Windows'
/// named pipe is not supported yet (set `DOCKER_HOST=tcp://...`). TLS
/// (`DOCKER_TLS_VERIFY`) is not supported: `tcp://` is plain HTTP.
///
/// Testcontainers (Java): `DockerClientProviderStrategy`
/// (`EnvironmentAndSystemPropertyClientProviderStrategy`,
/// `UnixSocketClientProviderStrategy`, ...).
final class DockerEndpoint {
  /// The daemon behind the Unix socket at [socketPath].
  const DockerEndpoint.unix(String this.socketPath) : host = null, port = null;

  /// The daemon behind the TCP address [host]:[port].
  const DockerEndpoint.tcp(String this.host, int this.port) : socketPath = null;

  /// The path of the Unix socket, or `null` for a TCP endpoint.
  final String? socketPath;

  /// The TCP host, or `null` for a Unix socket.
  final String? host;

  /// The TCP port, or `null` for a Unix socket.
  final int? port;

  /// Whether this is a Unix socket.
  bool get isUnix => socketPath != null;

  /// The host the published ports of a container are reached on:
  /// `127.0.0.1` for a local socket (ports are published on the loopback
  /// interface only, so a test database is never open to the network), the
  /// daemon's own host for `tcp://`.
  String get containerHost => isUnix ? '127.0.0.1' : host!;

  /// The `HostIp` ports are published on: the loopback interface for a
  /// local socket, every interface for a remote daemon.
  String get publishIp => isUnix ? '127.0.0.1' : '';

  /// The sockets looked at when `DOCKER_HOST` is not set, in order.
  static List<String> candidateSockets(Map<String, String> environment) {
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    final runtime = environment['XDG_RUNTIME_DIR'];
    return [
      '/var/run/docker.sock',
      if (home != null && home.isNotEmpty) ...[
        '$home/.docker/run/docker.sock',
        '$home/.colima/default/docker.sock',
        '$home/.rd/docker.sock',
      ],
      if (runtime != null && runtime.isNotEmpty) '$runtime/docker.sock',
    ];
  }

  /// The endpoint of the daemon, or `null` with the reason in
  /// [unavailableReason] when none is configured or no socket exists.
  ///
  /// It only looks at the environment and the file system: the daemon may
  /// still be down. [environment] is the process environment by default.
  static DockerEndpoint? resolve({Map<String, String>? environment}) =>
      _resolve(environment ?? Platform.environment).$1;

  /// Why [resolve] finds no daemon, or `null` when it does.
  static String? unavailableReason({Map<String, String>? environment}) =>
      _resolve(environment ?? Platform.environment).$2;

  static (DockerEndpoint?, String?) _resolve(Map<String, String> environment) {
    final configured = environment['DOCKER_HOST'];
    if (configured != null && configured.isNotEmpty) {
      return _fromUrl(configured);
    }
    if (Platform.isWindows) {
      return (
        null,
        "Windows' named pipe is not supported yet: set DOCKER_HOST to "
            'tcp://localhost:2375 (Docker Desktop can expose the daemon '
            'there)',
      );
    }
    final candidates = candidateSockets(environment);
    for (final path in candidates) {
      if (FileSystemEntity.typeSync(path) ==
          FileSystemEntityType.unixDomainSock) {
        return (DockerEndpoint.unix(path), null);
      }
    }
    return (
      null,
      'No Docker socket found (looked at ${candidates.join(', ')}): start '
          'Docker, or set DOCKER_HOST',
    );
  }

  static (DockerEndpoint?, String?) _fromUrl(String value) {
    final uri = Uri.tryParse(value);
    switch (uri?.scheme) {
      case 'unix':
        final path = uri!.path;
        if (FileSystemEntity.typeSync(path) !=
            FileSystemEntityType.unixDomainSock) {
          return (null, 'DOCKER_HOST=$value: there is no socket at $path');
        }
        return (DockerEndpoint.unix(path), null);
      case 'tcp' || 'http':
        if (uri!.host.isEmpty) {
          return (null, 'DOCKER_HOST=$value has no host');
        }
        return (
          DockerEndpoint.tcp(uri.host, uri.hasPort ? uri.port : 2375),
          null,
        );
      default:
        return (
          null,
          'DOCKER_HOST=$value is not supported: use unix:///path or '
              'tcp://host:port',
        );
    }
  }

  @override
  String toString() => isUnix ? 'unix://$socketPath' : 'tcp://$host:$port';
}
