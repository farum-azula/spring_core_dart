import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

HttpRequest _get(String url) =>
    HttpRequest(method: HttpMethod.get, url: Uri.parse(url));

void main() {
  test('prepared responses by method, path and query', () async {
    final transport = MockHttpTransport()
      ..when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1'})
      ..when(HttpMethod.get, '/books?q=dune').respond(200, body: 'found')
      ..when(HttpMethod.get, 'https://other.host/x').respond(204);
    final book = await transport.send(_get('https://api.neon.books/books/1'));
    expect(book.statusCode, 200);
    expect(book.bodyText, '{"isbn":"1"}');
    expect(book.headers['content-type'], 'application/json');
    expect(
      (await transport.send(_get('http://h/books?q=dune'))).bodyText,
      'found',
    );
    expect(
      (await transport.send(_get('https://other.host/x'))).statusCode,
      204,
    );
    expect(
      () => transport.send(_get('http://h/books?q=other')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Expected: GET /books/1'),
        ),
      ),
    );
    expect(
      () => transport.send(
        HttpRequest(
          method: HttpMethod.post,
          url: Uri.parse('http://h/books/1'),
        ),
      ),
      throwsStateError,
    );
    expect(transport.requests, hasLength(5));
    expect(transport.lastRequest.method, HttpMethod.post);
  });

  test(
    'answers in order, the last one repeats; handlers and failures',
    () async {
      final transport = MockHttpTransport();
      transport
          .when(HttpMethod.get, '/flaky')
          .fail(HttpTransportException('down'));
      transport.when(HttpMethod.get, '/flaky').respond(200, body: 'up');
      transport
          .when(HttpMethod.post, '/echo')
          .respondWith(
            (request) =>
                HttpResponse(201, body: request.body!, request: request),
          );
      await expectLater(
        transport.send(_get('/flaky')),
        throwsA(isA<HttpTransportException>()),
      );
      expect((await transport.send(_get('/flaky'))).bodyText, 'up');
      expect((await transport.send(_get('/flaky'))).bodyText, 'up');
      final echoed = await transport.send(
        HttpRequest(
          method: HttpMethod.post,
          url: Uri.parse('/echo'),
          body: const [104, 105],
        ),
      );
      expect(echoed.statusCode, 201);
      expect(echoed.bodyText, 'hi');
      transport.reset();
      expect(transport.requests, isEmpty);
      expect(() => transport.lastRequest, throwsStateError);
      transport.when(HttpMethod.get, '/x');
      expect(() => transport.send(_get('/x')), throwsStateError);
    },
  );

  group('a streamed body', () {
    HttpRequest post(StreamingBody body) => HttpRequest(
      method: HttpMethod.post,
      url: Uri.parse('/upload'),
      streamingBody: body,
    );

    Stream<List<int>> chunks() => Stream.fromIterable([
      [1, 2],
      [3],
    ]);

    test('is read as a server reads it and kept for the test', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.post, '/upload').respond(201);
      final body = StreamingBody(chunks(), length: 3);
      expect((await transport.send(post(body))).statusCode, 201);
      expect(transport.lastRequest.body, [1, 2, 3]);
      expect(transport.lastRequest.streamingBody, isNull);
      expect(transport.lastRequest.url, Uri.parse('/upload'));
      expect(body.isConsumed, isTrue);
      // Read once: a second attempt fails as with a real server.
      expect(
        () => transport.send(post(body)),
        throwsA(isA<NonRepeatableBodyException>()),
      );
    });

    test('a failure reads it too', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.post, '/upload').fail(HttpTransportException('x'));
      final body = StreamingBody(chunks());
      await expectLater(
        transport.send(post(body)),
        throwsA(isA<HttpTransportException>()),
      );
      expect(body.isConsumed, isTrue);
    });

    test('respondWith gets it unread', () async {
      final transport = MockHttpTransport()
        ..when(HttpMethod.post, '/upload').respondWith(
          (request) async => HttpResponse(
            200,
            body: await request.streamingBody!.toBytes(),
          ),
        );
      final response = await transport.send(post(StreamingBody(chunks())));
      expect(response.bodyBytes, [1, 2, 3]);
      // A repeatable one again, through stream().
      final streamed = await transport.stream(
        post(StreamingBody.repeatable(chunks, length: 3)),
      );
      expect(await streamed.body.expand((c) => c).toList(), [1, 2, 3]);
    });

    test('one respondWith left unread is read after it', () async {
      final transport = MockHttpTransport()
        ..when(
          HttpMethod.post,
          '/upload',
        ).respondWith((request) => HttpResponse(204));
      final body = StreamingBody(chunks());
      await transport.send(post(body));
      expect(body.isConsumed, isTrue);
    });
  });
}
