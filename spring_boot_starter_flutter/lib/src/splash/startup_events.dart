import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage_event.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_trace.dart';

/// Records each application event the context publishes into the
/// [SplashTrace] (`spring.event`, tagged `type`): from the context's
/// refresh on, the app's own events too. The stages are recorded by the
/// trace itself, so a `SplashStageEvent` is not.
///
/// Spring has no counterpart.
final class StartupEvents implements GenericApplicationListener {
  /// The recorder into [trace]; nothing without one (an app started
  /// without the `SpringApplicationWidget`).
  const StartupEvents(this.trace);

  /// Where the events go.
  final SplashTrace? trace;

  @override
  bool supportsEvent(Object event) =>
      trace != null && event is ApplicationEvent && event is! SplashStageEvent;

  @override
  void onApplicationEvent(Object event) =>
      trace?.recordEvent((event as ApplicationEvent).eventName);
}
