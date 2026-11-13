import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_scene/src/scene_events.dart';

/// What the scenes are doing now, for a loader that says it in words: the
/// last step published ([SceneEvent]) while something is being loaded,
/// `null` when nothing is.
///
/// ```dart
/// // In a loader: "Compiling shaders", "Loading hero, 2 of 5".
/// ValueListenableBuilder(
///   valueListenable: status,
///   builder: (context, step, _) => Text(status.text ?? ''),
/// )
/// ```
///
/// The words come from the app's messages (`scene.loading.engine`,
/// `scene.loading.model`), else the steps' own English.
final class SceneStatus extends ValueNotifier<SceneEvent?>
    implements GenericApplicationListener {
  /// The status, worded by [messages].
  SceneStatus(this.messages) : super(null);

  /// Where the steps' texts are looked up.
  final MessageSource messages;

  /// Every step heard so far, oldest first: the debug panel's list.
  final List<SceneEvent> history = [];

  int _loading = 0;

  /// The current step in words, `null` when nothing is being loaded.
  String? get text => switch (value) {
    final step? => messages.getMessageFromResolvable(step),
    null => null,
  };

  @override
  bool supportsEvent(Object event) => event is SceneEvent;

  @override
  void onApplicationEvent(Object event) {
    final step = event as SceneEvent;
    history.add(step);
    switch (step) {
      case SceneEngineStartingEvent() || SceneModelLoadingEvent():
        _loading++;
        value = step;
      case SceneEngineReadyEvent() || SceneModelLoadedEvent():
        _ended();
      case SceneFailedEvent(step: SceneStep.engine || SceneStep.model):
        _ended();
      case SceneFailedEvent() || SceneReadyEvent() || SceneUnavailableEvent():
        break;
    }
  }

  void _ended() {
    if (_loading > 0) {
      _loading--;
    }
    if (_loading == 0) {
      value = null;
    }
  }
}
