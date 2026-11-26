import 'package:flutter/foundation.dart' show ValueListenable;

import 'dart:ui' show Canvas, PictureRecorder;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show PaintedElsewhere, SpringScope;
import 'package:spring_boot_starter_flutter_scene/src/app/application_scene.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_availability.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_frames.dart';
import 'package:spring_boot_starter_flutter_scene/src/properties/scene_properties.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/on_screen.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_canvas_target.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_layer.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_route.dart';
import 'package:spring_boot_starter_flutter_scene/src/widgets/scene_screen.dart';
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
///   [maxFrameRate] when that is fewer, and the page is drawn for those
///   frames alone: the view does not tick with the display, it is given
///   its frames by the app's [SceneFrames], with every other moving view
///   on the same beat.
/// - **A still frame.** With `render: still`, or when the system asks for
///   less motion, it draws one frame and draws again only when what it
///   shows changes.
/// - **A pause off the screen** (`pause-off-screen`): scrolled away, it
///   stops drawing.
/// - **A canvas under the page** on the web ([canvas],
///   `spring.flutter.scene.canvas`): a layer of the scene's own, its frames
///   handed over to it, or the engine's own canvas, every scene drawn on
///   it where it stands; Flutter does not draw the page for a frame of
///   either.
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
    this.canvas,
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
    this.canvas,
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
  /// `max-frame-rate`; `0` asks for no fewer than they let it.
  final double? maxFrameRate;

  /// The view's own pixel ratio; the properties' `pixel-ratio` when
  /// `null`.
  final double? pixelRatio;

  /// Which canvas the scene is on in a browser: `page`, or `layer`, a
  /// canvas of its own under the page's that each frame is handed over
  /// to, and the browser puts together with the page. A frame of the
  /// scene then costs the scene alone, not the page drawn again around
  /// it; widgets of the page over the scene still draw over it. The
  /// properties' `canvas` when `null`. With `canvas: engine` in the
  /// properties every view is on the engine's canvas, whatever this says;
  /// elsewhere than on the web the view draws as always.
  final SceneCanvas? canvas;

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

  /// Whether the view above [context] stands still: `render: still`, a
  /// condition of `spring.flutter.scene.when` that asks for it, or the
  /// system asking for less motion. A scene widget that moves by the time
  /// draws its resting look then (a neon lit, not striking). The widget
  /// that asks is built again when it changes. Without a view, whether
  /// the system asks for less motion.
  static bool stillOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SceneRepaint>()?.still ??
      reducedMotionOf(context);

  /// Asks the view above [context] for one more frame: for a scene widget
  /// that changed what is drawn without a rebuild, so a still frame shows
  /// it. Does nothing in a view that moves anyway, or without a view.
  static void repaintOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SceneRepaint>()?.repaint();

  /// The [name] of the view above [context], `null` without a view: what
  /// the scenes' debug panel counts the uses of a material by.
  static String? nameOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SceneRepaint>()?.name;

  /// The time the scene of the view above [context] has run, notified on
  /// each of its frames; `null` without a view.
  static ValueListenable<Duration>? elapsedOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SceneRepaint>()?.elapsed;

  /// The loads the view above [context] waits for before its first
  /// frame, `null` without a view: a scene widget adds its own.
  static ResourceGroup? loadsOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SceneRepaint>()?.loads;

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
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  SceneFrames? _frames;
  SceneFrames? _ownFrames;
  DateTime? _origin;
  Duration? _last;
  Duration? _due;
  double _rate = 0;
  SceneCanvasTarget? _target;
  bool _canvasFailed = false;
  // The engine's view has loaded its scene; it shows once no condition of
  // `when` is still finding out ([_deciding]), and draws frames nobody
  // sees meanwhile.
  bool _loaded = false;
  bool _deciding = false;
  bool _presenting = false;
  Size _size = Size.zero;
  double _ratio = 1;
  Camera? _camera;
  SceneCameraBuilder? _cameraBuilder;

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
    // The route the view is on: its scene leaves the engine's canvas when
    // the route starts to leave, not when its transition ends.
    final route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      _route?.animation?.removeStatusListener(_routeMoved);
      _route?.secondaryAnimation?.removeStatusListener(_routeMoved);
      _route = route;
      route?.animation?.addStatusListener(_routeMoved);
      route?.secondaryAnimation?.addStatusListener(_routeMoved);
    }
    final frames =
        beans?.getBeanProvider<SceneFrames>().getIfAvailable() ??
        (_ownFrames ??= SceneFrames());
    if (!identical(frames, _frames)) {
      _frames?.leave(this);
      _frames = frames;
    }
    _start();
  }

  ModalRoute<Object?>? _route;

  // The route's transition turned: built again, its scene shown or hidden.
  void _routeMoved(AnimationStatus status) => _changed();

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_routeMoved);
    _route?.secondaryAnimation?.removeStatusListener(_routeMoved);
    _frames?.leave(this);
    _ownFrames?.dispose();
    _availability?.removeListener(_changed);
    _application?.removeListener(_changed);
    _measure?.closed();
    _target?.dispose();
    _loads.dispose();
    _elapsed.dispose();
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
    if (!shows || (_canvasFailed && sceneScreenOn)) {
      _frames?.leave(this);
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
    if (scene != null) {
      _configure(scene);
    }
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
    final cameraBuilder = widget.cameraBuilder;
    final ownCamera = cameraBuilder == null
        ? null
        : (Duration _) => cameraBuilder(_elapsed.value);
    final canvas = _canvasOf(availability);
    final layered = canvas != SceneCanvas.page;
    if (!layered) {
      _leaveCanvas();
    }
    // A scene that stands shows at once; one that moves waits for `when`.
    _deciding = paused == null && availability.deciding;
    _move(paused == null ? frameRate : 0);
    final view = widget._declarative
        ? SceneView.declarative(
            environment: widget.environment,
            environmentIntensity: widget.environmentIntensity,
            exposure: widget.exposure,
            toneMapping: widget.toneMapping!,
            camera: camera,
            cameraBuilder: ownCamera,
            autoTick: false,
            clock: _clock.clock,
            pixelRatio: pixelRatio,
            loading: widget.loading ?? _loads,
            loadingBuilder: _layerLoading,
            warmUp: widget.warmUp,
            children: [_SceneProbe(_found), ...widget.children],
          )
        : SceneView(
            scene!,
            camera: camera,
            cameraBuilder: ownCamera,
            autoTick: false,
            clock: _clock.clock,
            pixelRatio: pixelRatio,
            loading: widget.loading ?? _loads,
            loadingBuilder: _layerLoading,
            warmUp: widget.warmUp,
            children: widget.children,
          );
    // A pause leaves the beat and stops the clock: back on the screen the
    // scene moves on by one frame, not by the time it was away.
    _clock.paused = paused != null;
    // A scene's frame is its own layer: the widgets around it are not
    // painted again for it.
    return _SceneRepaint(
      name: widget.name,
      loads: widget.loading ?? _loads,
      elapsed: _elapsed,
      still: paused == 'still' || paused == 'motion',
      repaint: _repaint,
      child: layered
          ? _layered(canvas, view, camera, ownCamera, pixelRatio)
          : _paged(view, camera, ownCamera, pixelRatio),
    );
  }

  bool get _revealed => _loaded && !_deciding;

  // Flutter draws the scene into the page: the engine's view, offstage
  // until it shows, the placeholder over it meanwhile.
  Widget _paged(
    Widget view,
    Camera? camera,
    SceneCameraBuilder? cameraBuilder,
    double? pixelRatio,
  ) {
    _camera = camera;
    _cameraBuilder = cameraBuilder;
    _ratio = pixelRatio ?? View.of(context).devicePixelRatio;
    final revealed = _revealed;
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: !revealed,
              child: RepaintBoundary(child: view),
            ),
            if (!revealed) ?widget.placeholder,
          ],
        );
      },
    );
  }

  // The canvas the view is on: the engine's for every view when the
  // engine started on it, the page's after a layer failed.
  SceneCanvas _canvasOf(SceneAvailability availability) {
    if (sceneScreenOn) {
      return SceneCanvas.engine;
    }
    if (!sceneLayers || _canvasFailed) {
      return SceneCanvas.page;
    }
    return switch (widget.canvas ?? availability.properties.canvas) {
      SceneCanvas.page => SceneCanvas.page,
      SceneCanvas.layer || SceneCanvas.engine => SceneCanvas.layer,
    };
  }

  void _leaveCanvas() {
    _target?.dispose();
    _target = null;
  }

  // The engine's view builds the scene and is not painted; its frames go
  // on the layer's canvas or the engine's, the placeholder over it until
  // the first.
  Widget _layered(
    SceneCanvas canvas,
    Widget view,
    Camera? camera,
    SceneCameraBuilder? cameraBuilder,
    double? pixelRatio,
  ) {
    final onScreen = canvas == SceneCanvas.engine;
    if (_target != null && (_target is SceneScreenPlace) != onScreen) {
      _leaveCanvas();
    }
    final target = _target ??= onScreen
        ? SceneScreenPlace(context, _changed)
        : SceneLayer();
    final devicePixelRatio = View.of(context).devicePixelRatio;
    if (target is SceneScreenPlace) {
      target
        ..visible =
            TickerMode.valuesOf(context).enabled && !sceneRouteLeaving(_route)
        ..ratio = devicePixelRatio
        ..screen = MediaQuery.sizeOf(context);
    }
    _camera = camera;
    _cameraBuilder = cameraBuilder;
    _ratio = pixelRatio ?? devicePixelRatio;
    _presentAfterFrame();
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        if (target is SceneScreenPlace) {
          target.box = context;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            // Built here, drawn on the layer's or the engine's canvas: the
            // debug graph counts its widgets as on the screen.
            Offstage(key: const PaintedElsewhere(), child: view),
            IgnorePointer(child: target.build()),
            if (!_revealed) ?widget.placeholder,
          ],
        );
      },
    );
  }

  Widget _layerLoading(BuildContext context, double progress) =>
      _LayerLoading(shown: _shown);

  // The engine's view has its scene (false: it loads again).
  void _shown(bool loaded) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _loaded != loaded) {
        setState(() => _loaded = loaded);
      }
    });
  }

  void _presentAfterFrame() {
    if (_presenting) {
      return;
    }
    _presenting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _presenting = false;
      _present();
    });
  }

  // The engine draws the scene, into a picture nobody paints, and the
  // frame goes on the layer's canvas or the engine's; `true` when it drew.
  bool _present() {
    final target = _target;
    final scene = _state?.scene;
    if (!mounted || target == null || scene == null || !_revealed) {
      return false;
    }
    if (_size.isEmpty || !_size.isFinite) {
      return false;
    }
    final camera =
        _camera ??
        _cameraBuilder?.call(_elapsed.value) ??
        scene.camera ??
        _defaultCamera;
    final recorder = PictureRecorder();
    try {
      return target.present(
        () => scene.render(
          camera,
          Canvas(recorder),
          viewport: Offset.zero & _size,
          pixelRatio: _ratio,
        ),
      );
    } on Object catch (error, stack) {
      // The view draws as the others then: the scene stays.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'spring_boot_starter_flutter_scene',
          context: ErrorDescription(
            'while putting a frame of the scene "${widget.name}" on its '
            'canvas; ${sceneScreenOn ? 'its placeholder shows' : 'it is drawn by Flutter'} '
            'from now on',
          ),
        ),
      );
      setState(() {
        _leaveCanvas();
        _canvasFailed = true;
      });
      return false;
    } finally {
      recorder.endRecording().dispose();
    }
  }

  // Joins the beat at [rate] frames a second, or leaves it at 0.
  void _move(double rate) {
    if (rate <= 0) {
      _frames?.leave(this);
      _rate = 0;
      return;
    }
    if (rate != _rate) {
      _due = null;
    }
    _rate = rate;
    _frames?.join(this, rate, _beat);
  }

  // A beat: when the view is due, the time moves on, the engine steps the
  // scene by it and draws it, on its canvas or by a build of the view.
  // `true` when it drew a frame Flutter does not draw.
  bool _beat() {
    if (!mounted || _rate <= 0) {
      return false;
    }
    final now = _clock.clock.now();
    final origin = _origin ??= now;
    final elapsed = now.difference(origin);
    // As many as the screen shows: due at each beat.
    final period = _rate.isInfinite
        ? Duration.zero
        : Duration(
            microseconds: (Duration.microsecondsPerSecond / _rate).round(),
          );
    final due = _due;
    // Two fifths of a period of slack: the beat nearest the deadline,
    // whether the beats are a timer's or the screen's frames (a frame of
    // 60 a second is due at each of them, one of 30 at every other).
    if (due != null && elapsed < due - period * 2 ~/ 5) {
      return false;
    }
    _due = due == null || elapsed - due > period
        ? elapsed + period
        : due + period;
    final last = _last ?? elapsed;
    _last = elapsed;
    final delta =
        (elapsed - last).inMicroseconds / Duration.microsecondsPerSecond;
    _elapsed.value = elapsed;
    _state?.scene?.update(delta);
    _tick(elapsed, delta);
    if (!_revealed) {
      // While `when` is finding out, a frame nobody sees, measured.
      return _loaded && _deciding && _probe();
    }
    if (_target != null) {
      return _present();
    }
    setState(() {});
    return false;
  }

  // The engine draws the scene into a picture nobody paints, as it draws
  // one it shows: what a frame of it costs.
  bool _probe() {
    final scene = _state?.scene;
    if (!mounted || scene == null || _size.isEmpty || !_size.isFinite) {
      return false;
    }
    final camera =
        _camera ??
        _cameraBuilder?.call(_elapsed.value) ??
        scene.camera ??
        _defaultCamera;
    final recorder = PictureRecorder();
    try {
      scene.render(
        camera,
        Canvas(recorder),
        viewport: Offset.zero & _size,
        pixelRatio: _ratio,
      );
      return true;
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'spring_boot_starter_flutter_scene',
          context: ErrorDescription(
            'while measuring a frame of the scene "${widget.name}"',
          ),
        ),
      );
      return false;
    } finally {
      recorder.endRecording().dispose();
    }
  }

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
    _configure(scene);
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

  // The properties the engine reads from the scene itself.
  void _configure(Scene scene) {
    final clustering = _availability?.properties.lightClustering;
    if (clustering != null && scene.punctualLightClustering != clustering) {
      scene.punctualLightClustering = clustering;
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
    _leaveCanvas();
    _measure?.closed();
    _measure = null;
    _state = null;
  }
}

final Camera _defaultCamera = PerspectiveCamera();

/// Stands in the engine's view while it loads: tells the view
/// when its scene shows.
class _LayerLoading extends StatefulWidget {
  const _LayerLoading({required this.shown});

  final void Function(bool revealed) shown;

  @override
  State<_LayerLoading> createState() => _LayerLoadingState();
}

class _LayerLoadingState extends State<_LayerLoading> {
  @override
  void initState() {
    super.initState();
    widget.shown(false);
  }

  @override
  void dispose() {
    widget.shown(true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Gives the scene widgets below a way to ask for a frame.
class _SceneRepaint extends InheritedWidget {
  const _SceneRepaint({
    required this.name,
    required this.loads,
    required this.elapsed,
    required this.still,
    required this.repaint,
    required super.child,
  });

  final bool still;

  final String name;

  final ResourceGroup loads;

  final ValueListenable<Duration> elapsed;

  final VoidCallback repaint;

  @override
  bool updateShouldNotify(_SceneRepaint oldWidget) => still != oldWidget.still;
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
