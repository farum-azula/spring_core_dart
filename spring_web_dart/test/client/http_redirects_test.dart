import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/src/client/http_redirects.dart';
import 'package:test/test.dart';

void main() {
  final https = Uri.parse('https://a.example/books');

  group('which redirect is followed', () {
    test('https to http is not, with any status', () {
      for (final status in [301, 302, 303, 307, 308]) {
        expect(
          HttpRedirects.next(
            HttpMethod.get,
            https,
            status,
            'http://a.example/books',
          ),
          isNull,
        );
      }
    });

    test('a scheme other than http and https is not', () {
      expect(
        HttpRedirects.next(HttpMethod.get, https, 302, 'file:///etc/passwd'),
        isNull,
      );
    });

    test('a POST is followed only after a 303, as a GET', () {
      expect(
        HttpRedirects.next(HttpMethod.post, https, 307, '/next'),
        isNull,
      );
      final next = HttpRedirects.next(HttpMethod.post, https, 303, '/next');
      expect(next?.method, HttpMethod.get);
      expect(next?.url, Uri.parse('https://a.example/next'));
    });

    test('a status without a Location is the answer', () {
      expect(HttpRedirects.next(HttpMethod.get, https, 302, null), isNull);
      expect(HttpRedirects.next(HttpMethod.get, https, 200, '/x'), isNull);
    });
  });

  group('the credentials of a hop', () {
    HttpRequest request() => HttpRequest(
      method: HttpMethod.get,
      url: https,
      headers: HttpHeaders({
        'Authorization': 'a',
        'X-Api-Key': 'b',
        'X-Grant': 'c',
        'X-Plain': 'd',
      }),
      sensitiveHeaders: const {'x-grant'},
    );

    for (final (name, target) in [
      ('host', 'https://b.example/'),
      ('port', 'https://a.example:8443/'),
      ('scheme', 'http://a.example/'),
    ]) {
      test('another $name is another origin: they are dropped', () {
        final sent = request();
        HttpRedirects.applyHop(sent.headers, sent, https, Uri.parse(target));
        expect(sent.headers.names.map((n) => n.toLowerCase()), ['x-plain']);
      });
    }

    test('the same origin keeps them', () {
      final sent = request();
      HttpRedirects.applyHop(
        sent.headers,
        sent,
        https,
        Uri.parse('https://a.example/other'),
      );
      expect(sent.headers.names, hasLength(4));
    });

    test('a request copied with other headers keeps the rest', () {
      final abort = Future<void>.value();
      final original = HttpRequest(
        method: HttpMethod.post,
        url: https,
        body: const [1],
        timeout: const Duration(seconds: 3),
        readTimeout: const Duration(seconds: 2),
        followRedirects: false,
        sensitiveHeaders: const {'x-grant'},
        abort: abort,
      );
      final headers = HttpHeaders({'X-Grant': 'c'});
      final copy = original.withHeaders(headers);
      expect(copy.headers, same(headers));
      expect(copy.method, HttpMethod.post);
      expect(copy.url, https);
      expect(copy.body, const [1]);
      expect(copy.timeout, const Duration(seconds: 3));
      expect(copy.readTimeout, const Duration(seconds: 2));
      expect(copy.followRedirects, isFalse);
      expect(copy.sensitiveHeaders, {'x-grant'});
      expect(copy.abort, same(abort));
    });
  });
}
