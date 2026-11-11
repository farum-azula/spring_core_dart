// What a start the daemon refuses leaves behind, against a fake daemon (an
// HTTP server of the test) and a fake reaper: no Docker needed, and no
// container is started.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_test/containers.dart';
import 'package:test/test.dart';

/// A daemon of the test's own. It has every image, creates and starts the
/// reaper's container (the first that is created) at [reaperPort], and
/// answers the creation of a network or of any other container as
/// [refuse] says.
final class _FakeDaemon {
  _FakeDaemon._(this.server, this.reaperPort);

  static Future<_FakeDaemon> start({int reaperPort = 0}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final daemon = _FakeDaemon._(server, reaperPort);
    server.listen(daemon._answer);
    addTearDown(() => server.close(force: true));
    return daemon;
  }

  final HttpServer server;
  final int reaperPort;

  /// Every request but the pings, as `METHOD path`.
  final List<String> requests = [];

  /// Whether the creation of a network (`networks`) or of a container
  /// that is not the reaper's (`containers`) is refused with a 500.
  bool Function(String what) refuse = (_) => false;

  var _containers = 0;
  var _networks = 0;

  DockerClient client() {
    final docker = DockerClient(DockerEndpoint.tcp('127.0.0.1', server.port));
    addTearDown(docker.close);
    return docker;
  }

  int count(String request) => requests.where((r) => r == request).length;

  Future<void> _answer(HttpRequest request) async {
    await request.drain<void>();
    final path = request.uri.path;
    final response = request.response;
    void json(Object body, {int status = 200}) => response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    if (path == '/_ping') {
      response.write('OK');
      await response.close();
      return;
    }
    requests.add('${request.method} $path');
    switch ((request.method, path)) {
      case ('GET', final image) when image.startsWith('/images/'):
        json(<String, Object?>{});
      case ('POST', '/containers/create') when _containers++ == 0:
        json({'Id': 'reaper'});
      case ('POST', '/containers/create') when refuse('containers'):
        json({'message': 'no space left on device'}, status: 500);
      case ('POST', '/containers/create'):
        json({'Id': 'container-$_containers'});
      case ('POST', '/containers/reaper/start'):
        response.statusCode = 204;
      case ('GET', '/containers/reaper/json'):
        json({
          'Id': 'reaper',
          'State': {'Running': true, 'Status': 'running'},
          'NetworkSettings': {
            'Ports': {
              '8080/tcp': [
                {'HostIp': '127.0.0.1', 'HostPort': '$reaperPort'},
              ],
            },
          },
        });
      case ('POST', '/networks/create') when refuse('networks'):
        json({'message': 'could not find an available subnet'}, status: 500);
      case ('POST', '/networks/create'):
        json({'Id': 'network-${++_networks}'});
      case ('DELETE', final network) when network.startsWith('/networks/'):
        response.statusCode = 204;
      default:
        json({'message': 'not in the fake daemon'}, status: 404);
    }
    await response.close();
  }
}

/// A reaper of the test's own: it ACKs the label of every connection and
/// says when one ends.
final class _FakeReaper {
  _FakeReaper._(this.server);

  static Future<_FakeReaper> start() async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final reaper = _FakeReaper._(server);
    server.listen((connection) {
      reaper._open.add(connection);
      connection.listen(
        (data) {
          if (!reaper.registered.isCompleted) {
            reaper.registered.complete();
          }
          connection.add(utf8.encode('ACK\n'));
        },
        onError: (Object _) => reaper._ended(),
        onDone: reaper._ended,
      );
    });
    addTearDown(() async {
      for (final connection in reaper._open) {
        connection.destroy();
      }
      await server.close();
    });
    return reaper;
  }

  final ServerSocket server;
  final _open = <Socket>[];

  /// Done when a run has registered its label.
  final registered = Completer<void>();

  /// Done when the run's connection has ended.
  final released = Completer<void>();

  void _ended() {
    if (!released.isCompleted) {
      released.complete();
    }
  }
}

Future<String> _packageRoot() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:spring_boot_starter_test/containers.dart'),
  );
  return File.fromUri(lib!).parent.parent.path;
}

