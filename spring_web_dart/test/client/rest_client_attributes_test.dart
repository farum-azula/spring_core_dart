import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

// Request attributes: set on a call, by defaultRequest or by hand through
// attributes(...), handed to the interceptors, never sent.
void main() {
  late MockHttpTransport server;
  late List<Map<String, Object?>> seen;

  RestClientBuilder builder() => RestClient.builder()
      .baseUrl('https://api.neon.books')
      .transport(server)
      .requestInterceptor(
        ClientHttpRequestInterceptor.of((request, body, execution) {
          seen.add({...request.attributes});
          return execution.execute(request, body);
        }),
      );

  setUp(() {
    server = MockHttpTransport()
      ..when(HttpMethod.get, '/books').respond(200, body: 'ok')
      ..when(HttpMethod.post, '/books').respond(201, body: 'ok');
    seen = [];
  });

  test(
    "a call's attribute reaches the interceptors, not the server",
    () async {
      final rest = builder().build();
      await rest
          .get()
          .uri('/books')
          .attribute('tenant', 'neon')
          .retrieve()
          .body<String>();
      await rest
          .post()
          .uri('/books')
          .attribute('tenant', 'farum')
          .body('x')
          .retrieve()
          .toBodilessEntity();
      expect(seen, [
        {'tenant': 'neon'},
        {'tenant': 'farum'},
      ]);
      final sent = server.requests.first;
      expect(sent.headers.names, isNot(contains('tenant')));
      expect(sent.url.query, isEmpty);
    },
  );

  test(
    'defaultRequest sets them for every call; a call replaces one',
    () async {
      final rest = builder()
          .defaultRequest(
            (spec) => spec
              ..attribute('tenant', 'neon')
              ..attribute('trace', true),
          )
          .build();
      await rest.get().uri('/books').retrieve().body<String>();
      await rest
          .get()
          .uri('/books')
          .attribute('tenant', 'farum')
          .retrieve()
          .body<String>();
      expect(seen, [
        {'tenant': 'neon', 'trace': true},
        {'tenant': 'farum', 'trace': true},
      ]);
    },
  );

  test('attributes(...) changes the map; each request has its own', () async {
    final rest = builder()
        .requestInterceptor(
          ClientHttpRequestInterceptor.of((request, body, execution) {
            request.attributes['seen-by'] = 'second';
            return execution.execute(request, body);
          }),
        )
        .build();
    await rest
        .get()
        .uri('/books')
        .attributes((attributes) => attributes['tenant'] = 'neon')
        .retrieve()
        .body<String>();
    await rest.get().uri('/books').retrieve().body<String>();
    expect(seen, [
      {'tenant': 'neon'},
      <String, Object?>{},
    ]);
  });

  test(
    'a client without interceptors sends read-only empty attributes',
    () async {
      final rest = RestClient.builder()
          .baseUrl('https://api.neon.books')
          .transport(server)
          .build();
      await rest.get().uri('/books').retrieve().body<String>();
      expect(server.requests.single.attributes, isEmpty);
    },
  );
}
