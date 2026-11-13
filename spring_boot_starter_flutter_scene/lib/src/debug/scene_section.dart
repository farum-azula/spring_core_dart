import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugChip, DebugPanelSection, DebugStyle;
import 'package:spring_boot_starter_flutter_scene/src/debug/page_isolation.dart';
import 'package:spring_boot_starter_flutter_scene/src/debug/scene_debug.dart';
import 'package:spring_boot_starter_flutter_scene/src/debug/scene_model_shape.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_availability.dart';
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_engine.dart';
import 'package:spring_boot_starter_flutter_scene/src/models/scene_model_handle.dart';
import 'package:spring_boot_starter_flutter_scene/src/models/scene_models.dart';
import 'package:spring_boot_starter_flutter_scene/src/scene_status.dart';

/// The scenes' tab of the debug panel: the engine's start, every scene on
/// the screen and every model by its name, with what each costs.
///
/// - **The engine**: its state, how long the start took, whether the web
///   page is cross-origin isolated (Flutter draws in a worker then), the
///   steps of the start in words.
/// - **A scene** (a `SpringSceneView` by its `name`): the frames it draws
///   a second against those it may, why it stands still, the engine's
///   numbers of its last frame (draw calls, vertices, programs bound and
///   built), each pass with its time on the page's thread.
/// - **A model** (by its name in `spring.flutter.scene.models`): its
///   file, size, time to read and to import, what it is made of, and a
///   switch that hides it everywhere: the frame's numbers with and
///   without it are what it costs.
/// - **Memory**: what the engine's caches hold.
///
/// The engine gives no time on the GPU, and nothing per model: a model's
/// cost is seen by hiding it.
final class SceneDebugSection implements DebugPanelSection, Ordered {
  /// The tab over [debug]'s views, the [availability] and the [models].
  const SceneDebugSection({
    required this.debug,
    required this.availability,
    required this.models,
    required this.status,
  });

  /// The views on the screen.
  final SceneDebug debug;

  /// Whether scenes draw, and the engine.
  final SceneAvailability availability;

  /// The models of the properties.
  final SceneModels models;

  /// The steps of the start.
  final SceneStatus status;

  @override
  String get title => 'Scenes';

  @override
  int get order => 58;

  @override
  Widget build(BuildContext context) => _SceneDebugView(this);
}

class _SceneDebugView extends StatefulWidget {
  const _SceneDebugView(this.section);

  final SceneDebugSection section;

  @override
  State<_SceneDebugView> createState() => _SceneDebugViewState();
}

class _SceneDebugViewState extends State<_SceneDebugView> {
  // The numbers move with every frame of a scene: read twice a second,
  // so the panel does not redraw the page for each of them.
  late final Timer _refresh = Timer.periodic(
    const Duration(milliseconds: 500),
    (_) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _refresh;
  }

