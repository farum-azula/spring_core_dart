// GenericContainer and the modules on the real daemon. Skipped without
// Docker (and a failure with CONTAINERS_REQUIRED=true).
@Tags(['docker'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_test/containers.dart';
import 'package:test/test.dart';

import 'support/docker_support.dart';

const _busybox = 'busybox:1.37';

// CI runs this file twice at once (from the root and from the package): the
// labels the tests look containers up by are unique to this run, so one run
// never sees the other's containers.
final _run = '$pid-${DateTime.now().microsecondsSinceEpoch}';
const _nginx = 'nginx:1.29-alpine';

T _track<T extends GenericContainer>(T container) {
  addTearDown(container.stop);
  return container;
}

Future<int> _status(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  test(
    'starts a web server, waits for its HTTP answer and reaches it',
    () async {
      final nginx = _track(
        GenericContainer(_nginx)
            .withExposedPorts([80])
            .waitingFor(Wait.forHttp('/').forStatusCode(200)),
      );
      expect(nginx.isStarted, isFalse);
      await nginx.start();
      expect(nginx.isStarted, isTrue);
      expect(nginx.host, '127.0.0.1');
      expect(nginx.baseUrl(80), 'http://127.0.0.1:${nginx.mappedPort(80)}');
      expect(await _status(nginx.baseUrl(80)), 200);
      expect(await _status('${nginx.baseUrl(80)}/missing'), 404);
      // A port that was not published says how to publish it.
      expect(
        () => nginx.mappedPort(8080),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('withExposedPorts([8080])'),
          ),
        ),
      );
    },
    skip: dockerSkip,
  );

  test('the default wait is a listening port', () async {
    final nginx = _track(GenericContainer(_nginx).withExposedPorts([80]));
    await nginx.start();
    expect(await _status(nginx.baseUrl(80)), 200);
  }, skip: dockerSkip);

  test('environment, command, labels, copied files and the log wait', () async {
    final temp = Directory.systemTemp.createTempSync('container-test');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}/from-host.txt')
      ..writeAsStringSync('from the host');
    final container = _track(
      GenericContainer(_busybox)
          .withEnv('GREETING', 'hello')
          .withEnvironment({'NAME': 'world'})
          .withCommand([
            'sh',
            '-c',
            [
              r'echo "$GREETING $NAME"',
              'cat /data/host.txt /data/memory.txt',
              'echo',
              'echo started',
              'sleep 60',
            ].join('; '),
          ])
          .withCopyFile(file.path, '/data/host.txt')
          .withCopyContent('from memory', '/data/memory.txt')
          .withLabel('spring.test.owner', 'generic-container-test')
          .waitingFor(Wait.forLogMessage(r'started$'))
          .withStartupTimeout(const Duration(seconds: 30)),
    );
    await container.start();
    final logs = await container.getLogs();
    expect(logs, contains('hello world'));
    expect(logs, contains('from the host'));
    expect(logs, contains('from memory'));
    final docker = await dockerClient();
    final state = await docker.inspectContainer(container.containerId);
    expect(
      state.labels,
      allOf(
        containsPair('spring.test.owner', 'generic-container-test'),
        containsPair('org.testcontainers', 'true'),
        containsPair('org.testcontainers.lang', 'dart'),
        contains('org.testcontainers.sessionId'),
      ),
    );
    final exec = await container.execInContainer(['cat', '/data/memory.txt']);
    expect(exec.stdout, 'from memory');
  }, skip: dockerSkip);

  test('stop removes the container, twice is fine', () async {
    final container = GenericContainer(_busybox).withCommand(['sleep', '60']);
    await container.start();
    final id = container.containerId;
    final docker = await dockerClient();
    expect((await docker.inspectContainer(id)).running, isTrue);
    await container.stop();
    expect(container.isStarted, isFalse);
    await expectLater(
      docker.inspectContainer(id),
      throwsA(
        isA<DockerException>().having((e) => e.statusCode, 'status', 404),
      ),
    );
    await container.stop();
    // And it can start again, as a new container.
    await container.start();
    expect(container.containerId, isNot(id));
    await container.stop();
  }, skip: dockerSkip);

  test('a container that exits fails the start with its output', () async {
    final container = GenericContainer(_busybox)
        .withCommand(['sh', '-c', 'echo boom; exit 3'])
        .waitingFor(Wait.forLogMessage('never printed'));
    await expectLater(
      container.start(),
      throwsA(
        isA<ContainerLaunchException>().having(
          (e) => e.message,
          'message',
          allOf(contains('never printed'), contains('boom')),
        ),
      ),
    );
    expect(container.isStarted, isFalse);
  }, skip: dockerSkip);

  test(
    'a port wait on a container that exited reports its exit code',
    () async {
      final container = GenericContainer(_busybox)
          .withCommand(['sh', '-c', 'echo nothing listens; exit 3'])
          .withExposedPorts([8080]);
      await expectLater(
        container.start(),
        throwsA(
          isA<ContainerLaunchException>().having(
            (e) => e.message,
            'message',
            allOf(contains('exit code 3'), contains('nothing listens')),
          ),
        ),
      );
    },
    skip: dockerSkip,
  );

  test('the startup timeout removes the container', () async {
    final container = GenericContainer(_busybox)
        .withCommand(['sleep', '60'])
        .withLabel('spring.test.owner', 'startup-timeout-test-$_run')
        .waitingFor(Wait.forLogMessage('never printed'))
        .withStartupTimeout(const Duration(seconds: 2));
    await expectLater(
      container.start(),
      throwsA(
        isA<ContainerLaunchException>().having(
          (e) => e.message,
          'message',
          contains('startup timeout'),
        ),
      ),
    );
    final docker = await dockerClient();
    expect(
      await docker.listContainers(
        labels: ['spring.test.owner=startup-timeout-test-$_run'],
        all: true,
      ),
      isEmpty,
    );
  }, skip: dockerSkip);

  test('an image that does not exist is a DockerException', () async {
    final container = GenericContainer('spring-test-missing/nothing-here:1');
    await expectLater(
      container.start(),
      throwsA(
        isA<DockerException>().having(
          (e) => e.message,
          'message',
          contains('Cannot pull the image'),
        ),
      ),
    );
  }, skip: dockerSkip);

  test("Wait.forHealthcheck uses the container's health check", () async {
    final container = _track(
      GenericContainer(_busybox)
          .withCommand(['sh', '-c', 'sleep 2; touch /ready; sleep 60'])
          .withHealthCheck(
            ['CMD-SHELL', 'test -f /ready'],
            interval: const Duration(milliseconds: 500),
          )
          .waitingFor(Wait.forHealthcheck()),
    );
    final clock = Stopwatch()..start();
    await container.start();
    expect(clock.elapsed, greaterThan(const Duration(seconds: 1)));
    final docker = await dockerClient();
    expect(
      (await docker.inspectContainer(container.containerId)).health,
      'healthy',
    );
  }, skip: dockerSkip);

  test('Wait.forHealthcheck fails for an image without one', () async {
    final container = GenericContainer(_busybox)
        .withCommand(['sleep', '60'])
        .waitingFor(Wait.forHealthcheck());
    await expectLater(
      container.start(),
      throwsA(
        isA<ContainerLaunchException>().having(
          (e) => e.message,
          'message',
          contains('no HEALTHCHECK'),
        ),
      ),
    );
  }, skip: dockerSkip);

  test('PostgresContainer starts a server that accepts connections', () async {
    final postgres = _track(PostgresContainer('postgres:17'));
    await postgres.start();
    expect(
      postgres.jdbcUrl,
      'postgresql://127.0.0.1:${postgres.mappedPort(5432)}/test',
    );
    expect(postgres.connectionProperties['spring.datasource.username'], 'test');
    // The server answers its own client tool inside the container.
    final result = await postgres.execInContainer([
      'psql',
      '-U',
      'test',
      '-d',
      'test',
      '-tAc',
      'select 40 + 2',
    ]);
    expect(result.stdout, '42');
    // And the published port speaks the protocol: SSLRequest gets 'S' or 'N'.
    final socket = await Socket.connect('127.0.0.1', postgres.mappedPort(5432));
    socket.add([0, 0, 0, 8, 4, 210, 22, 47]);
    final answer = await socket.first;
    expect(utf8.decode(answer), anyOf('S', 'N'));
    socket.destroy();
  }, skip: dockerSkip);

  group('reuse', () {
    final ci = (Platform.environment['CI'] ?? '').isNotEmpty;

    GenericContainer reusable() =>
        GenericContainer(_busybox)
            .withCommand(['sleep', '120'])
            .withLabel('spring.test.owner', 'reuse-test-$_run')
            .withReuse(true);

    Future<void> removeLeftovers() async {
      final docker = await DockerClient.connect();
      for (final c in await docker.listContainers(
        labels: ['spring.test.owner=reuse-test-$_run'],
        all: true,
      )) {
        await docker.removeContainer(c.id);
      }
      docker.close();
    }

    setUp(() async {
      await removeLeftovers();
      addTearDown(removeLeftovers);
    });

    test(
      ci
          ? 'withReuse is ignored when CI is set'
          : 'a reusable container survives stop and is found again',
      () async {
        final first = reusable();
        await first.start();
        final id = first.containerId;
        final docker = await dockerClient();
        final state = await docker.inspectContainer(id);
        if (ci) {
          // Removed like any other, and carries the run id.
          expect(state.labels, contains('org.testcontainers.sessionId'));
          await first.stop();
          expect(
            await docker.listContainers(
              labels: ['spring.test.owner=reuse-test-$_run'],
              all: true,
            ),
            isEmpty,
          );
          return;
        }
        // No run id: the reaper leaves it alone. A hash of the configuration
        // finds it again.
        expect(state.labels, isNot(contains('org.testcontainers.sessionId')));
        expect(state.labels, contains('org.testcontainers.reuse.hash'));
        await first.stop();
        expect((await docker.inspectContainer(id)).running, isTrue);

        final second = reusable();
        await second.start();
        expect(second.containerId, id);
        await second.stop();

        // Another configuration is another container.
        final other = reusable().withEnv('SOMETHING', 'else');
        await other.start();
        expect(other.containerId, isNot(id));
        await other.stop();
        expect(
          await docker.listContainers(
            labels: ['spring.test.owner=reuse-test-$_run'],
          ),
          hasLength(2),
        );
      },
      skip: dockerSkip,
    );
  });
}
