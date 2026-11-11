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

/// A server: what it stops in, it notes.
class Server with SmartLifecycle {
  Server(this.availability, this.seen);

  final ApplicationAvailability availability;
  final List<Object> seen;
  var _running = false;

  @override
  bool get isRunning => _running;

  @override
  void start() => _running = true;

  @override
  void stop() {
    seen.add(availability.readinessState);
    _running = false;
  }
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

  group('a context that closes refuses traffic', () {
    ConfigurableApplicationContext server(
      List<Object> seen,
    ) => SpringApplication(
      [
        BeanModule('app', [
          BeanDefinition<Server>(
            name: 'server',
            types: const [Server, SmartLifecycle, Lifecycle],
            create: (factory) =>
                Server(factory.getBean<ApplicationAvailability>(), seen),
          ),
        ]),
      ],
      autoConfigurations: [springBootAutoConfiguration],
      out: (_) {},
      listeners: [
        // Before the server stops, and after the state changed.
        ApplicationListenerAdapter.of<ContextClosedEvent>(
          (event) => seen.add('closed'),
        ),
        ApplicationListenerAdapter.of<AvailabilityChangeEvent<ReadinessState>>(
          (event) => seen.add('event ${event.state.name}'),
        ),
      ],
    ).run(const [], systemEnvironment: const {});

    const expected = [
      'event acceptingTraffic',
      'event refusingTraffic',
      'closed',
      ReadinessState.refusingTraffic,
    ];

    test('before its lifecycle beans stop', () {
      final seen = <Object>[];
      final context = server(seen);
      final availability = context.getBean<ApplicationAvailability>();
      expect(availability.readinessState, ReadinessState.acceptingTraffic);
      context.close();
      expect(seen, expected);
      expect(availability.readinessState, ReadinessState.refusingTraffic);
      expect(availability.livenessState, LivenessState.correct);
      expect(
        availability.getLastChangeEvent<ReadinessState>()?.source,
        same(context),
      );
    });

    test('with closeAsync too', () async {
      final seen = <Object>[];
      final context = server(seen);
      final closing = context.closeAsync();
      // Already at the call, before anything is awaited.
      expect(
        context.getBean<ApplicationAvailability>().readinessState,
        ReadinessState.refusingTraffic,
      );
      await closing;
      expect(seen, expected);
    });

    test('once: a second close publishes nothing', () {
      final seen = <Object>[];
      server(seen)
        ..close()
        ..close();
      expect(seen, expected);
    });
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
