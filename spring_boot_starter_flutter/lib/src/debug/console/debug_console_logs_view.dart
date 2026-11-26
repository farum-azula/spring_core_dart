import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_logs_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_scroll.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_selection.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_selection.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_span.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_text.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/text/selection_controls.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart'
    show LogBuffer, SpringLogRecord;

/// The `logs` pane's widget: the records only, oldest on top, wrapped, in
/// a list that scrolls back through the buffer and follows the newest
/// while scrolled to the bottom. It listens to the buffer and the filter
/// only while it is built, and draws again at most once a frame, however
/// many records come. Taps go through it to the app unless it selects
/// ([LogsPane.selecting]); a scroll over it stays its own. A selection
/// that starts makes [console]'s panes interact.
class DebugConsoleLogsView extends StatefulWidget {
  /// The view of [pane] in [console].
  const DebugConsoleLogsView({
    required this.pane,
    required this.console,
    super.key,
  });

  /// The pane.
  final LogsPane pane;

  /// The console it shows in.
  final DebugConsole console;

  @override
  State<DebugConsoleLogsView> createState() => _DebugConsoleLogsViewState();
}

class _DebugConsoleLogsViewState extends State<DebugConsoleLogsView> {
  final _scroll = ScrollController();
  final _region = GlobalKey<SelectableRegionState>();
  final _records = GlobalKey();
  StreamSubscription<void>? _changes;
  int? _frame;
  bool _following = true;

