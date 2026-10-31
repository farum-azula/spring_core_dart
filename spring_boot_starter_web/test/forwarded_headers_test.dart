// server.forward-headers-strategy: the headers of a trusted reverse proxy
// give the request its scheme, host, port and client address; anyone
// else's are ignored.
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

final class _Capture implements WebFilterChain {
  ServerHttpRequest? seen;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async => seen = request;
}

Future<ServerHttpRequest> _through(
  ForwardedHeaderFilter filter,
  Map<String, String> headers, {
  String from = '10.0.0.5',
  String target = 'http://app.internal:8080/api/books?q=dune',
}) async {
  final request = MockServerHttpRequest(HttpMethod.get, target)
    ..remoteAddress = from;
  headers.forEach(request.headers.add);
  final chain = _Capture();
  await filter.doFilter(request, MockServerHttpResponse(), chain);
  return chain.seen!;
}

void main() {
  final filter = ForwardedHeaderFilter();

  test('X-Forwarded-*: https, the public host, the client', () async {
    final r = await _through(filter, {
      'X-Forwarded-Proto': 'https',
      'X-Forwarded-Host': 'shop.example.com',
      'X-Forwarded-For': '203.0.113.7',
    });
    expect(r.uri.toString(), 'https://shop.example.com/api/books?q=dune');
    expect(r.isSecure, isTrue);
    expect(r.remoteAddress, '203.0.113.7');
    expect(r.path, '/api/books');
    expect(r.headers['X-Forwarded-Proto'], isNull, reason: 'removed');
  });

  test('a new scheme without a port takes its own; a port is kept', () async {
    final noPort = await _through(filter, {'X-Forwarded-Proto': 'https'});
    expect(noPort.uri.port, 443);
    final port = await _through(filter, {
      'X-Forwarded-Proto': 'https',
      'X-Forwarded-Host': 'shop.example.com',
      'X-Forwarded-Port': '8443',
    });
    expect(
      port.uri.toString(),
      'https://shop.example.com:8443/api/books?q=dune',
    );
  });

  test('Forwarded (RFC 7239) wins over X-Forwarded-*', () async {
    final r = await _through(filter, {
      'Forwarded': 'for="[2001:db8::7]:4711";proto=https;host=shop.example.com',
      'X-Forwarded-Proto': 'http',
    });
    expect(r.uri.scheme, 'https');
    expect(r.uri.host, 'shop.example.com');
    expect(r.remoteAddress, '2001:db8::7');
  });

  test(
    'a client that reaches the server directly cannot claim anything',
    () async {
      final r = await _through(filter, {
        'X-Forwarded-Proto': 'https',
        'X-Forwarded-Host': 'bank.example',
        'X-Forwarded-For': '10.0.0.1',
      }, from: '203.0.113.99');
      expect(r.isSecure, isFalse);
      expect(r.uri.host, 'app.internal');
      expect(r.remoteAddress, '203.0.113.99');
    },
  );

  test(
    'the client is the first address from the right that is not a '
    'trusted proxy: addresses the client wrote on the left are ignored',
    () async {
      final r = await _through(filter, {
        'X-Forwarded-For': '6.6.6.6, 198.51.100.4, 10.0.0.9',
      });
      expect(r.remoteAddress, '198.51.100.4');
    },
  );

  test(
    'values that are not a scheme, host, port or address are ignored',
    () async {
      final r = await _through(filter, {
        'X-Forwarded-Proto': 'javascript',
        'X-Forwarded-Host': 'evil.example/path',
        'X-Forwarded-Port': '99999',
        'X-Forwarded-For': 'unknown',
      });
      expect(r.uri.toString(), 'http://app.internal:8080/api/books?q=dune');
      expect(r.remoteAddress, '10.0.0.5');
      for (final host in ['a b', 'x\r\ny', '[::1', 'h:0', '']) {
        final bad = await _through(filter, {'X-Forwarded-Host': host});
        expect(bad.uri.host, 'app.internal', reason: host);
      }
    },
  );

  test('trusted proxies: ranges, single addresses, IPv6, IPv4 in IPv6', () {
    final custom = ForwardedHeaderFilter(
      trustedProxies: ['192.0.2.0/24', '2001:db8::1', '10.1.0.0/16'],
    );
    expect(custom.isTrusted('192.0.2.200'), isTrue);
    expect(custom.isTrusted('192.0.3.1'), isFalse);
    expect(custom.isTrusted('2001:db8::1'), isTrue);
    expect(custom.isTrusted('2001:db8::2'), isFalse);
    expect(custom.isTrusted('::ffff:10.1.2.3'), isTrue);
    expect(custom.isTrusted('10.2.0.1'), isFalse);
    expect(custom.isTrusted(null), isFalse);
    expect(custom.isTrusted('not an address'), isFalse);
    expect(filter.isTrusted('127.0.0.1'), isTrue);
    expect(filter.isTrusted('172.31.255.1'), isTrue);
    expect(filter.isTrusted('172.32.0.1'), isFalse);
    expect(filter.isTrusted('::1'), isTrue);
    expect(filter.isTrusted('fd12::1'), isTrue);
    expect(filter.isTrusted('8.8.8.8'), isFalse);
    expect(
      () => ForwardedHeaderFilter(trustedProxies: ['10.0.0.0/33']),
      throwsArgumentError,
    );
    expect(
      () => ForwardedHeaderFilter(trustedProxies: ['nope']),
      throwsArgumentError,
    );
  });

  test('without forwarded headers the request passes as it is', () async {
    final request = MockServerHttpRequest(HttpMethod.get, '/x');
    final chain = _Capture();
    await filter.doFilter(request, MockServerHttpResponse(), chain);
    expect(chain.seen, same(request));
  });

  group('over a real socket (the server guide behind a TLS proxy)', () {
    test('with the strategy, the session cookie is Secure behind a TLS '
        'proxy on loopback', () async {
      await webRunner([
        'server.forward-headers-strategy=native',
      ]).runAsync((context) async {
        final client = await Client.of(context.context);
        final behindTls = await client.get(
          '/session/count',
          headers: {'X-Forwarded-Proto': 'https'},
        );
        final cookie = behindTls.headers['set-cookie']!.join();
        expect(cookie, contains('JSESSIONID='));
        expect(cookie.toLowerCase(), contains('secure'));
        final plain = await client.get('/session/count');
        expect(
          plain.headers['set-cookie']!.join().toLowerCase(),
          isNot(contains('secure')),
        );
        client.close();
      });
    });

    test('without the strategy the headers are ignored', () async {
      await webRunner().runAsync((context) async {
        expect(context.context.containsBean('forwardedHeaderFilter'), isFalse);
        final client = await Client.of(context.context);
        final r = await client.get(
          '/session/count',
          headers: {'X-Forwarded-Proto': 'https'},
        );
        expect(
          r.headers['set-cookie']!.join().toLowerCase(),
          isNot(contains('secure')),
        );
        client.close();
      });
    });

    test('a trusted list without loopback ignores a loopback peer', () async {
      await webRunner([
        'server.forward-headers-strategy=framework',
        'server.forward-headers.trusted-proxies=192.0.2.0/24',
      ]).runAsync((context) async {
        final client = await Client.of(context.context);
        final r = await client.get(
          '/session/count',
          headers: {'X-Forwarded-Proto': 'https'},
        );
        expect(
          r.headers['set-cookie']!.join().toLowerCase(),
          isNot(contains('secure')),
        );
        client.close();
      });
    });

    test('an unknown strategy or range stops the start', () async {
      for (final property in [
        'server.forward-headers-strategy=always',
        'server.forward-headers.trusted-proxies=10.0.0.0/99',
      ]) {
        final failure = await webRunner([
          'server.forward-headers-strategy=native',
          property,
        ]).runAsync((context) async => context.startupFailure);
        expect(failure, isNotNull, reason: property);
      }
    });
  });
}
