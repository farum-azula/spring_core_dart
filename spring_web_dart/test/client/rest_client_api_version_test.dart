import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

// API versions, as Spring Framework 7's RestClient sends them: the
// client's default or a call's own, put into the request by the
// ApiVersionInserter; a version without an inserter is a StateError.
void main() {
  late MockHttpTransport server;

  RestClientBuilder builder() =>
      RestClient.builder().baseUrl('https://api.neon.books').transport(server);

  setUp(() {
    server = MockHttpTransport()
      ..when(HttpMethod.get, '/books').respond(200, body: 'ok')
      ..when(HttpMethod.get, '/1.2/books').respond(200, body: 'ok')
      ..when(HttpMethod.get, '/books/1.2/978-0').respond(200, body: 'ok')
      ..when(HttpMethod.post, '/books').respond(201, body: 'ok');
  });

  Future<HttpRequest> get(RestClient rest, {Object? version = _none}) async {
    final spec = rest.get().uri('/books');
    await (identical(version, _none) ? spec : spec.apiVersion(version))
        .retrieve()
        .body<String>();
    return server.lastRequest;
  }

  group('the inserters', () {
    test('a header: the default version, a call replacing it', () async {
      final rest = builder()
          .apiVersionInserter(ApiVersionInserter.useHeader('API-Version'))
          .defaultApiVersion('1.2')
          .build();
      expect((await get(rest)).headers['API-Version'], '1.2');
      expect(
        (await get(rest, version: '2.0')).headers.getAll('API-Version'),
        ['2.0'],
      );
    });

    test("apiVersion(null) sends none, as Spring's NO_VERSION", () async {
      final rest = builder()
          .apiVersionInserter(ApiVersionInserter.useHeader('API-Version'))
          .defaultApiVersion('1.2')
          .build();
      final request = await get(rest, version: null);
      expect(request.headers.contains('API-Version'), isFalse);
    });

    test('the version replaces a header of the same name', () async {
      final rest = builder()
          .apiVersionInserter(ApiVersionInserter.useHeader('API-Version'))
          .defaultHeader('API-Version', '0.1')
          .defaultApiVersion('1.2')
          .build();
      expect((await get(rest)).headers.getAll('API-Version'), ['1.2']);
    });

    test('a query parameter, after those of the URI', () async {
      final rest = builder()
          .apiVersionInserter(ApiVersionInserter.useQueryParam('version'))
          .defaultApiVersion('1.2')
          .build();
      await rest.get().uri('/books?sort=title').retrieve().body<String>();
      expect(server.lastRequest.url.query, 'sort=title&version=1.2');
      expect((await get(rest, version: '2 beta')).url.query, 'version=2+beta');
    });

    test('a path segment, at its index', () async {
      final first = builder()
          .apiVersionInserter(ApiVersionInserter.usePathSegment(0))
          .defaultApiVersion('1.2')
          .build();
      expect('${(await get(first)).url}', 'https://api.neon.books/1.2/books');
      final second = builder()
          .apiVersionInserter(ApiVersionInserter.usePathSegment(1))
          .defaultApiVersion('1.2')
          .build();
      await second.get().uri('/books/978-0').retrieve().body<String>();
      expect(server.lastRequest.url.path, '/books/1.2/978-0');
    });

    test("a path segment past the end is a StateError, as Spring's", () async {
      final rest = builder()
          .apiVersionInserter(ApiVersionInserter.usePathSegment(3))
          .defaultApiVersion('1.2')
          .build();
      await expectLater(
        get(rest),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            "Cannot insert version into '/books' at path segment index 3",
          ),
        ),
      );
    });

    test("a parameter of the Content-Type, the converter's too", () async {
      final rest = builder()
          .apiVersionInserter(ApiVersionInserter.useMediaTypeParam('v'))
          .defaultApiVersion('1.2')
          .build();
      await rest
          .post()
          .uri('/books')
          .body({'title': 'Dune'})
          .retrieve()
          .toBodilessEntity();
      expect(server.lastRequest.headers.contentType, 'application/json;v=1.2');
      // No body, no Content-Type: nothing to add the parameter to.
      expect((await get(rest)).headers.contentType, isNull);
    });

    test('several places and a formatter, through the builder', () async {
      final rest = builder()
          .apiVersionInserter(
            ApiVersionInserter.builder()
                .useHeader('API-Version')
                .useQueryParam('v')
                .withVersionFormatter((version) => 'v$version')
                .build(),
          )
          .defaultApiVersion(2)
          .build();
      final request = await get(rest);
      expect(request.headers['API-Version'], 'v2');
      expect(request.url.query, 'v=v2');
    });

    test('a builder with no place set throws', () {
      expect(
        () => ApiVersionInserter.builder().build(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an inserter of its own, extending the class', () async {
      final rest = builder()
          .apiVersionInserter(const _AcceptVersion())
          .defaultApiVersion('3')
          .build();
      expect(
        (await get(rest)).headers[HttpHeaders.acceptHeader],
        'application/vnd.neon.v3+json',
      );
    });

    test('a version with a line break is refused, not sent', () async {
      final rest = builder()
          .apiVersionInserter(ApiVersionInserter.useHeader('API-Version'))
          .build();
      await expectLater(
        get(rest, version: '1\r\nX-Injected: 1'),
        throwsA(isA<ArgumentError>()),
      );
      expect(server.requests, isEmpty);
    });
  });

  group('without an inserter', () {
    test('no version: nothing changes', () async {
      final request = await get(builder().build());
      expect(request.headers.names, isNot(contains('API-Version')));
      expect('${request.url}', 'https://api.neon.books/books');
    });

    test('a call with a version is a StateError, as in Spring', () async {
      await expectLater(
        get(builder().build(), version: '1.2'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            startsWith('No ApiVersionInserter configured'),
          ),
        ),
      );
      expect(server.requests, isEmpty);
    });

    test('a default version is a StateError at the call', () async {
      final rest = builder().defaultApiVersion('1.2').build();
      await expectLater(get(rest), throwsA(isA<StateError>()));
    });
  });

  test('mutate keeps the version and the inserter', () async {
    final rest = builder()
        .apiVersionInserter(ApiVersionInserter.useHeader('API-Version'))
        .defaultApiVersion('1.2')
        .build()
        .mutate()
        .build();
    expect((await get(rest)).headers['API-Version'], '1.2');
  });

  test('the version is in the request the interceptors see', () async {
    final seen = <String?>[];
    final rest = builder()
        .apiVersionInserter(ApiVersionInserter.useHeader('API-Version'))
        .defaultApiVersion('1.2')
        .requestInterceptor(
          ClientHttpRequestInterceptor.of((request, body, execution) {
            seen.add(request.headers['API-Version']);
            return execution.execute(request, body);
          }),
        )
        .build();
    await get(rest);
    expect(seen, ['1.2']);
  });
}

const _none = Object();

final class _AcceptVersion extends ApiVersionInserter {
  const _AcceptVersion();

  @override
  void insertVersionIntoHeaders(Object version, HttpHeaders headers) =>
      headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.neon.v$version+json',
      );
}
