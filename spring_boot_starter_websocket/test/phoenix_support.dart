// What the Phoenix tests share: a server played on a mock connection, in
// the second wire format.
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

/// Lets the microtasks and timers that are due run.
Future<void> pump([int times = 5]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The server side of one mock connection: reads the frames the client
/// sent, `[join_ref, ref, topic, event, payload]`, and answers them.
final class PhoenixServer {
  PhoenixServer(this.socket);

  /// The next connection the client opens.
  static Future<PhoenixServer> next(MockWebSocketTransport sockets) async =>
      PhoenixServer(await sockets.nextConnection);

  final MockWebSocket socket;
  var _read = 0;

  /// Every frame the client sent on this connection.
  List<List<Object?>> get frames => [
    for (final frame in socket.sentJson) frame! as List<Object?>,
  ];

  /// The frames of [event].
  List<List<Object?>> framesOf(String event) => [
    for (final frame in frames)
      if (frame[3] == event) frame,
  ];

  /// The next frame of [event] that no earlier call returned, waiting for
  /// it; frames of other events before it are skipped.
  Future<List<Object?>> take(String event) async {
    for (var i = 0; i < 500; i++) {
      final sent = frames;
      while (_read < sent.length) {
        final frame = sent[_read++];
        if (frame[3] == event) {
          return frame;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    fail('the client sent no $event: $frames');
  }

  /// Answers [frame] with [status] and [response].
  void reply(
    List<Object?> frame, {
    String status = 'ok',
    Object? response = const <String, Object?>{},
  }) => socket.pushJson([
    frame[0],
    frame[1],
    frame[2],
    'phx_reply',
    {'status': status, 'response': response},
  ]);

  /// Waits for the next join and accepts it; gives its frame.
  Future<List<Object?>> acceptJoin({
    Object? response = const <String, Object?>{},
  }) async {
    final join = await take('phx_join');
    reply(join, response: response);
    await pump();
    return join;
  }

  /// Sends [event] on [topic], as a broadcast or for the join [joinRef].
  void send(String topic, String event, Object? payload, {Object? joinRef}) =>
      socket.pushJson([joinRef, null, topic, event, payload]);
}
