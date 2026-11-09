import 'package:spring_core_dart/spring_core_dart.dart';

const _log = SpringLog('spring.boot.availability.ApplicationAvailabilityBean');

/// A kind of availability of the running application: whether it is alive
/// ([LivenessState]) and whether it takes requests ([ReadinessState]).
///
/// Orchestrators such as Kubernetes ask these two questions separately: a
/// broken application is restarted, an application that is not ready only
/// gets no traffic for a while. The actuator's `liveness` and `readiness`
/// health groups answer them from the current states.
///
/// Spring Boot (Java): `AvailabilityState`.
abstract interface class AvailabilityState {}

/// Whether the application's internal state is correct: a broken
/// application cannot recover by itself and should be restarted.
///
/// `SpringApplication` sets it to [correct] once the context is started
/// (with `ApplicationStartedEvent`); code that detects a state it cannot
/// leave publishes [broken].
///
/// ```dart
/// AvailabilityChangeEvent.publish(context, LivenessState.broken);
/// ```
///
/// Spring Boot (Java): `LivenessState` (`CORRECT`, `BROKEN`).
enum LivenessState implements AvailabilityState {
  /// The application runs and its internal state is correct.
  correct,

  /// The application runs but its internal state is broken.
  broken,
}

/// Whether the application is ready to take requests.
///
/// `SpringApplication` sets it to [acceptingTraffic] once the runners are
/// done (with `ApplicationReadyEvent`). Code that is busy for a while (a
/// cache being rebuilt, a migration) publishes [refusingTraffic] and then
/// [acceptingTraffic] again, so a load balancer sends the requests
/// elsewhere meanwhile.
///
/// Spring Boot (Java): `ReadinessState` (`ACCEPTING_TRAFFIC`,
/// `REFUSING_TRAFFIC`).
enum ReadinessState implements AvailabilityState {
  /// The application takes requests.
  acceptingTraffic,

  /// The application does not want requests for now.
  refusingTraffic,
}

/// Announces a new [state] of the application's availability.
///
/// Publish one to change a state; [ApplicationAvailability] keeps the last
/// state of each kind, and listeners (an `@EventListener` method taking
/// the event) can react to it.
///
/// ```dart
/// @Component()
/// class CacheRebuild {
///   CacheRebuild(this.events);
///   final ApplicationEventPublisher events;
///
///   Future<void> rebuild() async {
///     AvailabilityChangeEvent.publish(
///       events,
///       ReadinessState.refusingTraffic,
///     );
///     await cache.rebuild();
///     AvailabilityChangeEvent.publish(
///       events,
///       ReadinessState.acceptingTraffic,
///     );
///   }
/// }
/// ```
///
/// Spring Boot (Java): `AvailabilityChangeEvent<S>`.
class AvailabilityChangeEvent<S extends AvailabilityState>
    extends PayloadApplicationEvent<S> {
  /// The event of [state], published by [source].
  // Named after what the event carries, as Boot's constructor.
  // ignore: matching_super_parameters
  AvailabilityChangeEvent(super.source, super.state);

  /// The new state.
  S get state => payload;

  /// Publishes the event of [state] through [publisher], which is also its
  /// source.
  static void publish<S extends AvailabilityState>(
    ApplicationEventPublisher publisher,
    S state,
  ) => publisher.publishEvent(AvailabilityChangeEvent<S>(publisher, state));

  @override
  String get eventName => 'AvailabilityChangeEvent $state';

  @override
  String toString() => 'AvailabilityChangeEvent[state=$state]';
}

/// The current availability states of the application.
///
/// Inject it to ask whether the application is alive or ready; change the
/// states by publishing an [AvailabilityChangeEvent].
///
/// ```dart
/// if (availability.readinessState == ReadinessState.acceptingTraffic) { ... }
/// ```
///
/// Spring Boot (Java): `ApplicationAvailability`.
abstract interface class ApplicationAvailability {
  /// The last [LivenessState] published; [LivenessState.broken] before the
  /// first.
  LivenessState get livenessState;

  /// The last [ReadinessState] published;
  /// [ReadinessState.refusingTraffic] before the first.
  ReadinessState get readinessState;

  /// The last state of type [S] published, or [defaultState] when none was.
  S getState<S extends AvailabilityState>(S defaultState);

  /// The last event of a state of type [S], or `null` when none was
  /// published.
  AvailabilityChangeEvent<S>? getLastChangeEvent<S extends AvailabilityState>();
}

/// The [ApplicationAvailability] bean: it listens to every
/// [AvailabilityChangeEvent] and keeps the last one of each kind of state.
///
/// `spring_boot_dart` declares it as the `applicationAvailability` bean
/// unless the application has its own [ApplicationAvailability].
///
/// Spring Boot (Java): `ApplicationAvailabilityBean`, declared by
/// `ApplicationAvailabilityAutoConfiguration`.
class ApplicationAvailabilityBean
    implements ApplicationAvailability, GenericApplicationListener {
  final _events = <Type, AvailabilityChangeEvent<AvailabilityState>>{};

  @override
  LivenessState get livenessState => getState(LivenessState.broken);

  @override
  ReadinessState get readinessState => getState(ReadinessState.refusingTraffic);

  @override
  S getState<S extends AvailabilityState>(S defaultState) =>
      switch (_events[S]?.state) {
        final S state => state,
        _ => defaultState,
      };

  @override
  AvailabilityChangeEvent<S>?
  getLastChangeEvent<S extends AvailabilityState>() => switch (_events[S]) {
    final AvailabilityChangeEvent<S> event => event,
    _ => null,
  };

  @override
  bool supportsEvent(Object event) =>
      event is AvailabilityChangeEvent<AvailabilityState>;

  @override
  void onApplicationEvent(Object event) {
    if (event is! AvailabilityChangeEvent<AvailabilityState>) {
      return;
    }
    // Keyed by the state's enum, whatever type argument the event has.
    final type = switch (event.state) {
      LivenessState() => LivenessState,
      ReadinessState() => ReadinessState,
      final other => other.runtimeType,
    };
    final last = _events[type];
    _events[type] = event;
    _log.debug(
      () =>
          'Application availability state $type changed'
          '${last == null ? '' : ' from ${_name(last.state)}'} to '
          '${_name(event.state)}',
    );
  }

  static String _name(AvailabilityState state) =>
      state is Enum ? (state as Enum).name : '$state';
}
