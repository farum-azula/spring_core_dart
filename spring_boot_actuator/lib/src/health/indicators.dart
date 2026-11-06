import 'package:spring_boot_actuator/src/health/contributor.dart';
import 'package:spring_boot_actuator/src/health/health.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Always `UP`: the application answers. The report's `ping`.
///
/// Spring Boot (Java): `PingHealthIndicator`.
class PingHealthIndicator extends HealthIndicator {
  @override
  Health health() => Health.up().build();
}

/// The health of an [AvailabilityState]: the [mappings] of the current
/// state of type [S] to a status.
///
/// Spring Boot (Java): `AvailabilityStateHealthIndicator`.
class AvailabilityStateHealthIndicator<S extends AvailabilityState>
    extends HealthIndicator {
  /// The indicator of the states [S] of [availability], [defaultState]
  /// until one is published.
  AvailabilityStateHealthIndicator(
    this.availability,
    this.defaultState,
    Map<S, Status> mappings,
  ) : mappings = Map.unmodifiable(mappings);

  /// Where the states come from.
  final ApplicationAvailability availability;

  /// The state before any was published.
  final S defaultState;

  /// The status of each state.
  final Map<S, Status> mappings;

  @override
  Health health() {
    final state = availability.getState<S>(defaultState);
    final status = mappings[state];
    if (status == null) {
      throw StateError('No status mapped for the availability state $state');
    }
    return Health.withStatus(status).build();
  }
}

/// `UP` while the application is [LivenessState.correct], `DOWN` when it
/// is broken: the `livenessState` of the `liveness` group.
///
/// Spring Boot (Java): `LivenessStateHealthIndicator`.
class LivenessStateHealthIndicator
    extends AvailabilityStateHealthIndicator<LivenessState> {
  /// The indicator of [availability]'s liveness.
  LivenessStateHealthIndicator(ApplicationAvailability availability)
    : super(availability, LivenessState.broken, const {
        LivenessState.correct: Status.up,
        LivenessState.broken: Status.down,
      });
}

/// `UP` while the application accepts traffic, `OUT_OF_SERVICE` when it
/// refuses it: the `readinessState` of the `readiness` group.
///
/// Spring Boot (Java): `ReadinessStateHealthIndicator`.
class ReadinessStateHealthIndicator
    extends AvailabilityStateHealthIndicator<ReadinessState> {
  /// The indicator of [availability]'s readiness.
  ReadinessStateHealthIndicator(ApplicationAvailability availability)
    : super(availability, ReadinessState.refusingTraffic, const {
        ReadinessState.acceptingTraffic: Status.up,
        ReadinessState.refusingTraffic: Status.outOfService,
      });
}
