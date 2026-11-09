import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _source = 'package:spring_boot_dart#ObservationAutoConfiguration';

/// The source of the `observedAdvisor`, the bean that puts `@Observed`
/// into effect (in `springBootObservedAnnotationsAutoConfiguration`, in the
/// build only with `spring.observations.annotations.enabled: true`).
///
/// Spring Boot: `ObservationAutoConfiguration.ObservedAspectConfiguration`
/// (`management.observations.annotations.enabled`).
const observedAnnotationsSource =
    'package:spring_boot_dart#ObservedAnnotationsAutoConfiguration';

/// The `observationRegistry` bean ([ObservationRegistry]) with every
/// `ObservationHandler` bean, left out when the app declares its own. A
/// registry without handlers costs nothing: each observation is a no-op.
///
/// Spring Boot: `ObservationAutoConfiguration`.
final observationAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<ObservationRegistry>(
    name: 'observationRegistry',
    factoryMethodName: 'observationRegistry',
    source: _source,
    conditions: const [
      ConditionGroup('$_source#observationRegistry', [
        ConditionalOnMissingBean(ObservationRegistry),
      ]),
    ],
    create: (r) => ObservationRegistry(
      handlers: r.optionalDependencyList<ObservationHandler>() ?? const [],
    ),
  ),
];
