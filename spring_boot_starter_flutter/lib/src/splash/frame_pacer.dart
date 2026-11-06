import 'package:flutter/scheduler.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Lets Flutter draw a frame while the beans are created: once the work
/// since the last frame has taken [budget], the start waits for the next
/// frame (`spring.flutter.splash.yield-frames`). The splash moves on while
/// the start goes on; the start takes the frames' time longer.
///
/// A bean that takes longer than [budget] by itself (a long constructor
/// or `@PostConstruct`) is not cut: the splash stops for its time.
final class FramePacer implements StartupPacer {
  /// A pacer that waits for a frame after [budget] of work.
  FramePacer({this.budget = const Duration(milliseconds: 8)});

  /// The work between two frames: half a frame at 60 frames a second.
  final Duration budget;

  final _watch = Stopwatch()..start();

  @override
  Future<void>? pace() {
    if (_watch.elapsed < budget) {
      return null;
    }
    final binding = SchedulerBinding.instance;
    binding.scheduleFrame();
    return binding.endOfFrame.whenComplete(_watch.reset);
  }
}
