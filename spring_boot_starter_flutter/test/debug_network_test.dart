// The network recorder and the debug panel's Network tab: the decorators
// pass every request, response, error and frame through unchanged and
// write a masked copy into the journal (bodies only when asked, cut at
// the limit; a streamed body never gathered), the journal keeps the last
// entries and tells its listeners at most once a frame, the tab lists,
// filters and opens them, and the recorder wraps the transport beans of a
// running app only with its module and the panel.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_web_dart/testing.dart';

// A transport that answers with what the test gives, keeping what it got.
final class _Transport implements HttpTransport {
  _Transport({this.answer, this.streamed, this.error});

  HttpResponse Function(HttpRequest request)? answer;
  StreamedHttpResponse Function(HttpRequest request)? streamed;
  Object? error;
  final requests = <HttpRequest>[];
  final responses = <Object>[];
  var closed = false;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    requests.add(request);
    if (error case final error?) {
      throw error;
    }
    final response = answer!(request);
    responses.add(response);
    return response;
  }

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    requests.add(request);
    if (error case final error?) {
      throw error;
    }
    final response = streamed!(request);
    responses.add(response);
    return response;
  }

  @override
  void close() => closed = true;
}

HttpRequest _get(String url, {Map<String, String>? headers}) => HttpRequest(
  method: HttpMethod.get,
  url: Uri.parse(url),
  headers: HttpHeaders(headers),
);

HttpResponse _json(String body, {int status = 200}) => HttpResponse(
  status,
  headers: HttpHeaders({'Content-Type': 'application/json'}),
  body: utf8.encode(body),
);

// The journal's notification run at once, so plain tests need no frame.
DebugNetworkJournal _journal({
  bool bodies = false,
  int bodyLimit = 64 * 1024,
  int maxEntries = 200,
  int maxFrames = 200,
}) => DebugNetworkJournal(
  bodies: bodies,
  bodyLimit: bodyLimit,
  maxEntries: maxEntries,
  maxFrames: maxFrames,
  schedule: (notify) => notify(),
);

String _headers(List<NetworkHeader> headers) =>
    headers.map((h) => '${h.name}: ${h.value}').join('\n');

