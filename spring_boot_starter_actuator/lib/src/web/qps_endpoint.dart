import 'package:spring_boot_actuator/spring_boot_actuator.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// The `qps` endpoint: requests per second, of every isolate and in
/// total, as the debug feature `qps` last worked them out. There only
/// with `spring.web.debug.qps.enabled: true` (the build then has the
/// code that counts), and exposed like any endpoint:
/// `management.endpoints.web.exposure.include=health,qps`.
///
/// `GET /actuator/qps` answers the last window
/// (`spring.web.debug.qps.log-interval` long), empty before the first
/// has passed; `GET /actuator/qps/now` ends the window now and answers
/// it, for a load test that reads after each step.
///
/// ```json
/// {"seconds": 10.0, "qps": 1250.4, "requests": 12504, "errors": 0,
///  "active": 14, "p50Micros": 1139, "p95Micros": 5767, "p99Micros": 8650,
///  "isolates": {"main": {"qps": 412.0, ...}, "isolate-1": {...}}}
/// ```
///
/// Spring Boot's counterpart is the `metrics` endpoint
/// (`http.server.requests`).
@Endpoint(id: 'qps')
class QpsEndpoint {
  /// The endpoint, asking the first isolate's `RequestRates` through
  /// [primary].
  QpsEndpoint(this.primary);

  /// Asks the application's first isolate, where the rates are worked
  /// out; so every isolate of a pool answers the same.
  final PrimaryIsolate primary;

  /// The last window; empty before the first has passed.
  @ReadOperation()
  Future<Map<String, Object?>> qps() async => _json(
    await primary.ask(RequestRates.handlerId),
  );

  /// With `now` as [window]: ends the window at this moment and answers
  /// it; anything else is unknown.
  @ReadOperation()
  Future<Map<String, Object?>?> window(@Selector() String window) async =>
      window == 'now'
      ? _json(await primary.ask(RequestRates.handlerId, 'now'))
      : null;

  static Map<String, Object?> _json(Object? answer) => {
    for (final MapEntry(:key, :value)
        in (answer as Map<Object?, Object?>? ?? const {}).entries)
      '$key': value,
  };
}
