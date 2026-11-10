import 'package:spring_boot_actuator/src/endpoint/annotations.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The `isolates` endpoint: the application's isolates and how busy each
/// is, the task manager as JSON.
///
/// `GET /actuator/isolates` asks the application's first isolate, which
/// asks the isolates of the server's pool for their numbers, and answers
/// every row [IsolateLoads] has there, whichever isolate took the
/// request (`isolate` names it): the
/// application's first isolate (`main`, with the process's memory), the
/// isolates of the web server's pool (`isolate-1`, …), those of the task
/// executor (`task-1`, …) while they exist, and what the application
/// tracks itself. Times are in microseconds; `busy` is a share from 0 to
/// 1; a number a source cannot measure is left out.
///
/// Measuring starts with the first request (the first answer has no
/// `busy` and no lag yet) and stops by itself when nobody asks.
///
/// It is not exposed by default:
/// `management.endpoints.web.exposure.include=health,isolates`.
///
/// ```json
/// {"isolate": "main",
///  "isolates": [
///   {"name": "main", "kind": "main", "busy": 0.02, "lagMicros": 180,
///    "maxLagMicros": 2100, "active": 3, "memory": 96468992,
///    "details": {"requests": 18250}},
///   {"name": "isolate-1", "kind": "server", "busy": 0.03, "lagMicros": 210,
///    "maxLagMicros": 1900, "active": 2, "details": {"requests": 18102}}]}
/// ```
///
/// Spring has no counterpart; nearest is the `threaddump` endpoint.
@Endpoint(id: 'isolates')
class IsolatesEndpoint {
  /// The endpoint, asking the first isolate through [primary].
  IsolatesEndpoint(this.primary);

  /// Asks the application's first isolate, which knows every isolate.
  final PrimaryIsolate primary;

  /// Every isolate with its load, and the isolate that answers.
  @ReadOperation()
  Future<Map<String, Object?>> isolates() async => {
    'isolate': IsolateInfo.current.name,
    'isolates': await primary.ask(IsolateLoadsHandler.handlerId),
  };
}
