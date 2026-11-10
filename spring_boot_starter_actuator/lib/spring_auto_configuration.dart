/// The starter's auto-configuration. Applications never import it: the
/// generator finds this file in every dependency and adds its module to
/// the generated application, which is what makes the dependency alone
/// enough. A test that builds a context by hand can name it.
library;

import 'package:spring_boot_actuator/spring_boot_actuator.dart';
import 'package:spring_boot_starter_actuator/src/actuator_auto_configuration.dart';
import 'package:spring_boot_starter_actuator/src/config/config.dart';
import 'package:spring_boot_starter_actuator/src/web/qps_endpoint.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart'
    show RequestRateFilter;

// The auto-configurations this starter builds on (the web starter, and
// through it logging and spring_boot_dart's), so a test of an application
// that lists only this starter can name them.
export 'package:spring_boot_starter_web/spring_auto_configuration.dart';

/// The actuator's beans: the health, info and mappings endpoints, their
/// contributors, and their answers over the web starter. After the web
/// starter's module, whose dispatcher it adds a handler mapping to. Like
/// it, only where a server can run ([ModulePlatform.native]).
@AutoConfigurationModule(
  after: ['springBootStarterWebAutoConfiguration'],
  platform: ModulePlatform.native,
)
final BeanModule springBootStarterActuatorAutoConfiguration = BeanModule(
  'springBootStarterActuatorAutoConfiguration',
  [...actuatorAutoConfiguration],
  imports: [actuatorProperties, actuatorWebProperties],
);

const _qps =
    'package:spring_boot_starter_actuator#QpsEndpointAutoConfiguration';

/// The `qps` endpoint ([QpsEndpoint]) of the web starter's debug feature
/// `qps`: in the build by the same property,
/// `spring.web.debug.qps.enabled: true`, so without the feature the
/// application has neither.
@AutoConfigurationModule(
  after: ['springBootStarterWebDebugQpsAutoConfiguration'],
  build: AutoConfigurationBuild(
    'spring.web.debug.qps.enabled',
    whenMissing: BuildInclusion.never,
  ),
  platform: ModulePlatform.native,
)
final BeanModule springBootStarterActuatorQpsAutoConfiguration = BeanModule(
  'springBootStarterActuatorQpsAutoConfiguration',
  [
    BeanDefinition<QpsEndpoint>(
      name: 'qpsEndpoint',
      factoryMethodName: 'qpsEndpoint',
      source: _qps,
      annotations: const [Endpoint(id: 'qps')],
      conditions: const [
        ConditionGroup('$_qps.qpsEndpoint', [
          // In every isolate of a pool: the filter is, the rates are in
          // the first one, asked from the others.
          ConditionalOnBean(RequestRateFilter),
          ConditionalOnMissingBean(QpsEndpoint),
        ]),
      ],
      create: (r) => QpsEndpoint(r.dependency<PrimaryIsolate>()),
      annotatedMethods: [
        BeanMethod<QpsEndpoint>(
          'qps',
          invoke: (bean, _) => bean.qps(),
          annotations: const [ReadOperation()],
        ),
        BeanMethod<QpsEndpoint>(
          'window',
          invoke: (bean, arguments) => bean.window(arguments.single! as String),
          parameters: const [
            BeanParameter(
              'window',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [Selector()],
            ),
          ],
          annotations: const [ReadOperation()],
        ),
      ],
    ),
  ],
);
