import 'package:spring_boot_dart/src/availability.dart';
import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _source =
    'package:spring_boot_dart#ApplicationAvailabilityAutoConfiguration';

/// The `applicationAvailability` bean, an [ApplicationAvailabilityBean]
/// that keeps the liveness and readiness states published with
/// [AvailabilityChangeEvent], unless the application declares its own
/// [ApplicationAvailability].
///
/// Switch it off with
/// `spring.autoconfigure.exclude=ApplicationAvailabilityAutoConfiguration`.
///
/// Spring (Java): `ApplicationAvailabilityAutoConfiguration`.
final availabilityAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<ApplicationAvailabilityBean>(
    name: 'applicationAvailability',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'applicationAvailability',
    types: const [
      ApplicationAvailabilityBean,
      ApplicationAvailability,
      GenericApplicationListener,
    ],
    source: _source,
    conditions: const [
      ConditionGroup('$_source.applicationAvailability', [
        ConditionalOnMissingBean(ApplicationAvailability),
      ]),
    ],
    create: (_) => ApplicationAvailabilityBean(),
  ),
];
