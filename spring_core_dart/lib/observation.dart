/// Observations: an application measures its own work (a method, a
/// request, a load) and handlers turn the measurements into logs, metrics
/// or a timeline.
///
/// Import it (the package's main library exports it too) to observe code
/// through an `ObservationRegistry`, or mark methods `@Observed()` and
/// register an `ObservedAspect` bean. `ObservationRegistry.noop` records
/// nothing, so a library can observe its work at no cost until the
/// application gives it a registry with handlers.
///
/// ```dart
/// final registry = ObservationRegistry(handlers: [SlowCallLogger()]);
/// final orders = await registry.observe('orders.load', api.loadOrders);
/// ```
///
/// Spring (Java): Micrometer's Observation API
/// (`io.micrometer.observation`).
library;

export 'package:spring_core_dart/src/observation/observation.dart';
export 'package:spring_core_dart/src/observation/observation_handler.dart';
export 'package:spring_core_dart/src/observation/observed.dart';
