import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/web_server.dart';
import 'package:spring_boot_starter_web/src/web_server_lifecycle.dart';

/// The requests of the web server in the row of its isolate: a source of
/// the task manager, added to what the isolate's sampler measures
/// (`active`: the requests in flight; `requests`: all it has taken;
/// `refused`: those answered 503 because the server was full).
final class WebServerLoadSource implements IsolateLoadSource {
  /// The load of the server [lifecycle] runs.
  const WebServerLoadSource(this.lifecycle);

  /// The server's lifecycle.
  final WebServerStartStopLifecycle lifecycle;

  @override
  List<IsolateLoad> loads() {
    final Object? server = lifecycle.webServer;
    if (server is! WebServerActivity) {
      return const [];
    }
    final isolate = IsolateInfo.current;
    return [
      IsolateLoad(
        name: isolate.name,
        kind: isolate.primary ? 'main' : 'server',
        active: server.activeRequests,
        details: {
          'requests': server.requestCount,
          if (server.refusedCount > 0) 'refused': server.refusedCount,
        },
      ),
    ];
  }
}
