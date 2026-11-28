// The network recorder's timings: the phases of a request (the wait for
// the headers and the body of a streamed one, the whole of a whole one,
// the browser's Resource Timing when a reader gives it), the caller's
// results unchanged by recording (timeouts, errors, bytes) against a real
// server, the waterfall's scale, a WebSocket's handshake, uptime,
// reconnects, close and Phoenix heartbeat round trips, the journal's
// summary, and the Network tab showing them.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/testing.dart';

// A transport that answers after [delay], whole or streamed.
final class _Transport implements HttpTransport {
  _Transport({this.delay = Duration.zero});

  final Duration delay;
  final List<int> body = const [1, 2, 3];

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    await Future<void>.delayed(delay);
    return HttpResponse(200, body: body, request: request);
  }

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    await Future<void>.delayed(delay);
    return StreamedHttpResponse(
      200,
      body: Stream.fromFuture(
        Future<List<int>>.delayed(delay, () => body),
      ),
      request: request,
    );
  }

  @override
  void close() {}
}

// A WebSocket transport whose handshake takes [delay].
final class _SlowSockets implements WebSocketTransport {
  _SlowSockets(this.delay);

  final Duration delay;
  final mock = MockWebSocketTransport();

  @override
  Future<WebSocketSession> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
    int? maxTextMessageSize,
    int? maxBinaryMessageSize,
  }) async {
    await Future<void>.delayed(delay);
    return mock.connect(url, headers: headers, protocols: protocols);
  }
}

// Resource Timing entries a test gives, on a clock it sets.
final class _Timings implements ResourceTimingSource {
  double clock = 1000;
  final entries = <String, List<ResourceTimingEntry>>{};
  final asked = <String>[];
  int observing = 0;

  @override
  double now() => clock;

  @override
  void Function() observe() {
    observing++;
    var stopped = false;
    return () {
      if (!stopped) {
        stopped = true;
        observing--;
      }
    };
  }

  @override
  Iterable<ResourceTimingEntry> entriesNamed(String name) {
    asked.add(name);
    return entries[name] ?? const [];
  }
}

// An HTTP client of dart:io itself: the test binding answers every
// request of its own with a 400.
final class _RealHttp extends io.HttpOverrides {}

DebugNetworkJournal _journal() =>
    DebugNetworkJournal(schedule: (notify) => notify());

HttpRequest _get(String url, {Duration? timeout, Duration? readTimeout}) =>
    HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse(url),
      timeout: timeout,
      readTimeout: readTimeout,
    );

// An entry with these times, for the waterfall.
HttpCall _exchange(
  int id,
  DateTime started, {
  Duration? total,
  Duration? firstByte,
  bool failed = false,
}) {
  final exchange = HttpCall(
    id: id,
    url: Uri.parse('https://api.neon.books/$id'),
    started: started,
    method: 'GET',
    requestHeaders: const [],
    requestSize: 0,
  );
  exchange
    ..headersTime = firstByte
    ..totalTime = total
    ..statusCode = failed ? null : (total == null ? null : 200)
    ..state = failed
        ? HttpCallState.failed
        : total == null
        ? HttpCallState.waiting
        : HttpCallState.done;
  return exchange;
}

const _browserEntry = ResourceTimingEntry(
  startTime: 1000,
  fetchStart: 1001,
  domainLookupStart: 1002,
  domainLookupEnd: 1010,
  connectStart: 1010,
  secureConnectionStart: 1020,
  connectEnd: 1040,
  requestStart: 1041,
  responseStart: 1100,
  responseEnd: 1150,
  nextHopProtocol: 'h2',
);

