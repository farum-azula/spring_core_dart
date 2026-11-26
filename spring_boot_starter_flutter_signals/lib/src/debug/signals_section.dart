import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show Ordered;
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugChip, DebugStyle, GroupedDebugPanelSection;
import 'package:spring_boot_starter_flutter_signals/src/debug/graph/signals_graph_layer.dart';
import 'package:spring_boot_starter_flutter_signals/src/debug/signals_debug_recorder.dart';
import 'package:spring_boot_starter_flutter_signals/src/debug/signals_rows.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_buffer.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_queue.dart';
import 'package:spring_boot_starter_flutter_signals/src/widgets/signal_build_tracker.dart';

/// The Signals tab of the debug panel: every bean with followed state
/// that lives now, by its class and scope, its members in columns (the
/// value, how long since it changed and since its readers were told, the
/// changes, writes, ticks and reads, the time of a computation), a row
/// that just changed lit and fading, the queues (what waits, the
/// schedule, the drops) and the open buffers: the `Fields` sub-tab. The
/// `Graph` sub-tab is the application graph of the signals layer alone
/// (with [graph], in the build when the Graph tab or a graph pane is); the
/// `List` sub-tab the same dependencies as a list, the widgets by name with
/// their rebuilds. The times, counts and dependencies are collected only
/// while the tab shows.
///
/// - A `@Signal` field: its value and how often it changed.
/// - A `@Computed` value: what it is now; for an asynchronous one, where
///   the load is and how often it ran.
/// - An `@Effect` method: how often it ran. An effect that runs far more
///   often than its state changes reads something it should not follow.
///
/// A member shows once it was first used: a field nobody read is not
/// followed yet. A field marked `@Signal(hidden: true)`, a member whose
/// name looks secret and a value kept for its caller show a lock, never
/// the value.
final class SignalsDebugSection implements GroupedDebugPanelSection, Ordered {
  /// The tab over the state kept in [beans]; with [recorder] the
  /// dependencies, times and counts, with [queues] the queues, with
  /// [graph] the Graph sub-tab.
  const SignalsDebugSection(
    this.beans, {
    this.recorder,
    this.queues,
    this.graph,
  });

  /// The beans with followed state.
  final SignalBeans beans;

  /// What is collected while the tab shows.
  final SignalsDebugRecorder? recorder;

  /// The application's queues.
  final SignalQueues? queues;

  /// The signals layer of the application graph, when the build has it.
  final SignalsGraphLayer? graph;

  @override
  String get title => 'Signals';

  @override
  int get order => 59;

  @override
  String get group => 'Logs & state';

  @override
  Widget build(BuildContext context) => _SignalsDebugView(
    beans,
    recorder: recorder,
    queues: queues,
    graph: graph,
  );
}

/// The sub-tabs of the Signals tab.
enum SignalsSubTab {
  /// The beans' members in columns, the queues, the buffers.
  fields,

  /// The application graph of the signals layer.
  graph,

  /// The dependencies as a list.
  list,
}

class _SignalsDebugView extends StatefulWidget {
  const _SignalsDebugView(
    this.beans, {
    this.recorder,
    this.queues,
    this.graph,
  });

  final SignalBeans beans;
  final SignalsDebugRecorder? recorder;
  final SignalQueues? queues;
  final SignalsGraphLayer? graph;

  @override
  State<_SignalsDebugView> createState() => _SignalsDebugViewState();
}

class _SignalsDebugViewState extends State<_SignalsDebugView> {
  // The values move with the app: read four times a second, without
  // following them (the tab must not become a reader of the state it
  // shows); the lamps fade between. The times since a change move once a
  // second.
  late final Timer _refresh = Timer.periodic(
    const Duration(milliseconds: 250),
    (_) => _tick(),
  );
  void Function()? _release;
  Duration _timesAt = Duration.zero;
  SignalsSubTab _tab = SignalsSubTab.fields;
  final Set<Object> _expanded = {};

  @override
  void initState() {
    super.initState();
    _refresh;
    _release = widget.recorder?.use();
    _timesAt = widget.recorder?.now ?? Duration.zero;
  }

