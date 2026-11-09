import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';

/// The start reached [stage], [at] its time from the start (on the web,
/// from the page's first moment). Listen with `@EventListener`:
///
/// ```dart
/// @Component()
/// class StartTimes {
///   @EventListener()
///   void stage(SplashStageEvent event) =>
///       _log.info('${event.stage.name} at ${event.at.inMilliseconds} ms');
/// }
/// ```
///
/// The stages before the context is ready ([SplashStage.page] to
/// [SplashStage.starting]) are delivered, in order, once it is: the
/// listeners are beans, which do not exist earlier. Spring (Java) does
/// the same with the events published before its multicaster exists.
final class SplashStageEvent extends ApplicationEvent {
  /// [stage] reached [at], published by [source] (the `SplashStages`).
  SplashStageEvent(super.source, {required this.stage, required this.at});

  /// The stage reached.
  final SplashStage stage;

  /// When, from the start.
  final Duration at;

  @override
  String toString() => 'SplashStageEvent[${stage.name} at $at]';

  @override
  String get eventName => 'SplashStageEvent';
}
