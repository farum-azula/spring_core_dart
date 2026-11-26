// The cost the network recorder adds to a request and to a WebSocket
// frame (debug / JIT, so slower than a release build), off first: no
// wrapper (the module out of the build, or `enabled: false`), then the
// wrapper paused, then on (the timings: total, the headers of a streamed
// response, a WebSocket's handshake, frame times and heartbeat round
// trips), then on with bodies. A transport that answers at once. Not part
// of the tests (outside test/); run with
//   flutter test benchmark/network_recorder_benchmark_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

final class _Instant implements HttpTransport {
  _Instant(this.response);

  final HttpResponse response;

  @override
  Future<HttpResponse> send(HttpRequest request) async => response;

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async =>
      StreamedHttpResponse(
        response.statusCode,
        headers: response.headers,
        body: Stream.value(response.bodyBytes),
        request: request,
      );

  @override
  void close() {}
}

final class _Session implements WebSocketSession {
  @override
  Uri get uri => Uri.parse('wss://a.neon/ws');

  @override
  Stream<Object> get messages => const Stream.empty();

  @override
  String? get acceptedProtocol => null;

  @override
  bool get isOpen => true;

  @override
  void sendMessage(Object message) {}

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) async {}

  @override
  CloseStatus? get closeStatus => null;
}

final class _Sockets implements WebSocketTransport {
  @override
  Future<WebSocketSession> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
    int? maxTextMessageSize,
    int? maxBinaryMessageSize,
  }) async => _Session();
}

const _rounds = 20000;

final _request = HttpRequest(
  method: HttpMethod.get,
  url: Uri.parse('https://api.neon.books/books?page=2&access_token=t'),
  headers: HttpHeaders({
    'Authorization': 'Bearer t0k3n',
    'Accept': 'application/json',
  }),
);

Future<double> _perRequest(HttpTransport transport) async {
  for (var i = 0; i < 2000; i++) {
    await transport.send(_request);
  }
  final clock = Stopwatch()..start();
  for (var i = 0; i < _rounds; i++) {
    await transport.send(_request);
  }
  return clock.elapsedMicroseconds / _rounds;
}

Future<double> _perStream(HttpTransport transport) async {
  Future<void> one() async =>
      (await transport.stream(_request)).body.drain<void>();
  for (var i = 0; i < 2000; i++) {
    await one();
  }
  final clock = Stopwatch()..start();
  for (var i = 0; i < _rounds; i++) {
    await one();
  }
  return clock.elapsedMicroseconds / _rounds;
}

Future<double> _perFrame(WebSocketSession session, String frame) async {
  const rounds = _rounds * 10;
  for (var i = 0; i < 2000; i++) {
    session.sendMessage(frame);
  }
  final clock = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    session.sendMessage(frame);
  }
  return clock.elapsedMicroseconds / rounds;
}

void _report(String title, Map<String, double> times, {int digits = 2}) {
  stdout.writeln(title);
  for (final MapEntry(:key, :value) in times.entries) {
    stdout.writeln('  ${key.padRight(20)} ${value.toStringAsFixed(digits)} µs');
  }
}

void main() {
  final response = HttpResponse(
    200,
    headers: HttpHeaders({'Content-Type': 'application/json'}),
    body: utf8.encode('{"items":[${List.filled(200, '{"id":1}').join(',')}]}'),
  );

  DebugNetworkJournal journal({bool bodies = false, bool paused = false}) =>
      DebugNetworkJournal(bodies: bodies, schedule: (_) {})..paused = paused;

  test('an HTTP request, whole (send)', () async {
    final bare = _Instant(response);
    _report('send', {
      'off (no wrapper)': await _perRequest(bare),
      'paused': await _perRequest(
        RecordingHttpTransport(bare, journal(paused: true)),
      ),
      'on': await _perRequest(RecordingHttpTransport(bare, journal())),
      'on, bodies': await _perRequest(
        RecordingHttpTransport(bare, journal(bodies: true)),
      ),
    });
  });

  test('an HTTP request, streamed (stream, read to its end)', () async {
    final bare = _Instant(response);
    _report('stream', {
      'off (no wrapper)': await _perStream(bare),
      'paused': await _perStream(
        RecordingHttpTransport(bare, journal(paused: true)),
      ),
      'on': await _perStream(RecordingHttpTransport(bare, journal())),
      'on, bodies': await _perStream(
        RecordingHttpTransport(bare, journal(bodies: true)),
      ),
    });
  });

  test('a WebSocket frame sent', () async {
    const message = '["1","5","room:lobby","new_msg",{"body":"hello there"}]';
    const heartbeat = '[null,"7","phoenix","heartbeat",{}]';
    final url = Uri.parse('wss://a.neon/ws');
    final bare = await _Sockets().connect(url);
    final on = await RecordingWebSocketTransport(
      _Sockets(),
      journal(),
    ).connect(url);
    final noMatchers = await RecordingWebSocketTransport(
      _Sockets(),
      journal(),
      pingMatchers: const [],
    ).connect(url);
    _report('frame', {
      'off (no wrapper)': await _perFrame(bare, message),
      'on, no heartbeats': await _perFrame(noMatchers, message),
      'on': await _perFrame(on, message),
      'on, a heartbeat': await _perFrame(on, heartbeat),
    }, digits: 3);
  });
}
