// The rate limiter: the client's address behind proxies, the rules of the
// configuration and @RateLimiter through MockMvc and a real server, the
// keys, a store that fails, and which store an application gets.
import 'dart:convert';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'support.dart';

// Stands for the security filter chain, at its order: it "authenticates"
// the user the header names, and counts the requests that reached it.
final class _Authentication implements WebFilter, Ordered {
  int requests = 0;

  @override
  int get order => -100;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    requests++;
    if (request.headers['X-User'] case final name?) {
      request.principal = _User(name);
    }
    return chain.doFilter(request, response);
  }
}

// A store of the application: it remembers the keys, and fails on demand.
final class _RecordingStore implements RateLimitStore {
  final keys = <String>[];
  final _memory = InMemoryRateLimitStore();
  bool failing = false;

  @override
  Future<RateLimitDecision> tryAcquire(
    String key,
    RateLimit limit, {
    int permits = 1,
  }) {
    if (failing) {
      throw StateError('the store is down, key $key');
    }
    keys.add(key);
    return _memory.tryAcquire(key, limit, permits: permits);
  }
}

// The keys of the rules of the configuration: the test controller's own
// `@RateLimiter` (the rule `limited`) counts every request too.
extension on _RecordingStore {
  List<String> get ruleKeys => [
    for (final key in keys)
      if (!key.startsWith('limited:')) key,
  ];
}

final _authentication = BeanModule('authentication', [
  BeanDefinition<_Authentication>(
    name: 'authentication',
    types: const [_Authentication, WebFilter, Ordered],
    create: (_) => _Authentication(),
  ),
]);

// A store that is asked at startup, and answers with [problem].
final class _VerifiedStore implements VerifiableRateLimitStore {
  _VerifiedStore(this.problem);

  final Object? problem;
  int verified = 0;

  @override
  Future<void> verify() async {
    verified++;
    if (problem case final problem?) {
      // The problem of the test, whatever it is.
      // ignore: only_throw_errors
      throw problem;
    }
  }

  @override
  Future<RateLimitDecision> tryAcquire(
    String key,
    RateLimit limit, {
    int permits = 1,
  }) async => const RateLimitDecision(allowed: true, remaining: 1);
}

BeanModule _verifiedStore([Object? problem]) => BeanModule('verifiedStore', [
  BeanDefinition<_VerifiedStore>(
    name: 'verifiedStore',
    types: const [_VerifiedStore, RateLimitStore],
    create: (_) => _VerifiedStore(problem),
  ),
]);

final _recordingStore = BeanModule('recordingStore', [
  BeanDefinition<_RecordingStore>(
    name: 'recordingStore',
    types: const [_RecordingStore, RateLimitStore],
    create: (_) => _RecordingStore(),
  ),
]);

ApplicationContextRunner _runner(
  List<String> properties, {
  List<BeanModule> beans = const [],
}) {
  var runner = webRunner(properties).withAutoConfiguration(
    springBootStarterWebRateLimitAutoConfiguration,
  );
  for (final module in beans) {
    runner = runner.withUserConfiguration(module);
  }
  return runner;
}

List<String> _rule(int index, Map<String, String> values) => [
  for (final MapEntry(:key, :value) in values.entries)
    'spring.web.rate-limit.rules[$index].$key=$value',
];

// A request of MockMvc from [address], maybe as [user].
MockRequestBuilder _from(
  String path, {
  String address = '198.51.100.7',
  String? user,
  Map<String, String> headers = const {},
  HttpMethod method = HttpMethod.get,
}) {
  final builder = MockRequestBuilder(method, path)
    ..with_(
      FunctionRequestPostProcessor(
        (request) => request..remoteAddress = address,
      ),
    );
  builder.headers.addAll(headers);
  if (user != null) {
    builder.headers['X-User'] = user;
  }
  return builder;
}

ServerHttpRequest _request(String peer, [Map<String, String>? headers]) =>
    MockServerHttpRequest(HttpMethod.get, '/')
      ..remoteAddress = peer
      ..headers.setAll(headers ?? const {});