  @override
  void dispose() {
    _refresh.cancel();
    _release?.call();
    super.dispose();
  }

  void _tick() {
    final recorder = widget.recorder;
    if (recorder != null) {
      recorder.pruneEnded();
      final now = recorder.now;
      if (now - _timesAt >= const Duration(seconds: 1)) {
        _timesAt = now;
      }
    }
    // The graph draws itself; the columns and the list move with the app.
    if (_tab != SignalsSubTab.graph) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final graph = widget.graph;
    final recorder = widget.recorder;
    final tabs = [
      SignalsSubTab.fields,
      if (graph != null) SignalsSubTab.graph,
      if (recorder != null) SignalsSubTab.list,
    ];
    final tab = tabs.contains(_tab) ? _tab : SignalsSubTab.fields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tabs.length > 1)
          Wrap(
            children: [
              for (final each in tabs)
                DebugChip(
                  switch (each) {
                    SignalsSubTab.fields => 'Fields',
                    SignalsSubTab.graph => 'Graph',
                    SignalsSubTab.list => 'List',
                  },
                  selected: each == tab,
                  onTap: () => setState(() => _tab = each),
                ),
            ],
          ),
        Expanded(
          child: switch (tab) {
            SignalsSubTab.graph when graph != null => graph.buildView(),
            SignalsSubTab.list when recorder != null => _list(style, recorder),
            _ => _fields(style),
          },
        ),
      ],
    );
  }

  Widget _list(DebugStyle style, SignalsDebugRecorder recorder) {
    final lines = SignalsTree.lines(recorder, widget.beans.live.toList());
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isEmpty)
            Text(
              'Nothing read yet.',
              style: style.text.copyWith(color: style.muted),
            ),
          for (final line in lines)
            _line(
              style,
              '${'  ' * line.depth}${line.depth == 0 ? '' : '└ '}'
              '${line.label}',
              recorder.lampOf(line.node),
            ),
        ],
      ),
    );
  }

  Widget _fields(DebugStyle style) {
    final beans = widget.beans.live.toList();
    final recorder = widget.recorder;
    final queues = widget.queues;
    final now = recorder?.now ?? Duration.zero;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (beans.isEmpty)
            Text(
              'No bean with a @Signal, @Computed or @Effect member lives now.',
              style: style.text.copyWith(color: style.muted),
            ),
          for (final bean in beans) ...[
            Text(
              '${bean.label}${bean.scope == null ? '' : '  ·  ${bean.scope}'}',
              style: style.title,
            ),
            const SizedBox(height: 6),
            if (bean.members.isEmpty && bean.effectRuns.isEmpty)
              Text(
                'Nothing read yet.',
                style: style.text.copyWith(color: style.muted),
              )
            else
              SignalsTable(
                [
                  for (final member in bean.members.values)
                    SignalsRow.member(member, recorder),
                  for (final MapEntry(key: name, value: runs)
                      in bean.effectRuns.entries)
                    SignalsRow.effect(bean, name, runs, recorder),
                ],
                recorder: recorder,
                now: now,
                timesAt: _timesAt,
                expanded: _expanded,
                onExpand: (node) => setState(() {
                  if (!_expanded.remove(node)) {
                    _expanded.add(node);
                  }
                }),
              ),
            const SizedBox(height: 14),
          ],
          if (queues != null) ...[
            Text('Queues', style: style.title),
            const SizedBox(height: 6),
            for (final queue in queues.all)
              _labelled(
                style,
                queue.name,
                '${queue.scheduleName}, ${queue.pending} waiting, '
                '${queue.drops} dropped',
              ),
            const SizedBox(height: 14),
          ],
          Text('Buffers', style: style.title),
          const SizedBox(height: 6),
          _labelled(
            style,
            'open',
            switch (SignalBuffer.openSizes) {
              [] => 'none',
              final sizes =>
                '${sizes.length}, holding ${sizes.fold(0, (a, b) => a + b)} '
                    'fields',
            },
          ),
        ],
      ),
    );
  }

  static Widget _line(DebugStyle style, String text, double lamp) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 6),
          child: SignalLamp(lamp),
        ),
        Expanded(child: Text(text, style: style.code)),
      ],
    ),
  );

  static Widget _labelled(DebugStyle style, String label, String value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: Text(
                label,
                style: style.text.copyWith(color: style.muted),
              ),
            ),
            Expanded(child: Text(value, style: style.code)),
          ],
        ),
      );
}

