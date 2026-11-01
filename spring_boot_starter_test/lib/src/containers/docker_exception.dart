/// An error of the Docker daemon, or a failure to talk to it: the daemon's
/// own message is [message].
///
/// Every call of the `DockerClient` throws it when the daemon answers with
/// an error (an unknown image, a name in use, a port already taken), so a
/// test fails with what `docker` itself would have printed.
///
/// Testcontainers (Java): `com.github.dockerjava.api.exception.DockerException`
/// (the docker-java client's), and `ContainerLaunchException` for a
/// container that did not start.
class DockerException implements Exception {
  /// An error with the daemon's [message]; [statusCode] is the HTTP status
  /// it answered with, when it did.
  DockerException(this.message, {this.statusCode});

  /// What the daemon said, or what went wrong on the way to it.
  final String message;

  /// The HTTP status of the daemon's answer, or `null` for an error that
  /// was not an answer (the connection failed, a pull stream reported an
  /// error).
  final int? statusCode;

  @override
  String toString() => 'DockerException: $message';
}

/// No Docker daemon could be reached: its socket does not exist, nothing
/// listens on it, or the platform is not supported yet (Windows' named
/// pipe).
///
/// Tests that need Docker are skipped when it is missing, or fail with this
/// error when `CONTAINERS_REQUIRED=true` is set.
///
/// Testcontainers (Java): `IllegalStateException: Could not find a valid
/// Docker environment`.
final class DockerUnavailableException extends DockerException {
  /// Docker is unavailable for [message].
  DockerUnavailableException(super.message);
}

/// A container that started but did not become ready: it exited, its
/// health check failed, or its wait strategy timed out. The message ends
/// with the last lines it printed.
///
/// Testcontainers (Java): `ContainerLaunchException`.
final class ContainerLaunchException extends DockerException {
  /// A container that did not become ready, for [message].
  ContainerLaunchException(super.message);
}
