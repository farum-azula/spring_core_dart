import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show SpringScope;
import 'package:spring_boot_starter_flutter_scene/src/app/application_scene.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_availability.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/on_screen.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_clock.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_view_observer.dart';

/// A 3D scene among the app's widgets: the engine's `SceneView` with the
/// app's properties applied, and a plain widget where scenes do not draw.
///
/// ```dart
/// // A scene of its own, declared in place.
/// SpringSceneView.declarative(
///   name: 'showroom',
///   placeholder: const ColoredBox(color: Color(0xFF101418)),
///   children: [SpringSceneModel('hero')],
/// )
///
/// // The application's scene (spring.flutter.scene.app.enabled).
/// const SpringSceneView()
/// ```
///
/// What the starter does around the engine's view:
///
/// - **A proxy where scenes do not draw.** With
///   `spring.flutter.scene.enabled: false`, `render: off`, no WebGL2 in the
///   browser or a failed start of the engine it builds [placeholder] and
///   nothing of the engine. The app's code has no branch for it.
/// - **The engine's start.** The first view that shows starts the engine
///   (unless the splash already did) and shows [placeholder] meanwhile.
/// - **A ceiling on frames.** It draws at most
///   `spring.flutter.scene.max-frame-rate` frames a second, or
///   [maxFrameRate] when that is fewer.
/// - **A still frame.** With `render: still`, or when the system asks for
///   less motion, it draws one frame and draws again only when what it
///   shows changes.
/// - **A pause off the screen** (`pause-off-screen`): scrolled away, it
///   stops drawing.
/// - **A whole scene or none.** The scene shows once its models are
///   loaded and the engine was asked to compile its materials' programs
///   ([warmUp]), with [placeholder] until then: a half-built scene is
///   never drawn.
///
/// A still frame is drawn again when the view is rebuilt. A scene widget
/// that changes what is drawn without a rebuild (a load that ended, a
/// value set on a material) asks for a frame with [repaintOf].
///
/// The scene widgets in [children] are the engine's (`SceneNode`,
/// `SceneMesh`, `SceneModel`, ...) and the starter's (`SpringSceneModel`).
class SpringSceneView extends StatefulWidget {
  /// A view of the application's scene (the `applicationScene` bean of
  /// `spring.flutter.scene.app.enabled`), seen through [camera] or the
  /// camera of the properties. [children] are added to it while this view
  /// shows. Without such a scene it is [placeholder].
  const SpringSceneView({
    super.key,
    this.name = 'application',
    this.placeholder,
    this.camera,
    this.cameraBuilder,
    this.maxFrameRate,
    this.pixelRatio,
    this.onTick,
    this.loading,
    this.warmUp = true,
    this.children = const [],
  }) : _declarative = false,
       environment = null,
       environmentIntensity = 1.0,
       exposure = 1.0,
       toneMapping = null;

  /// A view that owns its scene, described by [children] and freed with
  /// the widget.
  const SpringSceneView.declarative({
    super.key,
    this.name = 'scene',
    this.placeholder,
    this.environment,
    this.environmentIntensity = 1.0,
    this.exposure = 1.0,
    ToneMappingMode this.toneMapping = ToneMappingMode.pbrNeutral,
    this.camera,
    this.cameraBuilder,
    this.maxFrameRate,
    this.pixelRatio,
    this.onTick,
    this.loading,
    this.warmUp = true,
    this.children = const [],
  }) : _declarative = true;

  final bool _declarative;

  /// What the view is called in the scenes' debug panel.
  final String name;

  /// What stands in until the scene draws, and for good where it cannot.
  /// Nothing by default.
  final Widget? placeholder;

  /// The image the scene is lit by; the engine's default when `null`.
  final EnvironmentMap? environment;

  /// How strongly [environment] lights the scene.
  final double environmentIntensity;

  /// The scene's exposure.
  final double exposure;

  /// How bright colours are brought to the screen's range.
  final ToneMappingMode? toneMapping;

