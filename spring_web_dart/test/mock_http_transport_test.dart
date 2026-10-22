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
}
