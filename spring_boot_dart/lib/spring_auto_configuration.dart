/// The beans `spring_boot_dart` adds to every application by itself: a
/// `messageSource`, a JSON `ObjectMapper`, a `Validator`, the
/// `lifecycleProcessor` with the shutdown timeout of the configuration and
/// the `applicationAvailability` (liveness and readiness).
///
/// Applications do not import this file. The generator of every
/// application that depends on `spring_boot_dart` finds it (a package's
/// `lib/spring_auto_configuration.dart` is where it looks for an
/// `@AutoConfigurationModule`) and passes the module to the generated
/// `springApplication`.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_dart/src/autoconfigure/availability_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/isolate_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/jackson_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/json_schema_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/lifecycle_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/message_source_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/observation_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/resilience_auto_configuration.dart';
import 'package:spring_boot_dart/src/autoconfigure/validation_auto_configuration.dart';

/// The auto-configuration of `spring_boot_dart`:
/// `MessageSourceAutoConfiguration`, `JacksonAutoConfiguration`,
/// `JsonSchemaAutoConfiguration`, `ValidationAutoConfiguration`,
/// `LifecycleAutoConfiguration`, `ApplicationAvailabilityAutoConfiguration`,
/// `ObservationAutoConfiguration` and `IsolateAutoConfiguration`.
///
/// Each one backs off when the application declares its own bean, and
/// each can be switched off by name, for example
/// `spring.autoconfigure.exclude=JacksonAutoConfiguration`. The module as a
/// whole is excluded with `excludeName: ['springBootAutoConfiguration']`.
@AutoConfigurationModule()
final BeanModule springBootAutoConfiguration = BeanModule(
  'springBootAutoConfiguration',
  [
    ...messageSourceAutoConfiguration,
    ...jacksonAutoConfiguration,
    ...jsonSchemaAutoConfiguration,
    ...validationAutoConfiguration,
    ...lifecycleAutoConfiguration,
    ...availabilityAutoConfiguration,
    ...observationAutoConfiguration,
    ...isolateAutoConfiguration,
  ],
  imports: [bootPropertiesBeans],
);

/// `@Observed` put into effect (`ObservedAnnotationsAutoConfiguration`): in
/// the build only with `spring.observations.annotations.enabled: true`, so
/// without it no proxy is written for the beans marked `@Observed`.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.observations.annotations.enabled',
    whenMissing: BuildInclusion.never,
  ),
)
// The advisor is written here, in the module: the build reads the advisors
// of a module it leaves out as none, so the beans marked @Observed get no
// proxy then.
final BeanModule springBootObservedAnnotationsAutoConfiguration = BeanModule(
  'springBootObservedAnnotationsAutoConfiguration',
  [
    BeanDefinition<DefaultPointcutAdvisor>(
      name: 'observedAdvisor',
      types: const [
        DefaultPointcutAdvisor,
        PointcutAdvisor,
        Advisor,
        Ordered,
      ],
      source: observedAnnotationsSource,
      create: (r) => DefaultPointcutAdvisor(
        const ObservedPointcut(),
        ObservedInterceptor(r.dependency<ObservationRegistry>()),
        order: AdvisorOrder.observation,
      ),
    ),
  ],
);

/// `@Retryable` and `@ConcurrencyLimit` put into effect
/// (`ResilienceAutoConfiguration`): in the build only with
/// `spring.resilience.enabled: true`, so without it no proxy is written for
/// the beans that carry them, and they cost nothing.
///
/// - `concurrencyLimitAdvisor`, at `AdvisorOrder.concurrencyLimit`: the
///   limits, with the placeholders of `limitString` filled from the
///   environment;
/// - `retryAdvisor`, at `AdvisorOrder.retry`, inside it: the retries, with
///   the placeholders of the `*String` attributes filled, a
///   `MethodRetryEvent` published for each failure, every `RetryListener`
///   bean told (found at the first retry), and the `RetryStreamAdapter` and
///   `MethodRetryVeto` beans of the other starters.
///
/// Spring (Java): `@EnableResilientMethods`; Spring Boot adds nothing.
@AutoConfigurationModule(
  build: AutoConfigurationBuild(
    'spring.resilience.enabled',
    whenMissing: BuildInclusion.never,
  ),
)
// The advisors are written here, in the module, as the one of @Observed.
final BeanModule springBootResilienceAutoConfiguration = BeanModule(
  'springBootResilienceAutoConfiguration',
  [
    BeanDefinition<DefaultPointcutAdvisor>(
      name: 'concurrencyLimitAdvisor',
      types: const [
        DefaultPointcutAdvisor,
        PointcutAdvisor,
        Advisor,
        Ordered,
      ],
      source: resilienceSource,
      create: (r) => DefaultPointcutAdvisor(
        const ConcurrencyLimitPointcut(),
        ConcurrencyLimitInterceptor(
          environment: r.dependency<ConfigurableEnvironment>(),
        ),
        order: AdvisorOrder.concurrencyLimit,
      ),
    ),
    BeanDefinition<DefaultPointcutAdvisor>(
      name: 'retryAdvisor',
      types: const [
        DefaultPointcutAdvisor,
        PointcutAdvisor,
        Advisor,
        Ordered,
      ],
      source: resilienceSource,
      create: (r) {
        final listeners = r.provider<RetryListener>();
        return DefaultPointcutAdvisor(
          const RetryablePointcut(),
          RetryInterceptor(
            environment: r.dependency<ConfigurableEnvironment>(),
            introspector: r.dependency<Introspector>(),
            eventPublisher: r.dependency<ApplicationEventPublisher>(),
            retryListener: CompositeRetryListener.lazy(listeners.orderedList),
            streamAdapters:
                r.optionalDependencyList<RetryStreamAdapter>() ?? const [],
            vetoes: r.optionalDependencyList<MethodRetryVeto>() ?? const [],
          ),
          order: AdvisorOrder.retry,
        );
      },
    ),
  ],
);