/// The members of one bean in columns: `value | changed | told | changes
/// | writes | ticks | reads/5s | time`, a header over them. A row that
/// changed in the last two seconds is lit and fades; a tap on a
/// collection's value shows its first items.
class SignalsTable extends StatelessWidget {
  /// The table of [rows], their times at [timesAt] (moved once a second)
  /// and their lamps and highlights at [now].
  const SignalsTable(
    this.rows, {
    required this.now,
    required this.timesAt,
    this.recorder,
    this.expanded = const {},
    this.onExpand,
    super.key,
  });

  /// The rows.
  final List<SignalsRow> rows;

  /// What collects the times and counts.
  final SignalsDebugRecorder? recorder;

  /// The recorder's time now: the lamps and highlights.
  final Duration now;

  /// The time the `changed` and `told` columns count from.
  final Duration timesAt;

  /// The nodes whose collection shows its items.
  final Set<Object> expanded;

  /// Called with a row's node when its collection value is tapped.
  final ValueChanged<Object>? onExpand;

  /// The headers of the columns after the name.
  static List<String> headersOf(SignalsDebugRecorder? recorder) => [
    'value',
    'changed',
    'told',
    'changes',
    'writes',
    'ticks',
    'reads/${recorder?.readWindow.inSeconds ?? 5}s',
    'time',
  ];

  static const double _name = 140;
  static const double _least = 44;
  static const double _gap = 12;
  static const double _minValue = 160;

  static final Map<int, List<double>> _widths = {};

  /// The widths of the columns after the value, for [headers]: each at
  /// least as wide as its header in [header]'s font and a count or time of
  /// five characters in [values]' font, with room between, so a header
  /// never wraps.
  static List<double> columnWidths(
    List<String> headers,
    TextStyle header,
    TextStyle values,
  ) =>
      _widths[Object.hash(
        Object.hashAll(headers),
        header.fontSize,
        header.fontFamily,
        header.fontWeight,
        header.letterSpacing,
        values.fontSize,
        values.fontFamily,
      )] ??= [
        for (final text in headers)
          [
            _least,
            _measure(text, header) + _gap,
            _measure('00.0s', values) + _gap,
          ].reduce((a, b) => a > b ? a : b).ceilToDouble(),
      ];

