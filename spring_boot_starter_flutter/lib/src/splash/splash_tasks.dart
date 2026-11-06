import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_task.dart';

const _log = SpringLog('spring_boot_starter_flutter.SplashTasks');

/// Runs the [SplashTask] beans of a started context while the splash
/// shows (`spring.flutter.splash.tasks.*`), and gives the splash's loader
/// their progress.
final class SplashTasks {
  /// The tasks of [context], each given at most [timeout].
  SplashTasks(this.context, {required this.timeout, required this.share});

  /// The tasks of [context] as `spring.flutter.splash.tasks.*` sets them:
  /// `timeout` (default 5 s) and `share` of the loader (default 0.2).
  factory SplashTasks.of(ApplicationContext context) => SplashTasks(
    context,
    timeout:
        context.environment.getPropertyAs<Duration>(
          'spring.flutter.splash.tasks.timeout',
        ) ??
        const Duration(seconds: 5),
    share: shareIn(context.environment),
  );

  /// The share of the splash's loader the tasks take
  /// (`spring.flutter.splash.tasks.share`, default 0.2); 0 when
  /// `spring.flutter.splash.tasks.enabled` is `false`.
  static double shareIn(Environment environment) {
    if (!(environment.getPropertyAs<bool>(
          'spring.flutter.splash.tasks.enabled',
        ) ??
        true)) {
      return 0;
    }
    return (environment.getPropertyAs<double>(
              'spring.flutter.splash.tasks.share',
            ) ??
            0.2)
        .clamp(0, 1);
  }

  /// Whether [context] has tasks to run.
  static bool any(ApplicationContext context) =>
      shareIn(context.environment) > 0 &&
      context.getBeanNamesForType(SplashTask).isNotEmpty;

  /// The context whose tasks run.
  final ApplicationContext context;

  /// How long the splash waits for the tasks.
  final Duration timeout;

  /// The share of the splash's loader the tasks take, from 0 to 1; the
  /// start of the beans takes the rest.
  final double share;

  /// Runs every task at once; completes when all ended or [timeout] went
  /// by. [progress] gets the share done of all of them, from 0 to 1.
  Future<void> run(void Function(double fraction) progress) async {
    final tasks = context.getSortedBeans<SplashTask>();
    if (tasks.isEmpty) {
      progress(1);
      return;
    }
    final done = List<double>.filled(tasks.length, 0);
    void report(int i, double fraction) {
      if (fraction > done[i]) {
        done[i] = fraction;
        progress(done.fold(0.0, (a, b) => a + b) / tasks.length);
      }
    }

    final watch = Stopwatch()..start();
    final all = Future.wait([
      for (final (i, task) in tasks.indexed)
        _run(task, SplashTaskContext(context, (f) => report(i, f))).then(
          (_) => report(i, 1),
        ),
    ]);
    try {
      await all.timeout(timeout);
      _log.debug(() => 'Splash tasks done in ${watch.elapsedMilliseconds} ms');
    } on TimeoutException {
      _log.warning(
        () =>
            'Splash tasks still running after $timeout: '
            '${[
              for (final (i, task) in tasks.indexed)
                if (done[i] < 1) task.name,
            ].join(', ')}; the app is shown',
      );
    }
  }

  static Future<void> _run(SplashTask task, SplashTaskContext context) async {
    try {
      await task.run(context);
    } on Object catch (error, stackTrace) {
      _log.warning(
        () => 'Splash task ${task.name} failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
