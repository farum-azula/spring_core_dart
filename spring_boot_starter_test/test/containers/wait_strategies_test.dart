// The wait strategies against a fake container: log lines and states come
// from the test, ports from a server of the test's own. No Docker needed.
import 'dart:async';
import 'dart:io';

import 'package:spring_boot_starter_test/containers.dart';
import 'package:test/test.dart';

class _FakeContainer implements WaitTarget {
  _FakeContainer({
    this.ports = const [],
    this.timeout = const Duration(seconds: 3),
  });

  final List<int> ports;
  final Duration timeout;
  final Stopwatch _clock = Stopwatch()..start();

  /// The published port of every container port.
  final Map<int, int> mapped = {};

  /// The lines the fake container prints; close it to end the output.
  final StreamController<DockerLogLine> output = StreamController.broadcast();

  bool running = true;
  String? health;

  @override
  DockerClient get docker => throw UnimplementedError();

  @override
  String get containerId => 'fake';

  @override
  String get host => '127.0.0.1';

  @override
  List<int> get exposedPorts => ports;

  @override
  int mappedPort(int port) => mapped[port] ?? port;

  @override
  Duration get remaining => timeout - _clock.elapsed;

  @override
  Future<DockerContainerState> inspect() async => DockerContainerState(
    id: 'fake',
    running: running,
    status: running ? 'running' : 'exited',
    exitCode: running ? 0 : 3,
    health: health,
    ports: const {},
    labels: const {},
  );

  @override
  Stream<DockerLogLine> logs() => output.stream;

  @override
  Future<void> poll(
    String description,
    Future<bool> Function() check, {
    Duration interval = const Duration(milliseconds: 10),
  }) async {
    while (true) {
      final state = await inspect();
      if (!state.running) {
        throw ContainerLaunchException(
          'stopped (exit code ${state.exitCode}) before $description',
        );
      }
      if (await check()) {
        return;
      }
      if (remaining <= Duration.zero) {
        throw ContainerLaunchException('not ready: waiting for $description');
      }
      await Future<void>.delayed(interval);
    }
  }

  void print(String text, {DockerStream stream = DockerStream.stdout}) =>
      output.add(DockerLogLine(stream, text));
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  group('Wait.forLogMessage', () {
    test('is ready when the line has been printed', () async {
      final container = _FakeContainer();
      var ready = false;
      final wait = Wait.forLogMessage('ready to accept')
          .waitUntilReady(container)
          .then((_) => ready = true);
      await _settle();
      container.print('starting up');
      await _settle();
      expect(ready, isFalse);
      container.print('LOG: database ready to accept connections');
      await wait;
      expect(ready, isTrue);
    });

    test('counts matching lines, standard error included', () async {
      final container = _FakeContainer();
      var ready = false;
      final wait = Wait.forLogMessage(
        RegExp(r'ready \d'),
        2,
      ).waitUntilReady(container).then((_) => ready = true);
      await _settle();
      container
        ..print('ready 1')
        ..print('not it');
      await _settle();
      expect(ready, isFalse);
      container.print('ready 2', stream: DockerStream.stderr);
      await wait;
    });

    test('fails when the output ends before the line', () async {
      final container = _FakeContainer();
      final wait = Wait.forLogMessage('never', 2).waitUntilReady(container);
      container.print('never');
      unawaited(container.output.close());
      await expectLater(
        wait,
        throwsA(
          isA<ContainerLaunchException>().having(
            (e) => e.message,
            'message',
            allOf(contains("matching 'never'"), contains('1 seen')),
          ),
        ),
      );
    });

    test('fails at the startup timeout', () async {
      final container = _FakeContainer(
        timeout: const Duration(milliseconds: 100),
      );
      await expectLater(
        Wait.forLogMessage('never').waitUntilReady(container),
        throwsA(
          isA<ContainerLaunchException>().having(
            (e) => e.message,
            'message',
            contains('startup timeout'),
          ),
        ),
      );
    });
  });

