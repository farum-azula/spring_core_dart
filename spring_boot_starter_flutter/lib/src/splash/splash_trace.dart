import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/splash/performance_marks.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stages.dart';

/// The measured start, the app's [ApplicationStartup]: always the
/// splash's stages (a step `spring.flutter.splash.<stage>` each, from the
/// stage to the next) and the steps of the start (`spring.boot.*`, the
/// context's refresh), and the application events once the context
/// publishes them (`spring.event`, tagged `type`); each bean's creation
/// (`spring.beans.instantiate`) only with [beans]
/// (`spring.flutter.splash.trace`, or the debug timeline in the build). On
/// the web the steps are marks and measures of the browser's performance
/// timeline too. With [log], [report] logs it all once the splash is gone.
///
/// Read [steps] from the `splashTrace` bean.
final class SplashTrace extends BufferingApplicationStartup {
  /// A trace of [stages], timed by their clock.
  SplashTrace(this.stages, {this.beans = true, this.log = true})
    : super(onEnd: _measured, clock: () => stages.now) {
    stages.addListener(_stage);
    _stage();
  }

  /// The name of a stage's step.
  static String stepOf(SplashStage stage) =>
      'spring.flutter.splash.${stage.name}';

  /// The name of an application event's step.
  static const event = 'spring.event';

  /// Whether each bean's creation is a step.
  final bool beans;

  /// Whether [report] logs once the splash is gone.
  final bool log;

  static const _log = SpringLog('spring_boot_starter_flutter.SplashTrace');

  /// The stages traced.
  final SplashStages stages;

  final _marked = <SplashStage>{};

  @override
  StartupStep start(String name) {
    if (!beans && name == 'spring.beans.instantiate') {
      return ApplicationStartup.none.start(name);
    }
    final step = super.start(name);
    performanceMark('spring:${step.id}');
    return step;
  }

  static void _measured(RecordedStartupStep step) {
    final bean = [
      for (final (key, value) in step.tags)
        if (key == 'beanName') value,
    ].firstOrNull;
    performanceMeasure(
      bean == null ? step.name : '${step.name} $bean',
      'spring:${step.id}',
    );
  }

  void _stage() {
    final reached = stages.reached.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final (i, MapEntry(key: stage, value: at)) in reached.indexed) {
      final next = i + 1 < reached.length ? reached[i + 1].value : null;
      // A stage is a step once the next is reached (its length known); the
      // last, the app, at once.
      if ((next != null || stage == SplashStage.app) && _marked.add(stage)) {
        performanceMark('spring:splash:${stage.name}');
        record(
          stepOf(stage),
          startedAt: at,
          duration: next == null ? Duration.zero : next - at,
        );
      }
    }
    if (stages.value == SplashStage.app) {
      stages.removeListener(_stage);
      if (log) {
        report();
      }
    }
  }

  /// Records [event], published now, as a step of no length.
  void recordEvent(Object event) => record(
    SplashTrace.event,
    startedAt: stages.now,
    tags: [('type', '${event.runtimeType}')],
  );

  /// Logs the stages and the slowest beans.
  void report() {
    final reached = stages.reached;
    final beans = [
      for (final step in steps)
        if (step.name == 'spring.beans.instantiate' && step.duration != null)
          step,
    ]..sort((a, b) => b.duration!.compareTo(a.duration!));
    _log.info(
      () => [
        'The start: ${[for (final MapEntry(:key, :value) in reached.entries) '${key.name} ${value.inMilliseconds} ms'].join(', ')}',
        '${beans.length} beans; the slowest: ${beans.take(5).join(', ')}',
      ].join('. '),
    );
  }
}
