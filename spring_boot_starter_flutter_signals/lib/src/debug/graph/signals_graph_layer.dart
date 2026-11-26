import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show
        DebugGraphChoice,
        DebugGraphDetail,
        DebugGraphEdge,
        DebugGraphFit,
        DebugGraphKind,
        DebugGraphLayer,
        DebugGraphMemory,
        DebugGraphNode,
        DebugGraphPart,
        DebugGraphRoute,
        DebugGraphRoutes,
        DebugGraphScope,
        DebugGraphSettings,
        DebugGraphShape,
        DebugGraphView,
        DebugStyle,
        WidgetsGraphLayer;
import 'package:spring_boot_starter_flutter_signals/src/debug/signal_widget_names.dart';
import 'package:spring_boot_starter_flutter_signals/src/debug/signals_debug_recorder.dart';
import 'package:spring_boot_starter_flutter_signals/src/debug/signals_rows.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';
import 'package:spring_boot_starter_flutter_signals/src/widgets/signal_build_tracker.dart';

/// The signals as a layer of the application graph (`signalsGraphLayer`):
/// the `@Signal` fields, the `@Computed` values and the `@Effect` methods
/// of the live beans, each bean a lane; the widgets whose build read them
/// (a Spring widget by its name, a `Watch` after the widget it is in), in
/// the `Widgets` lane, the widgets of one type folded into one plate
/// (`ReviewTile ×10`) until tapped open; an edge from what is read to its
/// reader. A field that changes or an effect that runs flashes, and a
/// pulse runs along its edges to its readers.
///
/// With the route grouping of [routes] (the default of the app's graph)
/// the lanes are the navigator stack: the members of a bean go with the
/// bean (the route whose scope holds it, `App` for a singleton), a reader
/// widget with the route it is in.
///
/// It collects only while a view shows it ([start]: the recorder's
/// probe attached, what reads what checked twice a second); its nodes and
/// edges change only when what reads what does. In the build only with
/// the Graph tab, the console's `graph` or `signals` pane, by
/// `spring.flutter.debug.graph.layers` naming `signals` (or `*`, the
/// default).
final class SignalsGraphLayer extends DebugGraphLayer {
  /// The layer of [beans], as [recorder] hears them; with [widgets], each
  /// widget that read state is merged into that layer's node of it when
  /// both show.
  SignalsGraphLayer(this.beans, this.recorder, {this.widgets, this.routes});

  /// The beans with followed state.
  final SignalBeans beans;

  /// What is collected while a view shows.
  final SignalsDebugRecorder recorder;

  /// The widgets layer, when the build has it: a reader widget's node is
  /// the same as its node there ([DebugGraphNode.sameAs]).
  final WidgetsGraphLayer? widgets;

  /// How the graph groups its nodes, and the routes for the route
  /// grouping; `null`: a lane for each bean, one for the readers.
  final DebugGraphRoutes? routes;

  final _Changes _changes = _Changes();
  late final Listenable _merged = routes == null
      ? _changes
      : Listenable.merge([_changes, routes]);
  int _users = 0;
  void Function()? _release;
  Timer? _check;
  int? _signature;

  /// A `@Signal` field.
  static const signal = DebugGraphKind(
    'signal',
    '@Signal',
    DebugGraphShape.rounded,
    description: 'A @Signal field: state that tells its readers it changed',
  );

  /// A `@Computed` value.
  static const computed = DebugGraphKind(
    'computed',
    '@Computed',
    DebugGraphShape.hexagon,
    description:
        'A @Computed value: worked out from other state, again when what '
        'it read changes',
  );

  /// An `@Effect` method.
  static const effect = DebugGraphKind(
    'effect',
    '@Effect',
    DebugGraphShape.parallelogram,
    description: 'An @Effect method: runs again when what it read changes',
  );

  /// A Spring widget that read state.
  static const widget = DebugGraphKind(
    'widget',
    'Spring widget',
    DebugGraphShape.pill,
    description: 'A widget whose build read state: it rebuilds when it changes',
  );

  /// A `Watch` that read state.
  static const watch = DebugGraphKind(
    'watch',
    'Watch',
    DebugGraphShape.tagged,
    description: 'A Watch whose builder read state: only it rebuilds',
  );

  /// Another reader.
  static const reader = DebugGraphKind(
    'reader',
    'reader',
    DebugGraphShape.rectangle,
    description: 'Another reader of state',
  );

  /// The lane of the widgets.
  static const widgetsGroup = 'widgets';

  @override
  String get id => 'signals';

  @override
  String get title => 'Signals';

  @override
  int get order => 20;

