// The connection to the reaper against a fake reaper that ACKs and then cuts
// the connection: nothing that happens to the socket may reach the test as
// an uncaught error (package:test fails the running test on one), and the
// run registers again. No Docker needed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_test/containers.dart';
import 'package:spring_boot_starter_test/src/containers/reaper_connection.dart';
import 'package:test/test.dart';

/// A reaper of the test's own: it ACKs every label and then does what
/// `onRegistered` says.
final class _FakeReaper {
  _FakeReaper._(this.server);

  static Future<_FakeReaper> start({
    void Function(Socket connection, int number)? onRegistered,
    bool acknowledge = true,
    bool readLabel = true,
  }) async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final reaper = _FakeReaper._(server);
    server.listen((connection) {
      final number = ++reaper.connections;
      reaper.open.add(connection);
      void registered() {
        Timer(const Duration(milliseconds: 50), () {
          onRegistered?.call(connection, number);
        });
      }

      if (readLabel) {
        connection.listen(
          (data) {
            reaper.labels.add(utf8.decode(data).trim());
            if (acknowledge) {
              connection.add(utf8.encode('ACK\n'));
            }
            registered();
          },
          onError: (Object _) {},
        );
      } else {
        // Never reads the label: the data stays unread in the socket, so
        // closing the connection resets it (a FIN would not).
        if (acknowledge) {
          connection.add(utf8.encode('ACK\n'));
        }
        registered();
      }
    });
    addTearDown(reaper.close);
    return reaper;
  }

  final ServerSocket server;
  final List<Socket> open = [];
  final List<String> labels = [];
  int connections = 0;

  int get port => server.port;

  Future<void> close() async {
    for (final connection in open) {
      connection.destroy();
    }
    await server.close();
  }
}

Future<void> _until(bool Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason ?? 'the condition did not hold within 5 s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 300));

ReaperConnection _connection(_FakeReaper reaper) {
  final connection = ReaperConnection(
    '127.0.0.1',
    reaper.port,
    'label=org.testcontainers.sessionId=abc',
  );
  addTearDown(connection.close);
  return connection;
}

void main() {
  test('registers the label and stays connected', () async {
    final reaper = await _FakeReaper.start();
    final connection = _connection(reaper);
    await connection.open(seconds: 5);
    expect(connection.isConnected, isTrue);
    expect(reaper.labels, ['label=org.testcontainers.sessionId=abc']);
    await _settle();
    expect(connection.isConnected, isTrue);
    expect(reaper.connections, 1);
  });

  test('a reset of the connection is no uncaught error, and it registers '
      'again in the background', () async {
    // Only the first connection is reset; the second stays.
    final reaper = await _FakeReaper.start(
      readLabel: false,
      onRegistered: (connection, number) {
        if (number == 1) {
          connection.destroy();
        }
      },
    );
    final connection = _connection(reaper);
    await connection.open(seconds: 5);
    await _until(() => reaper.connections == 2, reason: 'no new connection');
    await _until(() => connection.isConnected);
    await _settle(); // a late error of the cut socket would fail the test
  });

  test('a connection the reaper closes is registered again', () async {
    final reaper = await _FakeReaper.start(
      onRegistered: (connection, number) {
        if (number == 1) {
          unawaited(connection.close());
        }
      },
    );
    final connection = _connection(reaper);
    await connection.open(seconds: 5);
    await _until(() => reaper.connections == 2);
    await _until(() => connection.isConnected);
    await _settle();
  });

  test('open after a loss connects again', () async {
    var cutting = true;
    final reaper = await _FakeReaper.start(
      readLabel: false,
      onRegistered: (connection, number) {
        if (cutting) {
          connection.destroy();
        }
      },
    );
    final connection = _connection(reaper);
    await connection.open(seconds: 5);
    await _until(() => reaper.connections >= 4);
    await _settle();
    expect(connection.isConnected, isFalse);
    cutting = false;
    await connection.open(seconds: 5);
    expect(connection.isConnected, isTrue);
    await _settle();
    expect(connection.isConnected, isTrue);
  });

  test('close ends the connection without registering again', () async {
    final reaper = await _FakeReaper.start();
    final connection = _connection(reaper);
    await connection.open(seconds: 5);
    connection.close();
    expect(connection.isConnected, isFalse);
    await _settle();
    expect(reaper.connections, 1);
  });

  test('a reaper that never answers is an error of open, not a hang', () async {
    final reaper = await _FakeReaper.start(acknowledge: false);
    final connection = _connection(reaper);
    await expectLater(
      connection.open(seconds: 1),
      throwsA(isA<DockerException>()),
    );
    expect(connection.isConnected, isFalse);
    await _settle();
  });

  test('a reaper that is not there is an error of open', () async {
    final probe = await ServerSocket.bind('127.0.0.1', 0);
    final port = probe.port;
    await probe.close();
    final connection = ReaperConnection('127.0.0.1', port, 'label=x=y');
    addTearDown(connection.close);
    await expectLater(
      connection.open(seconds: 1),
      throwsA(isA<DockerException>()),
    );
  });
}
