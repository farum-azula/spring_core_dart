import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_test/src/containers/docker_exception.dart';
import 'package:spring_boot_starter_test/src/containers/socket_guard.dart';

const _log = SpringLog('spring_boot_starter_test.containers.reaper');

/// The connection of a test run to its reaper (Ryuk): it registers the
/// run's label filter and stays open; its end is the signal to remove what
/// carries the label.
///
/// The connection can be cut while the run lives (the reaper restarted, a
/// port forwarder reset it): that is logged at debug level, forgotten, and
/// registered again, at once in the background and at the next [open]. The
/// containers stay protected meanwhile: the reaper waits for a reconnection
/// before it removes anything. Nothing that happens to the socket reaches
/// the test as an error.
final class ReaperConnection {
  /// A connection to the reaper at [host]:[port] that registers [label]
  /// (`key=value`).
  ReaperConnection(this.host, this.port, this.label);

  /// Where the reaper listens.
  final String host;

  /// The port the reaper listens on.
  final int port;

  /// The label filter the reaper watches, as `key=value`.
  final String label;

  Socket? _socket;
  Future<void>? _opening;
  bool _closed = false;
  int _lost = 0;

  /// Whether the reaper is connected and has acknowledged the label.
  bool get isConnected => _socket != null;

  /// Connects and registers the label unless connected; the reaper may still
  /// be starting, so a refused connection is tried again for [seconds].
  /// Throws a [DockerException] when it cannot be reached.
  Future<void> open({int seconds = 30}) {
    _closed = false;
    _lost = 0;
    if (_socket != null) {
      return Future<void>.value();
    }
    return _opening ??= _connect(seconds).whenComplete(() => _opening = null);
  }

  /// Closes the connection for good: the reaper starts its countdown.
  void close() {
    _closed = true;
    final socket = _socket;
    _socket = null;
    socket?.destroy();
  }

  Future<void> _connect(int seconds) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    Object? last;
    while (DateTime.now().isBefore(deadline)) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 2),
        );
        ignoreDoneErrors(socket);
        final acknowledged = Completer<void>();
        final text = StringBuffer();
        final connected = socket;
        var ended = false;
        socket
          ..listen(
            (data) {
              text.write(utf8.decode(data, allowMalformed: true));
              if (text.toString().contains('ACK') &&
                  !acknowledged.isCompleted) {
                acknowledged.complete();
              }
            },
            onError: (Object error) {
              if (!acknowledged.isCompleted) {
                acknowledged.completeError(error);
              }
              ended = true;
              _cut(connected, error);
            },
            onDone: () {
              if (!acknowledged.isCompleted) {
                acknowledged.completeError(
                  const SocketException('The reaper closed the connection'),
                );
              }
              ended = true;
              _cut(connected, 'closed by the reaper');
            },
          )
          ..write('$label\n');
        await acknowledged.future.timeout(const Duration(seconds: 3));
        if (ended) {
          // Cut between the ACK and now.
          throw const SocketException('The reaper closed the connection');
        }
        if (_closed) {
          socket.destroy();
          throw DockerException('The reaper connection was closed');
        }
        _socket = socket;
        return;
      } on DockerException {
        rethrow;
      } on Object catch (e) {
        last = e;
        socket?.destroy();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw DockerException('Cannot reach the reaper at $host:$port: $last');
  }

  // The connection [socket] ended or failed. If it is the registered one,
  // forget it and register again in the background.
  void _cut(Socket socket, Object reason) {
    if (!identical(_socket, socket)) {
      return; // not registered (yet), or already forgotten
    }
    _socket = null;
    socket.destroy();
    if (_closed) {
      return;
    }
    _log.debug(
      'The connection to the reaper at $host:$port ended ($reason); '
      'registering again',
    );
    // A reaper that cuts every connection must not be hammered: after three
    // cuts in a row the next [open] tries again.
    if (++_lost <= 3) {
      unawaited(_reconnect());
    }
  }

  Future<void> _reconnect() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (_closed || _socket != null) {
      return;
    }
    try {
      await (_opening ??= _connect(3).whenComplete(() => _opening = null));
    } on Object catch (e) {
      _log.debug('Registering again with the reaper failed: $e');
    }
  }
}