void main() {
  group('the client address', () {
    test('without trusted proxies no header is ever read', () {
      final addresses = TrustedProxyClientAddressResolver();
      expect(
        addresses.resolve(
          _request('203.0.113.9', {
            'X-Forwarded-For': '1.2.3.4',
            'CF-Connecting-IP': '1.2.3.4',
          }),
        ),
        '203.0.113.9',
      );
    });

    test("an untrusted peer's header is ignored", () {
      final addresses = TrustedProxyClientAddressResolver(
        trustedProxies: ['10.0.0.0/8'],
      );
      expect(
        addresses.resolve(
          _request('203.0.113.9', {'X-Forwarded-For': '1.2.3.4'}),
        ),
        '203.0.113.9',
      );
    });

    test('the entry the trusted proxy added; what is left of it is the '
        "client's own claim", () {
      final addresses = TrustedProxyClientAddressResolver(
        trustedProxies: ['10.0.0.0/8'],
      );
      expect(
        addresses.resolve(
          _request('10.0.0.1', {
            'X-Forwarded-For': '1.1.1.1, 8.8.8.8, 198.51.100.7',
          }),
        ),
        '198.51.100.7',
      );
      // A spoofed entry that names a trusted proxy changes nothing either.
      expect(
        addresses.resolve(
          _request('10.0.0.1', {'X-Forwarded-For': '10.0.0.5, 198.51.100.7'}),
        ),
        '198.51.100.7',
      );
    });

    test('a chain of trusted proxies is walked from the right', () {
      final addresses = TrustedProxyClientAddressResolver(
        trustedProxies: ['10.0.0.0/8', '173.245.48.0/20'],
      );
      expect(
        addresses.resolve(
          _request('10.0.0.1', {
            'X-Forwarded-For': '6.6.6.6, 198.51.100.7, 173.245.52.9',
          }),
        ),
        '198.51.100.7',
      );
      // Several header lines are one list.
      final request = _request('10.0.0.1')
        ..headers.add('X-Forwarded-For', '6.6.6.6, 198.51.100.7')
        ..headers.add('X-Forwarded-For', '173.245.52.9');
      expect(addresses.resolve(request), '198.51.100.7');
      // Only proxies in the list: the leftmost is the client.
      expect(
        addresses.resolve(
          _request('10.0.0.1', {'X-Forwarded-For': '10.0.0.3, 10.0.0.2'}),
        ),
        '10.0.0.3',
      );
    });

    test('CIDR ranges end where they end', () {
      final addresses = TrustedProxyClientAddressResolver(
        trustedProxies: ['173.245.48.0/20', '192.0.2.4'],
      );
      expect(addresses.isTrusted('173.245.48.0'), isTrue);
      expect(addresses.isTrusted('173.245.63.255'), isTrue);
      expect(addresses.isTrusted('173.245.64.0'), isFalse);
      expect(addresses.isTrusted('173.245.47.255'), isFalse);
      expect(addresses.isTrusted('192.0.2.4'), isTrue);
      expect(addresses.isTrusted('192.0.2.5'), isFalse);
      expect(addresses.isTrusted('not an address'), isFalse);
      expect(addresses.isTrusted(null), isFalse);
    });

    test('IPv6: ranges, brackets, ports and one spelling per address', () {
      final addresses = TrustedProxyClientAddressResolver(
        trustedProxies: ['2400:cb00::/32', '::1'],
        ipv6PrefixLength: 128,
      );
      expect(addresses.isTrusted('2400:cb00:1234::1'), isTrue);
      expect(addresses.isTrusted('2400:cb01::1'), isFalse);
      expect(
        addresses.resolve(
          _request('2400:cb00::5', {
            'X-Forwarded-For': '2001:db8::bad, [2001:DB8:0:0::1]:4711',
          }),
        ),
        '2001:db8:0:0:0:0:0:1',
      );
      expect(
        addresses.resolve(
          _request('::1', {'X-Forwarded-For': '198.51.100.7:55123'}),
        ),
        '198.51.100.7',
      );
      // An IPv4 peer seen through an IPv6 socket is that IPv4 address.
      expect(
        TrustedProxyClientAddressResolver().resolve(
          _request('::ffff:198.51.100.7'),
        ),
        '198.51.100.7',
      );
    });

    test('an IPv6 client is its /64: the addresses of one share a key', () {
      final addresses = TrustedProxyClientAddressResolver();
      String? of(String peer) => addresses.resolve(_request(peer));
      expect(of('2001:db8:1:2:aaaa:bbbb:cccc:dddd'), '2001:db8:1:2:0:0:0:0');
      expect(of('2001:db8:1:2::1'), '2001:db8:1:2:0:0:0:0');
      expect(
        of('[2001:DB8:1:2:ffff:ffff:ffff:ffff]:443'),
        of('2001:db8:1:2::1'),
      );
      // Another /64, one bit away.
      expect(of('2001:db8:1:3::1'), '2001:db8:1:3:0:0:0:0');
      expect(of('2001:db8:1:2::1'), isNot(of('2001:db8:1:3::1')));
    });

    test('the prefix length: 128 is every address, others cut inside a '
        'byte', () {
      String? of(int prefix, String peer) => TrustedProxyClientAddressResolver(
        ipv6PrefixLength: prefix,
      ).resolve(_request(peer));
      expect(of(128, '2001:db8:1:2::1'), '2001:db8:1:2:0:0:0:1');
      expect(of(128, '2001:db8:1:2::2'), '2001:db8:1:2:0:0:0:2');
      expect(of(56, '2001:db8:1:2ff:a::1'), '2001:db8:1:200:0:0:0:0');
      expect(of(48, '2001:db8:1:2::1'), '2001:db8:1:0:0:0:0:0');
      expect(of(60, '2001:db8:1:12f::1'), '2001:db8:1:120:0:0:0:0');
      expect(of(1, 'ffff::1'), '8000:0:0:0:0:0:0:0');
      expect(of(127, '2001:db8::3'), '2001:db8:0:0:0:0:0:2');
      for (final prefix in [0, -1, 129]) {
        expect(
          () => TrustedProxyClientAddressResolver(ipv6PrefixLength: prefix),
          throwsArgumentError,
        );
      }
    });

    test('IPv4 addresses, mapped into IPv6 too, are counted whole', () {
      for (final prefix in [1, 64, 128]) {
        final addresses = TrustedProxyClientAddressResolver(
          ipv6PrefixLength: prefix,
        );
        expect(addresses.resolve(_request('198.51.100.7')), '198.51.100.7');
        expect(addresses.resolve(_request('198.51.100.8')), '198.51.100.8');
        expect(
          addresses.resolve(_request('::ffff:198.51.100.7')),
          '198.51.100.7',
        );
        expect(
          addresses.resolve(_request('[::ffff:198.51.100.8]:4711')),
          '198.51.100.8',
        );
      }
    });

    test('the trusted proxies are compared by their whole address', () {
      // One address of a /64 is the proxy; its neighbours are clients.
      final addresses = TrustedProxyClientAddressResolver(
        trustedProxies: ['2001:db8:1:2::1'],
      );
      // From the proxy: the forwarded client, as its /64.
      expect(
        addresses.resolve(
          _request('2001:db8:1:2::1', {
            'X-Forwarded-For': '2001:db8:9:9:1:2:3:4',
          }),
        ),
        '2001:db8:9:9:0:0:0:0',
      );
      // From its neighbour in the same /64: not trusted, the header is
      // not read.
      expect(
        addresses.resolve(
          _request('2001:db8:1:2::2', {
            'X-Forwarded-For': '2001:db8:9:9:1:2:3:4',
          }),
        ),
        '2001:db8:1:2:0:0:0:0',
      );
      // A forwarded entry in the proxy's /64 that is not the proxy ends
      // the walk: it is the client.
      expect(
        addresses.resolve(
          _request('2001:db8:1:2::1', {
            'X-Forwarded-For': '203.0.113.5, 2001:db8:1:2::2',
          }),
        ),
        '2001:db8:1:2:0:0:0:0',
      );
      expect(addresses.isTrusted('2001:db8:1:2::1'), isTrue);
      expect(addresses.isTrusted('2001:db8:1:2::2'), isFalse);
    });

    test('a configured header with one address', () {
      final addresses = TrustedProxyClientAddressResolver(
        trustedProxies: ['173.245.48.0/20'],
        header: 'CF-Connecting-IP',
      );
      expect(
        addresses.resolve(
          _request('173.245.52.9', {
            'CF-Connecting-IP': '198.51.100.7',
            'X-Forwarded-For': '1.2.3.4',
          }),
        ),
        '198.51.100.7',
      );
      // Not from the proxy: the header is the client's own claim.
      expect(
        addresses.resolve(
          _request('203.0.113.9', {'CF-Connecting-IP': '198.51.100.7'}),
        ),
        '203.0.113.9',
      );
    });

    test('an entry that is no address ends the walk at the proxy', () {
      final addresses = TrustedProxyClientAddressResolver(
        trustedProxies: ['10.0.0.0/8'],
      );
      expect(
        addresses.resolve(
          _request('10.0.0.1', {'X-Forwarded-For': '1.2.3.4, unknown'}),
        ),
        '10.0.0.1',
      );
      expect(addresses.resolve(_request('10.0.0.1')), '10.0.0.1');
    });

    test('a range that is none is refused', () {
      expect(
        () =>
            TrustedProxyClientAddressResolver(trustedProxies: ['10.0.0.0/33']),
        throwsArgumentError,
      );
      expect(
        () => TrustedProxyClientAddressResolver(trustedProxies: ['proxy']),
        throwsArgumentError,
      );
    });
  });

  group('the rules through a real server', () {
    test('past the limit: 429, Retry-After, a problem, the headers', () async {
      await _runner([
        ..._rule(0, {'path': '/limited/plain', 'key': 'ip', 'limit': '3/1m'}),
      ]).runAsync((context) async {
        final client = await Client.of(context.context);
        addTearDown(client.close);
        for (var left = 2; left >= 0; left--) {
          final reply = await client.get('/limited/plain');
          expect(reply.status, 200);
          expect(reply.headers.value('RateLimit-Limit'), '3');
          expect(reply.headers.value('RateLimit-Remaining'), '$left');
          expect(
            int.parse(reply.headers.value('RateLimit-Reset')!),
            inInclusiveRange(1, 60),
          );
        }
        final refused = await client.get('/limited/plain');
        expect(refused.status, 429);
        expect(
          int.parse(refused.headers.value('Retry-After')!),
          inInclusiveRange(1, 20),
        );
        expect(refused.headers.value('RateLimit-Remaining'), '0');
        expect(
          refused.headers.contentType?.mimeType,
          'application/problem+json',
        );
        expect(refused.json, containsPair('status', 429));
        expect(refused.json, containsPair('title', 'Too Many Requests'));
        // Another path is not counted.
        expect((await client.get('/misc/text')).status, 200);
      });
    });

    test('a refused upload is answered without its body being read', () async {
      await _runner([
        ..._rule(0, {
          'path': '/limited/echo',
          'methods': 'POST',
          'key': 'ip',
          'limit': '1/1m',
        }),
      ]).runAsync((context) async {
        final client = await Client.of(context.context);
        addTearDown(client.close);
        expect(
          (await client.send('POST', '/limited/echo', body: 'hello')).body,
          'hello',
        );
        final refused = await client.send(
          'POST',
          '/limited/echo',
          body: 'x' * 100000,
        );
        expect(refused.status, 429);
        // The rule is for POST only.
        expect((await client.get('/limited/echo')).status, 405);
      });
    });

    test('behind a trusted proxy the forwarded client is counted', () async {
      await _runner([
        'spring.web.rate-limit.trusted-proxies=127.0.0.0/8,::1',
        ..._rule(0, {'path': '/limited/plain', 'key': 'ip', 'limit': '1/1m'}),
      ]).runAsync((context) async {
        final client = await Client.of(context.context);
        addTearDown(client.close);
        Future<int> from(String forwarded) async => (await client.get(
          '/limited/plain',
          headers: {'X-Forwarded-For': forwarded},
        )).status;
        expect(await from('198.51.100.7'), 200);
        expect(await from('198.51.100.7'), 429);
        // A spoofed entry on the left does not move the client to another
        // bucket; another client has its own.
        expect(await from('9.9.9.9, 198.51.100.7'), 429);
        expect(await from('198.51.100.8'), 200);
      });
    });

    test('without trusted proxies the header changes nothing', () async {
      await _runner([
        ..._rule(0, {'path': '/limited/plain', 'key': 'ip', 'limit': '1/1m'}),
      ]).runAsync((context) async {
        final client = await Client.of(context.context);
        addTearDown(client.close);
        Future<int> from(String forwarded) async => (await client.get(
          '/limited/plain',
          headers: {'X-Forwarded-For': forwarded},
        )).status;
        expect(await from('198.51.100.7'), 200);
        expect(await from('198.51.100.8'), 429);
      });
    });
  });

  group('the rules through MockMvc', () {
    test('several rules all apply; the headers are the tightest', () async {
      await _runner([
        ..._rule(0, {'path': '/limited/**', 'key': 'ip', 'limit': '10/1m'}),
        ..._rule(1, {'path': '/limited/plain', 'key': 'ip', 'limit': '2/1m'}),
        ..._rule(2, {'path': '/api/**', 'key': 'ip', 'limit': '1/1m'}),
      ]).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        final first = await mvc.perform(_from('/limited/plain')).andReturn();
        expect(first.response.statusCode, 200);
        expect(first.response.headers['RateLimit-Limit'], '2');
        expect(first.response.headers['RateLimit-Remaining'], '1');
        await mvc.perform(_from('/limited/plain')).andExpect(status: 200);
        final refused = await mvc.perform(_from('/limited/plain')).andReturn();
        expect(refused.response.statusCode, 429);
        expect(refused.response.headers['Retry-After'], isNotNull);
        expect(refused.response.headers['RateLimit-Limit'], '2');
        // The wide rule still has room for the other paths of the client,
        // and counted the refused request too.
        final other = await mvc.perform(_from('/limited/echo')).andReturn();
        expect(other.response.headers['RateLimit-Limit'], '10');
        expect(other.response.headers['RateLimit-Remaining'], '6');
        // Another client is not touched.
        await mvc
            .perform(_from('/limited/plain', address: '198.51.100.8'))
            .andExpect(status: 200);
      });
    });

    test('the headers can be turned off', () async {
      await _runner([
        'spring.web.rate-limit.headers=false',
        ..._rule(0, {'path': '/limited/plain', 'key': 'ip', 'limit': '1/1m'}),
      ]).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        final first = await mvc.perform(_from('/limited/plain')).andReturn();
        expect(first.response.headers['RateLimit-Limit'], isNull);
        final refused = await mvc.perform(_from('/limited/plain')).andReturn();
        expect(refused.response.statusCode, 429);
        expect(refused.response.headers['RateLimit-Limit'], isNull);
        expect(refused.response.headers['Retry-After'], isNotNull);
      });
    });

    test('a rule by address refuses before authentication; a rule by user '
        'sees the authenticated user', () async {
      await _runner(
        [
          ..._rule(0, {'path': '/api/**', 'key': 'ip', 'limit': '1/1m'}),
          ..._rule(1, {'path': '/limited/plain', 'limit': '1/1m'}),
        ],
        beans: [_authentication],
      ).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        final authentication = context.getBean<_Authentication>();
        final filters = context.context
            .getBeansOfType<RateLimitFilter>()
            .values
            .toList();
        expect(filters.map((f) => f.order), unorderedEquals([-5000, -50]));
        expect(
          filters.firstWhere((f) => f.order == -5000).rules.single.key,
          'ip',
        );
        expect(
          filters.firstWhere((f) => f.order == -50).rules.single.key,
          'user',
        );

        // By address: the second request never reaches authentication.
        await mvc.perform(_from('/api/books/1111')).andExpect(status: 200);
        expect(authentication.requests, 1);
        await mvc
            .perform(_from('/api/books/1111', user: 'ada'))
            .andExpect(status: 429);
        expect(authentication.requests, 1);

        // By user: each user a bucket, whatever the address.
        await mvc
            .perform(_from('/limited/plain', user: 'ada'))
            .andExpect(status: 200, body: 'ada');
        await mvc
            .perform(
              _from('/limited/plain', user: 'ada', address: '198.51.100.99'),
            )
            .andExpect(status: 429);
        await mvc
            .perform(_from('/limited/plain', user: 'bob'))
            .andExpect(status: 200, body: 'bob');
        // Nobody: by address.
        await mvc.perform(_from('/limited/plain')).andExpect(status: 200);
        await mvc.perform(_from('/limited/plain')).andExpect(status: 429);
        await mvc
            .perform(_from('/limited/plain', address: '198.51.100.8'))
            .andExpect(status: 200);
      });
    });

    test('a key by a SpEL expression', () async {
      await _runner([
        ..._rule(0, {
          'path': '/limited/plain',
          'key': "#{headers['x-tenant']}",
          'limit': '1/1m',
        }),
      ]).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        MockRequestBuilder tenant(String? name, {String address = '1.1.1.1'}) =>
            _from(
              '/limited/plain',
              address: address,
              headers: {'X-Tenant': ?name},
            );
        await mvc.perform(tenant('neon')).andExpect(status: 200);
        await mvc
            .perform(tenant('neon', address: '2.2.2.2'))
            .andExpect(status: 429);
        await mvc.perform(tenant('azula')).andExpect(status: 200);
        // No value: by address.
        await mvc.perform(tenant(null)).andExpect(status: 200);
        await mvc.perform(tenant(null)).andExpect(status: 429);
        await mvc
            .perform(tenant(null, address: '2.2.2.2'))
            .andExpect(status: 200);
      });
    });

    test('an IPv6 client is counted by its /64, an IPv4 one by its '
        'address', () async {
      await _runner([
        ..._rule(0, {'path': '/limited/plain', 'key': 'ip', 'limit': '2/1m'}),
      ]).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        Future<void> from(String address, int status) => mvc
            .perform(_from('/limited/plain', address: address))
            .andExpect(status: status);
        // A client that changes its address inside its /64 at every
        // request is one client.
        await from('2001:db8:1:2::1', 200);
        await from('2001:db8:1:2:aaaa:bbbb:cccc:dddd', 200);
        await from('2001:db8:1:2:1111:2222:3333:4444', 429);
        // Another /64 has its own bucket.
        await from('2001:db8:1:3::1', 200);
        // IPv4, and IPv4 mapped into IPv6: by address.
        await from('198.51.100.7', 200);
        await from('::ffff:198.51.100.7', 200);
        await from('198.51.100.7', 429);
        await from('198.51.100.8', 200);
        await from('::ffff:198.51.100.9', 200);
      });
    });

    test('ipv6-prefix-length: 128 counts every address; outside 1..128 '
        'stops the start', () async {
      await _runner([
        'spring.web.rate-limit.ipv6-prefix-length=128',
        ..._rule(0, {'path': '/limited/plain', 'key': 'ip', 'limit': '1/1m'}),
      ]).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        Future<void> from(String address, int status) => mvc
            .perform(_from('/limited/plain', address: address))
            .andExpect(status: status);
        await from('2001:db8:1:2::1', 200);
        await from('2001:db8:1:2::2', 200);
        await from('2001:db8:1:2::1', 429);
        await from('2001:DB8:1:2:0:0:0:2', 429);
      });
      for (final length in ['0', '129']) {
        final failure = await _runner([
          'spring.web.rate-limit.ipv6-prefix-length=$length',
          ..._rule(0, {'path': '/**', 'key': 'ip', 'limit': '1/1m'}),
        ]).runAsync((context) async => context.startupFailure);
        expect('$failure', contains('ipv6-prefix-length=$length'));
      }
    });

    test('a header is found in any case, as headers and as '
        'request.headers', () async {
      for (final key in [
        "#{request.headers['X-Api-Key']}",
        "#{headers['X-Api-Key']}",
        "#{headers['x-api-key']}",
        "#{request.headers['x-API-key']}",
      ]) {
        await _runner(
          [
            ..._rule(0, {
              'name': 'api',
              'path': '/limited/plain',
              'key': key,
              'limit': '1/1m',
            }),
          ],
          beans: [_recordingStore],
        ).runAsync((context) async {
          final mvc = MockMvc.of(context.context);
          final store = context.getBean<_RecordingStore>();
          MockRequestBuilder as_(
            String? apiKey, {
            String header = 'X-Api-Key',
            String address = '1.1.1.1',
          }) => _from(
            '/limited/plain',
            address: address,
            headers: {header: ?apiKey},
          );
          await mvc.perform(as_('k-1')).andExpect(status: 200);
          // The same key from another address, sent in another case.
          await mvc
              .perform(as_('k-1', header: 'x-api-key', address: '2.2.2.2'))
              .andExpect(status: 429);
          await mvc
              .perform(as_('k-2', header: 'X-API-KEY'))
              .andExpect(status: 200);
          expect(store.ruleKeys, [
            'api:key:k-1',
            'api:key:k-1',
            'api:key:k-2',
          ], reason: key);
        });
      }
    });

    test('a rule of some methods and of a named rule', () async {
      await _runner(
        [
          ..._rule(0, {
            'name': 'writes',
            'path': '/limited/**',
            'methods': 'POST,PUT',
            'key': 'ip',
            'limit': '60/1m',
            'burst': '1',
          }),
        ],
        beans: [_recordingStore],
      ).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        await mvc.perform(_from('/limited/plain')).andExpect(status: 200);
        await mvc.perform(_from('/limited/plain')).andExpect(status: 200);
        await mvc
            .perform(_from('/limited/echo', method: HttpMethod.post))
            .andExpect(status: 400);
        await mvc
            .perform(_from('/limited/echo', method: HttpMethod.post))
            .andExpect(status: 429);
        // (The class of the controller has a @RateLimiter of its own.)
        expect(context.getBean<_RecordingStore>().keys.toSet(), {
          'limited:ip:198.51.100.7',
          'writes:ip:198.51.100.7',
        });
      });
    });
  });

  group('the store is asked at startup that it is set up', () {
    final logs = captureLogs();
    const on = ['spring.web.rate-limit.enabled=true'];
    final arguments = ApplicationArguments(const []);

    test('a store that is set up: asked once, the start goes on', () async {
      await _runner(on, beans: [_verifiedStore()]).runAsync((context) async {
        expect(context.startupFailure, isNull);
        final verifier = context.getBean<RateLimitStoreVerifier>();
        expect(verifier, isA<ApplicationRunner>());
        await verifier.run(arguments);
        expect(context.getBean<_VerifiedStore>().verified, 1);
        expect(logs.atLevel(SpringLogLevel.warning), isEmpty);
      });
    });

    test(
      'what it needs is missing: the start fails with what to run',
      () async {
        const missing = RateLimitStoreSetupException('run the migration');
        await _runner(on, beans: [_verifiedStore(missing)]).runAsync((
          context,
        ) async {
          await expectLater(
            context.getBean<RateLimitStoreVerifier>().run(arguments),
            throwsA(
              isA<RateLimitStoreSetupException>().having(
                (e) => '$e',
                'text',
                contains('run the migration'),
              ),
            ),
          );
        });
      },
    );

    test('a store that cannot be reached now: a warning, the start goes '
        'on', () async {
      await _runner(on, beans: [_verifiedStore(StateError('down'))]).runAsync((
        context,
      ) async {
        await context.getBean<RateLimitStoreVerifier>().run(arguments);
        expect(
          logs.atLevel(SpringLogLevel.warning).single.message,
          allOf(
            contains('could not be checked at startup'),
            contains('on-store-failure'),
          ),
        );
      });
    });

    test('a store that cannot be asked is not; verify-store: false and no '
        'rate limiter turned off leave the check out', () async {
      await _runner(on, beans: [_recordingStore]).runAsync((context) async {
        await context.getBean<RateLimitStoreVerifier>().run(arguments);
        expect(context.getBean<_RecordingStore>().keys, isEmpty);
      });
      await _runner(
        [...on, 'spring.web.rate-limit.verify-store=false'],
        beans: [_verifiedStore()],
      ).runAsync((context) async {
        expect(context.startupFailure, isNull);
        expect(context.containsBean('rateLimitStoreVerifier'), isFalse);
      });
      await _runner(
        const ['spring.web.rate-limit.enabled=false'],
        beans: [_verifiedStore()],
      ).runAsync((
        context,
      ) async {
        expect(context.containsBean('rateLimitStoreVerifier'), isFalse);
      });
    });
  });

  group('@RateLimiter', () {
    final enabled = ['spring.web.rate-limit.enabled=true'];

    test('on a method: per user, by address without one', () async {
      await _runner(enabled, beans: [_authentication]).runAsync((
        context,
      ) async {
        final mvc = MockMvc.of(context.context);
        for (var i = 0; i < 2; i++) {
          await mvc
              .perform(_from('/limited/annotated', user: 'ada'))
              .andExpect(status: 200, body: 'annotated');
        }
        final refused = await mvc
            .perform(_from('/limited/annotated', user: 'ada'))
            .andReturn();
        expect(refused.response.statusCode, 429);
        expect(refused.response.headers['Retry-After'], isNotNull);
        expect(
          refused.response.headers['Content-Type'],
          contains('application/problem+json'),
        );
        await mvc
            .perform(_from('/limited/annotated', user: 'bob'))
            .andExpect(status: 200);
        await mvc.perform(_from('/limited/annotated')).andExpect(status: 200);
      });
    });

    test('a SpEL key over the headers and over the user', () async {
      await _runner(enabled, beans: [_authentication]).runAsync((
        context,
      ) async {
        final mvc = MockMvc.of(context.context);
        MockRequestBuilder withKey(String key) =>
            _from('/limited/by-header', headers: {'X-Api-Key': key});
        await mvc.perform(withKey('k1')).andExpect(status: 200);
        await mvc.perform(withKey('k1')).andExpect(status: 429);
        await mvc.perform(withKey('k2')).andExpect(status: 200);

        await mvc
            .perform(_from('/limited/by-user', user: 'ada'))
            .andExpect(status: 200, body: 'ada');
        await mvc
            .perform(_from('/limited/by-user', user: 'ada', address: '2.2.2.2'))
            .andExpect(status: 429);
        await mvc
            .perform(_from('/limited/by-user', user: 'bob'))
            .andExpect(status: 200, body: 'bob');
        // Nobody: `authentication.name` has no value, counted by address.
        await mvc
            .perform(_from('/limited/by-user'))
            .andExpect(status: 200, body: 'nobody');
        await mvc.perform(_from('/limited/by-user')).andExpect(status: 429);
      });
    });

    test('a limit from the configuration, with a burst; the class and the '
        'method both apply', () async {
      await _runner(
        [...enabled, 'limited.placeholder=60/1m'],
        beans: [_recordingStore],
      ).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        for (var i = 0; i < 3; i++) {
          await mvc
              .perform(_from('/limited/placeholder'))
              .andExpect(status: 200);
        }
        await mvc.perform(_from('/limited/placeholder')).andExpect(status: 429);
        expect(context.getBean<_RecordingStore>().keys.toSet(), {
          'limited:ip:198.51.100.7',
          'LimitedController.placeholder:ip:198.51.100.7',
        });
      });
    });

    test('through a real server', () async {
      await _runner(enabled).runAsync((context) async {
        final client = await Client.of(context.context);
        addTearDown(client.close);
        expect((await client.get('/limited/annotated')).status, 200);
        expect((await client.get('/limited/annotated')).status, 200);
        final refused = await client.get('/limited/annotated');
        expect(refused.status, 429);
        expect(refused.headers.value('Retry-After'), isNotNull);
        expect(refused.json, containsPair('status', 429));
      });
    });

    test('without rate limiting turned on the start fails; turned off on '
        'purpose it does not', () async {
      final failure = await _runner(
        [],
      ).runAsync((context) async => context.startupFailure);
      expect('$failure', contains('spring.web.rate-limit.enabled'));
      expect('$failure', contains('LimitedController'));

      await _runner(['spring.web.rate-limit.enabled=false']).runAsync((
        context,
      ) async {
        expect(context.startupFailure, isNull);
        expect(context.containsBean('requestRateLimiter'), isFalse);
        expect(context.containsBean('inMemoryRateLimitStore'), isFalse);
        final mvc = MockMvc.of(context.context);
        for (var i = 0; i < 4; i++) {
          await mvc.perform(_from('/limited/annotated')).andExpect(status: 200);
        }
      });
    });

    test('enabled: false turns the rules off too', () async {
      await _runner([
        'spring.web.rate-limit.enabled=false',
        ..._rule(0, {'path': '/limited/plain', 'key': 'ip', 'limit': '1/1m'}),
      ]).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        await mvc.perform(_from('/limited/plain')).andExpect(status: 200);
        await mvc.perform(_from('/limited/plain')).andExpect(status: 200);
      });
    });
  });

  group('the keys', () {
    test('an address is stored as its HMAC-SHA-256, a user as it is', () async {
      await _runner(
        [
          'spring.web.rate-limit.hash-addresses=true',
          'spring.web.rate-limit.hash-secret=s3cret',
          ..._rule(0, {
            'name': 'a',
            'path': '/limited/plain',
            'key': 'ip',
            'limit': '5/1m',
          }),
          ..._rule(1, {'name': 'u', 'path': '/limited/plain', 'limit': '5/1m'}),
        ],
        beans: [_recordingStore, _authentication],
      ).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        await mvc
            .perform(_from('/limited/plain', user: 'ada'))
            .andExpect(status: 200);
        await mvc.perform(_from('/limited/plain')).andExpect(status: 200);
        final keys = [
          for (final key in context.getBean<_RecordingStore>().keys)
            if (!key.startsWith('limited:')) key,
        ];
        final hash = Sha256.hex(
          Sha256.hmac(utf8.encode('s3cret'), utf8.encode('198.51.100.7')),
        );
        expect(keys, ['a:ip:$hash', 'u:user:ada', 'a:ip:$hash', 'u:ip:$hash']);
        expect(keys.join(), isNot(contains('198.51.100.7')));
      });
    });

    test('hashing without a secret stops the start', () async {
      final failure = await _runner([
        'spring.web.rate-limit.hash-addresses=true',
        ..._rule(0, {'limit': '5/1m'}),
      ]).runAsync((context) async => context.startupFailure);
      expect('$failure', contains('spring.web.rate-limit.hash-secret'));
    });

    test('a very long value is stored as its digest', () async {
      await _runner(
        [
          ..._rule(0, {
            'name': 'k',
            'path': '/limited/plain',
            'key': "#{headers['x-tenant']}",
            'limit': '5/1m',
          }),
        ],
        beans: [_recordingStore],
      ).runAsync((context) async {
        final value = 'v' * 500;
        await MockMvc.of(context.context)
            .perform(_from('/limited/plain', headers: {'X-Tenant': value}))
            .andExpect(status: 200);
        expect(
          context.getBean<_RecordingStore>().keys.first,
          [
            'k:key:',
            Sha256.hex(Sha256.digest(utf8.encode(value))),
          ].join(),
        );
      });
    });

    test('a key resolver of the application comes first', () async {
      final resolver = BeanModule('tenant', [
        BeanDefinition<_TenantResolver>(
          name: 'tenantResolver',
          types: const [_TenantResolver, RateLimitKeyResolver],
          create: (_) => const _TenantResolver(),
        ),
      ]);
      await _runner(
        [
          ..._rule(0, {'name': 't', 'key': 'tenant', 'limit': '1/1m'}),
        ],
        beans: [_recordingStore, resolver],
      ).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        await mvc
            .perform(_from('/limited/plain', headers: {'X-Tenant': 'neon'}))
            .andExpect(status: 200);
        await mvc
            .perform(_from('/limited/plain', headers: {'X-Tenant': 'neon'}))
            .andExpect(status: 429);
        expect(context.getBean<_RecordingStore>().keys.first, 't:tenant:neon');
        // It needs no user: its rule is in the filter before authentication.
        expect(
          context.context
              .getBeansOfType<RateLimitFilter>()
              .values
              .firstWhere((f) => f.order == -5000)
              .rules,
          hasLength(1),
        );
      });
    });

    test('a rule that cannot be read stops the start, by its place', () async {
      Future<String> failure(Map<String, String> rule) async {
        final failure = await _runner(
          _rule(0, rule),
        ).runAsync((context) async => context.startupFailure);
        return '$failure';
      }

      expect(await failure({'path': '/x'}), contains('rules[0].limit'));
      expect(await failure({'limit': 'often'}), contains('rules[0]'));
      expect(
        await failure({'limit': '1/1m', 'key': 'session'}),
        contains('"session"'),
      );
      expect(
        await failure({'limit': '1/1m', 'methods': 'FETCH IT'}),
        contains('rules[0]'),
      );
      expect(
        await failure({'limit': '1/1m', 'key': '#{1 +}'}),
        isNot('null'),
      );
    });

    test('an expression that cannot be parsed stops the start, with the '
        "rule's name", () async {
      Future<String> failure(Map<String, String> rule) async {
        final failure = await _runner(
          _rule(0, {'limit': '1/1m', ...rule}),
        ).runAsync((context) async => context.startupFailure);
        return '$failure';
      }

      final named = await failure({
        'name': 'api-keys',
        'key': "#{request.headers['X-Api-Key'}",
      });
      expect(named, contains('The rate limit rule api-keys'));
      expect(named, contains("#{request.headers['X-Api-Key'}"));
      expect(
        await failure({'key': '#{1 +}'}),
        contains('The rate limit rule rule-1'),
      );
      // Before authentication or after: both filters check their rules.
      expect(
        await failure({'name': 'open', 'key': '#{headers['}),
        contains('The rate limit rule open'),
      );
    });

    test('@RateLimiter with an expression that cannot be parsed stops the '
        'start', () {
      final limiter = RequestRateLimiter(
        store: InMemoryRateLimitStore(),
        addresses: TrustedProxyClientAddressResolver(),
      );
      expect(
        () => limiter.validate(
          RateLimitRule(
            name: 'ReportController.export',
            key: '#{authentication.}',
            limit: RateLimit.parse('1/1m'),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('The rate limit rule ReportController.export'),
          ),
        ),
      );
    });
  });

  group('an expression key that names what does not exist', () {
    late List<SpringLogRecord> records;
    late void Function() stop;

    setUp(() {
      records = [];
      stop = SpringLog.listen((record) {
        if (record.loggerName == 'spring.web.ratelimit' &&
            record.level.index >= SpringLogLevel.warning.index) {
          records.add(record);
        }
      });
    });

    tearDown(() => stop());

    test('warns once per rule and counts by address', () async {
      await _runner(
        [
          ..._rule(0, {
            'name': 'api',
            'path': '/limited/plain',
            'key': "#{request.header['X-Api-Key']}",
            'limit': '2/1m',
          }),
          ..._rule(1, {
            'name': 'tenants',
            'path': '/limited/plain',
            'key': '#{tenant}',
            'limit': '100/1m',
          }),
        ],
        beans: [_recordingStore],
      ).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        final store = context.getBean<_RecordingStore>();
        MockRequestBuilder as_(String apiKey, {String address = '1.1.1.1'}) =>
            _from(
              '/limited/plain',
              address: address,
              headers: {'X-Api-Key': apiKey},
            );
        // The fallback is the address: the header changes nothing.
        await mvc.perform(as_('secret-1')).andExpect(status: 200);
        await mvc.perform(as_('secret-2')).andExpect(status: 200);
        await mvc.perform(as_('secret-3')).andExpect(status: 429);
        await mvc
            .perform(as_('secret-1', address: '2.2.2.2'))
            .andExpect(status: 200);
        expect(store.ruleKeys.toSet(), {
          'api:ip:1.1.1.1',
          'tenants:ip:1.1.1.1',
          'api:ip:2.2.2.2',
          'tenants:ip:2.2.2.2',
        });
        // Four requests, two rules: one line each.
        expect(records, hasLength(2));
        final api = records.first.message;
        expect(api, contains('rate limit rule api '));
        expect(api, contains("#{request.header['X-Api-Key']}"));
        expect(api, contains("'header'"));
        expect(api, contains('counts by the address of the client'));
        expect(records.last.message, contains('rate limit rule tenants '));
        expect(records.last.message, contains("'tenant'"));
        for (final record in records) {
          expect(record.level, SpringLogLevel.warning);
          expect(record.message, isNot(contains('secret')));
          expect(record.message, isNot(contains('1.1.1.1')));
        }
      });
    });

    test('a header or a user the request does not have is no mistake: no '
        'warning', () async {
      await _runner(
        [
          ..._rule(0, {
            'name': 'api',
            'path': '/limited/plain',
            'key': "#{request.headers['X-Api-Key']}",
            'limit': '5/1m',
          }),
          ..._rule(1, {
            'name': 'users',
            'path': '/limited/plain',
            'key': '#{authentication.name}',
            'limit': '5/1m',
          }),
          ..._rule(2, {
            'name': 'hosts',
            'path': '/limited/plain',
            'key': '#{headers.tenant.trim()}',
            'limit': '5/1m',
          }),
        ],
        beans: [_recordingStore],
      ).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        final store = context.getBean<_RecordingStore>();
        await mvc.perform(_from('/limited/plain')).andExpect(status: 200);
        await mvc
            .perform(_from('/limited/plain', headers: {'Tenant': ' neon '}))
            .andExpect(status: 200);
        expect(store.ruleKeys, [
          'api:ip:198.51.100.7',
          'users:ip:198.51.100.7',
          'hosts:ip:198.51.100.7',
          'api:ip:198.51.100.7',
          'users:ip:198.51.100.7',
          'hosts:key:neon',
        ]);
        expect(records, isEmpty);
      });
    });
  });

  group('a store that cannot be reached', () {
    late List<SpringLogRecord> records;
    late void Function() stop;

    setUp(() {
      records = [];
      stop = SpringLog.listen((record) {
        if (record.loggerName == 'spring.web.ratelimit' &&
            record.level.index >= SpringLogLevel.warning.index) {
          records.add(record);
        }
      });
    });

    tearDown(() => stop());

    test('denies by default: 503 with Retry-After, one log line without the '
        'key', () async {
      await _runner(
        [
          'spring.web.rate-limit.store-failure-retry-after=7s',
          ..._rule(0, {
            'name': 'api',
            'path': '/limited/plain',
            'key': 'ip',
            'limit': '5/1m',
          }),
        ],
        beans: [_recordingStore],
      ).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        final store = context.getBean<_RecordingStore>();
        await mvc.perform(_from('/limited/plain')).andExpect(status: 200);
        store.failing = true;
        for (var i = 0; i < 3; i++) {
          final refused = await mvc
              .perform(_from('/limited/plain'))
              .andReturn();
          expect(refused.response.statusCode, 503);
          expect(refused.response.headers['Retry-After'], '7');
          expect(refused.response.bodyText, isNot(contains('198.51.100.7')));
          expect(refused.response.bodyText, isNot(contains('store is down')));
        }
        expect(records, hasLength(1));
        expect(records.single.message, contains('api'));
        expect(records.single.message, contains('on-store-failure: deny'));
        expect(records.single.message, isNot(contains('198.51.100.7')));
        expect(records.single.error, isNull);
        store.failing = false;
        await mvc.perform(_from('/limited/plain')).andExpect(status: 200);
      });
    });

    test('allows when asked to, for all rules or for one', () async {
      await _runner(
        [
          'spring.web.rate-limit.on-store-failure=allow',
          ..._rule(0, {'path': '/limited/plain', 'key': 'ip', 'limit': '5/1m'}),
          ..._rule(1, {
            'path': '/limited/annotated',
            'key': 'ip',
            'limit': '5/1m',
            'on-store-failure': 'deny',
          }),
        ],
        beans: [_recordingStore],
      ).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        context.getBean<_RecordingStore>().failing = true;
        await mvc.perform(_from('/limited/plain')).andExpect(status: 200);
        expect(records.single.message, contains('let through'));
        await mvc.perform(_from('/limited/annotated')).andExpect(status: 503);
      });
    });
  });

  group('which store', () {
    Future<Object?> storeOf(
      List<String> properties, {
      List<BeanModule> beans = const [],
    }) =>
        _runner(
          [
            ..._rule(0, {'limit': '5/1m'}),
            ...properties,
          ],
          beans: beans,
        ).runAsync(
          (context) async =>
              context.startupFailure ?? context.getBean<RateLimitStore>(),
        );

    test('memory by default', () async {
      expect(await storeOf([]), isA<InMemoryRateLimitStore>());
    });

    test('the first isolate for a pool of isolates, or when asked', () async {
      // server.isolates.max asks for a pool, without starting an isolate.
      expect(
        await storeOf(['server.isolates.max=2']),
        isA<PrimaryIsolateRateLimitStore>(),
      );
      expect(
        await storeOf(['spring.web.rate-limit.store=primary-isolate']),
        isA<PrimaryIsolateRateLimitStore>(),
      );
      expect(
        await storeOf([
          'server.isolates.max=2',
          'spring.web.rate-limit.store=memory',
        ]),
        isA<InMemoryRateLimitStore>(),
      );
    });

    test('a bean of the application replaces them all', () async {
      expect(
        await storeOf([], beans: [_recordingStore]),
        isA<_RecordingStore>(),
      );
      expect(
        await storeOf(
          ['server.isolates.max=2', 'spring.web.rate-limit.store=memory'],
          beans: [_recordingStore],
        ),
        isA<_RecordingStore>(),
      );
    });

    test('a store the application does not have stops the start', () async {
      final failure = await storeOf(['spring.web.rate-limit.store=jdbc']);
      expect('$failure', contains('spring.web.rate-limit.store=jdbc'));
      expect('$failure', contains('spring_boot_starter_data'));
    });

    test('the size of the store in memory', () async {
      final store = await storeOf([
        'spring.web.rate-limit.memory.max-entries=7',
      ]);
      expect((store! as InMemoryRateLimitStore).maxEntries, 7);
    });

    test('the pool store counts in the first isolate', () async {
      await _runner([
        'spring.web.rate-limit.store=primary-isolate',
        ..._rule(0, {'path': '/limited/plain', 'key': 'ip', 'limit': '10/1m'}),
      ]).runAsync((context) async {
        final mvc = MockMvc.of(context.context);
        final results = await Future.wait([
          for (var i = 0; i < 100; i++)
            mvc.perform(_from('/limited/plain')).andReturn(),
        ]);
        expect(
          results.where((r) => r.response.statusCode == 200),
          hasLength(10),
        );
        expect(
          results.where((r) => r.response.statusCode == 429),
          hasLength(90),
        );
        // The rule's bucket and the one of the controller's @RateLimiter.
        expect(
          context.getBean<PrimaryIsolateRateLimitHandler>().buckets.length,
          2,
        );
      });
    });
  });
}

final class _User implements Principal {
  const _User(this.name);

  @override
  final String name;
}

final class _TenantResolver implements RateLimitKeyResolver {
  const _TenantResolver();

  @override
  bool supports(String key) => key == 'tenant';

  @override
  bool beforeAuthentication(String key) => true;

  @override
  RateLimitSubject? resolve(String key, RateLimitRequest request) =>
      switch (request.request.headers['X-Tenant']) {
        final tenant? => RateLimitSubject('tenant', tenant),
        null => null,
      };
}
