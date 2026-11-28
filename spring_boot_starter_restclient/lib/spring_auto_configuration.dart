/// The beans the RestClient starter adds to an application: the HTTP
/// transport with its allowed addresses, the `RestClientBuilder` and the
/// HTTP service groups.
///
/// The generator finds this library in every dependency that has one and
/// registers its module (it is marked `@AutoConfigurationModule()`), so
/// listing the starter in `pubspec.yaml` is enough; Spring Boot finds its
/// auto-configurations through `AutoConfiguration.imports` the same way.
/// Applications do not import it; a test that builds a context by hand
/// may name [springBootStarterRestclientAutoConfiguration].
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_restclient/src/config/config.dart';
import 'package:spring_boot_starter_restclient/src/rest_client_auto_configuration.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

// The auto-configurations this starter builds on (logging, and through it
// spring_boot_dart's), so a test of an application that lists only this
// starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

/// The RestClient starter's auto-configuration module
/// (`restClientAutoConfiguration`): the `httpTransport` bean and its
/// allowed addresses, the `RestClientBuilder` (a new one per injection),
/// its configurer and the HTTP service groups, with the
/// `spring.http.clients.*` and `spring.http.serviceclient.*` properties.
///
/// Registered after the Flutter security starter's, whose transport for a
/// web app logged in by its server (the CSRF token, the server's cookies)
/// must win.
@AutoConfigurationModule(
  after: ['springBootStarterFlutterSecurityAutoConfiguration'],
)
final BeanModule springBootStarterRestclientAutoConfiguration = BeanModule(
  'springBootStarterRestclientAutoConfiguration',
  [...restClientAutoConfiguration],
  imports: [restClientConfigBeans],
);

/// The retries of `@Retryable` methods that return an `EventStream`: the
/// `eventStreamRetryAdapter` ([EventStreamRetryAdapter]), so the retried
/// stream stays an `EventStream` with its whole events. The web starter
/// declares the same bean; the first one registered is kept.
///
/// In the build with `spring.resilience.enabled: true`, as the retries:
/// without it the application has none of it.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.resilience.enabled',
    whenMissing: BuildInclusion.never,
  ),
)
final BeanModule springBootStarterRestclientResilienceAutoConfiguration =
    BeanModule('springBootStarterRestclientResilienceAutoConfiguration', [
      BeanDefinition<EventStreamRetryAdapter>(
        name: 'eventStreamRetryAdapter',
        types: const [EventStreamRetryAdapter, RetryStreamAdapter],
        source: _resilienceSource,
        conditions: const [
          ConditionGroup('$_resilienceSource.eventStreamRetryAdapter', [
            ConditionalOnMissingBean(EventStreamRetryAdapter),
          ]),
        ],
        create: (_) => const EventStreamRetryAdapter(),
      ),
    ]);

const _resilienceSource =
    'package:spring_boot_starter_restclient'
    '#RestClientResilienceAutoConfiguration';