  group('Wait.forListeningPort', () {
    test('is ready when the port accepts connections and keeps them', () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) => socket.listen((_) {}));
      final container = _FakeContainer(ports: [80])..mapped[80] = server.port;
      await Wait.forListeningPort().waitUntilReady(container);
    });

    test('waits while the connection is cut at once', () async {
      // Docker Desktop accepts and drops while nothing listens inside.
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) => socket.destroy());
      final container = _FakeContainer(
        ports: [80],
        timeout: const Duration(milliseconds: 600),
      )..mapped[80] = server.port;
      await expectLater(
        Wait.forListeningPort().waitUntilReady(container),
        throwsA(
          isA<ContainerLaunchException>().having(
            (e) => e.message,
            'message',
            contains('port 80'),
          ),
        ),
      );
    });

    test('waits for every published port', () async {
      final first = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(first.close);
      first.listen((socket) => socket.listen((_) {}));
      final probe = await ServerSocket.bind('127.0.0.1', 0);
      final lateServerPort = probe.port;
      await probe.close(); // nothing listens there yet
      final container = _FakeContainer(ports: [80, 81])
        ..mapped[80] = first.port
        ..mapped[81] = lateServerPort;
      var ready = false;
      final wait = Wait.forListeningPort()
          .waitUntilReady(container)
          .then((_) => ready = true);
      await _settle();
      expect(ready, isFalse);
      final late = await ServerSocket.bind('127.0.0.1', lateServerPort);
      addTearDown(late.close);
      late.listen((socket) => socket.listen((_) {}));
      await wait;
    });

    test('a container without ports only has to run', () async {
      await Wait.forListeningPort().waitUntilReady(_FakeContainer());
      final stopped = _FakeContainer()..running = false;
      await expectLater(
        Wait.forListeningPort().waitUntilReady(stopped),
        throwsA(
          isA<ContainerLaunchException>().having(
            (e) => e.message,
            'message',
            contains('exit code 3'),
          ),
        ),
      );
    });

    test('a container that exited fails with its exit code', () async {
      final stopped = _FakeContainer(ports: [80])..running = false;
      await expectLater(
        Wait.forListeningPort().waitUntilReady(stopped),
        throwsA(isA<ContainerLaunchException>()),
      );
    });
  });

  group('Wait.forHttp', () {
    late HttpServer server;
    final statuses = <String, int>{};

    setUp(() async {
      statuses.clear();
      server = await HttpServer.bind('127.0.0.1', 0);
      // The server is a late variable: no cascade on the assignment.
      // ignore: cascade_invocations
      server.listen((request) async {
        final response = request.response
          ..statusCode = statuses[request.uri.path] ?? 404;
        await response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('is ready on a 200 of the path, by default', () async {
      statuses['/health'] = 200;
      final container = _FakeContainer(ports: [8080])
        ..mapped[8080] = server.port;
      await Wait.forHttp('/health').waitUntilReady(container);
    });

    test('keeps asking until the status is the expected one', () async {
      final container = _FakeContainer(ports: [8080])
        ..mapped[8080] = server.port;
      statuses['/realms/neon'] = 503;
      var ready = false;
      final wait = Wait.forHttp('/realms/neon')
          .forStatusCode(204)
          .waitUntilReady(container)
          .then((_) => ready = true);
      await _settle();
      expect(ready, isFalse);
      statuses['/realms/neon'] = 204;
      await wait;
    });

    test('accepts several statuses, or a matcher', () async {
      statuses['/a'] = 302;
      final container = _FakeContainer(ports: [8080])
        ..mapped[8080] = server.port;
      await Wait.forHttp('/a')
          .forStatusCode(200)
          .forStatusCode(302)
          .waitUntilReady(container);
      statuses['/b'] = 401;
      await Wait.forHttp('/b')
          .forStatusCodeMatching((status) => status < 500)
          .waitUntilReady(container);
    });

    test('waits while nothing listens, then times out', () async {
      final probe = await ServerSocket.bind('127.0.0.1', 0);
      final closedPort = probe.port;
      await probe.close();
      final container = _FakeContainer(
        ports: [8080],
        timeout: const Duration(milliseconds: 400),
      )..mapped[8080] = closedPort;
      await expectLater(
        Wait.forHttp('/').waitUntilReady(container),
        throwsA(
          isA<ContainerLaunchException>().having(
            (e) => e.message,
            'message',
            contains('answering [200]'),
          ),
        ),
      );
    });

    test('needs a published port', () async {
      await expectLater(
        Wait.forHttp('/').waitUntilReady(_FakeContainer()),
        throwsA(isA<ContainerLaunchException>()),
      );
    });
  });

  group('Wait.forHealthcheck', () {
    test('is ready when the container turns healthy', () async {
      final container = _FakeContainer()..health = 'starting';
      var ready = false;
      final wait = Wait.forHealthcheck()
          .waitUntilReady(container)
          .then((_) => ready = true);
      await _settle();
      expect(ready, isFalse);
      container.health = 'healthy';
      await wait;
    });

    test('fails on unhealthy, and for an image without a check', () async {
      await expectLater(
        Wait.forHealthcheck().waitUntilReady(
          _FakeContainer()..health = 'unhealthy',
        ),
        throwsA(isA<ContainerLaunchException>()),
      );
      await expectLater(
        Wait.forHealthcheck().waitUntilReady(_FakeContainer()),
        throwsA(
          isA<ContainerLaunchException>().having(
            (e) => e.message,
            'message',
            contains('no HEALTHCHECK'),
          ),
        ),
      );
    });
  });

  test('Wait.forAll waits for each strategy in turn', () async {
    final container = _FakeContainer();
    final wait = Wait.forAll([
      Wait.forLogMessage('one'),
      Wait.forLogMessage('two'),
    ]).waitUntilReady(container);
    await _settle();
    container.print('one');
    await _settle();
    container.print('two');
    await wait;
  });
}
