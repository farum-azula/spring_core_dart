// The web starter's rate limiter around the security filter chain: a rule
// keyed by the address refuses before any authentication work, a rule
// keyed by the user sees the user the chain authenticated.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_auto_configuration.dart'
    show springBootStarterWebRateLimitAutoConfiguration;
import 'package:test/test.dart';

import 'support.dart';

// Remembers the keys it was asked for.
final class _Store implements RateLimitStore {
  final List<String> keys = [];
  final _memory = InMemoryRateLimitStore();

  @override
  Future<RateLimitDecision> tryAcquire(
    String key,
    RateLimit limit, {
    int permits = 1,
  }) {
    keys.add(key);
    return _memory.tryAcquire(key, limit, permits: permits);
  }
}

final _beans = BeanModule('rateLimitTest', [
  BeanDefinition<_Store>(
    name: 'recordingStore',
    types: const [_Store, RateLimitStore],
    create: (_) => _Store(),
  ),
]);

void main() {
  Future<void> withLimits(
    Future<void> Function(MockMvc mvc, _Store store) body,
  ) =>
      securityRunner(_beans, [
            'spring.security.user.name=ada',
            'spring.security.user.password=secret',
            'spring.web.rate-limit.rules[0].name=logins',
            'spring.web.rate-limit.rules[0].path=/api/admin',
            'spring.web.rate-limit.rules[0].key=ip',
            'spring.web.rate-limit.rules[0].limit=2/1m',
            'spring.web.rate-limit.rules[1].name=api',
            'spring.web.rate-limit.rules[1].path=/api/**',
            'spring.web.rate-limit.rules[1].limit=2/1m',
          ])
          .withAutoConfiguration(springBootStarterWebRateLimitAutoConfiguration)
          .runAsync((started) async {
            final failure = started.startupFailure;
            if (failure != null) {
              fail('The application failed to start: $failure');
            }
            await body(MockMvc.of(started.context), started.getBean<_Store>());
          });

  test('the filters stand on both sides of the security chain', () async {
    expect(
      RateLimitFilter.beforeAuthenticationOrder,
      lessThan(FilterChainProxy.defaultFilterOrder),
    );
    expect(
      RateLimitFilter.afterAuthenticationOrder,
      greaterThan(FilterChainProxy.defaultFilterOrder),
    );
  });

  test('a rule keyed by the user counts the authenticated user; a request '
      'the chain refused is not counted by it', () async {
    await withLimits((mvc, store) async {
      final ok = basic('ada', 'secret');
      await mvc
          .perform(request(HttpMethod.get, '/api/me', headers: ok))
          .andExpect(status: 200);
      expect(store.keys, ['api:user:ada']);
      await mvc
          .perform(request(HttpMethod.get, '/api/me', headers: ok))
          .andExpect(status: 200);
      final refused = await mvc
          .perform(request(HttpMethod.get, '/api/me', headers: ok))
          .andReturn();
      expect(refused.status, 429);
      expect(refused.header('Retry-After'), isNotNull);

      // Without credentials the chain answers 401 itself: the rule keyed
      // by the user never sees the request.
      store.keys.clear();
      await mvc
          .perform(request(HttpMethod.get, '/api/me'))
          .andExpect(
            status: 401,
          );
      expect(store.keys, isEmpty);
    });
  });

  test('a rule keyed by the address refuses before any authentication '
      'work', () async {
    await withLimits((mvc, store) async {
      final wrong = basic('ada', 'guess');
      for (var i = 0; i < 2; i++) {
        await mvc
            .perform(request(HttpMethod.get, '/api/admin', headers: wrong))
            .andExpect(status: 401);
      }
      expect(store.keys, ['logins:ip:127.0.0.1', 'logins:ip:127.0.0.1']);
      // The third guess is refused before the chain looks at it (the
      // chain would answer 401), and so is a request with the right
      // password.
      for (final headers in [wrong, basic('ada', 'secret')]) {
        final refused = await mvc
            .perform(request(HttpMethod.get, '/api/admin', headers: headers))
            .andReturn();
        expect(refused.status, 429);
      }
    });
  });
}