  // The records shown, newest first; kept while scrolled up.
  List<SpringLogRecord>? _entries;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
    _listen(widget.pane);
  }

  @override
  void didUpdateWidget(DebugConsoleLogsView old) {
    super.didUpdateWidget(old);
    if (old.pane != widget.pane) {
      _forget(old.pane);
      _listen(widget.pane);
      _follow();
    }
  }

  @override
  void dispose() {
    _forget(widget.pane);
    _scroll.dispose();
    super.dispose();
  }

  void _listen(LogsPane pane) {
    _changes = pane.buffer?.onChange.listen((_) => _changed());
    pane.filter.addListener(_filtered);
    pane.addListener(_selected);
    pane.marks.addListener(_schedule);
    _tellPaused(pane, paused: !_following);
  }

  void _forget(LogsPane pane) {
    unawaited(_changes?.cancel());
    _changes = null;
    pane.filter.removeListener(_filtered);
    pane.removeListener(_selected);
    pane.marks.removeListener(_schedule);
    if (_frame case final frame?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
      _frame = null;
    }
  }

  // New records: drawn while following; scrolled up, or selecting, the
  // lines read stay.
  // Cleared, the lines held go too, and the marks of the records the buffer
  // dropped go.
  void _changed() {
    final pane = widget.pane;
    final records = pane.buffer?.records ?? const <SpringLogRecord>[];
    pane.marks.prune(records);
    if (_entries case final held? when debugLogsHeldGone(held, records)) {
      _entries = null;
      _schedule();
      return;
    }
    if (_following && !pane.selecting) {
      _schedule();
    }
  }

  void _filtered() {
    _follow();
    _schedule();
  }

  // Selecting started: the panes interact, so the records take its taps
  // (after ⌥ let go too); ended: no text stays selected, and the panes stay
  // as they are.
  void _selected() {
    if (widget.pane.selecting) {
      widget.console.interaction = DebugConsoleInteraction.interact;
    } else {
      _region.currentState?.clearSelection();
    }
    _schedule();
  }

  void _follow() {
    _setFollowing(true);
    if (_scroll.hasClients && _scroll.offset != 0) {
      _scroll.jumpTo(0);
    }
  }

  void _scrolled() {
    final following = _scroll.offset <= 1;
    if (following != _following) {
      _setFollowing(following);
      _schedule();
    }
  }

  void _setFollowing(bool following) {
    _following = following;
    _tellPaused(widget.pane, paused: !following);
  }

  // The header shows `paused` from [LogsPane.paused]; told while widgets
  // build (a new view), it learns it after the frame.
  static void _tellPaused(LogsPane pane, {required bool paused}) {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) => pane.paused.value = paused);
    } else {
      pane.paused.value = paused;
    }
  }

  // However many changes come, one rebuild in the next frame.
  void _schedule() {
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      if (mounted) {
        setState(() {});
      }
    });
  }

  // The records the filter shows, newest first.
  List<SpringLogRecord> _matching(LogBuffer? buffer) {
    final filter = widget.pane.filter;
    final records = buffer?.records ?? const <SpringLogRecord>[];
    final entries = <SpringLogRecord>[];
    for (var i = records.length - 1; i >= 0; i--) {
      final record = records[i];
      if (filter.matches(record)) {
        entries.add(record);
      }
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final pane = widget.pane;
    final style = DebugStyle.of(context);
    final text = style.code.copyWith(
      height: 1.25,
      decoration: TextDecoration.none,
    );
    final buffer = pane.buffer;
    final entries = _following && !pane.selecting || _entries == null
        ? _entries = _matching(buffer)
        : _entries!;
    Widget note(String value) => Align(
      alignment: Alignment.topLeft,
      child: Text(
        value,
        style: text.copyWith(color: style.muted),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return SizedBox.expand(
      key: const ValueKey('debug-console-logs'),
      child: buffer == null && entries.isEmpty
          ? note('No logging system: add spring_boot_starter_logging.')
          : entries.isEmpty
          ? note('No records')
          : _list(entries, text, style),
    );
  }

  // The record under [position] (global), if any: what a long press or a
  // click with ⇧, ⌘ or Ctrl marks while the records let taps through.
  SpringLogRecord? _recordAt(Offset position) {
    final box = _records.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) {
      return null;
    }
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(position));
    for (final entry in result.path) {
      if (entry.target case RenderMetaData(
        metaData: final SpringLogRecord record,
      )) {
        return record;
      }
    }
    return null;
  }

  void _mark(SpringLogRecord record) {
    widget.pane
      ..selecting = true
      ..marks.toggle(record);
    // A record picked whole: no text stays selected, not even what the
    // gesture that picked it selected.
    scheduleMicrotask(() => _region.currentState?.clearSelection());
  }

  // While the records let taps through, the layer over them still marks
  // one by a long press, or by a click with ⇧, ⌘ or Ctrl; a plain tap
  // stays the app's.
  Map<Type, GestureRecognizerFactory> get _pickGestures => {
    _PickPressRecognizer:
        GestureRecognizerFactoryWithHandlers<_PickPressRecognizer>(
          () => _PickPressRecognizer(_recordAt),
          (recognizer) => recognizer.onLongPressStart = (details) {
            if (_recordAt(details.globalPosition) case final record?) {
              _mark(record);
            }
          },
        ),
    _PickClickRecognizer:
        GestureRecognizerFactoryWithHandlers<_PickClickRecognizer>(
          () => _PickClickRecognizer(_recordAt),
          (recognizer) => recognizer.onTapUp = (details) {
            if (_recordAt(details.globalPosition) case final record?) {
              _mark(record);
            }
          },
        ),
  };

  Widget _list(
    List<SpringLogRecord> entries,
    TextStyle text,
    DebugStyle style,
  ) {
    final pane = widget.pane;
    final selecting = pane.selecting;
    return DebugConsoleScrollArea(
      controller: _scroll,
      interactive: selecting,
      gestures: selecting ? const {} : _pickGestures,
      // The selection's handles and menu float in this overlay: the
      // console is over the app's navigator, outside its own.
      child: Overlay.wrap(
        child: SelectableRegion(
          key: _region,
          selectionControls: SpringTextSelectionControls.instance,
          contextMenuBuilder: debugLogSelectionMenu,
          child: KeyedSubtree(
            key: _records,
            child: ListView.builder(
              key: const ValueKey('debug-console-records'),
              controller: _scroll,
              reverse: true,
              padding: EdgeInsets.zero,
              physics: const ClampingScrollPhysics(),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final record = entries[i];
                return MetaData(
                  metaData: record,
                  behavior: HitTestBehavior.opaque,
                  child: debugLogPickGestures(
                    onPick: () => _mark(record),
                    tap: selecting,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: pane.marks.contains(record)
                              ? style.accent.withValues(alpha: 0.25)
                              : null,
                          border: Border(
                            left: BorderSide(
                              color: style.level(record.level),
                              width: 2,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text.rich(debugLogSpan(record, text, style)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// A long press on a record: one elsewhere does not join the gesture
// arena, so it stays the app's.
class _PickPressRecognizer extends LongPressGestureRecognizer {
  _PickPressRecognizer(this.recordAt) : super(duration: debugLogPickPress);

  final SpringLogRecord? Function(Offset position) recordAt;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      recordAt(event.position) != null && super.isPointerAllowed(event);
}

// A click with ⇧, ⌘ or Ctrl on a record: only such a click joins the
// gesture arena, so every other tap stays the app's.
class _PickClickRecognizer extends TapGestureRecognizer {
  _PickClickRecognizer(this.recordAt);

  final SpringLogRecord? Function(Offset position) recordAt;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      debugLogPickKeys &&
      recordAt(event.position) != null &&
      super.isPointerAllowed(event);
}

/// What the `logs` pane adds at the right of the console's header while
/// it shows: `paused` while its records are scrolled up, then its
/// selection ([DebugConsoleSelectionBar]). Drawn again when either
/// changes.
class DebugConsoleLogsHeader extends StatelessWidget {
  /// The header part of [pane].
  const DebugConsoleLogsHeader({required this.pane, super.key});

  /// The pane.
  final LogsPane pane;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final text = style.code.copyWith(
      height: 1.25,
      decoration: TextDecoration.none,
    );
    return ListenableBuilder(
      listenable: Listenable.merge([pane, pane.marks, pane.paused]),
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pane.paused.value) ...[
            Text('paused', style: text.copyWith(color: style.muted)),
            const SizedBox(width: 8),
          ],
          DebugConsoleSelectionBar(pane: pane, style: text),
        ],
      ),
    );
  }
}