  /// The camera; at most one of [camera] and [cameraBuilder].
  final Camera? camera;

  /// The camera for each frame, by the time the scene has run.
  final SceneCameraBuilder? cameraBuilder;

  /// The most frames a second this view draws, under the properties'
  /// `max-frame-rate`.
  final double? maxFrameRate;

  /// The view's own pixel ratio; the properties' `pixel-ratio` when
  /// `null`.
  final double? pixelRatio;

  /// Called for each frame the view draws, with the time since the last.
  final SceneTickCallback? onTick;

  /// Loads the view waits for before it shows, beside those of its own
  /// scene widgets (a `SpringSceneModel` is waited for without it).
  final ResourceGroup? loading;

  /// Whether the engine is asked to compile the programs of the scene's
  /// materials before its first frame (a program built in a frame holds
  /// the page for tens of milliseconds).
  final bool warmUp;

  /// The scene widgets.
  final List<Widget> children;

  /// Whether the system asks for less motion: scenes stand still then.
  static bool reducedMotionOf(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Asks the view above [context] for one more frame: for a scene widget
  /// that changed what is drawn without a rebuild, so a still frame shows
  /// it. Does nothing in a view that moves anyway, or without a view.
  static void repaintOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SceneRepaint>()?.repaint();

  @override
  State<SpringSceneView> createState() => _SpringSceneViewState();
}

class _SpringSceneViewState extends State<SpringSceneView> {
  SceneAvailability? _availability;
  ApplicationScene? _application;
  SceneViewObserver? _observer;
  SceneViewMeasure? _measure;
  SceneViewState? _state;
  // The view is gated on its loads even when the app gives none: the
  // engine then waits for the models of its scene widgets too.
  final ResourceGroup _loads = ResourceGroup();
  final SceneClock _clock = SceneClock();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final beans = SpringScope.maybeOf(context);
    final availability = beans
        ?.getBeanProvider<SceneAvailability>()
        .getIfAvailable();
    if (!identical(availability, _availability)) {
      _availability?.removeListener(_changed);
      _availability = availability?..addListener(_changed);
    }
    final application = widget._declarative
        ? null
        : beans?.getBeanProvider<ApplicationScene>().getIfAvailable();
    if (!identical(application, _application)) {
      _application?.removeListener(_changed);
      _application = application?..addListener(_changed);
    }
    _observer = beans?.getBeanProvider<SceneViewObserver>().getIfAvailable();
    _start();
  }

