// The request cache on its own: which requests are saved (wildcard Accept
// values do not exclude a page), that a target outside this origin is never
// saved, and that reading or removing never starts a session.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

final class _Exchange {
  _Exchange._(this.request, this.response);

  final MockServerHttpRequest request;
  final MockServerHttpResponse response;

  static Future<_Exchange> start(
    String target, {
    Map<String, String> headers = const {},
  }) async {
    final request = MockServerHttpRequest(HttpMethod.get, target);
    headers.forEach(request.headers.set);
    final exchange = _Exchange._(request, MockServerHttpResponse());
    await HttpSessionManager(
      InMemoryHttpSessionRepository(),
      const HttpSessionProperties(),
    ).attach(request, exchange.response);
    return exchange;
  }

  bool get hasSession => request.getSession(create: false) != null;
}

void main() {
  final cache = HttpSessionRequestCache();

  Future<String?> saved(String target, {Map<String, String>? headers}) async {
    final e = await _Exchange.start(target, headers: headers ?? const {});
    cache.saveRequest(e.request, e.response);
    return cache.getRedirectUrl(e.request);
  }

  group('which requests are saved', () {
    test('a page request, with its query', () async {
      expect(await saved('/page'), '/page?continue');
      expect(await saved('/page?a=1&b=2'), '/page?a=1&b=2&continue');
    });

    test('a browser Accept header', () async {
      expect(
        await saved(
          '/page',
          headers: {'accept': 'text/html,application/xhtml+xml,*/*;q=0.8'},
        ),
        '/page?continue',
      );
    });

    for (final accept in [
      'application/json',
      'text/event-stream',
      'multipart/form-data',
    ]) {
      test('$accept is not saved', () async {
        expect(await saved('/page', headers: {'accept': accept}), isNull);
      });
    }

    for (final accept in ['application/*', 'text/*', 'multipart/*']) {
      test('$accept alone is not an exact match: saved', () async {
        expect(
          await saved('/page', headers: {'accept': accept}),
          '/page?continue',
        );
      });
    }

    test('XMLHttpRequest, favicons and other methods are not saved', () async {
      expect(
        await saved('/page', headers: {'x-requested-with': 'XMLHttpRequest'}),
        isNull,
      );
      expect(await saved('/favicon.ico'), isNull);
      expect(await saved('/a/favicon.png'), isNull);
      final post = MockServerHttpRequest(HttpMethod.post, '/page');
      final response = MockServerHttpResponse();
      await HttpSessionManager(
        InMemoryHttpSessionRepository(),
        const HttpSessionProperties(),
      ).attach(post, response);
      cache.saveRequest(post, response);
      expect(cache.getRedirectUrl(post), isNull);
    });
  });

  group('a target outside this origin is never saved', () {
    for (final path in ['//evil.example/x', '//evil.example', 'relative']) {
      test(path, () async {
        final e = await _Exchange.start('/page');
        e.request.uri = path.startsWith('//')
            ? Uri(scheme: 'http', host: 'localhost', path: path)
            : Uri(path: path);
        cache.saveRequest(e.request, e.response);
        expect(e.hasSession, isFalse);
        expect(cache.getRedirectUrl(e.request), isNull);
      });
    }
  });

  group('reading and removing', () {
    test('never start a session', () async {
      final e = await _Exchange.start('/page');
      expect(cache.getRedirectUrl(e.request), isNull);
      cache.removeRequest(e.request);
      expect(e.hasSession, isFalse);
      expect(e.response.cookies, isEmpty);
    });

    test('removeRequest forgets the saved request', () async {
      final e = await _Exchange.start('/page');
      cache.saveRequest(e.request, e.response);
      expect(cache.getRedirectUrl(e.request), '/page?continue');
      cache.removeRequest(e.request);
      expect(cache.getRedirectUrl(e.request), isNull);
    });
  });

  test('NullRequestCache saves nothing', () async {
    final e = await _Exchange.start('/page');
    const none = NullRequestCache();
    none.saveRequest(e.request, e.response);
    expect(none.getRedirectUrl(e.request), isNull);
    expect(e.hasSession, isFalse);
  });
}
