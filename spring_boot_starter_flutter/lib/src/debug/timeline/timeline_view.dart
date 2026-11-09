import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/debug_timeline.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_chart.dart';
import 'package:spring_boot_starter_flutter/src/debug/timeline/timeline_observations.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stage.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_trace.dart';

/// The timeline in full, in three tabs: Start, the start as a waterfall
/// (the splash's stages as a band, the steps as bars, the beans grouped,
/// the events as dots; pinch or Ctrl+wheel zooms); Observations, the stats
/// of each name; Events, the application events published. "Copy JSON"
/// copies it all.
class TimelineView extends StatefulWidget {
  /// The view of [timeline].
  const TimelineView({required this.timeline, super.key});

  /// The timeline.
  final DebugTimeline timeline;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

enum _Tab {
  start('Start'),
  observations('Observations'),
  events('Events');

  const _Tab(this.label);

  final String label;
}

class _TimelineViewState extends State<TimelineView> {
  _Tab _tab = _Tab.start;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent(
          '  ',
        ).convert(widget.timeline.toJson()),
      ),
    );
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final timeline = widget.timeline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tab in _Tab.values)
                      DebugChip(
                        tab.label,
                        selected: tab == _tab,
                        onTap: () => setState(() {
                          _tab = tab;
                          _copied = false;
                        }),
                      ),
                  ],
                ),
              ),
            ),
            DebugChip(_copied ? 'Copied' : 'Copy JSON', onTap: _copy),
          ],
        ),
        Container(height: 1, color: style.line),
        const SizedBox(height: 8),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              timeline.trace.stages,
              timeline.observations,
            ]),
            builder: (context, _) => switch (_tab) {
              _Tab.start => _Waterfall(trace: timeline.trace),
              _Tab.observations => _Observations(
                observations: timeline.observations,
              ),
              _Tab.events => _Events(trace: timeline.trace),
            },
          ),
        ),
      ],
    );
  }
}

const _beanStep = 'spring.beans.instantiate';
const _rowHeight = 16.0;
const _shownBeans = 10;

double _ms(Duration duration) => duration.inMicroseconds / 1000;

Duration _end(RecordedStartupStep step) =>
    step.startedAt + (step.duration ?? Duration.zero);

String? _tag(RecordedStartupStep step, String key) => [
  for (final (k, value) in step.tags)
    if (k == key) '$value',
].firstOrNull;

// A row of the waterfall: a label on the left, a bar on the time axis.
final class _Row {
  const _Row(
    this.label, {
    required this.depth,
    required this.color,
    this.start,
    this.duration,
    this.onTap,
  });

  final String label;
  final int depth;
  final Color color;
  final Duration? start;
  final Duration? duration;
  final VoidCallback? onTap;
}

class _Waterfall extends StatefulWidget {
  const _Waterfall({required this.trace});

  final SplashTrace trace;

  @override
  State<_Waterfall> createState() => _WaterfallState();
}

class _WaterfallState extends State<_Waterfall> {
  static const _maxZoom = 64.0;

  double _zoom = 1;
  bool _beansOpen = true;
  bool _allBeans = false;

  final _pointers = <int, Offset>{};
  double? _pinchFrom;
  double _zoomFrom = 1;

  set _zoomTo(double value) {
    final zoom = value.clamp(1.0, _maxZoom);
    if (zoom != _zoom) {
      setState(() => _zoom = zoom);
    }
  }

  double get _spread {
    final [a, b] = _pointers.values.take(2).toList();
    return (a - b).distance;
  }

