// The Docker client against the real daemon. Skipped without Docker (and a
// failure with CONTAINERS_REQUIRED=true).
@Tags(['docker'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_test/containers.dart';
import 'package:test/test.dart';

import 'support/docker_support.dart';

const _image = 'busybox:1.37';
const _labels = {'spring.test.owner': 'docker-client-test'};

void main() {
  late DockerClient docker;

  setUp(() async {
    docker = await dockerClient();
    if (!await docker.imageExists(_image)) {
      await docker.pullImage(_image);
    }
  });

  Future<String> create(DockerContainerConfig config) async {
    final id = await docker.createContainer(config);
    removeAfter(docker, id);
    return id;
  }

  DockerContainerConfig busybox(
    List<String> command, {
    List<int> ports = const [],
  }) => DockerContainerConfig(
    image: _image,
    command: command,
    labels: _labels,
    exposedPorts: ports,
    publishIp: '127.0.0.1',
  );

  test('ping and version', () async {
    await docker.ping();
    final version = await docker.version();
    expect(version['Version'], isA<String>());
    expect(version['ApiVersion'], isA<String>());
  }, skip: dockerSkip);

  test('imageExists tells a local image from one that is not', () async {
    expect(await docker.imageExists(_image), isTrue);
    expect(await docker.imageExists('spring-test/not-there:0'), isFalse);
  }, skip: dockerSkip);

  test("pulling a missing image fails with the daemon's reason", () async {
    await expectLater(
      docker.pullImage('spring-test-missing/nothing-here:1'),
      throwsA(
        isA<DockerException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains(
              "Cannot pull the image 'spring-test-missing/nothing-here:1'",
            ),
            anyOf(contains('repository does not exist'), contains('denied')),
          ),
        ),
      ),
    );
  }, skip: dockerSkip);

  test('create, start, inspect, logs, exec, list and remove', () async {
    final id = await create(
      busybox(
        [
          'sh',
          '-c',
          'echo to-stdout; echo to-stderr >&2; sleep 60',
        ],
        ports: [8080],
      ),
    );
    expect((await docker.inspectContainer(id)).running, isFalse);

    await docker.startContainer(id);
    final state = await docker.inspectContainer(id);
    expect(state.running, isTrue);
    expect(
      state.labels,
      containsPair('spring.test.owner', 'docker-client-test'),
    );
    expect(state.mappedPort(8080), isPositive); // a random host port
    expect(state.health, isNull); // busybox has no HEALTHCHECK

    // Output of both channels, line by line.
    var logs = await docker.containerLogs(id).toList();
    for (var i = 0; i < 50 && logs.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      logs = await docker.containerLogs(id).toList();
    }
    expect(
      logs.map((l) => '${l.stream.name}:${l.text}'),
      unorderedEquals([
        'stdout:to-stdout',
        'stderr:to-stderr',
      ]),
    );

    final result = await docker.exec(id, [
      'sh',
      '-c',
      'echo hi; echo oops >&2; exit 3',
    ]);
    expect(result.exitCode, 3);
    expect(result.stdout, 'hi');
    expect(result.stderr, 'oops');

    final listed = await docker.listContainers(
      labels: ['spring.test.owner=docker-client-test'],
    );
    expect(listed.map((c) => c.id), contains(id));
    expect(listed.firstWhere((c) => c.id == id).state, 'running');

    await docker.removeContainer(id);
    await expectLater(
      docker.inspectContainer(id),
      throwsA(
        isA<DockerException>().having((e) => e.statusCode, 'status', 404),
      ),
    );
    // Removing again, or stopping what is gone, is not an error.
    await docker.removeContainer(id);
    await docker.stopContainer(id);
  }, skip: dockerSkip);

  test('logs follow a container until it stops', () async {
    final id = await create(
      busybox(['sh', '-c', 'echo one; sleep 1; printf two']), // no line break
    );
    await docker.startContainer(id);
    final lines = await docker
        .containerLogs(id, follow: true)
        .map((l) => l.text)
        .toList();
    expect(lines, ['one', 'two']);
    expect((await docker.inspectContainer(id)).exitCode, 0);
  }, skip: dockerSkip);

  test('files are copied in before the container starts', () async {
    final id = await create(
      busybox(['sh', '-c', 'cat /etc/app/config.json; ls -l /etc/app/run.sh']),
    );
    await docker.putFiles(id, [
      TarFile('/etc/app/config.json', utf8.encode('{"a":1}')),
      TarFile('/etc/app/run.sh', utf8.encode('echo'), mode: 0x1ED),
    ]);
    await docker.startContainer(id);
    final logs = (await docker.containerLogs(id, follow: true).toList())
        .map((l) => l.text)
        .join('\n');
    expect(logs, contains('{"a":1}'));
    expect(logs, contains('-rwxr-xr-x')); // the mode 0755 of the tar header
  }, skip: dockerSkip);

  test('stopContainer stops a running container', () async {
    final id = await create(busybox(['sleep', '60']));
    await docker.startContainer(id);
    await docker.stopContainer(id, timeout: Duration.zero);
    expect((await docker.inspectContainer(id)).running, isFalse);
  }, skip: dockerSkip);

  test("the daemon's message comes with its status", () async {
    await expectLater(
      docker.startContainer('no-such-container'),
      throwsA(
        isA<DockerException>()
            .having((e) => e.statusCode, 'status', 404)
            .having((e) => e.message, 'message', contains('No such container')),
      ),
    );
    await expectLater(
      docker.createContainer(
        const DockerContainerConfig(image: 'spring-test/not-there:0'),
      ),
      throwsA(
        isA<DockerException>().having((e) => e.statusCode, 'status', 404),
      ),
    );
  }, skip: dockerSkip);

  test('a published port answers on the loopback interface', () async {
    final id = await create(
      busybox(['sh', '-c', 'echo ok | nc -l -p 8080'], ports: [8080]),
    );
    await docker.startContainer(id);
    final port = (await docker.inspectContainer(id)).mappedPort(8080)!;
    final line = await _readLine(port);
    expect(line, 'ok');
  }, skip: dockerSkip);
}

Future<String> _readLine(int port) async {
  for (var i = 0; i < 50; i++) {
    try {
      final socket = await Socket.connect('127.0.0.1', port);
      final text = await utf8.decodeStream(socket);
      if (text.isNotEmpty) {
        return text.trim();
      }
    } on SocketException {
      // not listening yet
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('nothing answered on port $port');
}
