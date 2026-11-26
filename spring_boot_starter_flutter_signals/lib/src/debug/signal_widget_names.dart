import 'dart:collection';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugGraphWidgets, SpringStatefulWidget, SpringStatelessWidget;
import 'package:spring_boot_starter_flutter_signals/src/widgets/signal_build_tracker.dart';
import 'package:spring_boot_starter_flutter_signals/src/widgets/watch.dart';

/// Names the Spring widgets whose builds the signals follow, for the
/// Signals tab: by their type (`MatchHeader`), and a widget shown more
/// than once by its key (`ReviewTile [42]`) or a number (`ReviewTile #3`).
///
/// A `Watch` is named after the widget it is in (`Watch in PageBackdrop`):
/// the nearest Spring widget above it, else the nearest widget of the
/// application's.
///
/// It names widgets only while a debug tool collects ([start], by the
/// `signalsDebugRecorder` while one shows, to [stop]): while every tool is
/// closed a widget's tracking keeps its element alone, and no name, type,
/// key or number is worked out. When a tool starts, every Spring widget
/// and `Watch` on the screen is built once again ([refreshAll]) and named
/// as it builds: what a widget read before the tool showed is not heard
/// otherwise, and a widget under the debug panel is not built again by it.
///
/// The `signalWidgetNames` bean, in the debug modules of the signals (the
/// Signals tab's, the console's `signals` pane's, the graph's) while one
/// of their views is in the running app: an application without them has
/// neither this class nor anything kept for any widget.
final class SignalWidgetNames {
  /// The names; numbers are given per type and reused once free.
  SignalWidgetNames();

  /// The names of the running application, for the widgets that make their
  /// own tracking (`Watch`); set by [install], `null` without the debug
  /// tools in the build.
  static SignalWidgetNames? current;

  final Map<String, int> _next = {};
  final Map<String, SplayTreeSet<int>> _free = {};
  final Map<String, int> _live = {};
  int _starts = 0;

  /// Whether it names the widgets as they build: between a [start] and its
  /// [stop].
  bool get naming => _starts > 0;

  /// Makes these the [current] names (the bean, when it is made).
  void install() => current = this;

  /// No longer the [current] names (the bean, when it is destroyed).
  void uninstall() {
    if (identical(current, this)) {
      current = null;
    }
  }

  /// Names the widgets from now on, and has those on the screen built once
  /// again ([refreshAll]): a debug tool started collecting. Each call is
  /// ended by a [stop].
  void start() {
    if (_starts++ == 0) {
      refreshAll();
    }
  }

  /// Ends a [start]: after the last, no more widgets are named as they
  /// build. Those named keep their names while they are on the screen.
  void stop() {
    if (_starts > 0) {
      _starts--;
    }
  }

  /// The tracking of the widget of [widget], named after it once it
  /// builds while [naming]; with [watch], the tracking of a `Watch`.
  NamedSignalTracking track(
    VoidCallback rebuild,
    BuildContext widget, {
    bool watch = false,
  }) => NamedSignalTracking._(rebuild, this, context: widget, watch: watch);

  /// The tracking of the `Watch` of [widget]: `Watch in PageBackdrop`, or
  /// `Watch` alone at the root of the tree.
  NamedSignalTracking trackWatch(VoidCallback rebuild, BuildContext widget) =>
      track(rebuild, widget, watch: true);

