import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/splash/performance_marks.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stages.dart';

/// The measured start (`spring.flutter.splash.trace`): an
/// [ApplicationStartup] that records each bean's creation, and the
/// splash's stages; on the web both are marks and measures of the
/// browser's performance timeline. [report] logs it all once the splash
/// is gone.
final class SplashTrace extends BufferingApplicationStartup {
  /// A trace of [stages].
  SplashTrace(this.stages) : super(onEnd: _measured) {
    stages.addListener(_stage);
    _stage();
  }

  static const _log = SpringLog('spring_boot_starter_flutter.SplashTrace');

  /// The stages traced.
  final SplashStages stages;

  final _marked = <SplashStage>{};

  @override
  StartupStep start(String name) {
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
    for (final stage in stages.reached.keys) {
      if (_marked.add(stage)) {
        performanceMark('spring:splash:${stage.name}');
      }
    }
    if (stages.value == SplashStage.app) {
      stages.removeListener(_stage);
      report();
    }
  }

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
