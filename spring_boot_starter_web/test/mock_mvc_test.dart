import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('MockMvc (no server)', () {
    final app = springBootTest(
      testApplication,
      properties: {'logging.level.root': 'warn'},
    );

    test('no server runs in the mock web environment', () {
      expect(app.environment.getProperty('local.server.port'), isNull);
      expect(() => app.localServerPort, throwsStateError);
    });

    test('calls the controllers in memory', () async {
      final mvc = app.mockMvc;
      await mvc
          .get('/api/books/1111')
          .andExpect(
            status: 200,
            contentType: MediaType.applicationJson,
            headers: {'X-Trace': 'on'},
            json: {
              'isbn': '1111',
              'title': 'Dune',
              'stock': 3,
              'genre': 'fiction',
            },
          );
      await mvc
          .get('/api/books', params: {'q': 'dune'})
          .andExpect(status: 200, json: hasLength(1));
      await mvc
          .post('/api/books', json: {'isbn': '', 'title': ''})
          .andExpect(
            status: 400,
            contentType: MediaType.applicationProblemJson,
          );
      await mvc.delete('/api/books/2222').andExpect(status: 204);
      await mvc.get('/misc/text').andExpect(body: 'hello');
    });

    test('a builder with uri variables, headers and cookies', () async {
      await app.mockMvc
          .perform(
            MockRequestBuilder(HttpMethod.get, '/misc/echo-header')
              ..headers['X-Name'] = 'Bob',
          )
          .andExpect(body: 'hi Bob');
      await app.mockMvc
          .perform(
            MockRequestBuilder(HttpMethod.get, '/api/books/{isbn}', ['1111']),
          )
          .andExpect(json: containsPair('title', 'Dune'));
      await app.mockMvc
          .perform(
            MockRequestBuilder(HttpMethod.get, '/misc/cookie')
              ..cookies['session'] = 's1',
          )
          .andExpect(body: 's1');
    });

    test('server-sent events, read as they come', () async {
      final result = await app.mockMvc.get('/api/books/changes').andReturn();
      expect(
        result.response.headers.contentType,
        startsWith('text/event-stream'),
      );
      final next = result.response.eventStream.firstWhere(
        (e) => e.data != null,
      );
      await app.mockMvc.post(
        '/api/books',
        json: {'isbn': '5555', 'title': 'Vurt'},
      );
      final event = await next;
      expect(event.id, '5555');
      expect(event.data, contains('Vurt'));
      await result.cancel();
    });

    test('a failed expectation names the request and the response', () async {
      await expectLater(
        app.mockMvc.get('/api/books/1111').andExpect(status: 404),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            allOf(contains('GET'), contains('expected status 404, got 200')),
          ),
        ),
      );
    });
  });

  group('a real server on a random port', () {
    final app = springBootTest(
      testApplication,
      webEnvironment: WebEnvironment.randomPort,
      properties: {'logging.level.root': 'warn', 'server.address': '127.0.0.1'},
    );

    test('localServerPort answers', () async {
      final client = Client(app.localServerPort);
      try {
        final reply = await client.get('/misc/text');
        expect(reply.body, 'hello');
      } finally {
        client.close();
      }
    });
  });
}