  @override
  void dispose() {
    _availability?.removeListener(_changed);
    _application?.removeListener(_changed);
    _measure?.closed();
    _loads.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  /// The first view that shows starts the engine, and the application's
  /// scene when it shows that.
  void _start() {
    final availability = _availability;
    if (availability == null || !availability.draws) {
      return;
    }
    if (_application case final application?) {
      application.create().ignore();
    } else {
      availability.engine.start().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;
    final scene = _application?.scene;
    final shows =
        availability != null &&
        availability.isReady &&
        (widget._declarative || scene != null);
    if (!shows) {
      _close();
      return widget.placeholder ?? const SizedBox.shrink();
    }
    return OnScreen(
      enabled: availability.properties.pauseOffScreen,
      builder: (context, onScreen) =>
          _view(context, availability, scene, onScreen: onScreen),
    );
  }

  Widget _view(
    BuildContext context,
    SceneAvailability availability,
    Scene? scene, {
    required bool onScreen,
  }) {
    final paused = _paused(context, availability, onScreen: onScreen);
    final frameRate = availability.frameRate(widget.maxFrameRate);
    final pixelRatio = widget.pixelRatio ?? availability.properties.pixelRatio;
    _observe(
      SceneViewState(
        scene: scene ?? _state?.scene,
        animated: paused == null,
        frameRate: frameRate,
        pixelRatio: pixelRatio,
        paused: paused,
      ),
    );
    final camera =
        widget.camera ??
        (widget.cameraBuilder == null ? _application?.camera : null);
    final view = widget._declarative
        ? SceneView.declarative(
            environment: widget.environment,
            environmentIntensity: widget.environmentIntensity,
            exposure: widget.exposure,
            toneMapping: widget.toneMapping!,
            camera: camera,
            cameraBuilder: widget.cameraBuilder,
            autoTick: availability.animates,
            clock: _clock.clock,
            maxFrameRate: frameRate,
            pixelRatio: pixelRatio,
            onTick: _tick,
            loading: widget.loading ?? _loads,
            loadingBuilder: _loading,
            warmUp: widget.warmUp,
            children: [_SceneProbe(_found), ...widget.children],
          )
        : SceneView(
            scene!,
            camera: camera,
            cameraBuilder: widget.cameraBuilder,
            autoTick: availability.animates,
            clock: _clock.clock,
            maxFrameRate: frameRate,
            pixelRatio: pixelRatio,
            onTick: _tick,
            loading: widget.loading ?? _loads,
            loadingBuilder: _loading,
            warmUp: widget.warmUp,
            children: widget.children,
          );
    // A pause mutes the view's ticker and stops its clock. The view's own
    // `autoTick` is never changed after it is made: the engine's view
    // makes a second ticker when it goes back on, which Flutter refuses
    // (flutter_scene 0.24.3).
    _clock.paused = paused != null;
    // A scene's frame is its own layer: the widgets around it are not
    // painted again for it.
    return _SceneRepaint(
      repaint: _repaint,
      child: TickerMode(
        enabled: paused == null,
        child: RepaintBoundary(child: view),
      ),
    );
  }

  Widget _loading(BuildContext context, double progress) =>
      widget.placeholder ?? const SizedBox.shrink();

  /// A rebuild gives the engine's view a new widget, which it paints.
  void _repaint() {
    if (mounted && !(_state?.animated ?? true)) {
      setState(() {});
    }
  }

  /// Why the view stands still, `null` when it moves.
  String? _paused(
    BuildContext context,
    SceneAvailability availability, {
    required bool onScreen,
  }) {
    if (!availability.animates) {
      return 'still';
    }
    if (SpringSceneView.reducedMotionOf(context)) {
      return 'motion';
    }
    if (!onScreen) {
      return 'off-screen';
    }
    return null;
  }

  /// The scene a declarative view made for itself, for the observer.
  void _found(Scene scene) {
    final state = _state;
    if (state != null && !identical(state.scene, scene)) {
      _observe(
        SceneViewState(
          scene: scene,
          animated: state.animated,
          frameRate: state.frameRate,
          pixelRatio: state.pixelRatio,
          paused: state.paused,
        ),
      );
    }
  }

  void _tick(Duration elapsed, double deltaSeconds) {
    _measure?.frame(
      Duration(
        microseconds: (deltaSeconds * Duration.microsecondsPerSecond).round(),
      ),
    );
    widget.onTick?.call(elapsed, deltaSeconds);
  }

  void _observe(SceneViewState state) {
    _state = state;
    final measure = _measure;
    if (measure != null) {
      measure.changed(state);
      return;
    }
    _measure = _observer?.opened(widget.name, state);
  }

  void _close() {
    _measure?.closed();
    _measure = null;
    _state = null;
  }
}

/// Gives the scene widgets below a way to ask for a frame.
class _SceneRepaint extends InheritedWidget {
  const _SceneRepaint({required this.repaint, required super.child});

  final VoidCallback repaint;

  @override
  bool updateShouldNotify(_SceneRepaint oldWidget) => false;
}

/// Finds the scene a declarative view owns: the engine gives it to the
/// widgets below the view.
class _SceneProbe extends StatelessWidget {
  const _SceneProbe(this.found);

  final void Function(Scene scene) found;

  @override
  Widget build(BuildContext context) {
    if (SceneScope.maybeOf(context)?.scene case final scene?) {
      found(scene);
    }
    return const SizedBox.shrink();
  }
}