  @override
  Color colorOf(DebugStyle style) =>
      style.graphLayer(id, orElse: style.command);

  @override
  String get flashMeaning => 'a signal ticked or an effect ran';

  @override
  List<DebugGraphKind> get kinds => const [
    signal,
    computed,
    effect,
    widget,
    watch,
    reader,
  ];

  @override
  List<DebugGraphChoice> get choices => routes?.choicesOf(this) ?? const [];

  @override
  Listenable get changes => _merged;

  /// Whether a view collects now.
  bool get started => _users > 0;

  @override
  void Function() start() {
    final stopRoutes = routes?.start(this);
    if (_users++ == 0) {
      _release = recorder.use();
      _signature = _signatureNow();
      _check = Timer.periodic(const Duration(milliseconds: 500), (_) {
        final signature = _signatureNow();
        if (signature != _signature) {
          _signature = signature;
          _changes.changed();
        }
      });
    }
    var stopped = false;
    return () {
      if (stopped) {
        return;
      }
      stopped = true;
      stopRoutes?.call();
      if (--_users == 0) {
        _check?.cancel();
        _check = null;
        _release?.call();
        _release = null;
      }
    };
  }

  // Changes when what reads what does: the recorder's structure, the
  // beans and how many members and effects each has.
  int _signatureNow() {
    recorder.pruneEnded();
    var hash = recorder.structure;
    for (final bean in beans.live) {
      hash = Object.hash(
        hash,
        identityHashCode(bean),
        bean.members.length,
        bean.effectRuns.length,
      );
    }
    return hash;
  }

  @override
  void Function() onActivity(VoidCallback wake) => recorder.onActivity(wake);

  @override
  DebugGraphPart collect(DebugGraphScope scope) {
    final nodes = <DebugGraphNode>[];
    final idOf = <Object, String>{};
    final live = beans.live.toList();
    final counts = <String, int>{};
    for (final bean in live) {
      counts[bean.label] = (counts[bean.label] ?? 0) + 1;
    }
    final numbered = <String, int>{};
    final lanes = (routes?.byRoute ?? false) ? routes!.beanLanes() : null;
    void add(DebugGraphNode node, Object key) {
      idOf[key] = node.id;
      nodes.add(node);
    }

    for (final bean in live) {
      final group = counts[bean.label]! > 1
          ? '${bean.label} #${numbered[bean.label] = (numbered[bean.label] ?? 0) + 1}'
          : bean.label;
      final lane = lanes?.ofInstance(bean.bean, bean.scope);
      final (laneKey, laneTitle) = lanes == null
          ? (group, null)
          : (lane?.key, lane?.title);
      for (final member in bean.members.values) {
        final name = member.name.split('.').last;
        add(
          DebugGraphNode(
            id: 'signals:$group.$name',
            layer: id,
            kind: member is ValueMember ? signal.id : computed.id,
            label: name,
            group: laneKey,
            groupTitle: laneTitle,
            groupOrder: lane?.order,
            groupRole: lane?.role,
            source: _Source(member, member: member, bean: bean),
          ),
          member,
        );
      }
      for (final name in bean.effectRuns.keys) {
        // This bean's effect, apart from the same one of another bean.
        final Object key = bean.effectFollowers[name] ?? '$group.$name';
        add(
          DebugGraphNode(
            id: 'signals:$group.$name()',
            layer: id,
            kind: effect.id,
            label: '$name()',
            group: laneKey,
            groupTitle: laneTitle,
            groupOrder: lane?.order,
            groupRole: lane?.role,
            sink: true,
            source: _Source(key, bean: bean, effect: name),
          ),
          key,
        );
      }
    }

    // The widgets and other readers; a widget whose last build read
    // nothing followed is no reader, nor is the effect of a bean that is
    // not shown (closed, or of another application).
    for (final MapEntry(key: reader, value: read) in recorder.readers.entries) {
      if (read.isEmpty ||
          idOf.containsKey(reader) ||
          reader is SignalMember ||
          reader is EffectFollower ||
          (reader is SignalTracking && reader.disposed)) {
        continue;
      }
      final (kind, label, repeat, context) = switch (reader) {
        final NamedSignalTracking tracking => (
          tracking.watch ? watch : widget,
          tracking.label,
          tracking.type,
          tracking.context,
        ),
        SignalTracking() => (widget, 'unnamed widget', 'unnamed widget', null),
        _ => (SignalsGraphLayer.reader, '$reader', null, null),
      };
      final DebugGraphRoute? lane = lanes == null
          ? null
          : context is Element
          ? routes!.laneOf(context)
          : DebugGraphRoute.app;
      add(
        DebugGraphNode(
          id: 'signals:reader:${identityHashCode(reader)}',
          layer: id,
          kind: kind.id,
          label: label,
          group: lane?.key ?? widgetsGroup,
          groupTitle: lane?.title ?? 'Widgets',
          groupOrder: lane?.order,
          groupRole: lane?.role,
          repeatKey: repeat,
          widget: context,
          sameAs: context == null ? null : widgets?.nodeIdOf(context),
          sink: true,
          source: _Source(reader),
        ),
        reader,
      );
    }

    final edges = <DebugGraphEdge>[];
    for (final MapEntry(key: reader, value: read) in recorder.readers.entries) {
      final to = idOf[reader];
      if (to == null) {
        continue;
      }
      for (final member in read) {
        if (idOf[member] case final from? when from != to) {
          edges.add(DebugGraphEdge(from, to));
        }
      }
    }
    return DebugGraphPart(nodes, edges);
  }

