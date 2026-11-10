import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart'
    show IsolateLoad, IsolateLoads;
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/isolate_loads_watch.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/isolates_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_handler.dart';
import 'package:spring_boot_starter_flutter/src/shortcuts/shortcut_invocation.dart';

/// The task manager of the app's isolates and the engine's threads (the
/// `debugIsolates` bean): a small table over the app with a line per row
/// of `isolateLoads` ([DebugIsolatesGauge]): how busy each is and how
/// late it answers. The debug panel's Isolates tab has every value.
///
/// The action `debug.isolates` shows or hides it: by default ⌘⇧I
/// (Ctrl+Shift+I) or seven quick taps and an eighth held two seconds;
/// `spring.flutter.shortcuts.debug.isolates` names other keys or taps.
/// The debug panel's Isolates tab switches it too.
///
/// The [rows] are read only while a widget shows them, so the isolates
/// and the engine are measured only then.
class DebugIsolates extends ChangeNotifier
    implements KeyedShortcutHandler, DebugOverlay {
  /// The task manager of [loads], hidden, in the corner [position], read
  /// every [interval] while it shows.
  DebugIsolates({
    required IsolateLoads loads,
    Duration interval = const Duration(seconds: 1),
    this._position = DebugOverlayCorner.bottomRight,
  }) : rows = IsolateLoadsWatch(loads, interval: interval);

  /// The rows, read while a widget listens.
  final IsolateLoadsWatch rows;

  DebugOverlayCorner _position;
  bool _shown = false;

  @override
  String get action => 'debug.isolates';

  @override
  List<String> get keys => const ['primary+shift+i', 'taps:7+hold:2s'];

  @override
  bool handle(ShortcutInvocation invocation) {
    shown = !shown;
    return true;
  }

  @override
  String get id => 'isolates';

  @override
  String get title => 'Isolates';

  @override
  DebugOverlayCorner get corner => _position;

  /// Moves the table to [value].
  set corner(DebugOverlayCorner value) {
    if (value != _position) {
      _position = value;
      notifyListeners();
    }
  }

  @override
  int get order => 20;

  @override
  bool get shown => _shown;

  @override
  set shown(bool value) {
    if (value != _shown) {
      _shown = value;
      notifyListeners();
    }
  }

  /// As high as the rows read last, four before the first read.
  @override
  Size get size => DebugIsolatesGauge.sizeOf(
    rows.value.isEmpty ? 4 : rows.value.length,
  );

  @override
  Widget build(BuildContext context) => DebugIsolatesGauge(rows: rows);

  @override
  void dispose() {
    rows.dispose();
    super.dispose();
  }
}

/// The task manager's small table: a line per row with its name, a bar
/// and a percentage of how busy it is, and its lag. At most [maxRows]
/// lines, then how many more there are, so it fits a phone.
class DebugIsolatesGauge extends StatelessWidget {
  /// The table of [rows].
  const DebugIsolatesGauge({required this.rows, super.key});

  /// The width of the table.
  static const double width = 200;

  /// The most rows shown.
  static const int maxRows = 8;

  static const double _line = 15;
  static const _padding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);

  /// The room a table of [count] rows takes.
  static Size sizeOf(int count) => Size(
    width,
    _padding.vertical + _line * count.clamp(1, maxRows + 1),
  );

  /// The rows, listened to while the table shows.
  final ValueListenable<List<IsolateLoad>> rows;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final text = style.code.copyWith(fontSize: 10, height: 1.2);
    return Container(
      width: width,
      padding: _padding,
      decoration: BoxDecoration(
        color: style.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListenableBuilder(
        listenable: rows,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final load in rows.value.take(maxRows))
              SizedBox(
                height: _line,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        load.name,
                        style: text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 4,
                      child: IsolateBusyBar(load.busy),
                    ),
                    SizedBox(
                      width: 34,
                      child: Text(
                        formatIsolateBusy(load.busy),
                        style: text,
                        maxLines: 1,
                        textAlign: TextAlign.end,
                      ),
                    ),
                    SizedBox(
                      width: 46,
                      child: Text(
                        formatIsolateLag(load.lag),
                        style: text.copyWith(color: style.muted),
                        maxLines: 1,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
            if (rows.value.length > maxRows)
              SizedBox(
                height: _line,
                child: Text(
                  '… ${rows.value.length - maxRows} more',
                  style: text.copyWith(color: style.muted),
                  maxLines: 1,
                ),
              ),
            if (rows.value.isEmpty)
              SizedBox(
                height: _line,
                child: Text(
                  'no isolates',
                  style: text.copyWith(color: style.muted),
                  maxLines: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
