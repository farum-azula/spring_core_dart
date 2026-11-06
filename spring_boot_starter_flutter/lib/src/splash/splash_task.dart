import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Work done while the splash shows, once the beans exist and before the
/// app is shown: the stage `tasks` of the start. Declare a bean of this
/// type; every one runs, at the same time as the others, and the splash's
/// loader follows their progress.
///
/// ```dart
/// @Component()
/// class WarmCache implements SplashTask {
///   WarmCache(this.repository);
///
///   final ArticleRepository repository;
///
///   @override
///   String get name => 'articles';
///
///   @override
///   Future<void> run(SplashTaskContext task) async {
///     final ids = await repository.latest();
///     for (final (i, id) in ids.indexed) {
///       await repository.load(id);
///       task.progress((i + 1) / ids.length);
///     }
///   }
/// }
/// ```
///
/// A task that fails is logged and the start goes on; one still running
/// after `spring.flutter.splash.tasks.timeout` goes on behind the app.
/// The order of the start (`@Order`, `Ordered`) is the order they begin.
abstract class SplashTask {
  /// What the task does, in the log.
  String get name => '$runtimeType';

  /// Does the work; reports its share done to [task].
  Future<void> run(SplashTaskContext task);
}

/// What a [SplashTask] gets while it runs.
final class SplashTaskContext {
  /// The context of [applicationContext]; [progress] takes the share done.
  SplashTaskContext(this.applicationContext, this._progress);

  /// The started application.
  final ApplicationContext applicationContext;

  final void Function(double fraction) _progress;

  /// The task's share done, from 0 to 1. Reporting is optional: a task
  /// that does not report counts as done when it ends.
  void progress(double fraction) => _progress(fraction.clamp(0, 1));
}
