// The property strings are lists of independent entries, each one a single
// string; a long key cannot be split in two (adjacent strings in a list).
// ignore_for_file: lines_longer_than_80_chars

import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'contract.dart';

// Spring Cloud OpenFeign binds `spring.feign.client.config.*`
// with Boot's relaxed names: camelCase, snake_case and environment
// variables work like the canonical kebab-case keys.
void main() {
  late MockHttpTransport server;
  late ApplicationContextRunner runner;

  setUp(() {
    server = MockHttpTransport()
      ..when(HttpMethod.get, '/static').respond(200, body: 'ok');
    runner = const ApplicationContextRunner()
        .withUserConfiguration(contractModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withBean<HttpTransport>(() => server);
  });

  test('camelCase keys: readTimeout, followRedirects, loggerLevel, '
      'defaultRequestHeaders, defaultQueryParameters', () async {
    await runner
        .withPropertyValues([
          'spring.feign.client.config.contract-v2.readTimeout=5s',
          'spring.feign.client.config.contract-v2.followRedirects=false',
          'spring.feign.client.config.contract-v2.loggerLevel=basic',
          'spring.feign.client.config.contract-v2.defaultRequestHeaders.X-Shop=neon',
          'spring.feign.client.config.default.defaultQueryParameters.lang=en',
          'spring.feign.client.config.default.eventStream.reconnectDelay=1s',
        ])
        .runAsync((context) async {
          await context.getBean<ContractClient>().statics();
          final request = server.lastRequest;
          expect(request.readTimeout, const Duration(seconds: 5));
          expect(request.followRedirects, isFalse);
          expect(request.headers['X-Shop'], 'neon');
          expect(request.url.queryParameters['lang'], 'en');
          final config = FeignClientConfig.of(
            context.getBean<FeignProperties>(),
            'contract-v2',
          );
          expect(config.loggerLevel, FeignLoggerLevel.basic);
          expect(config.eventStreamReconnectDelay, const Duration(seconds: 1));
        });
  });

  test('snake_case keys and environment variables', () async {
    await runner
        .withPropertyValues([
          'spring.feign.client.config.contract-v2.read_timeout=3s',
          'spring.feign.client.config.contract-v2.default_request_headers.X-Trace=t1',
        ])
        .withSystemEnvironment({
          'SPRING_FEIGN_CLIENT_CONFIG_DEFAULT_CONNECTTIMEOUT': '4s',
          'SPRING_FEIGN_CLIENT_CONFIG_CONTRACTV2_FOLLOWREDIRECTS': 'false',
        })
        .runAsync((context) async {
          await context.getBean<ContractClient>().statics();
          final request = server.lastRequest;
          expect(request.readTimeout, const Duration(seconds: 3));
          expect(request.headers['X-Trace'], 't1');
          expect(request.followRedirects, isFalse);
          expect(
            FeignClientConfig.connectTimeout(
              context.getBean<FeignProperties>(),
            ),
            const Duration(seconds: 4),
          );
        });
  });

  test('property-source precedence decides, not the form', () async {
    await runner
        .withPropertyValues([
          'spring.feign.client.config.contract-v2.readTimeout=2s',
        ])
        .withSystemEnvironment({
          // The OS environment is below the test properties.
          'SPRING_FEIGN_CLIENT_CONFIG_CONTRACTV2_READTIMEOUT': '9s',
        })
        .runAsync((context) async {
          await context.getBean<ContractClient>().statics();
          expect(server.lastRequest.readTimeout, const Duration(seconds: 2));
        });
  });
}