void main() {
  group('HTTP phases', () {
    test('a streamed request: the wait for the headers, then the body to '
        'its end', () async {
      final journal = _journal();
      final transport = RecordingHttpTransport(
        _Transport(delay: const Duration(milliseconds: 30)),
        journal,
      );

      final response = await transport.stream(
        _get('https://api.neon.books/events'),
      );
      final exchange = journal.entries.single as HttpCall;
      expect(exchange.headersTime, greaterThanOrEqualTo(_ms(25)));
      expect(exchange.firstByte, exchange.headersTime);
      final inFlight = exchange.phases(
        exchange.started.add(const Duration(seconds: 5)),
      );
      expect(inFlight.map((p) => p.name), ['Waiting', 'Body']);
      expect(inFlight.last.end, const Duration(seconds: 5));

      await response.body.drain<void>();
      final phases = exchange.phases(DateTime.now());
      expect(phases.map((p) => p.name), ['Waiting', 'Body']);
      expect(phases.first.start, Duration.zero);
      expect(phases.first.duration, exchange.headersTime);
      expect(phases.last.start, exchange.headersTime);
      expect(phases.last.end, exchange.totalTime);
      expect(exchange.totalTime! - exchange.headersTime!, greaterThan(_ms(20)));
    });

    test('a whole request: the total only, no headers time (send hands '
        'the response over whole)', () async {
      final journal = _journal();
      final transport = RecordingHttpTransport(
        _Transport(delay: const Duration(milliseconds: 20)),
        journal,
      );
      expect(transport.resourceTiming, isNull, reason: 'not a browser');

      await transport.send(_get('https://api.neon.books/books'));
      final exchange = journal.entries.single as HttpCall;
      expect(exchange.headersTime, isNull);
      expect(exchange.firstByte, isNull);
      expect(exchange.phases(DateTime.now()), [
        NetworkPhase('Total', Duration.zero, exchange.totalTime!),
      ]);
    });

    test("a whole request on the web: the browser's phases and first "
        'byte, read by the address the request had', () async {
      final timings = _Timings();
      timings.entries['https://api.neon.books/books?page=2'] = const [
        _browserEntry,
      ];
      final journal = _journal();
      final transport = RecordingHttpTransport(
        _Transport(),
        journal,
        resourceTiming: ResourceTimingReader(timings),
      );

      await transport.send(_get('https://api.neon.books/books?page=2'));
      final exchange = journal.entries.single as HttpCall;
      final browser = exchange.resourceTiming!;
      expect(browser.restricted, isFalse);
      expect(browser.protocol, 'h2');
      expect(exchange.headersTime, isNull);
      expect(exchange.firstByte, _ms(100));
      expect(exchange.phases(DateTime.now()).map((p) => p.name), [
        'Queued',
        'DNS',
        'TCP',
        'TLS',
        'Waiting',
        'Download',
      ]);
    });

    test('a streamed request on the web reads the browser once its body '
        'is done; an entry added later is read a moment later', () async {
      final timings = _Timings();
      final journal = _journal();
      final transport = RecordingHttpTransport(
        _Transport(),
        journal,
        resourceTiming: ResourceTimingReader(timings),
      );

      final response = await transport.stream(
        _get('https://api.neon.books/events'),
      );
      final exchange = journal.entries.single as HttpCall;
      expect(timings.asked, isEmpty, reason: 'not before the body is done');
      timings.entries['https://api.neon.books/events'] = const [_browserEntry];
      await response.body.drain<void>();
      expect(timings.asked, hasLength(1));
      expect(exchange.resourceTiming, isNotNull);
      expect(exchange.firstByte, exchange.headersTime, reason: 'measured');

      timings.asked.clear();
      await transport.send(_get('https://api.neon.books/later'));
      final later = journal.entries.last as HttpCall;
      expect(later.resourceTiming, isNull);
      timings.entries['https://api.neon.books/later'] = const [_browserEntry];
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(timings.asked, hasLength(2));
      expect(later.resourceTiming, isNotNull);
    });

    test('the browser is observed only while a recorded request waits '
        'for its timing', () async {
      final timings = _Timings();
      final journal = _journal();
      final transport = RecordingHttpTransport(
        _Transport(),
        journal,
        resourceTiming: ResourceTimingReader(timings),
      );
      expect(timings.observing, 0);
      timings.entries['https://api.neon.books/a'] = const [_browserEntry];
      await transport.send(_get('https://api.neon.books/a'));
      expect(timings.observing, 0, reason: 'read at once');

      await transport.send(_get('https://api.neon.books/late'));
      expect(timings.observing, 1, reason: 'its entry not there yet');
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(timings.observing, 0, reason: 'given up');

      final response = await transport.stream(_get('https://api.neon.books/s'));
      expect(timings.observing, 1);
      await response.body.listen((_) {}).cancel();
      expect(timings.observing, 0, reason: 'cancelled');

      final failing = RecordingHttpTransport(
        _FailingTransport(),
        journal,
        resourceTiming: ResourceTimingReader(timings),
      );
      await expectLater(
        failing.send(_get('https://api.neon.books/x')),
        throwsA(isA<HttpTransportException>()),
      );
      expect(timings.observing, 0);

      journal.paused = true;
      await transport.send(_get('https://api.neon.books/paused'));
      expect(timings.observing, 0, reason: 'not recording');
    });

    test('a failure reads nothing from the browser', () async {
      final timings = _Timings();
      final journal = _journal();
      final transport = RecordingHttpTransport(
        _FailingTransport(),
        journal,
        resourceTiming: ResourceTimingReader(timings),
      );
      await expectLater(
        transport.send(_get('https://api.neon.books/x')),
        throwsA(isA<HttpTransportException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(timings.asked, isEmpty);
      final exchange = journal.entries.single as HttpCall;
      expect(exchange.phases(DateTime.now()).single.name, 'Total');
    });
  });

  group('the Resource Timing reader', () {
    test('the phases of an entry, each from its start', () {
      final timing = ResourceTimingReader.timingOf(
        const ResourceTimingEntry(
          startTime: 500,
          redirectStart: 500,
          redirectEnd: 520,
          fetchStart: 520,
          domainLookupStart: 525,
          domainLookupEnd: 535,
          connectStart: 535,
          connectEnd: 560,
          requestStart: 561,
          responseStart: 600.5,
          responseEnd: 650,
        ),
      );
      expect(timing.total, _ms(150));
      expect(timing.firstByte, const Duration(microseconds: 100500));
      expect(timing.protocol, isNull);
      expect(timing.phases, [
        NetworkPhase('Redirect', Duration.zero, _ms(20)),
        NetworkPhase('Queued', _ms(20), _ms(5)),
        NetworkPhase('DNS', _ms(25), _ms(10)),
        NetworkPhase('TCP', _ms(35), _ms(25)),
        NetworkPhase('Waiting', _ms(61), const Duration(microseconds: 39500)),
        NetworkPhase(
          'Download',
          const Duration(microseconds: 100500),
          _ms(
                49,
              ) +
              const Duration(microseconds: 500),
        ),
      ]);
    });

    test('TLS split from TCP; a reused connection has neither', () {
      final tls = ResourceTimingReader.timingOf(_browserEntry);
      expect(tls.phases.map((p) => (p.name, p.duration)), [
        ('Queued', _ms(1)),
        ('DNS', _ms(8)),
        ('TCP', _ms(10)),
        ('TLS', _ms(20)),
        ('Waiting', _ms(59)),
        ('Download', _ms(50)),
      ]);
      final reused = ResourceTimingReader.timingOf(
        const ResourceTimingEntry(
          startTime: 10,
          fetchStart: 10,
          domainLookupStart: 10,
          domainLookupEnd: 10,
          connectStart: 10,
          connectEnd: 10,
          requestStart: 11,
          responseStart: 30,
          responseEnd: 31,
        ),
      );
      expect(reused.phases.map((p) => p.name), ['Waiting', 'Download']);
    });

    test('another origin without Timing-Allow-Origin: restricted, the '
        'total only', () {
      final timing = ResourceTimingReader.timingOf(
        const ResourceTimingEntry(startTime: 100, responseEnd: 180),
      );
      expect(timing.restricted, isTrue);
      expect(timing.total, _ms(80));
      expect(timing.firstByte, isNull);
      expect(timing.phases, isEmpty);
      final exchange = _exchange(1, DateTime(2026), total: _ms(85))
        ..resourceTiming = timing;
      expect(exchange.firstByte, isNull);
      expect(exchange.phases(DateTime(2026)).single.name, 'Total');
    });

    test('reads the first entry of the address that started at the mark or '
        'after, and finished', () {
      final timings = _Timings();
      final reader = ResourceTimingReader(timings);
      const name = 'https://api.neon.books/poll';
      timings.entries[name] = const [
        ResourceTimingEntry(startTime: 900, responseEnd: 950),
        ResourceTimingEntry(startTime: 1300, responseEnd: 1400),
        ResourceTimingEntry(startTime: 1000.5, responseEnd: 1100),
        ResourceTimingEntry(startTime: 1200, responseEnd: 0),
      ];
      timings.clock = 1000.8;
      final mark = reader.mark();
      expect(mark, 1000.8);
      expect(reader.read(Uri.parse(name), mark)!.total, _ms(99.5));
      expect(reader.read(Uri.parse(name), 1250)!.total, _ms(100));
      expect(reader.read(Uri.parse(name), 1500), isNull);
      expect(reader.read(Uri.parse('https://other.neon/'), 0), isNull);
    });

    test("an address as the browser names it: absolute against the page's, "
        'with a path, without a fragment', () {
      final reader = ResourceTimingReader(
        _Timings(),
        base: Uri.parse('https://app.neon.books/shop/'),
      );
      expect(
        reader.nameOf(Uri.parse('/api/books?page=2')),
        'https://app.neon.books/api/books?page=2',
      );
      expect(
        reader.nameOf(Uri.parse('cart')),
        'https://app.neon.books/shop/cart',
      );
      expect(
        reader.nameOf(Uri.parse('https://api.neon.books')),
        'https://api.neon.books/',
      );
      expect(
        reader.nameOf(Uri.parse('https://api.neon.books/a#top')),
        'https://api.neon.books/a',
      );
    });

    test('none outside a browser', () {
      expect(ResourceTimingReader.platform(), isNull);
    });
  });

  group('recording leaves the results unchanged (a real server)', () {
    late io.HttpServer server;
    late HttpTransport bare;
    late DebugNetworkJournal journal;
    late HttpTransport recorded;
    final big = Uint8List.fromList(
      List.generate(300 * 1024, (i) => (i * 31) % 251),
    );

    setUp(() async {
      server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final response = request.response;
        switch (request.uri.path) {
          case '/big':
            response.add(big);
          case '/slow-body':
            response.headers.contentType = io.ContentType.text;
            response.write('head ');
            await response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 400));
            response.write('tail');
          case '/missing':
            response.statusCode = 404;
            response.write('no');
        }
        await response.close();
      });
      bare = io.HttpOverrides.runWithHttpOverrides(
        IoHttpTransport.new,
        _RealHttp(),
      );
      journal = _journal();
      recorded = RecordingHttpTransport(
        io.HttpOverrides.runWithHttpOverrides(
          IoHttpTransport.new,
          _RealHttp(),
        ),
        journal,
      );
    });

    tearDown(() async {
      bare.close();
      recorded.close();
      await server.close(force: true);
    });

    String url(String path) => 'http://127.0.0.1:${server.port}$path';

    test('the same bytes, the same status; sizes recorded', () async {
      final plain = await bare.send(_get(url('/big')));
      final through = await recorded.send(_get(url('/big')));
      expect(through.statusCode, plain.statusCode);
      expect(through.bodyBytes, plain.bodyBytes);
      expect(through.bodyBytes, big);
      final missing = await recorded.send(_get(url('/missing')));
      expect(missing.statusCode, 404);
      expect(missing.bodyText, 'no');

      final streamed = await recorded.stream(_get(url('/big')));
      final chunks = await streamed.body.toList();
      expect(chunks.expand((c) => c).toList(), big);
      final exchanges = journal.entries.cast<HttpCall>().toList();
      expect(exchanges.map((e) => e.responseSize), [big.length, 2, big.length]);
      expect(exchanges.last.headersTime, isNotNull);
      expect(exchanges.first.headersTime, isNull);
    });

    test("send's timeout covers the body as without recording; stream's "
        'the headers only', () async {
      final timeout = _get(
        url('/slow-body'),
        timeout: const Duration(milliseconds: 150),
      );
      Future<HttpTransportException> failure(HttpTransport transport) async {
        try {
          await transport.send(timeout);
        } on HttpTransportException catch (error) {
          return error;
        }
        fail('no timeout');
      }

      final plain = await failure(bare);
      final through = await failure(recorded);
      expect(through.isTimeout, isTrue);
      expect(through.isTimeout, plain.isTimeout);
      expect(through.message, plain.message);
      final failed = journal.entries.single as HttpCall;
      expect(failed.state, HttpCallState.failed);
      expect(failed.timeout, isTrue);

      final streamedPlain = await bare.stream(timeout);
      final streamedThrough = await recorded.stream(timeout);
      expect(
        utf8.decode(await streamedThrough.body.expand((c) => c).toList()),
        'head tail',
      );
      expect(
        utf8.decode(await streamedPlain.body.expand((c) => c).toList()),
        'head tail',
      );
    });

    test('a read timeout and a refused connection fail as without '
        'recording', () async {
      final idle = _get(
        url('/slow-body'),
        readTimeout: const Duration(milliseconds: 150),
      );
      Future<String> message(Future<Object?> call) async {
        try {
          await call;
        } on HttpTransportException catch (error) {
          return '${error.isTimeout} ${error.message}';
        }
        return 'no failure';
      }

      expect(
        await message(recorded.send(idle)),
        await message(bare.send(idle)),
      );
      final closed = await io.ServerSocket.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      final port = closed.port;
      await closed.close();
      final refused = _get('http://127.0.0.1:$port/');
      final plain = await message(bare.send(refused));
      expect(plain, startsWith('false connection failed'));
      expect(await message(recorded.send(refused)), plain);
    });
  });

  group('the waterfall', () {
    final t0 = DateTime(2026, 11, 25, 12);
    DateTime at(int ms) => t0.add(_ms(ms));

    test('one scale from the first start to the last end: overlaps and '
        'the first byte', () {
      final a = _exchange(1, at(0), total: _ms(400), firstByte: _ms(100));
      final b = _exchange(2, at(200), total: _ms(800));
      final waterfall = NetworkWaterfall([b, a], at(5000));
      expect(waterfall.start, t0);
      expect(waterfall.span, _ms(1000));
      expect(
        waterfall.barOf(a),
        const WaterfallBar(start: 0, firstByte: 0.1, end: 0.4),
      );
      expect(waterfall.barOf(b), const WaterfallBar(start: 0.2, end: 1));
      expect(waterfall.barOf(a).end, greaterThan(waterfall.barOf(b).start));
    });

    test('in flight ends now; slow from a second; failed', () {
      final done = _exchange(1, at(0), total: _ms(200));
      final waiting = _exchange(2, at(500));
      final slow = _exchange(3, at(0), total: _ms(1200));
      final failed = _exchange(4, at(100), total: _ms(50), failed: true);
      final waterfall = NetworkWaterfall([
        done,
        waiting,
        slow,
        failed,
      ], at(2000));
      expect(waterfall.span, _ms(2000));
      final pending = waterfall.barOf(waiting);
      expect(pending.inFlight, isTrue);
      expect(pending.start, 0.25);
      expect(pending.end, 1);
      expect(pending.slow, isTrue, reason: 'waiting 1.5 s so far');
      expect(waterfall.barOf(slow).slow, isTrue);
      expect(waterfall.barOf(done).slow, isFalse);
      expect(waterfall.barOf(failed).failed, isTrue);
    });

    test('an instant request still shows; a WebSocket does not stretch the '
        'scale, its bar is clipped', () {
      final instant = _exchange(1, at(1000), total: Duration.zero);
      final request = _exchange(2, at(0), total: _ms(1000));
      final socket =
          WebSocketConnection(
              id: 3,
              url: Uri.parse('wss://rt.neon.books/socket'),
              started: at(500),
              requestHeaders: const [],
            )
            ..opened = true
            ..connectTime = _ms(100);
      final waterfall = NetworkWaterfall([
        instant,
        request,
        socket,
      ], at(600000));
      expect(waterfall.span, _ms(1000));
      final dot = waterfall.barOf(instant);
      expect(dot.end - dot.start, closeTo(NetworkWaterfall.minWidth, 1e-9));
      expect(dot.end, 1);
      final bar = waterfall.barOf(socket);
      expect(bar.start, 0.5);
      expect(bar.firstByte, closeTo(0.6, 1e-9));
      expect(bar.end, 1);
      expect(bar.clipped, isTrue);
      expect(bar.slow, isFalse, reason: 'a socket is never slow');
    });

    test('only WebSockets: they make the scale; nothing: an empty one', () {
      final socket =
          WebSocketConnection(
              id: 1,
              url: Uri.parse('wss://a.neon/ws'),
              started: at(0),
              requestHeaders: const [],
            )
            ..closedAfter = _ms(300)
            ..closeCode = 1000;
      final waterfall = NetworkWaterfall([socket], at(9000));
      expect(waterfall.span, _ms(300));
      expect(waterfall.barOf(socket), const WaterfallBar(start: 0, end: 1));
      expect(NetworkWaterfall(const [], at(0)).span, Duration.zero);
    });
  });

  group('WebSocket timings', () {
    test('the handshake time, the time connected, the uptime to now or the '
        'close, and the close code, reason and time', () async {
      final sockets = _SlowSockets(const Duration(milliseconds: 30));
      final journal = _journal();
      final transport = RecordingWebSocketTransport(sockets, journal);

      final session = await transport.connect(Uri.parse('wss://a.neon/ws'));
      session.messages.listen((_) {});
      final connection = journal.entries.single as WebSocketConnection;
      expect(connection.connectTime, greaterThanOrEqualTo(_ms(25)));
      expect(
        connection.connectedAt,
        connection.started.add(connection.connectTime!),
      );
      final connectedAt = connection.connectedAt!;
      expect(
        connection.uptime(connectedAt.add(const Duration(minutes: 3))),
        const Duration(minutes: 3),
      );
      expect(connection.closedAt, isNull);

      await sockets.mock.lastConnection.closeFromServer(
        const CloseStatus(4000, 'bye'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(connection.closeCode, 4000);
      expect(connection.closeReason, 'bye');
      expect(
        connection.closedAt,
        connection.started.add(connection.closedAfter!),
      );
      final up = connection.uptime(DateTime(2100))!;
      expect(up, connection.closedAt!.difference(connectedAt));
    });

    test('a failed handshake has no uptime; each frame has its time', () async {
      final sockets = MockWebSocketTransport();
      final journal = _journal();
      final transport = RecordingWebSocketTransport(sockets, journal);
      sockets.failNextConnect(WebSocketException('refused'));
      await expectLater(
        transport.connect(Uri.parse('wss://a.neon/ws')),
        throwsA(isA<WebSocketException>()),
      );
      final failed = journal.entries.single as WebSocketConnection;
      expect(failed.connectedAt, isNull);
      expect(failed.uptime(DateTime.now()), isNull);

      final session = await transport.connect(Uri.parse('wss://a.neon/ws'));
      session.sendMessage('one');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      session.sendMessage('two');
      final connection = journal.entries.last as WebSocketConnection;
      final [first, second] = connection.frames;
      expect(second.time - first.time, greaterThanOrEqualTo(_ms(15)));
      expect(connection.timeOf(second), connection.started.add(second.time));
    });

    test('the connections to an address are counted: the reconnects; a '
        'failed attempt counts, Clear starts again', () async {
      final sockets = MockWebSocketTransport();
      final journal = _journal();
      final transport = RecordingWebSocketTransport(sockets, journal);
      Future<void> connect(String url) async {
        try {
          await transport.connect(Uri.parse(url));
        } on WebSocketException {
          // A failed attempt.
        }
      }

      await connect('wss://rt.neon.books/socket?apikey=k1&vsn=2.0.0');
      sockets.failNextConnect(WebSocketException('down'));
      await connect('wss://rt.neon.books/socket?apikey=k1&vsn=2.0.0');
      await connect('wss://rt.neon.books/socket?apikey=k2&vsn=2.0.0');
      await connect('wss://other.neon/ws');
      final attempts = [
        for (final entry in journal.entries)
          (entry as WebSocketConnection).attempt,
      ];
      expect(attempts, [1, 2, 3, 1], reason: 'the key is masked: one address');
      expect((journal.entries[2] as WebSocketConnection).reconnects, 2);

      journal.clear();
      await connect('wss://other.neon/ws');
      expect((journal.entries.single as WebSocketConnection).attempt, 1);
    });

    test("Phoenix's heartbeat round trip, matched by ref; other replies "
        'and unanswered heartbeats are not', () async {
      final sockets = MockWebSocketTransport();
      final journal = _journal();
      final session = await RecordingWebSocketTransport(
        sockets,
        journal,
      ).connect(Uri.parse('wss://rt.neon.books/socket'));
      session.messages.listen((_) {});
      final server = sockets.lastConnection;

      session.sendMessage('[null,"7","phoenix","heartbeat",{}]');
      session.sendMessage('["1","8","room:lobby","phx_join",{}]');
      server.push('["1","8","room:lobby","phx_reply",{"status":"ok"}]');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      server.push('[null,"9","phoenix","phx_reply",{"status":"ok"}]');
      server.push(
        '[null,"7","phoenix","phx_reply",{"status":"ok","response":{}}]',
      );
      await Future<void>.delayed(Duration.zero);

      final connection = journal.entries.single as WebSocketConnection;
      expect(connection.latencies, hasLength(1));
      expect(connection.lastLatency, greaterThanOrEqualTo(_ms(25)));
      final labels = connection.frames.map((f) => f.label).toList();
      expect(labels[0], 'heartbeat');
      expect(labels[1], 'join room:lobby');
      expect(labels[2], isNull);
      expect(labels[3], isNull, reason: 'no heartbeat 9 was sent');
      expect(labels[4], startsWith('heartbeat reply '));
      expect(labels[4], endsWith(' ms'));

      server.push(
        '[null,"7","phoenix","phx_reply",{"status":"ok","response":{}}]',
      );
      await Future<void>.delayed(Duration.zero);
      expect(connection.latencies, hasLength(1), reason: 'answered once');

      session.sendMessage(
        '{"topic":"phoenix","event":"heartbeat",'
        '"payload":{},"ref":"10"}',
      );
      server.push(
        '{"topic":"phoenix","event":"phx_reply",'
        '"payload":{"status":"ok"},"ref":"10"}',
      );
      await Future<void>.delayed(Duration.zero);
      expect(connection.latencies, hasLength(2), reason: 'version 1');
      expect(journal.summary.lastSocketLatency, connection.lastLatency);
    });

    test('the round trips kept are the last max-latencies; heartbeats never '
        'answered do not pile up', () async {
      final sockets = MockWebSocketTransport();
      final journal = _journal();
      final session = await RecordingWebSocketTransport(
        sockets,
        journal,
      ).connect(Uri.parse('wss://rt.neon.books/socket'));
      session.messages.listen((_) {});
      final connection = journal.entries.single as WebSocketConnection;
      for (var ref = 0; ref < 70; ref++) {
        session.sendMessage('[null,"$ref","phoenix","heartbeat",{}]');
        sockets.lastConnection.push(
          '[null,"$ref","phoenix","phx_reply",{"status":"ok"}]',
        );
        await Future<void>.delayed(Duration.zero);
      }
      expect(connection.latencies, hasLength(connection.maxLatencies));

      for (var ref = 100; ref < 200; ref++) {
        session.sendMessage('[null,"$ref","phoenix","heartbeat",{}]');
      }
      sockets.lastConnection.push(
        '[null,"100","phoenix","phx_reply",{"status":"ok"}]',
      );
      sockets.lastConnection.push(
        '[null,"199","phoenix","phx_reply",{"status":"ok"}]',
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        connection.frames.last.label,
        startsWith('heartbeat reply'),
        reason: 'the newest heartbeats are kept, the oldest dropped',
      );
      expect(
        connection.frames[connection.frames.length - 2].label,
        isNull,
      );
    });

    test('the Phoenix matcher', () {
      const matcher = PhoenixHeartbeatMatcher();
      expect(matcher.ping('[null,"3","phoenix","heartbeat",{}]'), '3');
      expect(
        matcher.ping(' [ null , "3" , "phoenix" , "heartbeat" , {} ]'),
        '3',
      );
      expect(matcher.ping('[null,"3","phoenix","phx_heartbeat",{}]'), '3');
      expect(matcher.ping('[null,"3","phoenix","phx_reply",{}]'), isNull);
      expect(matcher.ping('["1","3","room:phoenix","heartbeat",{}]'), isNull);
      expect(
        matcher.ping('["1","3","room","new_msg",{"x":"phoenix"}]'),
        isNull,
      );
      expect(matcher.pong('[null,"3","phoenix","phx_reply",{}]'), '3');
      expect(matcher.pong('["1","3","room","phx_reply",{}]'), isNull);
      expect(
        matcher.ping('{"topic":"phoenix","event":"heartbeat","ref":"4"}'),
        '4',
      );
      expect(
        matcher.pong('{"topic":"phoenix","event":"phx_reply","ref":"4"}'),
        '4',
      );
      expect(
        matcher.pong(
          '{"topic":"room","event":"phx_reply","ref":"4","x":"phoenix"}',
        ),
        isNull,
      );
      expect(matcher.ping('plain'), isNull);
    });
  });

  test('the summary: requests in flight and the last round trip of the '
      'newest open WebSocket', () async {
    final journal = _journal();
    final gate = Completer<void>();
    final transport = RecordingHttpTransport(_GatedTransport(gate), journal);
    final pending = transport.send(_get('https://api.neon.books/slow'));
    await Future<void>.delayed(Duration.zero);
    final sockets = MockWebSocketTransport();
    final recorder = RecordingWebSocketTransport(sockets, journal);
    final first = await recorder.connect(Uri.parse('wss://a.neon/ws'));
    first.messages.listen((_) {});
    final second = await recorder.connect(Uri.parse('wss://b.neon/ws'));
    second.messages.listen((_) {});
    first.sendMessage('[null,"1","phoenix","heartbeat",{}]');
    sockets.connections.first.push('[null,"1","phoenix","phx_reply",{}]');
    await Future<void>.delayed(Duration.zero);

    var summary = journal.summary;
    expect(summary.requestsInFlight, 1);
    expect(summary.inFlight, 3, reason: 'the request and two sockets');
    expect(summary.openSockets, 2);
    final firstLatency =
        (journal.entries[1] as WebSocketConnection).lastLatency;
    expect(summary.lastSocketLatency, firstLatency);

    second.sendMessage('[null,"2","phoenix","heartbeat",{}]');
    sockets.connections.last.push('[null,"2","phoenix","phx_reply",{}]');
    await Future<void>.delayed(Duration.zero);
    expect(
      journal.summary.lastSocketLatency,
      (journal.entries[2] as WebSocketConnection).lastLatency,
    );

    gate.complete();
    await pending;
    await second.close();
    summary = journal.summary;
    expect(summary.requestsInFlight, 0);
    expect(summary.lastSocketLatency, firstLatency, reason: 'b is closed');
  });

  group('the Network tab', () {
    Future<void> pump(WidgetTester tester, DebugNetworkJournal journal) async {
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
    }

    testWidgets('each row has its waterfall bar; a WebSocket row its '
        'handshake, uptime, heartbeat and reconnects', (tester) async {
      final journal = DebugNetworkJournal(schedule: (notify) => notify());
      late MockWebSocketTransport sockets;
      await tester.runAsync(() async {
        final transport = RecordingHttpTransport(_Transport(), journal);
        await transport.send(_get('https://api.neon.books/books'));
        sockets = MockWebSocketTransport();
        final recorder = RecordingWebSocketTransport(sockets, journal);
        final old = await recorder.connect(Uri.parse('wss://rt.neon/socket'));
        await old.close();
        final session = await recorder.connect(
          Uri.parse('wss://rt.neon/socket'),
        );
        session.messages.listen((_) {});
        session.sendMessage('[null,"1","phoenix","heartbeat",{}]');
        sockets.lastConnection.push('[null,"1","phoenix","phx_reply",{}]');
        await Future<void>.delayed(Duration.zero);
      });
      await pump(tester, journal);

      for (final id in [1, 2, 3]) {
        expect(find.byKey(NetworkView.barKey(id)), findsOneWidget);
      }
      final line = tester.widget<Text>(find.byKey(NetworkView.socketKey(3)));
      expect(line.data, startsWith('connect '));
      expect(line.data, contains(' · up '));
      expect(line.data, contains(' · heartbeat '));
      expect(line.data, endsWith(' · reconnect 1'));
      final closed = tester.widget<Text>(find.byKey(NetworkView.socketKey(2)));
      expect(closed.data, contains('was up'));
      expect(find.byKey(NetworkView.socketKey(1)), findsNothing);
      final bar = tester.widget<CustomPaint>(find.byKey(NetworkView.barKey(1)));
      expect((bar.painter! as WaterfallBarPainter).bar.end, 1);

      await tester.tap(find.text('/socket').first);
      await tester.pump();
      expect(find.text('Connected at'), findsOneWidget);
      expect(find.text('Uptime'), findsOneWidget);
      expect(
        find.textContaining('1 (connection 2 to this address)'),
        findsOneWidget,
      );
      expect(find.text('Heartbeat round trips (1)'), findsOneWidget);
      expect(find.textContaining('last '), findsOneWidget);
      expect(
        find.textContaining('heartbeat reply', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets("a request's detail breaks its time into phases", (
      tester,
    ) async {
      final journal = DebugNetworkJournal(schedule: (notify) => notify());
      final timings = _Timings()
        ..entries['https://api.neon.books/books'] = const [_browserEntry];
      await tester.runAsync(() async {
        final browser = RecordingHttpTransport(
          _Transport(),
          journal,
          resourceTiming: ResourceTimingReader(timings),
        );
        await browser.send(_get('https://api.neon.books/books'));
        final restricted = ResourceTimingReader(
          _Timings()
            ..entries['https://cdn.neon/a'] = const [
              ResourceTimingEntry(startTime: 1000, responseEnd: 1010),
            ],
        );
        await RecordingHttpTransport(
          _Transport(),
          journal,
          resourceTiming: restricted,
        ).send(_get('https://cdn.neon/a'));
        await RecordingHttpTransport(
          _Transport(),
          journal,
        ).send(_get('https://api.neon.books/plain'));
      });
      await pump(tester, journal);

      await tester.tap(find.text('/books'));
      await tester.pump();
      expect(find.text('Timing'), findsOneWidget);
      for (final phase in [
        'Queued',
        'DNS',
        'TCP',
        'TLS',
        'Waiting',
        'Download',
      ]) {
        expect(find.text(phase), findsOneWidget, reason: phase);
      }
      expect(find.text('100 ms (browser)'), findsOneWidget);
      expect(find.text('h2'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pump();

      await tester.tap(find.text('/a'));
      await tester.pump();
      expect(find.textContaining('Timing-Allow-Origin'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pump();

      await tester.tap(find.text('/plain'));
      await tester.pump();
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Timing'), findsNothing, reason: 'one phase: no split');
      expect(find.textContaining('a whole response'), findsOneWidget);
    });

    testWidgets('while something is in flight the tab refreshes once a '
        'second, and stops after', (tester) async {
      final journal = DebugNetworkJournal(schedule: (notify) => notify());
      final sockets = MockWebSocketTransport();
      late WebSocketSession session;
      await tester.runAsync(() async {
        session = await RecordingWebSocketTransport(
          sockets,
          journal,
        ).connect(Uri.parse('wss://rt.neon/socket'));
      });
      await pump(tester, journal);
      Widget row() => tester.widget(find.byKey(NetworkView.rowKey(1)));
      final before = row();
      await tester.pump(const Duration(milliseconds: 500));
      expect(row(), same(before), reason: 'not yet');
      await tester.pump(const Duration(milliseconds: 600));
      expect(row(), isNot(same(before)), reason: 'rebuilt after a second');

      await tester.runAsync(session.close);
      await tester.pump();
      final closed = row();
      await tester.pump(const Duration(seconds: 3));
      expect(row(), same(closed), reason: 'nothing in flight: no refresh');
    });
  });
}

Duration _ms(num milliseconds) =>
    Duration(microseconds: (milliseconds * 1000).round());

final class _FailingTransport implements HttpTransport {
  @override
  Future<HttpResponse> send(HttpRequest request) async =>
      throw HttpTransportException('connection failed: refused');

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async =>
      throw HttpTransportException('connection failed: refused');

  @override
  void close() {}
}

final class _GatedTransport implements HttpTransport {
  _GatedTransport(this.gate);

  final Completer<void> gate;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    await gate.future;
    return HttpResponse(200, request: request);
  }

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) =>
      throw UnimplementedError();

  @override
  void close() {}
}