  @override
  double glowOf(DebugGraphNode node) => switch (node.source) {
    _Source(:final key) => recorder.lampAt(key, recorder.now),
    _ => 0,
  };

  @override
  bool isLive(DebugGraphNode node, Duration window) {
    final source = node.source;
    if (source is! _Source) {
      return false;
    }
    final at = recorder.litAt(source.key);
    return at != null && recorder.now - at <= window;
  }

  @override
  List<DebugGraphDetail> detailsOf(DebugGraphNode node) {
    final source = node.source;
    if (source is! _Source) {
      return node.details;
    }
    final now = recorder.now;
    final member = source.member;
    final bean = source.bean;
    final effect = source.effect;
    final row = member != null
        ? SignalsRow.member(member, recorder)
        : bean != null && effect != null
        ? SignalsRow.effect(
            bean,
            effect,
            bean.effectRuns[effect] ?? 0,
            recorder,
          )
        : null;
    final key = source.key;
    final window = recorder.readWindow.inSeconds;
    return [
      if (row != null) ...[
        DebugGraphDetail(
          'value',
          row.tone == SignalsValueTone.locked
              ? 'hidden (${row.lock})'
              : row.value,
        ),
        DebugGraphDetail('changed', SignalsValues.ago(row.changedAt, now)),
        if (row.kind == SignalsRowKind.signal)
          DebugGraphDetail('told', SignalsValues.ago(row.toldAt, now)),
        DebugGraphDetail(
          'counts',
          [
            if (row.changes != null) '${row.changes} changes',
            if (row.writes != null) '${row.writes} writes',
            if (row.ticks != null) '${row.ticks} ticks',
            if (row.reads != null) '${row.reads} reads/${window}s',
          ].join(' · '),
        ),
        if (row.timing case final timing?)
          DebugGraphDetail(
            'time',
            '${SignalsValues.took(timing.last)} last · '
                '${SignalsValues.took(timing.average)} avg · '
                '${SignalsValues.took(timing.max)} max',
          ),
        if (row.queue case final queue?) DebugGraphDetail('queue', queue),
      ],
      if (key is SignalTracking) ...[
        DebugGraphDetail(
          'rebuilds',
          '${recorder.rebuildsOf(key)} in ${window}s',
        ),
        DebugGraphDetail(
          'reads',
          [for (final member in recorder.readBy(key)) member.name].join(', '),
        ),
      ],
    ];
  }

  /// What the Signals tab's graph keeps while the app runs (its settings,
  /// place, legend and cards), apart from the console's `signals` pane.
  final DebugGraphMemory viewMemory = DebugGraphMemory();

  /// The application graph of this layer alone, for the Signals tab and
  /// the console's `signals` pane; [compact] for a pane; it keeps its
  /// state in [memory], by default [viewMemory].
  Widget buildView({
    bool compact = false,
    DebugGraphSettings settings = const DebugGraphSettings(),
    DebugGraphMemory? memory,
  }) => DebugGraphView(
    layers: [this],
    compact: compact,
    settings: settings,
    memory: memory ?? viewMemory,
    fit: DebugGraphFit.width,
  );

  /// Frees its notifier (the bean, when it is destroyed).
  void dispose() {
    _check?.cancel();
    _release?.call();
    _changes.dispose();
  }
}

// What a node is to the recorder: its key (a member, an effect of one
// bean, a widget's tracking), and for a member or an effect its bean.
final class _Source {
  const _Source(this.key, {this.member, this.bean, this.effect});

  final Object key;
  final SignalMember? member;
  final SignalBean? bean;
  final String? effect;
}

final class _Changes extends ChangeNotifier {
  void changed() => notifyListeners();
}