  @override
  void dispose() {
    _refresh.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final style = DebugStyle.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        section.debug,
        section.availability,
        ...section.models.all,
      ]),
      builder: (context, _) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Engine', style: style.title),
            const SizedBox(height: 8),
            ..._engine(style, section.availability),
            const SizedBox(height: 16),
            Text('Scenes on the screen', style: style.title),
            const SizedBox(height: 8),
            if (section.debug.views.isEmpty)
              _muted(style, 'None.')
            else
              for (final view in section.debug.views) ..._view(style, view),
            const SizedBox(height: 16),
            Text('Models', style: style.title),
            const SizedBox(height: 8),
            if (section.models.all.isEmpty)
              _muted(style, 'None in spring.flutter.scene.models.')
            else
              for (final model in section.models.all) ..._model(style, model),
            const SizedBox(height: 16),
            Text('Memory', style: style.title),
            const SizedBox(height: 8),
            ..._memory(style, section.availability.engine),
          ],
        ),
      ),
    );
  }

  List<Widget> _engine(DebugStyle style, SceneAvailability availability) {
    final engine = availability.engine;
    final isolated = pageIsolated;
    return [
      _row(style, 'Backend', engine.backend.name),
      _row(
        style,
        'State',
        engine.state.name,
        color: engine.hasFailed ? style.error : null,
      ),
      if (engine.took case final took?) _row(style, 'Start', _ms(took)),
      if (engine.failure case final failure?)
        _row(style, 'Failure', '$failure', color: style.error),
      _row(
        style,
        'Render',
        '${availability.properties.render.name}, at most '
            '${_number(availability.properties.maxFrameRate)} frames a second',
      ),
      if (isolated != null)
        _row(
          style,
          'Page isolated',
          isolated
              ? 'yes: Flutter draws in a worker'
              : "no: Flutter draws on the page's thread "
                    '(Cross-Origin-Opener-Policy, Cross-Origin-Embedder-Policy)',
          color: isolated ? null : style.warning,
        ),
      for (final step in widget.section.status.history)
        _row(
          style,
          step.eventName,
          widget.section.status.messages.getMessageFromResolvable(step),
          color: style.muted,
        ),
    ];
  }

  List<Widget> _view(DebugStyle style, SceneViewRecord view) {
    final state = view.state;
    final stats = view.stats;
    final surface = stats == null || stats.views.isEmpty
        ? null
        : stats.views.first;
    return [
      Text(view.name, style: style.code.copyWith(color: style.accent)),
      const SizedBox(height: 4),
      _row(
        style,
        'Frames',
        state.animated
            ? '${view.framesPerSecond} a second of ${_number(state.frameRate)}'
            : 'a still frame (${state.paused})',
      ),
      if (surface != null)
        _row(
          style,
          'Surface',
          '${surface.width} x ${surface.height} px'
              '${state.pixelRatio == null ? '' : ', pixel ratio ${_number(state.pixelRatio!)}'}',
        ),
      if (stats != null) ...[
        _row(
          style,
          'Frame',
          "${_micros(stats.cpuMicros)} on the page's thread, "
              '${stats.counters.draws} draw calls, '
              '${stats.counters.vertices} vertices',
        ),
        _row(
          style,
          'Programs',
          '${stats.counters.pipelineBinds} bound, '
              '${stats.counters.pipelineBuilds} built in the frame',
          color: stats.counters.pipelineBuilds > 0 ? style.warning : null,
        ),
        _row(
          style,
          'Items',
          '${stats.counters.submitted} considered, '
              '${stats.counters.culled} culled, '
              '${stats.counters.instances} instances',
        ),
        if (surface != null)
          for (final pass in surface.passes)
            _row(
              style,
              '  ${pass.name}',
              '${_micros(pass.cpuMicros)}, ${pass.counters.draws} draw calls',
              color: style.muted,
            ),
      ],
      const SizedBox(height: 10),
    ];
  }

  List<Widget> _model(DebugStyle style, SceneModelHandle model) {
    final template = model.template;
    final shape = template == null ? null : SceneModelShape.of(template);
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              model.name,
              style: style.code.copyWith(color: style.accent),
            ),
          ),
          if (model.state == SceneModelState.ready)
            DebugChip(
              model.hidden ? 'Hidden' : 'Shown',
              selected: !model.hidden,
              onTap: () => model.hidden = !model.hidden,
            ),
        ],
      ),
      _row(style, 'Source', model.location),
      _row(
        style,
        'State',
        '${model.state.name}${model.eager ? ', eager' : ', lazy'}',
        color: model.state == SceneModelState.failed ? style.error : null,
      ),
      if (model.failure case final failure?)
        _row(style, 'Failure', '$failure', color: style.error),
      if (model.bytes case final bytes?) _row(style, 'File', _bytes(bytes)),
      if (model.readTook case final read?)
        _row(
          style,
          'Load',
          '${_ms(read)} to read'
              '${model.importTook == null ? '' : ', ${_ms(model.importTook!)} to import'}',
        ),
      if (shape != null)
        _row(
          style,
          'Made of',
          '${shape.nodes} nodes, ${shape.meshes} meshes, '
              '${shape.primitives} draw calls a use, '
              '${shape.materials} materials',
        ),
      const SizedBox(height: 10),
    ];
  }

  List<Widget> _memory(DebugStyle style, SceneEngine engine) {
    if (!engine.isReady) {
      return [_muted(style, 'The engine has not started.')];
    }
    final report = takeMemoryReport();
    return [
      for (final category in report.categories)
        _row(
          style,
          category.name,
          '${category.count}'
          '${category.bytes == null ? '' : ', ${_bytes(category.bytes!)}'}',
        ),
      _row(style, 'Total', _bytes(report.totalBytes)),
    ];
  }

  static Widget _muted(DebugStyle style, String text) =>
      Text(text, style: style.text.copyWith(color: style.muted));

  static Widget _row(
    DebugStyle style,
    String label,
    String value, {
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(label, style: style.text.copyWith(color: style.muted)),
        ),
        Expanded(
          child: Text(value, style: style.code.copyWith(color: color)),
        ),
      ],
    ),
  );

  static String _ms(Duration time) =>
      '${(time.inMicroseconds / 1000).toStringAsFixed(1)} ms';

  static String _micros(int micros) =>
      '${(micros / 1000).toStringAsFixed(2)} ms';

  static String _number(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  static String _bytes(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} kB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}
