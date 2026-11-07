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

/// The tasks run while the splash shows: `spring.flutter.splash.tasks.*`
/// (`SplashTask` beans).
@ConfigurationProperties('spring.flutter.splash.tasks')
class SplashTasksProperties {
  /// Runs the `SplashTask` beans before the app is shown; `false`: none
  /// runs, the beans take the whole loader.
  bool enabled = true;

  /// How long the splash waits for the tasks; one still running goes on
  /// behind the app.
  Duration timeout = const Duration(seconds: 5);

  /// The share of the splash's loader the tasks take, from 0 to 1, when
  /// the app has any.
  double share = 0.2;
}

/// The fonts of the app's text downloaded while the splash shows:
/// `spring.flutter.splash.warm-up.text.*` (`TextWarmUp`).
@ConfigurationProperties('spring.flutter.splash.warm-up.text')
class TextWarmUpProperties {
  /// Lays out the characters of the app's text while the splash shows. Off
  /// by default; worth it on the web, where the fonts for Japanese, Chinese
  /// or emoji are downloaded.
  bool enabled = false;

  /// The files whose characters are laid out (location patterns).
  List<String> resources = ['resources:messages*.properties'];

  /// No font downloaded in that time: none is needed.
  Duration firstFont = const Duration(milliseconds: 400);

  /// After a font came in, how long without another before the warm-up
  /// ends.
  Duration settle = const Duration(milliseconds: 250);

  /// How many characters are laid out in one frame, so the splash keeps
  /// moving on a phone.
  int chunk = 200;
}
