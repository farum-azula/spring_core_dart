import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugConsoleTone, DebugConsoleValue, SampledDebugConsoleSegment;
import 'package:spring_boot_starter_flutter_signals/src/debug/signals_debug_recorder.dart';

/// The debug console's `signals` segment: the ticks (readers told),
/// flushes and effect runs of the last frame
/// (`signals 3 ticks · 1 flush · 2 effects`), a zero muted, read
/// four times a second while the console shows; the recorder collects only
/// then.
final class SignalsSegment extends SampledDebugConsoleSegment {
  /// The segment of [recorder].
  const SignalsSegment(this.recorder);

  /// What it shows.
  final SignalsDebugRecorder recorder;

  @override
  void Function() open() => recorder.use();

  @override
  DebugConsoleValue read() {
    // Sampled while the console shows: what ended is forgotten here too.
    recorder.pruneEnded();
    final last = recorder.lastFrame;
    return DebugConsoleValue.of([
      _count(last.ticks, 'tick', 'ticks'),
      _count(last.flushes, 'flush', 'flushes'),
      _count(last.effects, 'effect', 'effects'),
    ], label: 'signals');
  }

  static DebugConsoleValue _count(int count, String one, String many) =>
      DebugConsoleValue(
        '$count',
        unit: count == 1 ? one : many,
        tone: count == 0 ? DebugConsoleTone.muted : DebugConsoleTone.number,
      );
}