  static double _measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final headers = headersOf(recorder);
    final muted = style.text.copyWith(color: style.muted);
    final numbers = columnWidths(headers.sublist(1), muted, style.code);
    final least = _name + _minValue + numbers.fold<double>(0, (a, b) => a + b);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? (constraints.maxWidth < least ? least : constraints.maxWidth)
            : least;
        final table = SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cells(
                numbers,
                const SizedBox.shrink(),
                Text(headers.first, style: muted, maxLines: 1, softWrap: false),
                [
                  for (final header in headers.skip(1))
                    Text(
                      header,
                      style: muted,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      softWrap: false,
                    ),
                ],
              ),
              for (final row in rows) ...[
                SignalsRowHighlight(
                  changedAt: row.changedAt,
                  now: now,
                  color: style.number,
                  child: _row(style, row, numbers),
                ),
                if (row.expandable case final collection?
                    when expanded.contains(row.node))
                  Padding(
                    padding: const EdgeInsets.only(left: _name, bottom: 3),
                    child: Text(
                      SignalsValues.items(collection),
                      style: style.code.copyWith(color: style.muted),
                    ),
                  ),
              ],
            ],
          ),
        );
        return width > constraints.maxWidth
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              )
            : table;
      },
    );
  }

  Widget _row(DebugStyle style, SignalsRow row, List<double> widths) {
    String? count(int? value) => value?.toString();
    final timing = row.timing;
    return _cells(
      widths,
      Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: SignalLamp(recorder?.lampAt(row.node, now) ?? 0),
          ),
          Flexible(
            child: Text(
              row.label,
              style: style.text.copyWith(color: style.muted),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
      _value(style, row),
      [
        _number(style, SignalsValues.ago(row.changedAt, timesAt)),
        _number(
          style,
          row.kind == SignalsRowKind.signal
              ? SignalsValues.ago(row.toldAt, timesAt)
              : null,
        ),
        _number(style, count(row.changes)),
        _number(style, count(row.writes)),
        _number(style, count(row.ticks)),
        _number(style, count(row.reads)),
        _number(style, timing == null ? null : SignalsValues.took(timing.last)),
      ],
    );
  }

  Widget _value(DebugStyle style, SignalsRow row) {
    final valueStyle = style.code.copyWith(
      color: switch (row.tone) {
        SignalsValueTone.value => style.number,
        SignalsValueTone.loading => style.warning,
        SignalsValueTone.failed => style.bad,
        SignalsValueTone.locked || SignalsValueTone.none => style.muted,
      },
      fontWeight: row.tone == SignalsValueTone.none ? null : FontWeight.w600,
    );
    if (row.tone == SignalsValueTone.locked) {
      return SignalsLock(row.lock ?? 'hidden');
    }
    final text = Text(
      row.value,
      style: valueStyle,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    if (row.expandable == null || onExpand == null) {
      return text;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onExpand!(row.node),
      child: Row(
        children: [
          Flexible(child: text),
          Text(
            expanded.contains(row.node) ? ' ▾' : ' ▸',
            style: style.code.copyWith(color: style.muted),
          ),
        ],
      ),
    );
  }

  // A count or a time: muted when zero or none, else the text's colour.
  static Widget _number(DebugStyle style, String? text) {
    final shown = text ?? '—';
    return Text(
      shown,
      textAlign: TextAlign.right,
      maxLines: 1,
      style: style.code.copyWith(
        color: shown == '—' || shown == '0' ? style.muted : style.foreground,
      ),
    );
  }

  static Widget _cells(
    List<double> widths,
    Widget name,
    Widget value,
    List<Widget> numbers,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: _name, child: name),
        Expanded(child: value),
        for (var i = 0; i < numbers.length; i++)
          SizedBox(width: widths[i], child: numbers[i]),
      ],
    ),
  );
}

/// The background of a row that changed: lit when it changed and fading
/// out over [fade]; nothing once faded, and no frames drawn for it then.
class SignalsRowHighlight extends StatefulWidget {
  /// The highlight of a row that changed at [changedAt], [now] being the
  /// recorder's time.
  const SignalsRowHighlight({
    required this.changedAt,
    required this.now,
    required this.color,
    required this.child,
    this.fade = const Duration(seconds: 2),
    super.key,
  });

  /// When the row changed.
  final Duration? changedAt;

  /// The recorder's time now.
  final Duration now;

  /// The colour it is lit in.
  final Color color;

  /// How long it fades.
  final Duration fade;

  /// The row.
  final Widget child;

  @override
  State<SignalsRowHighlight> createState() => _SignalsRowHighlightState();
}

