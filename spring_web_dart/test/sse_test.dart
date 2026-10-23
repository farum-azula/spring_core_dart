import 'dart:async';
import 'dart:convert';

import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

Stream<List<int>> _chunks(List<String> parts) =>
    Stream.fromIterable([for (final part in parts) utf8.encode(part)]);

HttpRequest _get(String url, [String? lastEventId]) => HttpRequest(
  method: HttpMethod.get,
  url: Uri.parse(url),
  headers: HttpHeaders({
    HttpHeaders.acceptHeader: MediaType.textEventStream,
    'Last-Event-ID': ?lastEventId,
  }),
);

void main() {
  group('SseDecoder', () {
    test('data, id, event, retry and comments, split anywhere', () async {
      final events = await _chunks([
        '﻿: hello\n',
        'id: 1\nevent: order-created\nda',
        'ta: {"id":1}\n\n',
        'data: line one\r\ndata: line two\r\n\r',
        '\nretry: 2500\n\n',
        'data\n\n',
        'data:no space\nid\n\n',
        'data: unfinished',
      ]).transform(const SseDecoder()).toList();
      expect(events, [
        const ServerSentEvent<String?>(
          '{"id":1}',
          id: '1',
          event: 'order-created',
          comment: 'hello',
        ),
        const ServerSentEvent<String?>('line one\nline two'),
        const ServerSentEvent<String?>(
          null,
          retry: Duration(milliseconds: 2500),
        ),
        const ServerSentEvent<String?>(''),
        const ServerSentEvent<String?>('no space', id: ''),
      ]);
    });

    test('parse, ignored fields and bad retry values', () {
      final events = SseDecoder.parse(
        'foo: bar\nretry: soon\ndata: x\n\n:heartbeat\n\n',
      );
      expect(events, [
        const ServerSentEvent<String?>('x'),
        const ServerSentEvent<String?>(null, comment: 'heartbeat'),
      ]);
    });

    test('encode is read back the same', () {
      const event = ServerSentEvent(
        'a\nb',
        id: '7',
        event: 'note',
        retry: Duration(seconds: 1),
        comment: 'c',
      );
      expect(
        event.encode(),
        ': c\nid: 7\nevent: note\nretry: 1000\ndata: a\ndata: b\n\n',
      );
      expect(SseDecoder.parse(event.encode()).single, event);
      expect(ServerSentEvent({'n': 1}).encode(jsonEncode), 'data: {"n":1}\n\n');
    });
  });

  group('EventStream', () {
    test('is a stream of the data; events carry the rest', () async {
      final stream = EventStream<int>(
        () => Stream.fromIterable(const [
          ServerSentEvent(1, id: 'a'),
          ServerSentEvent(2, event: 'tick'),
        ]),
      );
      expect(await stream.toList(), [1, 2]);
      expect(stream.lastEventId, 'a');
      final events = await stream.events.toList();
      expect(events.last.event, 'tick');
      // Cold: every listener gets its own run.
      expect(await stream.first, 1);
    });

    test('factories for fallbacks and tests', () async {
      expect(await EventStream.fromIterable(['a', 'b']).toList(), ['a', 'b']);
      expect(await EventStream.of(Stream.value(3)).toList(), [3]);
      expect(await EventStream<int>.empty().toList(), isEmpty);
      final events = EventStream.fromEvents(
        Stream.value(const ServerSentEvent('x', id: '9')),
      );
      expect((await events.events.single).id, '9');
      expect(EventStream.fromIterable([1]), isA<Stream<int>>());
    });
  });

  group('connectServerSentEvents', () {
    late MockHttpTransport server;
    const url = 'https://api.neon.test/events';

    Stream<ServerSentEvent<String>> connect({
      SseReconnect reconnect = const SseReconnect(
        delay: Duration(milliseconds: 5),
      ),
      void Function(Object? error, Duration delay, int attempt)? onReconnect,
    }) => connectServerSentEvents(
      (lastEventId) async {
        final response = await server.stream(_get(url, lastEventId));
        if (!response.isSuccess && response.statusCode != 204) {
          throw StateError('HTTP ${response.statusCode}');
        }
        return response;
      },
      reconnect: reconnect,
      onReconnect: onReconnect,
    );

    setUp(() => server = MockHttpTransport());

    test('reconnects with Last-Event-ID and the server retry', () async {
      server
        ..when(HttpMethod.get, url).respondEvents([
          const ServerSentEvent('one', id: '1'),
          const ServerSentEvent(null, retry: Duration(milliseconds: 1)),
        ])
        ..when(
          HttpMethod.get,
          url,
        ).respondEvents([const ServerSentEvent('two', id: '2')])
        ..when(HttpMethod.get, url).respond(204);
      final delays = <Duration>[];
      final events = await connect(
        onReconnect: (_, delay, _) => delays.add(delay),
      ).toList();
      expect([for (final e in events) e.data], ['one', 'two']);
      expect(events.first.id, '1');
      expect(
        [for (final r in server.requests) r.headers['Last-Event-ID']],
        [null, '1', '2'],
      );
      expect(delays, everyElement(const Duration(milliseconds: 1)));
    });

    test('transport failures are retried, other errors end it', () async {
      server
        ..when(HttpMethod.get, url).fail(HttpTransportException('down'))
        ..when(HttpMethod.get, url).respondEvents([const ServerSentEvent('up')])
        ..when(HttpMethod.get, url).respond(500);
      final seen = <Object?>[];
      final data = <String>[];
      final done = Completer<Object>();
      connect(onReconnect: (error, _, _) => seen.add(error)).listen(
        (e) => data.add(e.data),
        onError: (Object error) => done.complete(error),
      );
      final error = await done.future;
      expect(error, isA<StateError>());
      expect(data, ['up']);
      expect(seen.first, isA<HttpTransportException>());
    });

    test('never and maxAttempts stop reconnecting', () async {
      server.when(HttpMethod.get, url).respondEvents([
        const ServerSentEvent('x'),
      ]);
      expect(
        await connect(reconnect: SseReconnect.never)
            .map((e) => e.data)
            .toList(),
        ['x'],
      );
      expect(server.requests, hasLength(1));

      server
        ..reset()
        ..when(HttpMethod.get, url).respondEvents(const []);
      await connect(
        reconnect: const SseReconnect(
          delay: Duration(milliseconds: 1),
          maxAttempts: 3,
        ),
      ).toList();
      expect(server.requests, hasLength(3));

      server
        ..reset()
        ..when(HttpMethod.get, url).fail(HttpTransportException('down'));
      await expectLater(
        connect(
          reconnect: const SseReconnect(
            delay: Duration(milliseconds: 1),
            maxAttempts: 2,
          ),
        ).toList(),
        throwsA(isA<HttpTransportException>()),
      );
    });

    test('cancelling closes the open connection', () async {
      var cancelled = false;
      server.when(HttpMethod.get, url).respondStream(200, () {
        late final StreamController<List<int>> body;
        body = StreamController<List<int>>(
          onListen: () => body.add(utf8.encode('data: hi\n\n')),
          onCancel: () => cancelled = true,
        );
        return body.stream;
      });
      final first = await connect().first;
      expect(first.data, 'hi');
      expect(cancelled, isTrue);
      expect(server.requests, hasLength(1));
    });

    test('through EventStream with decoding', () async {
      server
        ..when(HttpMethod.get, url).respondEvents([
          ServerSentEvent({'n': 1}, id: 'a'),
          ServerSentEvent({'n': 2}, id: 'b'),
        ])
        ..when(HttpMethod.get, url).respond(204);
      final numbers = EventStream<int>(
        () => connect().map(
          (e) => e.withData(
            (jsonDecode(e.data) as Map<String, Object?>)['n']! as int,
          ),
        ),
      );
      expect(await numbers.toList(), [1, 2]);
      expect(numbers.lastEventId, 'b');
    });
  });

  test('MockHttpTransport.respondEvents is readable as a whole too', () async {
    final server = MockHttpTransport()
      ..when(
        HttpMethod.get,
        '/e',
      ).respondEvents([const ServerSentEvent('x', event: 'e')]);
    final response = await server.send(_get('http://h/e'));
    expect(
      response.headers[HttpHeaders.contentTypeHeader],
      MediaType.textEventStream,
    );
    expect(response.bodyText, 'event: e\ndata: x\n\n');
  });
}
