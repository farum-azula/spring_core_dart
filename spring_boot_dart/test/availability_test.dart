// ApplicationAvailability: the liveness and readiness states that
// SpringApplication publishes after the start and the runners, changed by
// AvailabilityChangeEvent, as in Spring Boot.
import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

/// An availability of the application's own.
class FixedAvailability implements ApplicationAvailability {
  @override
  LivenessState get livenessState => LivenessState.broken;

  @override
  ReadinessState get readinessState => ReadinessState.refusingTraffic;

  @override
  S getState<S extends AvailabilityState>(S defaultState) => defaultState;

  @override
  AvailabilityChangeEvent<S>?
  getLastChangeEvent<S extends AvailabilityState>() => null;
}

/// A state that is neither liveness nor readiness.
enum Maintenance implements AvailabilityState { on, off }

void main() {
  ConfigurableApplicationContext run([
    List<BeanDefinition<Object>> beans = const [],
  ]) => SpringApplication(
    [BeanModule('app', beans)],
    autoConfigurations: [springBootAutoConfiguration],
    out: (_) {},
  ).run(const [], systemEnvironment: const {});

  test('correct and accepting traffic once the application is ready', () {
    final context = run();
    addTearDown(context.close);
    final availability = context.getBean<ApplicationAvailability>();
    expect(availability, isA<ApplicationAvailabilityBean>());
    expect(availability.livenessState, LivenessState.correct);
    expect(availability.readinessState, ReadinessState.acceptingTraffic);
    expect(
      availability.getLastChangeEvent<ReadinessState>()?.source,
      same(context),
    );
  });

  test('an AvailabilityChangeEvent changes the state', () {
    final context = run();
    addTearDown(context.close);
    final availability = context.getBean<ApplicationAvailability>();
    AvailabilityChangeEvent.publish(context, ReadinessState.refusingTraffic);
    AvailabilityChangeEvent.publish(context, LivenessState.broken);
    expect(availability.readinessState, ReadinessState.refusingTraffic);
    expect(availability.livenessState, LivenessState.broken);
    expect(
      availability.getLastChangeEvent<LivenessState>()?.state,
      LivenessState.broken,
    );
  });

  test('states of other kinds are kept too', () {
    final context = run();
    addTearDown(context.close);
    final availability = context.getBean<ApplicationAvailability>();
    expect(availability.getState(Maintenance.off), Maintenance.off);
    expect(availability.getLastChangeEvent<Maintenance>(), isNull);
    AvailabilityChangeEvent.publish(context, Maintenance.on);
    expect(availability.getState(Maintenance.off), Maintenance.on);
  });

  test('before any event: broken and refusing traffic', () {
    final availability = ApplicationAvailabilityBean();
    expect(availability.livenessState, LivenessState.broken);
    expect(availability.readinessState, ReadinessState.refusingTraffic);
    expect(availability.getLastChangeEvent<LivenessState>(), isNull);
  });

  test('backs off for an ApplicationAvailability of the application', () {
    final context = run([
      BeanDefinition<FixedAvailability>(
        name: 'fixedAvailability',
        types: const [FixedAvailability, ApplicationAvailability],
        create: (_) => FixedAvailability(),
      ),
    ]);
    addTearDown(context.close);
    expect(
      context.getBean<ApplicationAvailability>(),
      isA<FixedAvailability>(),
    );
    expect(context.containsBean('applicationAvailability'), isFalse);
  });

  test('an @EventListener sees the events with their states', () {
    final seen = <AvailabilityState>[];
    final context = SpringApplication(
      [BeanModule('app', const [])],
      autoConfigurations: [springBootAutoConfiguration],
      out: (_) {},
      listeners: [
        ApplicationListenerAdapter.of<AvailabilityChangeEvent<LivenessState>>(
          (event) => seen.add(event.state),
        ),
      ],
    ).run(const [], systemEnvironment: const {});
    addTearDown(context.close);
    expect(seen, [LivenessState.correct]);
  });
}
