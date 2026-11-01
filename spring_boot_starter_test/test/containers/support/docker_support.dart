// What the tests that talk to Docker share: the reason to skip without it,
// and a way to remove what a test made.
import 'package:spring_boot_starter_test/containers.dart';
import 'package:test/test.dart';

/// Why the Docker tests are skipped, or `null` when they run.
final String? dockerSkip = TestContainers.skipReason();

/// A client of the daemon for the test, closed with it.
Future<DockerClient> dockerClient() async {
  final client = await DockerClient.connect();
  addTearDown(client.close);
  return client;
}

/// Removes the container [id] when the test ends, whatever happens.
void removeAfter(DockerClient docker, String id) =>
    addTearDown(() => docker.removeContainer(id));
