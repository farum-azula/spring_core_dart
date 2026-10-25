import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Published when the app's lifecycle state changes
/// (`AppLifecycleListener`): `resumed`, `inactive`, `hidden`, `paused`,
/// `detached`.
///
/// ```dart
/// @EventListener()
/// void onLifecycle(AppLifecycleStateEvent event) {
///   if (event.state == AppLifecycleState.paused) drafts.save();
/// }
/// ```
///
/// Next to it `SpringApplicationWidget` pauses the context when the app goes to the
/// background (`hidden` or `paused`: `@Scheduled` tasks, WebSocket
/// connections and other pauseable `SmartLifecycle` beans stop, then
/// `ContextPausedEvent`) and restarts it when the app is `resumed` again
/// (`ContextRestartedEvent`); `spring.flutter.lifecycle.pause-in-background=false`
/// keeps them running.
class AppLifecycleStateEvent extends ApplicationEvent {
  /// The app moved to [state]; [source] is the application context.
  AppLifecycleStateEvent(super.source, this.state);

  /// The new state.
  final AppLifecycleState state;

  @override
  String toString() => 'AppLifecycleStateEvent[$state]';
}
