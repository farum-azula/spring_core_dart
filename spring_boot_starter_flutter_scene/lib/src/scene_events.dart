import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A step of the scenes' start or of a later load, published as an
/// application event (heard with `@EventListener`) and told in words: an
/// event is a [MessageSourceResolvable], so
/// `context.getMessageFromResolvable(event)` is its text in the app's
/// language. An app rewords a step by its code in `messages.properties`
/// (`scene.loading.model=Loading {0}, {1} of {2}`); without one the text
/// is the English [defaultMessage].
///
/// Spring has no counterpart.
sealed class SceneEvent extends ApplicationEvent
    implements MessageSourceResolvable {
  /// A step raised by [source].
  SceneEvent(super.source);

  /// The message code of the step.
  String get code;

  @override
  List<String> get codes => [code];

  @override
  List<Object?> get arguments => const [];
}

/// The engine starts: its shaders are compiled, its lookup tables loaded.
final class SceneEngineStartingEvent extends SceneEvent {
  /// The start of [backend], raised by [source].
  SceneEngineStartingEvent(super.source, {required this.backend});

  /// The engine's name.
  final String backend;

  @override
  String get eventName => 'SceneEngineStarting';

  @override
  String get code => 'scene.loading.engine';

  @override
  String get defaultMessage => 'Compiling shaders';
}

/// The engine started.
final class SceneEngineReadyEvent extends SceneEvent {
  /// [backend] started in [took], raised by [source].
  SceneEngineReadyEvent(
    super.source, {
    required this.backend,
    required this.took,
  });

  /// The engine's name.
  final String backend;

  /// How long the start took.
  final Duration took;

  @override
  String get eventName => 'SceneEngineReady';

  @override
  String get code => 'scene.ready.engine';

  @override
  String get defaultMessage => 'The 3D engine is ready';
}

/// A model is being loaded.
final class SceneModelLoadingEvent extends SceneEvent {
  /// The load of model [name] from [location], the [index]th of [count]
  /// loaded together (both 1 for a model loaded alone).
  SceneModelLoadingEvent(
    super.source, {
    required this.name,
    required this.location,
    this.index = 1,
    this.count = 1,
  });

  /// The model's name (`spring.flutter.scene.models.<name>`).
  final String name;

  /// Where it is loaded from.
  final String location;

  /// Its place among the models loaded together, from 1.
  final int index;

  /// How many are loaded together.
  final int count;

  @override
  String get eventName => 'SceneModelLoading';

  @override
  String get code => 'scene.loading.model';

  @override
  List<Object?> get arguments => [name, index, count];

  @override
  String get defaultMessage => 'Loading {0}, {1} of {2}';
}

/// A model is loaded.
final class SceneModelLoadedEvent extends SceneEvent {
  /// Model [name] of [bytes] loaded in [took].
  SceneModelLoadedEvent(
    super.source, {
    required this.name,
    required this.took,
    required this.bytes,
  });

  /// The model's name.
  final String name;

  /// How long it took: the download and the import.
  final Duration took;

  /// The size of its file.
  final int bytes;

  @override
  String get eventName => 'SceneModelLoaded';

  @override
  String get code => 'scene.ready.model';

  @override
  List<Object?> get arguments => [name];

  @override
  String get defaultMessage => '{0} is loaded';
}

/// Everything asked for with the splash is ready: the engine, the eager
/// models, the application's scene.
final class SceneReadyEvent extends SceneEvent {
  /// The scenes ready in [took].
  SceneReadyEvent(super.source, {required this.took});

  /// How long it all took.
  final Duration took;

  @override
  String get eventName => 'SceneReady';

  @override
  String get code => 'scene.ready';

  @override
  String get defaultMessage => 'The scenes are ready';
}

/// A step failed. The app goes on: what failed shows its placeholder.
final class SceneFailedEvent extends SceneEvent {
  /// The failure of [step] (of model [name], when it is one) with [error].
  SceneFailedEvent(
    super.source, {
    required this.step,
    required this.error,
    this.name,
  });

  /// What failed.
  final SceneStep step;

  /// The model's name, for [SceneStep.model].
  final String? name;

  /// What was thrown.
  final Object error;

  @override
  String get eventName => 'SceneFailed';

  @override
  String get code => 'scene.failed.${step.name}';

  @override
  List<Object?> get arguments => [name ?? step.name];

  @override
  String get defaultMessage => switch (step) {
    SceneStep.engine => 'The 3D engine did not start',
    SceneStep.model => '{0} did not load',
    SceneStep.application => "The application's scene was not made",
  };
}

/// Scenes do not draw here, said once: the widgets show their
/// placeholders.
final class SceneUnavailableEvent extends SceneEvent {
  /// Scenes that do not draw for [reason].
  SceneUnavailableEvent(super.source, {required this.reason});

  /// Why.
  final SceneUnavailable reason;

  @override
  String get eventName => 'SceneUnavailable';

  @override
  String get code => 'scene.unavailable.${reason.name}';

  @override
  String get defaultMessage => switch (reason) {
    SceneUnavailable.off => 'Scenes are turned off',
    SceneUnavailable.engine => 'Scenes cannot be drawn on this device',
  };
}

/// A step of the scenes' start, in a [SceneFailedEvent].
enum SceneStep {
  /// The start of the engine.
  engine,

  /// The load of a model.
  model,

  /// The making of the application's scene.
  application,
}

/// Why scenes do not draw.
enum SceneUnavailable {
  /// `spring.flutter.scene.render` is `off`.
  off,

  /// The engine did not start: no WebGL2 in the browser, no Flutter GPU on
  /// the device.
  engine,
}