void main() {
  group('Network, when the daemon refuses its creation', () {
    test('the failure is not remembered: the next call creates it', () async {
      final daemon = await _FakeDaemon.start();
      final docker = daemon.client();
      final network = Network.newNetwork();
      daemon.refuse = (_) => true;
      await expectLater(
        network.create(docker),
        throwsA(
          isA<DockerException>().having(
            (e) => e.message,
            'message',
            contains('available subnet'),
          ),
        ),
      );
      expect(network.isCreated, isFalse);
      daemon.refuse = (_) => false;
      expect(await network.create(docker), 'network-1');
      expect(network.isCreated, isTrue);
      // Created once from then on.
      expect(await network.create(docker), 'network-1');
      expect(daemon.count('POST /networks/create'), 2);
      await network.close();
      expect(daemon.requests.last, 'DELETE /networks/network-1');
      expect(network.isCreated, isFalse);
    });

    test('those who asked together get the one failure', () async {
      final daemon = await _FakeDaemon.start();
      final docker = daemon.client();
      final network = Network.newNetwork();
      daemon.refuse = (_) => true;
      final first = network.create(docker);
      final second = network.create(docker);
      await expectLater(first, throwsA(isA<DockerException>()));
      await expectLater(second, throwsA(isA<DockerException>()));
      expect(daemon.count('POST /networks/create'), 1);
    });

    test('close does nothing, and does not throw the failure again', () async {
      final daemon = await _FakeDaemon.start();
      final docker = daemon.client();
      final network = Network.newNetwork();
      daemon.refuse = (_) => true;
      await expectLater(network.create(docker), throwsA(anything));
      await network.close();
      await network.close();
      expect(daemon.requests, ['POST /networks/create']);
    });

    test('close while the creation fails does not throw either', () async {
      final daemon = await _FakeDaemon.start();
      final docker = daemon.client();
      final network = Network.newNetwork();
      daemon.refuse = (_) => true;
      final creating = network.create(docker);
      final closing = network.close();
      await expectLater(creating, throwsA(isA<DockerException>()));
      await closing;
      expect(daemon.requests, ['POST /networks/create']);
      // And the network can be asked for again.
      daemon.refuse = (_) => false;
      expect(await network.create(docker), 'network-1');
    });

    test('close of a network never created asks the daemon nothing', () async {
      await Network.newNetwork().close();
    });
  });

  group('a start the daemon refuses releases the reaper', () {
    // In a process of its own: the runtime finds its daemon in DOCKER_HOST.
    Future<void> refused(String what, String message) async {
      final reaper = await _FakeReaper.start();
      final daemon = await _FakeDaemon.start(reaperPort: reaper.server.port)
        ..refuse = (asked) => asked == what;
      final child = await Process.start(
        Platform.resolvedExecutable,
        [
          'run',
          'test/containers/support/failing_start.dart',
          if (what == 'networks') 'network' else 'container',
        ],
        workingDirectory: await _packageRoot(),
        environment: {
          'DOCKER_HOST': 'tcp://127.0.0.1:${daemon.server.port}',
          'TESTCONTAINERS_RYUK_DISABLED': 'false',
        },
      );
      var exited = false;
      unawaited(child.exitCode.then((_) => exited = true));
      addTearDown(() => child.kill(ProcessSignal.sigkill));
      final errors = StringBuffer();
      child.stderr.transform(utf8.decoder).listen(errors.write);
      final outcome = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(
            const Duration(minutes: 2),
            onTimeout: () => fail('The child said nothing:\n$errors'),
          );
      expect(outcome, allOf(startsWith('FAILED '), contains(message)));
      expect(reaper.registered.isCompleted, isTrue, reason: '$errors');
      // The connection to the reaper ends though the process lives on.
      await reaper.released.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail(
          'The reaper is still connected after the failed start: '
          '${daemon.requests}',
        ),
      );
      expect(exited, isFalse, reason: '$errors');
      expect(
        daemon.requests,
        isNot(contains(startsWith('DELETE /containers/'))),
      );
    }

    test(
      'when the network cannot be created',
      () => refused('networks', 'available subnet'),
    );

    test(
      'when the container cannot be created',
      () => refused('containers', 'no space left'),
    );
  });
}
