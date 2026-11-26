import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_segment.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/debug_isolates.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/isolates_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_figure.dart';

/// `memory`, the debug console's header segment of the app's memory
/// (`memorySegment`): every figure with a short label, the process's
/// resident memory natively and the JavaScript heap on the web (`mem`),
/// and Flutter's image cache (`img`): `mem 182 MB · img 34 MB`.
///
/// It listens to the task manager's memory only while the console shows
/// it, so the memory is read only then. In the build only with the
/// console, `spring.flutter.debug.console.segments` naming `memory` (or
/// `*`) and the task manager (`spring.flutter.debug.isolates.enabled`).
final class MemoryConsoleSegment extends DebugConsoleSegment {
  /// The segment of [isolates]' memory.
  const MemoryConsoleSegment(this.isolates);

  /// The task manager.
  final DebugIsolates isolates;

  @override
  void Function() start(void Function() changed) {
    final memory = isolates.memory..addListener(changed);
    return () => memory.removeListener(changed);
  }

  @override
  DebugConsoleValue? read() {
    final parts = [
      for (final figure
          in isolates.memory.value?.figures ?? const <MemoryFigure>[])
        if ((figure.short, figure.used) case (final short?, final used?))
          _part(short, used),
    ];
    return parts.isEmpty ? null : DebugConsoleValue.of(parts);
  }

  static DebugConsoleValue _part(String label, int bytes) {
    final (number, unit) = formatIsolateMemoryParts(bytes);
    return DebugConsoleValue(number, label: label, unit: unit);
  }
}
