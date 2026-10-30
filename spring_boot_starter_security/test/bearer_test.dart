// How bearer tokens are found in a request: the header syntax of RFC 6750,
// the query parameter that is off unless allowed, and a token in two places
// or an empty one refused.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

MockServerHttpRequest _request(String target, {String? authorization}) {
  final request = MockServerHttpRequest(HttpMethod.get, target);
  if (authorization != null) {
    request.headers.set(HttpHeaders.authorizationHeader, authorization);
  }
  return request;
}

final Matcher _invalid = throwsA(isA<InvalidBearerTokenException>());

void main() {
  group('the Authorization header', () {
    const resolver = DefaultBearerTokenResolver();

    test('the scheme is case-insensitive', () {
      for (final scheme in ['Bearer', 'bearer', 'BEARER', 'bEaReR']) {
        expect(
          resolver.resolve(_request('/', authorization: '$scheme abc.def')),
          'abc.def',
          reason: scheme,
        );
      }
    });

    test('a malformed bearer header is refused', () {
      for (final header in ['Bearer', 'Bearer ', 'Bearer a b', 'Bearer a=b']) {
        expect(
          () => resolver.resolve(_request('/', authorization: header)),
          _invalid,
          reason: header,
        );
      }
    });

    test('other schemes are not a bearer token', () {
      expect(
        resolver.resolve(_request('/', authorization: 'Basic YTpi')),
        isNull,
      );
      expect(resolver.resolve(_request('/')), isNull);
    });
  });

  group('the access_token query parameter', () {
    test('is ignored by default', () {
      const resolver = DefaultBearerTokenResolver();
      expect(resolver.resolve(_request('/?access_token=abc')), isNull);
      expect(
        resolver.resolve(
          _request('/?access_token=abc', authorization: 'Bearer x'),
        ),
        'x',
      );
    });

    test('is read when allowed', () {
      const resolver = DefaultBearerTokenResolver(allowUriQueryParameter: true);
      expect(resolver.resolve(_request('/?access_token=abc')), 'abc');
      expect(resolver.resolve(_request('/?other=abc')), isNull);
    });

    test('twice is refused', () {
      const resolver = DefaultBearerTokenResolver(allowUriQueryParameter: true);
      expect(
        () => resolver.resolve(_request('/?access_token=a&access_token=b')),
        _invalid,
      );
    });

    test('together with the header is refused', () {
      const resolver = DefaultBearerTokenResolver(allowUriQueryParameter: true);
      expect(
        () => resolver.resolve(
          _request('/?access_token=abc', authorization: 'Bearer abc'),
        ),
        _invalid,
      );
      expect(
        resolver.resolve(_request('/', authorization: 'Bearer abc')),
        'abc',
      );
    });

    test('empty is refused', () {
      const resolver = DefaultBearerTokenResolver(allowUriQueryParameter: true);
      expect(() => resolver.resolve(_request('/?access_token=')), _invalid);
      expect(() => resolver.resolve(_request('/?access_token')), _invalid);
    });

    // Any page can post a form to /logout?access_token=x: only GET reads
    // the parameter, as Spring's DefaultBearerTokenResolver.
    test('is read in GET requests only', () {
      const resolver = DefaultBearerTokenResolver(allowUriQueryParameter: true);
      final others = HttpMethod.values.where((m) => m != HttpMethod.get);
      for (final method in others) {
        final request = MockServerHttpRequest(
          method,
          '/logout?access_token=abc',
        );
        expect(resolver.resolve(request), isNull, reason: '$method');
        // Not "two tokens" next to the header either: the query is ignored.
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer x');
        expect(resolver.resolve(request), 'x', reason: '$method');
      }
    });
  });

  test('a token header of another name', () {
    const resolver = DefaultBearerTokenResolver(
      bearerTokenHeaderName: 'X-Token',
    );
    final request = MockServerHttpRequest(HttpMethod.get, '/');
    request.headers.set('X-Token', 'Bearer abc');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer other');
    expect(resolver.resolve(request), 'abc');
  });
}
