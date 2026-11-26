import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_segment.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/debug_network_journal.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_format.dart';

/// `net`, the debug console's header segment of the network recorder
/// (`networkSegment`): the requests in flight, those that got no response
/// (`failed`: a transport error, a timeout, an abort), those answered with
/// a `4xx` or `5xx` (`errors`: a 403 is a response, not a failure), and the
/// last heartbeat round trip of the newest open WebSocket when one has one
/// (`net 2 in flight · 0 failed · 1 error · 45 ms ws`). A zero is muted, a
/// failure red, an error amber.
///
/// It listens to [journal] only while the console shows it, and the
/// journal tells it at most once a frame. In the build only with the
/// console, `spring.flutter.debug.console.segments` naming `net` (or `*`)
/// and `spring.flutter.debug.network.enabled: true`.
final class NetworkConsoleSegment extends DebugConsoleSegment {
  /// The segment of [journal].
  const NetworkConsoleSegment(this.journal);

  /// The traffic recorded.
  final DebugNetworkJournal journal;

  @override
  void Function() start(void Function() changed) {
    journal.addListener(changed);
    return () => journal.removeListener(changed);
  }

  @override
  DebugConsoleValue read() {
    final summary = journal.summary;
    final inFlight = summary.requestsInFlight;
    final failed = summary.failed;
    final errors = summary.errors;
    return DebugConsoleValue.of([
      DebugConsoleValue(
        '$inFlight',
        unit: 'in flight',
        tone: inFlight == 0 ? DebugConsoleTone.muted : DebugConsoleTone.number,
      ),
      DebugConsoleValue(
        '$failed',
        unit: 'failed',
        tone: failed == 0 ? DebugConsoleTone.muted : DebugConsoleTone.bad,
      ),
      DebugConsoleValue(
        '$errors',
        unit: errors == 1 ? 'error' : 'errors',
        tone: errors == 0 ? DebugConsoleTone.muted : DebugConsoleTone.warning,
      ),
      if (summary.lastSocketLatency case final latency?)
        DebugConsoleValue(
          NetworkFormat.duration(latency),
          unit: 'ws',
          tone: DebugConsoleTone.number,
        ),
    ], label: 'net');
  }
}