  void _down(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      _pinchFrom = _spread;
      _zoomFrom = _zoom;
    }
  }

  void _move(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) {
      return;
    }
    _pointers[event.pointer] = event.position;
    final from = _pinchFrom;
    if (_pointers.length == 2 && from != null && from > 0) {
      _zoomTo = _zoomFrom * _spread / from;
    }
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    _pinchFrom = null;
  }

  void _signal(PointerSignalEvent event) {
    if (event is PointerScaleEvent) {
      _zoomTo = _zoom * event.scale;
    } else if (event is PointerScrollEvent &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        (event) => _zoomTo =
            _zoom *
            math.exp(-(event as PointerScrollEvent).scrollDelta.dy / 300),
      );
    }
  }

  List<_Row> _rows(List<RecordedStartupStep> steps, DebugStyle style) {
    final shown = [
      for (final step in steps)
        if (!step.name.startsWith('spring.flutter.splash.') &&
            step.name != SplashTrace.event)
          step,
    ];
    final byId = {for (final step in shown) step.id: step};
    final depths = <int, int>{};
    int depthOf(RecordedStartupStep step) =>
        depths[step.id] ??= switch (byId[step.parentId]) {
          final parent? => depthOf(parent) + 1,
          null => 0,
        };
    final beans = [
      for (final step in shown)
        if (step.name == _beanStep) step,
    ];
    final rows = <_Row>[];
    var grouped = false;
    for (final step in shown) {
      if (step.name != _beanStep) {
        rows.add(
          _Row(
            step.name.replaceFirst('spring.', ''),
            depth: depthOf(step),
            color: style.accent,
            start: step.startedAt,
            duration: step.duration,
          ),
        );
      } else if (!grouped) {
        grouped = true;
        rows.addAll(_beanRows(beans, depthOf(step), style));
      }
    }
    return rows;
  }

  List<_Row> _beanRows(
    List<RecordedStartupStep> beans,
    int depth,
    DebugStyle style,
  ) {
    final start = beans.map((b) => b.startedAt).reduce(_min);
    final end = beans.map(_end).reduce(_max);
    final slowest = [...beans]
      ..sort(
        (a, b) => (b.duration ?? Duration.zero).compareTo(
          a.duration ?? Duration.zero,
        ),
      );
    final shown = _allBeans ? slowest : slowest.take(_shownBeans).toList();
    return [
      _Row(
        '${_beansOpen ? '▾' : '▸'} beans ${beans.length}',
        depth: depth,
        color: style.muted,
        start: start,
        duration: end - start,
        onTap: () => setState(() => _beansOpen = !_beansOpen),
      ),
      if (_beansOpen) ...[
        for (final bean in shown)
          _Row(
            _tag(bean, 'beanName') ?? bean.name,
            depth: depth + 1,
            color: style.warning,
            start: bean.startedAt,
            duration: bean.duration,
          ),
        if (shown.length < slowest.length)
          _Row(
            '… ${slowest.length - shown.length} more',
            depth: depth + 1,
            color: style.muted,
            onTap: () => setState(() => _allBeans = true),
          ),
      ],
    ];
  }

  static Duration _min(Duration a, Duration b) => a < b ? a : b;

  static Duration _max(Duration a, Duration b) => a > b ? a : b;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final steps = widget.trace.steps;
    final reached = widget.trace.stages.reached.entries.toList();
    final rows = _rows(steps, style);
    // The start: up to the last stage or step of it. The events after it
    // (a tab hidden a minute later) are on the Events tab, not stretching
    // the start into a sliver.
    final total = math.max(
      1.0,
      _ms(
        [
          for (final step in steps)
            if (step.name != SplashTrace.event) _end(step),
          for (final MapEntry(:value) in reached) value,
        ].fold(Duration.zero, _max),
      ),
    );
    final events = [
      for (final step in steps)
        if (step.name == SplashTrace.event && _ms(step.startedAt) <= total)
          step,
    ];
    final small = style.code.copyWith(fontSize: 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${formatTimelineDuration(Duration(microseconds: (total * 1000).round()))}'
                ' · zoom ${_zoom.toStringAsFixed(1)}×',
                style: style.text.copyWith(color: style.muted),
              ),
            ),
            DebugChip('−', onTap: () => _zoomTo = _zoom / 1.5),
            DebugChip('+', onTap: () => _zoomTo = _zoom * 1.5),
            DebugChip('Fit', onTap: () => _zoomTo = 1),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, room) {
              final labelWidth = math.min(170.0, room.maxWidth * 0.4);
              final width =
                  math.max(40.0, room.maxWidth - labelWidth - 4) * _zoom;
              final scale = width / total;
              double x(Duration at) => _ms(at) * scale;
              final labels = <Widget>[
                const SizedBox(height: 14),
                _label('stages', 0, null, null, style, small, height: 18),
                _label('events ${events.length}', 0, null, null, style, small),
                for (final row in rows)
                  _label(
                    row.label,
                    row.depth,
                    row.duration,
                    row.onTap,
                    style,
                    small,
                  ),
              ];
              final lanes = <Widget>[
                _Ruler(total: total, scale: scale, style: small),
                SizedBox(
                  height: 18,
                  child: Stack(
                    children: [
                      for (final (i, MapEntry(key: stage, value: at))
                          in reached.indexed)
                        Positioned(
                          left: x(at),
                          width: math.max(
                            2,
                            i + 1 < reached.length
                                ? x(reached[i + 1].value) - x(at)
                                : 2,
                          ),
                          top: 1,
                          bottom: 1,
                          child: _Segment(stage: stage, style: small),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: _rowHeight,
                  child: Stack(
                    children: [
                      for (final event in events)
                        Positioned(
                          left: x(event.startedAt) - 3,
                          top: 5,
                          width: 6,
                          height: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: style.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                for (final row in rows)
                  SizedBox(
                    height: _rowHeight,
                    child: Stack(
                      children: [
                        if (row.start case final start?)
                          Positioned(
                            left: x(start),
                            width: math.max(
                              2,
                              x(row.duration ?? Duration.zero),
                            ),
                            top: 3,
                            height: 10,
                            child: ColoredBox(color: row.color),
                          ),
                      ],
                    ),
                  ),
              ];
              return SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: labels,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Listener(
                        onPointerDown: _down,
                        onPointerMove: _move,
                        onPointerUp: _up,
                        onPointerCancel: _up,
                        onPointerPanZoomStart: (_) => _zoomFrom = _zoom,
                        onPointerPanZoomUpdate: (event) =>
                            _zoomTo = _zoomFrom * event.scale,
                        onPointerSignal: _signal,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: width,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: lanes,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _label(
    String label,
    int depth,
    Duration? duration,
    VoidCallback? onTap,
    DebugStyle style,
    TextStyle small, {
    double height = _rowHeight,
  }) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(width: depth * 8.0),
          Expanded(
            child: Text(
              label,
              style: small.copyWith(
                color: onTap == null ? style.foreground : style.accent,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (duration != null)
            Text(
              ' ${formatTimelineDuration(duration)}',
              style: small.copyWith(color: style.muted),
            ),
        ],
      ),
    ),
  );
}

// The time axis: a tick every round number of milliseconds, at least
// 60 wide apart.
class _Ruler extends StatelessWidget {
  const _Ruler({required this.total, required this.scale, required this.style});

  static const _steps = [
    1, 2, 5, 10, 20, 50, 100, 200, 500, //
    1000, 2000, 5000, 10000, 20000, 30000, 60000, 120000, 300000, 600000,
  ];

  final double total;
  final double scale;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // Labels at least 60 apart, so they never run into each other.
    final step = _steps.firstWhere(
      (ms) => ms * scale >= 60,
      orElse: () => (60 / scale).ceil(),
    );
    final muted = DebugStyle.of(context).muted;
    return SizedBox(
      height: 14,
      child: Stack(
        children: [
          for (var ms = 0; ms <= total; ms += step)
            Positioned(
              left: ms * scale,
              top: 0,
              child: Text(
                ms >= 1000 ? '${ms / 1000}s' : '${ms}ms',
                style: style.copyWith(color: muted, fontSize: 9),
              ),
            ),
        ],
      ),
    );
  }
}

// A stage of the splash in the band: its color, its name inside.
class _Segment extends StatelessWidget {
  const _Segment({required this.stage, required this.style});

  final SplashStage stage;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Container(
    color: HSVColor.fromAHSV(
      1,
      stage.index * 360 / SplashStage.values.length,
      0.45,
      0.75,
    ).toColor(),
    padding: const EdgeInsets.symmetric(horizontal: 2),
    alignment: Alignment.centerLeft,
    child: Text(
      stage.name,
      style: style.copyWith(color: const Color(0xFF101010), fontSize: 9),
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
    ),
  );
}

class _Observations extends StatefulWidget {
  const _Observations({required this.observations});

  final TimelineObservations observations;

  @override
  State<_Observations> createState() => _ObservationsState();
}

class _ObservationsState extends State<_Observations> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final stats = widget.observations.stats.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    if (stats.isEmpty) {
      return Text(
        'No observations yet: an @Observed method or an Observation of '
        'the observationRegistry shows here once it stops.',
        style: style.text.copyWith(color: style.muted),
      );
    }
    Widget row(List<String> cells, {Color? color}) => Row(
      children: [
        Expanded(
          child: Text(
            cells.first,
            style: style.code.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final cell in cells.skip(1))
          SizedBox(
            width: 52,
            child: Text(
              cell,
              textAlign: TextAlign.right,
              style: style.code.copyWith(color: color),
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(['name', 'count', 'avg', 'max', 'last'], color: style.muted),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: stats.length,
            itemBuilder: (context, i) {
              final stat = stats[i];
              final selected = stat.name == _selected;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    setState(() => _selected = selected ? null : stat.name),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: style.line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      row(
                        [
                          stat.name,
                          '${stat.count}',
                          formatTimelineDuration(stat.average),
                          formatTimelineDuration(stat.max),
                          formatTimelineDuration(stat.last),
                        ],
                        color: selected ? style.accent : null,
                      ),
                      if (selected)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: SizedBox(
                            height: 40,
                            child: TimelineSparkline(
                              [for (final d in stat.recent) _ms(d)],
                              color: style.accent,
                              bars: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Events extends StatelessWidget {
  const _Events({required this.trace});

  final SplashTrace trace;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final events = [
      for (final step in trace.steps)
        if (step.name == SplashTrace.event) step,
    ];
    if (events.isEmpty) {
      return Text(
        'No events yet.',
        style: style.text.copyWith(color: style.muted),
      );
    }
    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (context, i) {
        final event = events[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          // A long name wraps under itself, the time stays on top.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  formatTimelineDuration(event.startedAt),
                  style: style.code.copyWith(color: style.muted),
                ),
              ),
              Expanded(
                child: Text(
                  _tag(event, 'type') ?? event.name,
                  style: style.code,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
