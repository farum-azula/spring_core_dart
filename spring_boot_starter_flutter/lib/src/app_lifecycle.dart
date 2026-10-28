import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// An application event published each time the app's lifecycle state
/// changes: `resumed`, `inactive`, `hidden`, `paused` or `detached`.
///
/// It lets beans react to the app going to the background or coming back,
/// without a widget in between: save a draft, stop polling a server,
/// refresh data. Listen to it with `@EventListener()` in any bean;
/// `SpringApplicationWidget` publishes it (from Flutter's
/// `AppLifecycleListener`).
///
/// ```dart
/// // An unsent draft is saved when the user leaves the app.
/// @EventListener()
/// void onLifecycle(AppLifecycleStateEvent event) {
///   if (event.state == AppLifecycleState.paused) drafts.save();
/// }
/// ```
///
/// Besides publishing the event, `SpringApplicationWidget` pauses the
/// context when the app goes to the background (`hidden` or `paused`):
/// `@Scheduled` tasks, WebSocket connections and other pauseable
/// `SmartLifecycle` beans stop, then a `ContextPausedEvent` follows. When
/// the app is `resumed`, the context restarts (`ContextRestartedEvent`).
/// `spring.flutter.lifecycle.pause-in-background=false` keeps them
/// running.
///
/// Spring has no counterpart: a server has no foreground and background.
class AppLifecycleStateEvent extends ApplicationEvent {
  /// The app moved to [state]; [source] is the application context that
  /// publishes the event.
  AppLifecycleStateEvent(super.source, this.state);

  /// The state the app just entered.
  final AppLifecycleState state;

  @override
  String toString() => 'AppLifecycleStateEvent[$state]';
}
