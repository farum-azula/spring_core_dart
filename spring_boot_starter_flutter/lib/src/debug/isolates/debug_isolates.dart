import 'package:spring_boot_dart/spring_boot_dart.dart' show IsolateLoads;
import 'package:spring_boot_starter_flutter/src/debug/isolates/isolate_loads_watch.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_watch.dart';

/// The task manager of the app's isolates and the engine's threads (the
/// `debugIsolates` bean): the rows of `isolateLoads`, how busy each is and
/// how late it answers, and the app's [memory], shown by the debug panel's
/// Isolates tab and the debug console's `isolates` and `memory` segments.
///
/// The [rows] and the [memory] are read only while a widget shows them,
/// so the isolates, the engine and the memory are measured only then.
final class DebugIsolates {
  /// The task manager of [loads] and [memory] (by default the platform's
  /// and the image cache's), read every [interval] while something shows
  /// them.
  DebugIsolates({
    required IsolateLoads loads,
    Duration interval = const Duration(seconds: 1),
    DebugMemoryWatch? memory,
  }) : rows = IsolateLoadsWatch(loads, interval: interval),
       memory = memory ?? DebugMemoryWatch(interval: interval);

  /// The rows, read while a widget listens.
  final IsolateLoadsWatch rows;

  /// The memory, read while a widget or the `memory` segment listens.
  final DebugMemoryWatch memory;

  /// Stops reading.
  void dispose() {
    rows.dispose();
    memory.dispose();
  }
}
