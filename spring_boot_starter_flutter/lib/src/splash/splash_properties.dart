import 'package:spring_boot_dart/spring_boot_dart.dart';

/// How the start behaves while the splash shows: `spring.flutter.splash.*`
/// (the splash's look is the theme's `splash`).
@ConfigurationProperties('spring.flutter.splash')
class SplashProperties {
  /// Lets Flutter draw a frame while the beans are created, so the splash
  /// keeps moving: after [frameBudget] of work the start waits for the next
  /// frame. On by default on the web, off elsewhere; `false` turns it off
  /// (no pacer at all).
  bool? yieldFrames;

  /// The work between two frames when [yieldFrames] is on.
  Duration frameBudget = const Duration(milliseconds: 8);

  /// Measures the start: each stage of the splash and each bean's creation
  /// with its time, in the log at the end; on the web also as marks of the
  /// browser's performance timeline (the Performance tab). Off by default.
  bool trace = false;
}
