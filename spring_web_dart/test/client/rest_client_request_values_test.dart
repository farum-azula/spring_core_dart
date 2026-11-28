import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

// What a request accepts in a header or a cookie (nothing that ends the
// line or the pair), the query parameters of a map, and the
// UriBuilderFactory that expands a URL against another base.
void main() {
  late MockHttpTransport server;
  late RestClient rest;

  setUp(() {
    server = MockHttpTransport()
      ..when(HttpMethod.get, '/books').respond(200, body: 'ok');
    rest = RestClient.builder()
        .baseUrl('https://api.neon.books')
        .transport(server)
        .build();
  });

  group('header injection', () {
    for (final value in ['a\r\nX-Injected: 1', 'a\nb', 'a\rb', 'a\u0000b']) {
      test('a header value ${value.codeUnits} is refused', () {
        expect(
          () => rest.get().uri('/books').header('X-Tag', value),
          throwsA(isA<ArgumentError>()),
        );
      });
    }

    test('a header name that is no token is refused', () {
      for (final name in ['X Tag', 'X-Tag:', 'X\r\nY', '']) {
        expect(
          () => rest.get().uri('/books').header(name, 'v'),
          throwsA(isA<ArgumentError>()),
          reason: name,
        );
      }
    });

    test('headers(...) is checked after it ran', () {
      expect(
        () => rest
            .get()
            .uri('/books')
            .headers((headers) => headers.add('X-Tag', 'a\r\nX-Injected: 1')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a default header is checked when the client is built', () {
      expect(
        () => RestClient.builder()
            .transport(server)
            .defaultHeader('X-Tag', 'a\nb')
            .build(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a cookie value with ";" or a line break is refused', () {
      for (final value in ['a; admin=1', 'a\r\nb', 'a\u0000']) {
        expect(
          () => rest.get().uri('/books').cookie('session', value),
          throwsA(isA<ArgumentError>()),
          reason: value,
        );
      }
      expect(
        () => rest.get().uri('/books').cookie('a=b', 'v'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a tab, spaces and other text stay as they are', () async {
      await rest
          .get()
          .uri('/books')
          .header('X-Tag', 'a\tb c, "d"')
          .cookie('session', 'a b')
          .retrieve()
          .body<String>();
      expect(server.lastRequest.headers['X-Tag'], 'a\tb c, "d"');
      expect(server.lastRequest.headers['Cookie'], 'session=a b');
    });
  });

  group('UriBuilder.queryParams', () {
    test('one parameter per entry, per item; nulls left out', () {
      final uri = UriBuilder('https://api.neon.books')
          .path('/books')
          .queryParams({
            'author': 'Frank Herbert',
            'tag': ['sf', null, 'classic'],
            'year': null,
            'shelf': _Shelf.fiction,
          })
          .build();
      expect(
        '$uri',
        'https://api.neon.books/books?author=Frank%20Herbert&tag=sf'
            '&tag=classic&shelf=fiction',
      );
    });

    test('a "{" in a value is data, not a variable', () {
      final uri = UriBuilder().path('/b').queryParams({'q': '{isbn}x'}).build({
        'isbn': '1',
      });
      expect('$uri', '/b?q=%7Bisbn%7Dx');
    });
  });

  group('UriBuilderFactory', () {
    test('expands a template against its base URL', () {
      const mirror = UriBuilderFactory('https://mirror.neon.books/v1/');
      expect(
        '${mirror.expand('/books/{isbn}', {'isbn': '978 0'})}',
        'https://mirror.neon.books/v1/books/978%200',
      );
      expect(
        '${mirror.uriString('/books').queryParam('q', 'dune').build()}',
        'https://mirror.neon.books/v1/books?q=dune',
      );
      expect(
        '${mirror.builder().path('x').build()}',
        'https://mirror.neon.books/v1/x',
      );
    });

    test('a whole URL stays as it is; no base, a relative one', () {
      const mirror = UriBuilderFactory('https://mirror.neon.books');
      expect(
        '${mirror.expand('https://other.neon.books/a')}',
        'https://other.neon.books/a',
      );
      expect('${const UriBuilderFactory().expand('/a/{b}', ['c'])}', '/a/c');
    });

    test('its default variables', () {
      const factory = UriBuilderFactory('https://{host}', {
        'host': 'api.neon.books',
      });
      expect('${factory.expand('/books')}', 'https://api.neon.books/books');
    });

    test('a URI it expands is sent as it is by the RestClient', () async {
      server.when(HttpMethod.get, '/books').respond(200, body: 'ok');
      await rest
          .get()
          .uri(
            const UriBuilderFactory('https://mirror.neon.books').expand(
              '/books',
            ),
          )
          .retrieve()
          .body<String>();
      expect('${server.lastRequest.url}', 'https://mirror.neon.books/books');
    });
  });
}

enum _Shelf { fiction }
