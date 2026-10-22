// Local stand-ins for the three public servers, on one dart:io port, so the
// application can be tested end to end without the internet (also in CI):
//
// - JSONPlaceholder: GET /users/1, /posts?userId=1, /posts/1/comments,
//   /posts/9999 (404), POST /posts;
// - Wikimedia EventStreams: GET /v2/stream/recentchange sends events 1-3
//   and ends; the reconnect (Last-Event-ID: 3) gets events 4-6 and stays
//   open until the client leaves;
// - the echo server: a WebSocket at /echo sending back what it gets.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'fixtures.dart';

/// The servers and what they saw.
final class LocalServers {
  LocalServers._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  bool _closing = false;

  /// Starts the servers on a free port.
  static Future<LocalServers> start() async =>
      LocalServers._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  /// The base URL of JSONPlaceholder and of Wikimedia.
  String get httpUrl => 'http://127.0.0.1:${_server.port}';

  /// The address of the echo server.
  String get echoUrl => 'ws://127.0.0.1:${_server.port}/echo';

  /// `METHOD /path?query` of every HTTP request, in order.
  final requests = <String>[];

  /// The `X-Client` header of the JSONPlaceholder requests.
  final clientHeaders = <String?>[];

  /// The `User-Agent` and `Last-Event-ID` of each event stream connection.
  final streamConnections = <({String? userAgent, String? lastEventId})>[];

  /// Completes when the client closes the event stream it keeps open.
  final streamLeft = Completer<void>();

  /// The messages the echo server received.
  final echoed = <String>[];

  /// Stops the servers.
  Future<void> close() async {
    _closing = true;
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/echo' && WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) {
        echoed.add('$message');
        socket.add(message);
      });
      return;
    }
    requests.add('${request.method} ${request.uri}');
    final response = request.response;
    if (path == '/v2/stream/recentchange') {
      await _events(request, response);
      return;
    }
    clientHeaders.add(request.headers.value('X-Client'));
    void json(int status, Object? body) {
      response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
    }

    switch ((request.method, path)) {
      case ('GET', '/users/1'):
        json(200, user);
      case ('GET', '/posts') when request.uri.queryParameters['userId'] == '1':
        json(200, posts);
      case ('GET', '/posts/1/comments'):
        json(200, comments);
      case ('POST', '/posts'):
        final body = await utf8.decodeStream(request);
        json(201, created(jsonDecode(body) as Map<String, Object?>));
      default:
        json(404, <String, Object?>{});
    }
    await response.close();
  }

  Future<void> _events(HttpRequest request, HttpResponse response) async {
    final lastEventId = request.headers.value('Last-Event-ID');
    streamConnections.add((
      userAgent: request.headers.value('User-Agent'),
      lastEventId: lastEventId,
    ));
    response
      ..headers.contentType = ContentType('text', 'event-stream')
      ..bufferOutput = false;
    final first = lastEventId == null ? 1 : int.parse(lastEventId) + 1;
    for (var n = first; n < first + 3; n++) {
      // retry: a short reconnect delay, like servers ask for.
      response.write(
        'id: $n\nevent: message\nretry: 10\n'
        'data: ${jsonEncode(recentChange(n))}\n\n',
      );
    }
    if (lastEventId == null) {
      await response.close(); // the client reconnects
      return;
    }
    // Stay open (heartbeat comments) until the client leaves; write errors
    // after it left go to `done`.
    var left = false;
    unawaited(
      response.done.then(
        (_) => left = true,
        onError: (Object _) => left = true,
      ),
    );
    while (!left && !_closing) {
      response.write(':heartbeat\n\n');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (left && !streamLeft.isCompleted) {
      streamLeft.complete();
    }
  }
}