void main() {
  group('HTTP', () {
    test('a request and its response pass through unchanged and are '
        'recorded', () async {
      final delegate = _Transport(answer: (_) => _json('{"id":1}'));
      final journal = _journal();
      final transport = RecordingHttpTransport(delegate, journal);
      final request = HttpRequest(
        method: HttpMethod.post,
        url: Uri.parse('https://api.neon.books/books?page=2'),
        headers: HttpHeaders({'Content-Type': 'application/json'}),
        body: utf8.encode('{"title":"Dune"}'),
      );

      final response = await transport.send(request);

      expect(delegate.requests.single, same(request));
      expect(response, same(delegate.responses.single));
      final exchange = journal.entries.single as HttpExchange;
      expect(exchange.method, 'POST');
      expect('${exchange.url}', 'https://api.neon.books/books?page=2');
      expect(exchange.statusCode, 200);
      expect(exchange.status, '200');
      expect(exchange.statusClass, NetworkStatusClass.success);
      expect(exchange.state, HttpExchangeState.done);
      expect(exchange.isDone, isTrue);
      expect(exchange.requestSize, 16);
      expect(exchange.responseSize, 8);
      expect(exchange.totalTime, isNotNull);
      expect(exchange.headersTime, isNull, reason: 'a whole response');
      expect(_headers(exchange.requestHeaders), contains('application/json'));
      expect(_headers(exchange.responseHeaders), contains('application/json'));

      transport.close();
      expect(delegate.closed, isTrue);
    });

    test(
      'a failure is recorded and the same error reaches the caller',
      () async {
        final failure = HttpTransportException(
          'no data within 10 ms (read timeout)',
          isTimeout: true,
        );
        final journal = _journal();
        final transport = RecordingHttpTransport(
          _Transport(error: failure),
          journal,
        );

        await expectLater(
          transport.send(_get('https://api.neon.books/slow')),
          throwsA(same(failure)),
        );
        final exchange = journal.entries.single as HttpExchange;
        expect(exchange.state, HttpExchangeState.failed);
        expect(exchange.status, 'ERR');
        expect(exchange.statusClass, NetworkStatusClass.failed);
        expect(exchange.error, failure.message);
        expect(exchange.timeout, isTrue);
        expect(exchange.totalTime, isNotNull);
      },
    );

    test('paused, requests only pass through', () async {
      final delegate = _Transport(answer: (_) => _json('{}'));
      final journal = _journal()..paused = true;
      final transport = RecordingHttpTransport(delegate, journal);

      await transport.send(_get('https://api.neon.books/a'));

      expect(delegate.requests, hasLength(1));
      expect(journal.entries, isEmpty);
      journal.paused = false;
      await transport.send(_get('https://api.neon.books/b'));
      expect(journal.entries, hasLength(1));
    });
  });

  group('masking', () {
    test('credentials in headers are masked, by the family rule and by the '
        "request's sensitive headers", () async {
      final journal = _journal();
      final transport = RecordingHttpTransport(
        _Transport(
          answer: (_) => HttpResponse(
            200,
            headers: HttpHeaders.fromEntries([
              const MapEntry('Set-Cookie', 'session=s3cr3t'),
              const MapEntry('X-Request-Id', 'r-1'),
            ]),
          ),
        ),
        journal,
      );
      await transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('https://api.neon.books/me'),
          headers: HttpHeaders({
            'Authorization': 'Bearer t0k3n',
            'Cookie': 'sid=abc',
            'X-Api-Token': 'tk-1',
            'apikey': 'anon-key',
            'X-Tenant': 'neon',
            'X-Shop-Pass': 'p4ss',
            'Accept': 'application/json',
          }),
          sensitiveHeaders: const {'x-shop-pass'},
        ),
      );

      final exchange = journal.entries.single as HttpExchange;
      final sent = _headers(exchange.requestHeaders);
      final received = _headers(exchange.responseHeaders);
      for (final secret in [
        't0k3n',
        'sid=abc',
        'tk-1',
        'anon-key',
        'p4ss',
        's3cr3t',
      ]) {
        expect('$sent\n$received', isNot(contains(secret)));
      }
      expect(sent, contains('Authorization: ******'));
      expect(sent, contains('X-Shop-Pass: ******'));
      expect(sent, contains('X-Tenant: neon'));
      expect(sent, contains('Accept: application/json'));
      expect(received, contains('Set-Cookie: ******'));
      expect(received, contains('X-Request-Id: r-1'));
      expect(
        exchange.requestHeaders.where((h) => h.masked).map((h) => h.name),
        containsAll(['Authorization', 'Cookie', 'X-Api-Token', 'apikey']),
      );
    });

    test("an address's credentials are masked", () {
      const masking = NetworkMasking();
      expect(
        '${masking.url(Uri.parse('https://ada:pw@api.neon.books/cb?code=c0de&state=st&page=2&access_token=t0k'))}',
        'https://ada:******@api.neon.books/cb?code=******&state=******&page=2&access_token=******',
      );
      expect(
        '${masking.url(Uri.parse('wss://rt.neon.books/socket?apikey=anon&vsn=2.0.0'))}',
        'wss://rt.neon.books/socket?apikey=******&vsn=2.0.0',
      );
      final plain = Uri.parse('https://api.neon.books/books?page=2');
      expect(masking.url(plain), same(plain));
    });

    test('the secrets of a recorded body are masked', () {
      const masking = NetworkMasking();
      expect(
        masking.body(
          '{"user":"ada","password":"p4ss","access_token":"t0k","n":{"apiKey":12}}',
          'application/json',
        ),
        '{"user":"ada","password":"******","access_token":"******",'
        '"n":{"apiKey":"******"}}',
      );
      expect(
        masking.body(
          'grant_type=authorization_code&code=c0de&client_secret=s3c&redirect_uri=x',
          'application/x-www-form-urlencoded',
        ),
        'grant_type=authorization_code&code=******&client_secret=******'
        '&redirect_uri=x',
      );
      expect(
        masking.body('{"refresh_token":"abc', null),
        '{"refresh_token":"******"',
        reason: 'a body cut at the limit',
      );
      expect(
        masking.body('plain text password', 'text/plain'),
        'plain text password',
      );
    });

    test('the URLs in a recorded error are masked', () async {
      final journal = _journal();
      final transport = RecordingHttpTransport(
        _Transport(
          error: StateError(
            'HttpException: Connection closed, '
            'uri = https://api.neon.books/me?token=t0k3n&page=2',
          ),
        ),
        journal,
      );
      await expectLater(
        transport.send(_get('https://api.neon.books/me')),
        throwsStateError,
      );
      final failed = journal.entries.single as HttpExchange;
      expect(failed.error, isNot(contains('t0k3n')));
      expect(failed.error, contains('token=******&page=2'));

      final sockets = MockWebSocketTransport()
        ..failNextConnect(
          StateError('refused wss://rt.neon.books/ws?apikey=anon1 (401)'),
        );
      await expectLater(
        RecordingWebSocketTransport(
          sockets,
          journal,
        ).connect(Uri.parse('wss://rt.neon.books/ws')),
        throwsStateError,
      );
      final refused = journal.entries.last as WebSocketConnection;
      expect(
        refused.error,
        'Bad state: refused '
        'wss://rt.neon.books/ws?apikey=****** (401)',
      );
    });

    test('the URLs of Location, Content-Location and Link and the '
        'subprotocols that carry a credential are masked', () async {
      final journal = _journal();
      await RecordingHttpTransport(
        _Transport(
          answer: (_) => HttpResponse(
            302,
            headers: HttpHeaders.fromEntries([
              const MapEntry(
                'Location',
                'https://app.neon/cb?code=c0de&state=st&page=2',
              ),
              const MapEntry(
                'Content-Location',
                'https://ada:pw@cdn.neon/a.json',
              ),
              const MapEntry(
                'Link',
                '<https://api.neon/next?access_token=t0k>; rel="next"',
              ),
            ]),
          ),
        ),
        journal,
      ).send(_get('https://api.neon.books/login'));
      final received = _headers(
        (journal.entries.single as HttpExchange).responseHeaders,
      );
      for (final secret in ['c0de', 'st&', ':pw@', 't0k']) {
        expect(received, isNot(contains(secret)));
      }
      expect(received, contains('page=2'));
      expect(received, contains('rel="next"'));

      final sockets = MockWebSocketTransport();
      await RecordingWebSocketTransport(sockets, journal).connect(
        Uri.parse('wss://k8s.neon/exec'),
        protocols: const [
          'v4.channel.k8s.io',
          'base64url.bearer.authorization.k8s.io.ZXlKaGJHY2lPaUpTVXpJMU5pSXNJbXRw',
          'access_token',
          'eyJhbGciOiJIUzI1NiJ9.e30.sig',
        ],
      );
      final connection = journal.entries.last as WebSocketConnection;
      expect(connection.protocols, [
        'v4.channel.k8s.io',
        NetworkMasking.masked,
        'access_token',
        NetworkMasking.masked,
      ]);
    });

    test("an application's masker comes first", () {
      const masking = NetworkMasking(
        bodyMaskers: [_LinesMasker(), ...NetworkMasking.defaultBodyMaskers],
      );
      expect(
        masking.body('secret=1\nname=a', 'text/x-lines'),
        'secret=***\nname=a',
      );
    });
  });

  group('bodies', () {
    test('off by default: only the sizes', () async {
      final journal = _journal();
      final transport = RecordingHttpTransport(
        _Transport(answer: (_) => _json('{"title":"Dune"}')),
        journal,
      );
      await transport.send(
        HttpRequest(
          method: HttpMethod.put,
          url: Uri.parse('https://api.neon.books/books/1'),
          body: utf8.encode('{"title":"Dune"}'),
        ),
      );

      final exchange = journal.entries.single as HttpExchange;
      expect(DebugNetworkJournal().bodies, isFalse);
      expect(const FlutterDebugNetworkProperties().bodies, isFalse);
      expect(
        const FlutterDebugNetworkProperties().bodyLimit.toBytes(),
        64 * 1024,
      );
      expect(exchange.requestBody, isNull);
      expect(exchange.responseBody, isNull);
      expect(exchange.requestSize, 16);
      expect(exchange.responseSize, 16);
    });

    test(
      'on: kept up to the limit, masked, JSON indented when whole',
      () async {
        final journal = _journal(bodies: true, bodyLimit: 20);
        final transport = RecordingHttpTransport(
          _Transport(answer: (_) => _json('{"id":1,"password":"x"}')),
          journal,
        );
        await transport.send(
          HttpRequest(
            method: HttpMethod.post,
            url: Uri.parse('https://api.neon.books/login'),
            headers: HttpHeaders({'Content-Type': 'application/json'}),
            body: utf8.encode('{"a":1}'),
          ),
        );

        final exchange = journal.entries.single as HttpExchange;
        final request = exchange.requestBody!;
        expect(request.truncated, isFalse);
        expect(request.text, '{"a":1}');
        expect(request.pretty, '{\n  "a": 1\n}');
        final response = exchange.responseBody!;
        expect(response.length, 23);
        expect(response.kept, 20);
        expect(response.truncated, isTrue);
        expect(response.text, '{"id":1,"password":"******"');
        expect(response.pretty, response.text, reason: 'cut: not indented');
      },
    );

    test('a binary body keeps its size, not its bytes as text', () async {
      final journal = _journal(bodies: true);
      final transport = RecordingHttpTransport(
        _Transport(
          answer: (_) => HttpResponse(
            200,
            headers: HttpHeaders({'Content-Type': 'image/png'}),
            body: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
          ),
        ),
        journal,
      );
      await transport.send(_get('https://api.neon.books/cover.png'));

      final body = (journal.entries.single as HttpExchange).responseBody!;
      expect(body.text, isNull);
      expect(body.length, 4);
    });
  });

  group('the body budget', () {
    test('bodies past the journal-wide budget keep their size only, until '
        'the old entries go; a body limit is capped', () async {
      final journal = DebugNetworkJournal(
        bodies: true,
        bodyLimit: 1 << 30,
        bodyBudget: 250,
        schedule: (notify) => notify(),
      );
      expect(journal.bodyLimit, DebugNetworkJournal.maxBodyLimit);
      final transport = RecordingHttpTransport(
        _Transport(
          answer: (_) => HttpResponse(
            200,
            headers: HttpHeaders({'Content-Type': 'text/plain'}),
            body: List.filled(100, 0x61),
          ),
        ),
        journal,
      );
      for (final path in ['a', 'b', 'c']) {
        await transport.send(_get('https://api.neon.books/$path'));
      }
      List<int> kept() => [
        for (final entry in journal.entries)
          (entry as HttpExchange).responseBody!.kept,
      ];
      expect(kept(), [100, 100, 0]);
      expect((journal.entries.last as HttpExchange).responseSize, 100);
      journal.clear();
      await transport.send(_get('https://api.neon.books/d'));
      expect(kept(), [100]);
    });

    test('the budget frees what evicted entries kept', () async {
      final journal = DebugNetworkJournal(
        bodies: true,
        bodyBudget: 150,
        maxEntries: 1,
        schedule: (notify) => notify(),
      );
      final transport = RecordingHttpTransport(
        _Transport(
          answer: (_) => HttpResponse(
            200,
            headers: HttpHeaders({'Content-Type': 'text/plain'}),
            body: List.filled(100, 0x61),
          ),
        ),
        journal,
      );
      await transport.send(_get('https://api.neon.books/a'));
      await transport.send(_get('https://api.neon.books/b'));
      final kept = (journal.entries.single as HttpExchange).responseBody!;
      expect(kept.kept, 100, reason: 'the first one went with its body');
    });
  });

  group('a streamed response', () {
    test('is passed on as it is read, never gathered: listened, paused, '
        'resumed with the caller', () async {
      final source = StreamController<List<int>>();
      final journal = _journal();
      final transport = RecordingHttpTransport(
        _Transport(
          streamed: (request) => StreamedHttpResponse(
            200,
            headers: HttpHeaders({'Content-Type': 'text/event-stream'}),
            body: source.stream,
            request: request,
          ),
        ),
        journal,
      );
      final request = _get('https://api.neon.books/events');

      final response = await transport.stream(request);

      expect(response.statusCode, 200);
      expect(response.request, same(request));
      expect(response.headers.contentType, 'text/event-stream');
      final exchange = journal.entries.single as HttpExchange;
      expect(exchange.streamed, isTrue);
      expect(exchange.state, HttpExchangeState.receiving);
      expect(exchange.headersTime, isNotNull);
      expect(exchange.totalTime, isNull);
      expect(source.hasListener, isFalse, reason: 'nobody reads it yet');

      final chunks = <List<int>>[];
      final subscription = response.body.listen(chunks.add);
      expect(source.hasListener, isTrue);
      final first = utf8.encode('data: 1\n\n');
      source.add(first);
      await Future<void>.delayed(Duration.zero);
      expect(chunks.single, same(first));
      expect(exchange.responseSize, first.length);

      subscription.pause();
      expect(source.isPaused, isTrue);
      subscription.resume();
      expect(source.isPaused, isFalse);

      source.add(utf8.encode('data: 2\n\n'));
      await source.close();
      await Future<void>.delayed(Duration.zero);
      expect(chunks, hasLength(2));
      expect(exchange.state, HttpExchangeState.done);
      expect(exchange.responseSize, 18);
      expect(exchange.totalTime, isNotNull);
      expect(exchange.responseBody, isNull, reason: 'bodies off');
    });

    test('a caller that stops reading cancels the source; with bodies the '
        'first bytes are kept', () async {
      final source = StreamController<List<int>>();
      final journal = _journal(bodies: true, bodyLimit: 4);
      final transport = RecordingHttpTransport(
        _Transport(
          streamed: (_) => StreamedHttpResponse(200, body: source.stream),
        ),
        journal,
      );
      var cancelled = false;
      source.onCancel = () => cancelled = true;

      final response = await transport.stream(
        _get('https://api.neon.books/download'),
      );
      final subscription = response.body.listen((_) {});
      source
        ..add(utf8.encode('abc'))
        ..add(utf8.encode('defgh'));
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(cancelled, isTrue);
      final exchange = journal.entries.single as HttpExchange;
      expect(exchange.state, HttpExchangeState.cancelled);
      expect(exchange.responseSize, 8);
      expect(exchange.responseBody!.text, 'abcd');
      expect(exchange.responseBody!.truncated, isTrue);
    });

    test(
      'an error on the body reaches the caller and fails the exchange',
      () async {
        final source = StreamController<List<int>>();
        final journal = _journal();
        final transport = RecordingHttpTransport(
          _Transport(
            streamed: (_) => StreamedHttpResponse(200, body: source.stream),
          ),
          journal,
        );
        final response = await transport.stream(
          _get('https://api.neon.books/s'),
        );
        final errors = <Object>[];
        response.body.listen((_) {}, onError: errors.add);
        final broken = HttpTransportException('connection reset');
        source.addError(broken);
        await Future<void>.delayed(Duration.zero);

        expect(errors.single, same(broken));
        final exchange = journal.entries.single as HttpExchange;
        expect(exchange.state, HttpExchangeState.failed);
        expect(exchange.error, 'connection reset');
        expect(exchange.status, '200');
      },
    );
  });

  group('WebSocket', () {
    test('frames each way, Phoenix joins and leaves, and the close are '
        'recorded; the session passes everything through', () async {
      final sockets = MockWebSocketTransport();
      final journal = _journal(bodies: true);
      final transport = RecordingWebSocketTransport(sockets, journal);

      final session = await transport.connect(
        Uri.parse('wss://rt.neon.books/socket?apikey=anon&vsn=2.0.0'),
        headers: HttpHeaders({'Authorization': 'Bearer t0k3n'}),
        protocols: const ['phoenix'],
      );
      final server = sockets.lastConnection;
      expect(server.headers['Authorization'], 'Bearer t0k3n');
      expect(session.acceptedProtocol, 'phoenix');
      final received = <Object>[];
      session.messages.listen(received.add);

      const join = '["1","1","room:lobby","phx_join",{"access_token":"t0k"}]';
      session.sendMessage(join);
      server.push('["1","1","room:lobby","phx_reply",{"status":"ok"}]');
      server.push(Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(Duration.zero);
      final joined = journal.entries.single as WebSocketConnection;
      expect(joined.channels, {'room:lobby'});
      session.sendMessage('["1","2","room:lobby","phx_leave",{}]');

      expect(server.sent, [join, '["1","2","room:lobby","phx_leave",{}]']);
      expect(received, hasLength(2));
      final connection = journal.entries.single as WebSocketConnection;
      expect(connection.method, 'WS');
      expect(connection.isWebSocket, isTrue);
      expect('${connection.url}', contains('apikey=******'));
      expect(_headers(connection.requestHeaders), 'Authorization: ******');
      expect(connection.opened, isTrue);
      expect(connection.status, '101');
      expect(connection.acceptedProtocol, 'phoenix');
      expect(connection.framesOut, 2);
      expect(connection.framesIn, 2);
      expect(
        connection.bytesIn,
        utf8.encode(received.first as String).length + 3,
      );
      final frames = connection.frames;
      expect(frames.map((f) => f.label), [
        'join room:lobby',
        null,
        null,
        'leave room:lobby',
      ]);
      expect(frames[0].direction, WebSocketDirection.outgoing);
      expect(frames[1].direction, WebSocketDirection.incoming);
      expect(frames[2].binary, isTrue);
      expect(frames[2].size, 3);
      expect(frames[0].payload!.text, isNot(contains('t0k')));
      expect(connection.channels, isEmpty);

      await session.close(CloseStatus.goingAway);
      expect(server.closedByClient, isTrue);
      expect(connection.closeCode, 1001);
      expect(connection.closedByClient, isTrue);
      expect(connection.isDone, isTrue);
      expect(connection.closedAfter, isNotNull);
    });

    test('a close by the server and a failed handshake', () async {
      final sockets = MockWebSocketTransport();
      final journal = _journal();
      final transport = RecordingWebSocketTransport(sockets, journal);

      final session = await transport.connect(Uri.parse('wss://a.neon/ws'));
      session.messages.listen((_) {});
      sockets.lastConnection.push('{"topic":"t","event":"phx_join"}');
      await sockets.lastConnection.closeFromServer(
        const CloseStatus(4001, 'kicked'),
      );
      await Future<void>.delayed(Duration.zero);
      final connection = journal.entries.single as WebSocketConnection;
      expect(connection.frames.single.label, 'join t');
      expect(connection.frames.single.payload, isNull, reason: 'bodies off');
      expect(connection.channels, {'t'});
      expect(connection.closeCode, 4001);
      expect(connection.closeReason, 'kicked');
      expect(connection.closedByClient, isFalse);
      expect(connection.statusClass, NetworkStatusClass.clientError);

      final refused = WebSocketException('handshake refused');
      sockets.failNextConnect(refused);
      await expectLater(
        transport.connect(Uri.parse('wss://b.neon/ws')),
        throwsA(same(refused)),
      );
      final failed = journal.entries.last as WebSocketConnection;
      expect(failed.status, 'ERR');
      expect(failed.statusClass, NetworkStatusClass.failed);
      expect(failed.error, 'handshake refused');
      expect(failed.isDone, isTrue);
    });

    test('the frames kept are the last max-frames; the counts go on', () async {
      final sockets = MockWebSocketTransport();
      final journal = _journal(maxFrames: 2);
      final session = await RecordingWebSocketTransport(
        sockets,
        journal,
      ).connect(Uri.parse('wss://a.neon/ws'));
      for (var i = 0; i < 5; i++) {
        session.sendMessage('m$i');
      }
      final connection = journal.entries.single as WebSocketConnection;
      expect(connection.frames, hasLength(2));
      expect(connection.framesOut, 5);
      expect(connection.bytesOut, 10);
    });

    test('UTF-8 sizes are counted without encoding', () {
      for (final text in ['abc', 'é', '€', '😀', 'a😀é€']) {
        expect(
          RecordingWebSocketTransport.utf8Length(text),
          utf8.encode(text).length,
          reason: text,
        );
      }
    });
  });

  group('the journal', () {
    test(
      'keeps the last max-entries, oldest first; clear empties it',
      () async {
        final journal = _journal(maxEntries: 3);
        final transport = RecordingHttpTransport(
          _Transport(answer: (_) => _json('{}')),
          journal,
        );
        for (var i = 1; i <= 5; i++) {
          await transport.send(_get('https://api.neon.books/$i'));
        }
        expect(journal.entries.map((e) => e.url.path), ['/3', '/4', '/5']);
        expect(journal.entries.map((e) => e.id), [3, 4, 5]);
        final version = journal.version;
        journal.clear();
        expect(journal.entries, isEmpty);
        expect(journal.version, greaterThan(version));
      },
    );

    test('a summary for a compact view', () async {
      final journal = _journal();
      final transport = RecordingHttpTransport(
        _Transport(
          answer: (request) => _json(
            '{}',
            status: request.url.path == '/missing' ? 404 : 200,
          ),
        ),
        journal,
      );
      await transport.send(_get('https://api.neon.books/ok'));
      await transport.send(_get('https://api.neon.books/missing'));
      final sockets = MockWebSocketTransport();
      await RecordingWebSocketTransport(
        sockets,
        journal,
      ).connect(Uri.parse('wss://a.neon/ws'));

      final summary = journal.summary;
      expect(summary.entries, 3);
      expect(summary.failed, 0, reason: 'a 404 is a response');
      expect(summary.errors, 1);
      expect(summary.inFlight, 1);
      expect(summary.openSockets, 1);
      expect(summary.received, 4);
    });

    testWidgets('tells its listeners at most once a frame, and schedules '
        'nothing without listeners', (tester) async {
      final journal = DebugNetworkJournal();
      addTearDown(journal.dispose);
      for (var i = 0; i < 10; i++) {
        journal.changed();
      }
      expect(tester.binding.hasScheduledFrame, isFalse);

      var heard = 0;
      journal.addListener(() => heard++);
      for (var i = 0; i < 10; i++) {
        journal.changed();
      }
      expect(heard, 0);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      expect(heard, 1);
      await tester.pump();
      expect(heard, 1);
    });
  });

  group('the Network tab', () {
    Future<DebugNetworkJournal> filled() async {
      final journal = DebugNetworkJournal(bodies: true);
      final transport = RecordingHttpTransport(
        _Transport(
          answer: (request) => switch (request.url.path) {
            '/books' => _json('{"items":[1,2]}'),
            '/missing' => _json('{"error":"no"}', status: 404),
            _ => _json('{}', status: 500),
          },
        ),
        journal,
      );
      await transport.send(
        _get(
          'https://api.neon.books/books',
          headers: {'Authorization': 'Bearer t0k3n'},
        ),
      );
      await transport.send(
        HttpRequest(
          method: HttpMethod.post,
          url: Uri.parse('https://api.neon.books/missing'),
        ),
      );
      await transport.send(
        HttpRequest(
          method: HttpMethod.delete,
          url: Uri.parse('https://api.neon.books/broken'),
        ),
      );
      final sockets = MockWebSocketTransport();
      final session = await RecordingWebSocketTransport(
        sockets,
        journal,
      ).connect(Uri.parse('wss://rt.neon.books/socket'));
      session.sendMessage('["1","1","room:lobby","phx_join",{}]');
      return journal;
    }

    Future<DebugNetworkSection> pump(
      WidgetTester tester,
      DebugNetworkJournal journal,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final section = DebugNetworkSection(journal);
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          builder: (context, _) => Builder(builder: section.build),
        ),
      );
      return section;
    }

    testWidgets('a group of its own; rows newest first with method, path, '
        'status, time and size', (tester) async {
      final journal = await tester.runAsync(filled);
      final section = await pump(tester, journal!);

      expect(section.title, 'Network');
      expect(section.group, 'Network');
      for (final text in ['/books', '/missing', '/broken', '/socket']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('404'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('101'), findsOneWidget);
      expect(find.text('15 B'), findsOneWidget);
      final rows = [
        for (final id in [4, 3, 2, 1])
          tester.getTopLeft(find.byKey(NetworkView.rowKey(id))).dy,
      ];
      expect(rows, orderedEquals([...rows]..sort()));
    });

    testWidgets('the colours: two for methods, three for statuses', (
      tester,
    ) async {
      final journal = await tester.runAsync(filled);
      await pump(tester, journal!);
      final style = DebugStyle.of(tester.element(find.text('200')));
      Color? colorOf(String text) => tester
          .widget<Text>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.text(text),
            ),
          )
          .style
          ?.color;

      expect(colorOf('GET'), style.methodRead);
      expect(colorOf('POST'), style.methodWrite);
      expect(colorOf('DELETE'), style.methodWrite);
      expect(colorOf('200'), style.good);
      expect(colorOf('404'), style.warning);
      expect(colorOf('500'), style.bad);
      expect(style.methodRead, isNot(style.methodWrite));
    });

    testWidgets('filters by method, WebSocket, status class and address', (
      tester,
    ) async {
      final journal = await tester.runAsync(filled);
      final section = await pump(tester, journal!);
      Future<void> tap(String chip) async {
        await tester.tap(find.widgetWithText(DebugChip, chip).first);
        await tester.pump();
      }

      await tap('POST');
      expect(find.text('/missing'), findsOneWidget);
      expect(find.text('/books'), findsNothing);
      await tap('WS');
      expect(find.text('/socket'), findsOneWidget);
      expect(find.text('/missing'), findsNothing);
      await tap('All');
      await tap('4xx');
      expect(find.text('/missing'), findsOneWidget);
      expect(find.text('/broken'), findsNothing);
      await tap('5xx');
      expect(find.text('/broken'), findsOneWidget);
      await tester.tap(find.widgetWithText(DebugChip, 'All').last);
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'MISS');
      await tester.pump();
      expect(find.text('/missing'), findsOneWidget);
      expect(find.text('/books'), findsNothing);
      expect(section.filter.text, 'MISS');
      await tester.enterText(find.byType(EditableText), 'nothing');
      await tester.pump();
      expect(find.text('No request matches'), findsOneWidget);
    });

    testWidgets('the method chips are the methods recorded, in a fixed '
        'order, and the one chosen', (tester) async {
      final journal = await tester.runAsync(filled);
      final section = await pump(tester, journal!);
      // The method chips: from the first `All` to the status chips' own.
      List<String> chips() {
        final labels = [
          for (final chip in tester.widgetList<DebugChip>(
            find.byType(DebugChip),
          ))
            chip.label,
        ];
        return labels.sublist(0, labels.indexOf('All', 1));
      }

      expect(chips(), ['All', 'GET', 'POST', 'DELETE', 'WS']);
      section.filter.method = 'HEAD';
      await tester.pump();
      expect(chips(), ['All', 'GET', 'HEAD', 'POST', 'DELETE', 'WS']);
    });

    testWidgets('a row opens its detail: masked headers, indented JSON, '
        'timings; Back returns', (tester) async {
      final journal = await tester.runAsync(filled);
      await pump(tester, journal!);

      await tester.tap(find.text('/books'));
      await tester.pump();
      expect(find.text('Request headers'), findsOneWidget);
      expect(find.textContaining('******'), findsOneWidget);
      expect(find.textContaining('t0k3n'), findsNothing);
      expect(find.textContaining('"items": ['), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.text('/missing'), findsOneWidget);

      await tester.tap(find.text('/socket'));
      await tester.pump();
      expect(find.text('Frames'), findsOneWidget);
      expect(
        find.textContaining('join room:lobby', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('room:lobby'), findsOneWidget);
    });

    testWidgets('Pause stops recording, Clear empties the list', (
      tester,
    ) async {
      final journal = await tester.runAsync(filled);
      await pump(tester, journal!);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(journal.paused, isTrue);
      expect(find.text('Resume'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(journal.entries, isEmpty);
      expect(find.text('No requests yet'), findsOneWidget);
    });
  });

  group('in a running app', () {
    Future<ApplicationContext> start(
      WidgetTester tester, {
      String properties = '',
      List<BeanModule>? debug,
      List<BeanDefinition<Object>> beans = const [],
    }) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => SpringApplication(
            [
              BeanModule(
                'test',
                beans,
                resources: {
                  'application.properties': EmbeddedResource.text(
                    'spring.flutter.app.type=widgets\n$properties',
                  ),
                },
              ),
            ],
            autoConfigurations: [
              springBootStarterFlutterAutoConfiguration,
              ...debug ??
                  [
                    springBootStarterFlutterDebugAutoConfiguration,
                    springBootStarterFlutterDebugNetworkAutoConfiguration,
                  ],
              springBootStarterLoggingAutoConfiguration,
            ],
            bannerMode: BannerMode.off,
          ),
          home: const Text('home'),
        ),
      );
      await tester.pumpAndSettle();
      return SpringScope.of(tester.element(find.text('home')));
    }

    final http = _Transport(answer: (_) => _json('{}'));
    final mock = MockHttpTransport();
    final sockets = MockWebSocketTransport();
    List<BeanDefinition<Object>> transports() => [
      BeanDefinition<HttpTransport>(name: 'httpTransport', create: (_) => http),
      BeanDefinition<WebSocketTransport>(
        name: 'webSocketTransport',
        create: (_) => sockets,
      ),
    ];

    testWidgets('the transport beans are wrapped, the tab is in the panel, '
        'the settings come from the configuration', (tester) async {
      final context = await start(
        tester,
        beans: transports(),
        properties:
            'spring.flutter.debug.network.bodies=true\n'
            'spring.flutter.debug.network.body-limit=1KB\n'
            'spring.flutter.debug.network.max-entries=7\n'
            'spring.flutter.debug.network.max-frames=3',
      );

      final transport = context.getBean<HttpTransport>();
      expect(transport, isA<RecordingHttpTransport>());
      expect((transport as RecordingHttpTransport).delegate, same(http));
      expect(
        context.getBean<WebSocketTransport>(),
        isA<RecordingWebSocketTransport>(),
      );
      final journal = context.getBean<DebugNetworkJournal>();
      expect(journal.bodies, isTrue);
      expect(journal.bodyLimit, 1024);
      expect(journal.maxEntries, 7);
      expect(journal.maxFrames, 3);
      expect(transport.journal, same(journal));

      await tester.runAsync(
        () => transport.send(_get('https://api.neon.books/books')),
      );
      context.getBean<DebugPanel>().toggle();
      await tester.pump();
      await tester.tap(find.text('Network').last);
      await tester.pump();
      expect(find.text('/books'), findsOneWidget);
    });

    testWidgets('a transport injected by its own class is left as it is', (
      tester,
    ) async {
      final context = await start(
        tester,
        beans: [
          BeanDefinition<MockHttpTransport>(
            name: 'httpTransport',
            types: const [MockHttpTransport, HttpTransport],
            create: (_) => mock,
          ),
        ],
      );
      expect(context.getBean<HttpTransport>(), same(mock));
      expect(context.getBean<MockHttpTransport>(), same(mock));
      expect(context.containsBean('debugNetworkRecorder'), isTrue);
    });

    testWidgets('without the panel nothing is recorded', (tester) async {
      final context = await start(
        tester,
        beans: transports(),
        debug: [springBootStarterFlutterDebugNetworkAutoConfiguration],
      );
      expect(context.containsBean('debugNetworkRecorder'), isFalse);
      expect(context.containsBean('debugNetworkJournal'), isFalse);
      expect(context.getBean<HttpTransport>(), same(http));
    });

    testWidgets('spring.flutter.debug.network.enabled=false turns it off in '
        'a running app', (tester) async {
      final context = await start(
        tester,
        beans: transports(),
        properties: 'spring.flutter.debug.network.enabled=false',
      );
      expect(context.containsBean('debugNetworkRecorder'), isFalse);
      expect(context.containsBean('debugNetworkSection'), isFalse);
      expect(context.containsBean('debugPanel'), isTrue);
      expect(context.getBean<HttpTransport>(), same(http));
    });

    testWidgets('the panel off in a running app turns the recorder off too', (
      tester,
    ) async {
      final context = await start(
        tester,
        beans: transports(),
        properties: 'spring.flutter.debug.enabled=false',
      );
      expect(context.containsBean('debugNetworkRecorder'), isFalse);
      expect(context.getBean<WebSocketTransport>(), same(sockets));
    });
  });

  testWidgets('a debug theme sets the method colours', (tester) async {
    final environment = StandardEnvironment()
      ..propertySources.addFirst(
        MapPropertySource('t', {
          'spring.flutter.debug.themes.night.method-read': '#112233',
          'spring.flutter.debug.themes.night.method-write': '#445566',
        }),
      );
    final themes = ConfiguredDebugTheme.declaredIn(environment, const {
      'night': FlutterDebugThemeProperties(
        methodRead: '#112233',
        methodWrite: '#445566',
      ),
    });
    late DebugStyle style;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          style = themes.single.styleOf(context);
          return const SizedBox();
        },
      ),
    );
    expect(style.methodRead, const Color(0xFF112233));
    expect(style.methodWrite, const Color(0xFF445566));
  });
}

final class _LinesMasker implements NetworkBodyMasker {
  const _LinesMasker();

  @override
  bool supports(String text, String? contentType) =>
      contentType == 'text/x-lines';

  @override
  String mask(String text) =>
      text.replaceAllMapped(RegExp(r'^(secret=).*$', multiLine: true), (m) {
        return '${m[1]}***';
      });
}
