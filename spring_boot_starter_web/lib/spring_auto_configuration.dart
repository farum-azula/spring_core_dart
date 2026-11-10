/// The beans the web starter adds to an application: the server, the
/// dispatcher, the controller mapping, sessions and uploads.
///
/// The generator finds this library in every dependency that has one and
/// registers its module, so listing the starter in `pubspec.yaml` is
/// enough; Spring Boot finds its auto-configurations through
/// `AutoConfiguration.imports` the same way. Applications do not import
/// it; a test that builds a context by hand may name
/// [springBootStarterWebAutoConfiguration].
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/config/config.dart';
import 'package:spring_boot_starter_web/src/config/web_properties.dart';
import 'package:spring_boot_starter_web/src/debug/request_rate.dart';
import 'package:spring_boot_starter_web/src/dispatcher.dart';
import 'package:spring_boot_starter_web/src/web_auto_configuration.dart';

// The auto-configurations this starter builds on (logging, and through it
// spring_boot_dart's), so a test of an application that lists only this
// starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

/// The web starter's auto-configuration module: the bean definitions of
/// `webMvcAutoConfiguration`. Only where a server can run
/// ([ModulePlatform.native]): a browser build has none of it.
@AutoConfigurationModule(platform: ModulePlatform.native)
final BeanModule springBootStarterWebAutoConfiguration = BeanModule(
  'springBootStarterWebAutoConfiguration',
  [...webMvcAutoConfiguration],
  imports: [webConfigBeans],
);

const _qps = 'package:spring_boot_starter_web#RequestRateAutoConfiguration';

/// The debug feature `qps`: requests per second, logged and answered by
/// the actuator's `qps` endpoint. In the build only with
/// `spring.web.debug.qps.enabled: true`: without it the application has
/// no code that counts its requests.
///
/// - `requestRateFilter` ([RequestRateFilter]): the first filter, counts
///   the requests of its isolate;
/// - `requestRates` ([RequestRates]), in the application's first isolate:
///   the rate of every isolate and of all together, each
///   `spring.web.debug.qps.log-interval`.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.web.debug.qps.enabled',
    whenMissing: BuildInclusion.never,
  ),
  platform: ModulePlatform.native,
)
final BeanModule springBootStarterWebDebugQpsAutoConfiguration = BeanModule(
  'springBootStarterWebDebugQpsAutoConfiguration',
  [
    BeanDefinition<RequestRateFilter>(
      name: 'requestRateFilter',
      types: const [RequestRateFilter, WebFilter, Ordered, IsolateReporter],
      source: _qps,
      create: (_) => RequestRateFilter(),
    ),
    BeanDefinition<RequestRates>(
      name: 'requestRates',
      types: const [
        RequestRates,
        SmartLifecycle,
        Lifecycle,
        PrimaryIsolateHandler,
      ],
      source: _qps,
      conditions: const [
        ConditionGroup('$_qps.requestRates', [ConditionalOnPrimaryIsolate()]),
      ],
      create: (r) => RequestRates(
        r.dependency<RequestRateFilter>(),
        r.dependency<IsolateReports>(),
        interval: r.dependency<WebDebugSettings>().qps.logInterval,
      ),
    ),
  ],
);