  /// Has every Spring widget and `Watch` on the screen built once again,
  /// after the frame when called during one: a debug tool that starts
  /// collecting hears what each reads.
  void refreshAll() {
    final WidgetsBinding binding;
    try {
      binding = WidgetsBinding.instance;
    } on Object {
      return;
    }
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding
        ..addPostFrameCallback((_) => _markReaders(binding.rootElement))
        ..ensureVisualUpdate();
      return;
    }
    _markReaders(binding.rootElement);
  }

  static void _markReaders(Element? root) {
    void visit(Element element) {
      final shown = element.widget;
      if (shown is SpringStatelessWidget ||
          shown is SpringStatefulWidget ||
          shown is Watch) {
        element.markNeedsBuild();
      }
      element.visitChildren(visit);
    }

    root?.visitChildren(visit);
  }

  /// The type of the widget [widget] is in: the nearest Spring widget,
  /// else the nearest stateless or stateful widget that is not one of the
  /// framework's builders, else the nearest widget of a public type
  /// (`Column`); `null` only at the root.
  static String? ownerOf(BuildContext widget) {
    String? spring;
    String? plain;
    String? any;
    var depth = 0;
    widget.visitAncestorElements((ancestor) {
      final shown = ancestor.widget;
      if (shown is SpringStatelessWidget || shown is SpringStatefulWidget) {
        spring = '${shown.runtimeType}';
        return false;
      }
      final type = '${shown.runtimeType}';
      final named = !DebugGraphWidgets.isBuilderType(type);
      if (plain == null &&
          named &&
          (shown is StatelessWidget || shown is StatefulWidget)) {
        plain = type;
      }
      if (any == null && named && !type.startsWith('_')) {
        any = type;
      }
      return ++depth < 80;
    });
    return spring ?? plain ?? any;
  }

  // The name of [tracking], worked out once: its type, key and number,
  // the number taken among the widgets of its type on the screen. A widget
  // that left the screen before it was named is only its kind.
  _WidgetName _nameOf(NamedSignalTracking tracking) {
    final context = tracking.context;
    if (!context.mounted) {
      return _WidgetName(tracking.watch ? 'Watch' : 'a widget', null, 0);
    }
    final shown = context.widget;
    final type = tracking.watch
        ? switch (ownerOf(context)) {
            final owner? => 'Watch in $owner',
            null => 'Watch',
          }
        : '${shown.runtimeType}';
    _live[type] = (_live[type] ?? 0) + 1;
    return _WidgetName(type, keyLabel(shown.key), _take(type), counted: true);
  }

  // The smallest free number of [type].
  int _take(String type) {
    final free = _free[type];
    if (free != null && free.isNotEmpty) {
      final number = free.first;
      free.remove(number);
      return number;
    }
    return _next[type] = (_next[type] ?? 0) + 1;
  }

  /// How many named widgets of [type] are on the screen.
  int liveOf(String type) => _live[type] ?? 0;

  void _release(String type, int number) {
    final live = (_live[type] ?? 1) - 1;
    if (live <= 0) {
      _live.remove(type);
      _free.remove(type);
      _next.remove(type);
      return;
    }
    _live[type] = live;
    (_free[type] ??= SplayTreeSet<int>()).add(number);
  }

  /// What a widget's [key] adds to its name: a [ValueKey] of a number, an
  /// enum or a short plain word, never another key (an object's, a global
  /// one) nor a text that could be data (spaces, `@`, longer than 24).
  static String? keyLabel(Key? key) => switch (key) {
    ValueKey<Object?>(value: final int value) => '$value',
    ValueKey<Object?>(value: final Enum value) => value.name,
    ValueKey<Object?>(value: final String value)
        when _plainWord.hasMatch(value) =>
      value,
    _ => null,
  };

  static final RegExp _plainWord = RegExp(r'^[A-Za-z0-9_.:\-]{1,24}$');
}

// What a widget is called: its type, what its key says, its number among
// the widgets of its type ([counted] when it holds one of them).
final class _WidgetName {
  _WidgetName(this.type, this.key, this.number, {this.counted = false});

  final String type;
  final String? key;
  final int number;
  final bool counted;
}

/// The followed reads of one widget's `build`, with the widget's name:
/// what [SignalWidgetNames] makes. The name is worked out when the widget
/// first builds while a debug tool collects, or when it is first asked
/// for.
final class NamedSignalTracking extends SignalTracking {
  NamedSignalTracking._(
    super.rebuild,
    this._names, {
    required this.context,
    required this.watch,
  });

  final SignalWidgetNames _names;
  _WidgetName? _name;
  bool _released = false;

  /// The widget's element, for the application graph's "On screen" scope:
  /// kept while the widget is on the screen, as the tracking is.
  final BuildContext context;

  /// Whether it is a `Watch`'s, not a Spring widget's.
  final bool watch;

  _WidgetName get _named => _name ??= _names._nameOf(this);

  /// The widget's type: `ReviewTile`.
  String get type => _named.type;

  /// What its key says, when it says something to show ([SignalWidgetNames.keyLabel]).
  String? get key => _named.key;

  /// Its number among the widgets of its [type] on the screen, from 1.
  int get number => _named.number;

  /// `ReviewTile [42]` by its key, `ReviewTile #3` while more than one is
  /// on the screen, else `ReviewTile`.
  @override
  String get label => switch (key) {
    final key? => '$type [$key]',
    _ when _names.liveOf(type) > 1 => '$type #$number',
    _ => type,
  };

  @override
  T track<T>(T Function() build) {
    if (_name == null && _names.naming) {
      _named;
    }
    return super.track(build);
  }

  @override
  void dispose() {
    super.dispose();
    if (_name case final name? when name.counted && !_released) {
      _released = true;
      _names._release(name.type, name.number);
    }
  }
}
