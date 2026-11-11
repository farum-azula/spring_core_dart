// Environment variables that write a dash of a property as an underscore
// (`RATE_LIMIT` for `rate-limit`): lists, maps and the properties of
// their elements bind from them the way scalars do.
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

class Upstream {
  String host = '';
  Duration readTimeout = Duration.zero;
}

final upstreamIntrospection = BeanIntrospection<Upstream>(
  properties: [
    BeanProperty<Upstream>(
      'host',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.host,
      set: (b, v) => b.host = v! as String,
    ),
    BeanProperty<Upstream>(
      'readTimeout',
      type: Duration,
      typeInfo: const ClassType<Duration>(),
      get: (b) => b.readTimeout,
      set: (b, v) => b.readTimeout = v! as Duration,
    ),
  ],
  instantiate: Upstream.new,
);

void main() {
  StandardEnvironment environment(
    Map<String, String> system, [
    Map<String, Object?> properties = const {},
  ]) {
    final env = StandardEnvironment(systemEnvironment: system)
      ..propertySources.addFirst(MapPropertySource('test', properties));
    ConfigurationPropertySources.attach(env);
    return env;
  }

  Binder binder(Map<String, String> system) => Binder(
    environment(system),
    introspector: BeanIntrospector()..register(upstreamIntrospection),
  );

  const strings = ListType<String>(ClassType<String>());
  const labels = MapType<String, String>(
    ClassType<String>(),
    ClassType<String>(),
  );
  const upstreams = ListType<Upstream>(ClassType<Upstream>());
  const upstreamsByName = MapType<String, Upstream>(
    ClassType<String>(),
    ClassType<Upstream>(),
  );

  group('the rate limiter from environment variables', () {
    test('a rule under RATE_LIMIT', () {
      final properties = bindRateLimitProperties(
        environment({
          'SPRING_WEB_RATE_LIMIT_RULES_0_LIMIT': '5/1m',
          'SPRING_WEB_RATE_LIMIT_RULES_0_PATH': '/api/**',
          'SPRING_WEB_RATE_LIMIT_RULES_0_METHODS_0': 'POST',
          'SPRING_WEB_RATE_LIMIT_RULES_1_LIMIT': '120/1m',
        }),
      );
      expect(properties.rules, hasLength(2));
      expect(properties.rules[0].limit, '5/1m');
      expect(properties.rules[0].path, '/api/**');
      expect(properties.rules[0].methods, ['POST']);
      expect(properties.rules[1].limit, '120/1m');
      expect(properties.isOn, isTrue);
    });

    test('the trusted proxies under RATE_LIMIT_TRUSTED_PROXIES', () {
      final properties = bindRateLimitProperties(
        environment({
          'SPRING_WEB_RATE_LIMIT_TRUSTED_PROXIES_0': '10.0.0.1',
          'SPRING_WEB_RATE_LIMIT_TRUSTED_PROXIES_1': '10.0.0.0/8',
        }),
      );
      expect(properties.trustedProxies, ['10.0.0.1', '10.0.0.0/8']);
    });

    test("a rule's ON_STORE_FAILURE under RATELIMIT and RATE_LIMIT", () {
      for (final prefix in ['SPRING_WEB_RATELIMIT', 'SPRING_WEB_RATE_LIMIT']) {
        final properties = bindRateLimitProperties(
          environment({
            '${prefix}_RULES_0_LIMIT': '5/1m',
            '${prefix}_RULES_0_ON_STORE_FAILURE': 'allow',
          }),
        );
        expect(
          properties.rules.single.onStoreFailure,
          RateLimitStoreFailure.allow,
          reason: prefix,
        );
      }
    });

    test('the scalars as before, in both spellings', () {
      final underscored = bindRateLimitProperties(
        environment({
          'SPRING_WEB_RATE_LIMIT_ENABLED': 'true',
          'SPRING_WEB_RATE_LIMIT_MEMORY_MAX_ENTRIES': '7',
        }),
      );
      expect(underscored.enabled, isTrue);
      expect(underscored.memory.maxEntries, 7);
      final joined = bindRateLimitProperties(
        environment({
          'SPRING_WEB_RATELIMIT_ENABLED': 'true',
          'SPRING_WEB_RATELIMIT_MEMORY_MAXENTRIES': '7',
          'SPRING_WEB_RATELIMIT_RULES_0_ONSTOREFAILURE': 'allow',
        }),
      );
      expect(joined.enabled, isTrue);
      expect(joined.memory.maxEntries, 7);
      expect(joined.rules.single.onStoreFailure, RateLimitStoreFailure.allow);
    });
  });

  group('a dash written as an underscore', () {
    test('a list of scalars', () {
      final hosts = binder({
        'APP_ALLOWED_HOSTS_0': 'a.example',
        'APP_ALLOWED_HOSTS_1': 'b.example',
      }).bind('app.allowed-hosts', strings).get();
      expect(hosts, ['a.example', 'b.example']);
    });

    test('a list of scalars as one variable still binds', () {
      final hosts = binder({
        'APP_ALLOWED_HOSTS': 'a.example, b.example',
      }).bind('app.allowed-hosts', strings).get();
      expect(hosts, ['a.example', 'b.example']);
    });

    test('a list of objects, the prefix and the properties', () {
      final bound = binder({
        'APP_MAIN_UPSTREAMS_0_HOST': 'a.example',
        'APP_MAIN_UPSTREAMS_0_READ_TIMEOUT': '2s',
        'APP_MAIN_UPSTREAMS_1_HOST': 'b.example',
        'APP_MAIN_UPSTREAMS_1_READTIMEOUT': '3s',
      }).bind('app.main-upstreams', upstreams).get();
      expect(bound.map((u) => u.host), ['a.example', 'b.example']);
      expect(bound.map((u) => u.readTimeout), const [
        Duration(seconds: 2),
        Duration(seconds: 3),
      ]);
    });

    test('a map of scalars', () {
      final bound = binder({
        'APP_EXTRA_LABELS_TEAM': 'core',
        'APP_EXTRA_LABELS_TIER': 'web',
      }).bind('app.extra-labels', labels).get();
      expect(bound, {'team': 'core', 'tier': 'web'});
    });

    test('a map of objects', () {
      final bound = binder({
        'APP_MAIN_UPSTREAMS_EU_HOST': 'eu.example',
        'APP_MAIN_UPSTREAMS_EU_READ_TIMEOUT': '2s',
        'APP_MAINUPSTREAMS_US_HOST': 'us.example',
      }).bind('app.main-upstreams', upstreamsByName).get();
      expect(bound.keys, unorderedEquals(['eu', 'us']));
      expect(bound['eu']!.host, 'eu.example');
      expect(bound['eu']!.readTimeout, const Duration(seconds: 2));
      expect(bound['us']!.host, 'us.example');
    });

    test('a gap in the indexes is still reported', () {
      final result = binder({
        'APP_ALLOWED_HOSTS_0': 'a.example',
        'APP_ALLOWED_HOSTS_2': 'c.example',
      });
      expect(
        () => result.bind('app.allowed-hosts', strings).get(),
        throwsA(
          predicate((e) => '$e'.contains('app.allowed-hosts[2]'), 'names [2]'),
        ),
      );
    });

    test('the spelling without the underscore wins', () {
      final hosts = binder({
        'APP_ALLOWED_HOSTS_0': 'underscored',
        'APP_ALLOWEDHOSTS_0': 'joined',
      }).bind('app.allowed-hosts', strings).get();
      expect(hosts, ['joined']);
    });

    test('a variable that only starts alike is not taken', () {
      final result = binder({
        'APP_ALLOWED_0': 'x',
        'APP_ALLOWED_HOSTSFILE_0': 'y',
        'APPALLOWED_HOSTS_0': 'z',
      }).bind('app.allowed-hosts', strings);
      expect(result.isBound, isFalse);
    });

    test('only for environment variables', () {
      final env = StandardEnvironment(systemEnvironment: const {})
        ..propertySources.addFirst(
          const MapPropertySource('test', {
            'app.allowed.hosts[0]': 'a.example',
          }),
        );
      ConfigurationPropertySources.attach(env);
      expect(Binder(env).bind('app.allowed-hosts', strings).isBound, isFalse);
    });
  });
}