class _SignalsRowHighlightState extends State<SignalsRowHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: widget.fade,
    value: 1,
  );
  Duration? _lit;

  @override
  void initState() {
    super.initState();
    _light();
  }

  @override
  void didUpdateWidget(SignalsRowHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    _light();
  }

  // Lit again for a new change, from as far as its age has faded it.
  void _light() {
    final at = widget.changedAt;
    if (at == null || at == _lit) {
      return;
    }
    _lit = at;
    final age = widget.now - at;
    if (age >= widget.fade) {
      return;
    }
    unawaited(
      _fade.forward(
        from: age.isNegative
            ? 0
            : age.inMicroseconds / widget.fade.inMicroseconds,
      ),
    );
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fade,
    builder: (context, child) => DecoratedBox(
      decoration: BoxDecoration(
        color: _fade.value >= 1
            ? null
            : widget.color.withValues(alpha: 0.22 * (1 - _fade.value)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: child,
    ),
    child: widget.child,
  );
}

/// A lock in place of a value the tab does not show: a hidden field, a
/// member whose name looks secret, a value kept for its caller. Why shows
/// beside it while the pointer is over it or after a tap.
class SignalsLock extends StatefulWidget {
  /// The lock telling [reason].
  const SignalsLock(this.reason, {super.key});

  /// Why the value is not shown.
  final String reason;

  @override
  State<SignalsLock> createState() => _SignalsLockState();
}

class _SignalsLockState extends State<SignalsLock> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Semantics(
      tooltip: widget.reason,
      child: MouseRegion(
        onEnter: (_) => setState(() => _shown = true),
        onExit: (_) => setState(() => _shown = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _shown = !_shown),
          child: Row(
            children: [
              CustomPaint(
                size: const Size(10, 12),
                painter: _LockPainter(style.muted),
              ),
              if (_shown)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      widget.reason,
                      style: style.text.copyWith(color: style.muted),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockPainter extends CustomPainter {
  const _LockPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final body = Rect.fromLTWH(
      0,
      size.height * 0.45,
      size.width,
      size.height * 0.55,
    );
    canvas
      ..drawArc(
        Rect.fromLTWH(
          size.width * 0.2,
          0,
          size.width * 0.6,
          size.height * 0.75,
        ),
        3.1416,
        3.1416,
        false,
        paint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(body, const Radius.circular(1.5)),
        Paint()..color = color,
      );
  }

  @override
  bool shouldRepaint(_LockPainter oldDelegate) => oldDelegate.color != color;
}

/// A dot that is lit (1) when its node just changed or ran, and fades to
/// dark (0).
class SignalLamp extends StatelessWidget {
  /// The lamp lit at [level].
  const SignalLamp(this.level, {super.key});

  /// From 0 (dark) to 1 (lit).
  final double level;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 8,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(
          const Color(0xFF3A3D45),
          const Color(0xFF7CFC9A),
          level.clamp(0, 1).toDouble(),
        ),
      ),
    ),
  );
}

/// One line of the list of dependencies.
final class SignalsTreeLine {
  /// The line of [node], [depth] levels in, called [label].
  const SignalsTreeLine(this.node, this.depth, this.label);

  /// A member, an effect, a widget's tracking.
  final Object node;

  /// How far in: 0 for a field.
  final int depth;

  /// What it is called: a widget by its name and rebuilds
  /// (`MatchHeader · 4 rebuilds/5s`).
  final String label;
}

/// The dependencies as a list: each `@Signal` field, under it what read it
/// in its last run (computed values, effects, widgets), and so on.
abstract final class SignalsTree {
  /// The lines of the tree of [beans] as [recorder] saw them.
  static List<SignalsTreeLine> lines(
    SignalsDebugRecorder recorder,
    List<SignalBean> beans,
  ) {
    final lines = <SignalsTreeLine>[];
    final readers = recorder.readers;
    void under(Object node, int depth, Set<Object> seen) {
      if (depth > 6) {
        return;
      }
      for (final MapEntry(key: reader, value: read) in readers.entries) {
        if (read.contains(node) && seen.add(reader)) {
          lines.add(SignalsTreeLine(reader, depth, label(recorder, reader)));
          under(reader, depth + 1, seen);
        }
      }
    }

    for (final bean in beans) {
      for (final member in bean.members.values) {
        if (member is ValueMember) {
          lines.add(SignalsTreeLine(member, 0, member.name));
          under(member, 1, {member});
        }
      }
    }
    return lines;
  }

  /// What the list calls [node]: a member by its name, a widget by its
  /// name and its builds over the read window.
  static String label(SignalsDebugRecorder recorder, Object node) =>
      switch (node) {
        final SignalMember member => member.name,
        final EffectFollower effect => '${effect.name}()',
        final SignalTracking tracking =>
          '${tracking.label} · ${recorder.rebuildsOf(tracking)} rebuilds/'
              '${recorder.readWindow.inSeconds}s',
        _ => '$node',
      };
}
