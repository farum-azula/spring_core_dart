import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_filter.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_marks.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_selection.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_span.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_log_text.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_logs_action.dart';
import 'package:spring_boot_starter_flutter/src/text/selection_controls.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

/// The logs: the records of the logging system's buffer (`logBuffer`),
/// newest first, live, scrolling, each coloured as the console colours it
/// ([debugLogSpan]), filtered by level and text. The filter is the
/// `debugLogFilter` bean: kept while the panel is closed, and the one the
/// debug console shows by.
///
/// The text selects across records, by mouse or touch, and copies with
/// ⌘C (Ctrl+C) or the Copy of its context menu. A long press, or a click
/// with ⇧, ⌘ or Ctrl, marks a whole record and starts the pick mode, in
/// which a tap marks or unmarks one: Copy puts the marked records on the
/// clipboard as the console prints them, without colours; Clear selection
/// ends it. The [actions] (the log export's `Export .log`, `Export
/// .jsonl`) take the marked records, or every record the filter shows.
final class DebugLogsSection implements GroupedDebugPanelSection, Ordered {
  /// The section of [buffer], shown by [filter]; `null`: the app has no
  /// logging system. Records are copied in the pattern of [logging]'s
  /// console.
  const DebugLogsSection(
    this.buffer,
    this.filter, {
    this.logging,
    this.actions = const [],
  });

  /// The records.
  final LogBuffer? buffer;

  /// Which records show.
  final DebugLogFilter filter;

  /// The logging system, whose console pattern the copies are in.
  final LoggingSystem? logging;

  /// What adds buttons to the tab (the log export).
  final List<DebugLogsActions> actions;

  @override
  String get title => 'Logs';

  @override
  int get order => 0;

  @override
  String get group => 'Logs & state';

  @override
  Widget build(BuildContext context) => switch (buffer) {
    final buffer? => _Logs(
      buffer: buffer,
      filter: filter,
      pattern: () => logging?.console.pattern ?? debugLogFallbackPattern,
      actions: [for (final source in actions) ...source.actions],
    ),
    null => Text(
      'No logging system: add spring_boot_starter_logging.',
      style: DebugStyle.of(context).text,
    ),
  };
}

class _Logs extends StatefulWidget {
  const _Logs({
    required this.buffer,
    required this.filter,
    required this.pattern,
    required this.actions,
  });

  final LogBuffer buffer;
  final DebugLogFilter filter;
  final LogPattern Function() pattern;
  final List<DebugLogsAction> actions;

  @override
  State<_Logs> createState() => _LogsState();
}

class _LogsState extends State<_Logs> {
  final _marks = DebugLogMarks();
  // The newest record at the bottom, the list opened there (a jump after
  // the first frame, no animation); scrolled up, the records shown are
  // held, so new ones do not move them, until the bottom is reached again
  // or the buffer is cleared. The list is not reversed: a reversed list
  // breaks the long-press selection of its text.
  final _scroll = ScrollController();
  List<SpringLogRecord>? _held;
  bool _away = false;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
    widget.filter.addListener(_filtered);
    _changes = widget.buffer.onChange.listen((_) => _bufferChanged());
  }

  // The buffer changed: the marks of records it dropped go; cleared, the
  // records held go too.
  void _bufferChanged() {
    final records = widget.buffer.records;
    _marks.prune(records);
    if (_held case final held? when debugLogsHeldGone(held, records)) {
      _held = null;
      _away = false;
    }
  }

  // Another filter: the records it lets through, from the newest.
  void _filtered() {
    _held = null;
    _away = false;
  }

  // Away from the bottom (the newest) by more than a line.
  bool get _awayNow =>
      _scroll.hasClients &&
      _scroll.position.maxScrollExtent - _scroll.offset > 8;

  // At the bottom, kept there as records come: a jump, no animation, and
  // again after each frame in which the end moved, since the rows of
  // many heights are measured only as they come into view.
  void _stickToBottom() {
    if (_away) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom(0));
  }

  static const _bottomJumps = 10;

  void _jumpToBottom(int jumps) {
    if (!mounted || !_scroll.hasClients || _away) {
      return;
    }
    final position = _scroll.position;
    final end = position.maxScrollExtent;
    if (position.pixels != end) {
      _scroll.jumpTo(end);
    }
    if (jumps < _bottomJumps) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _scroll.hasClients &&
            _scroll.position.maxScrollExtent != end) {
          _jumpToBottom(jumps + 1);
        }
      });
    }
  }

  // The end of the list moved (a row measured taller than its estimate):
  // at the bottom, it stays there.
  bool _metricsChanged(ScrollMetricsNotification notification) {
    if (!_away && notification.metrics.extentAfter > 0) {
      _stickToBottom();
    }
    return false;
  }

  void _scrolled() {
    final away = _awayNow;
    if (away != _away) {
      setState(() => _away = away);
    }
  }

  final _region = GlobalKey<SelectableRegionState>();
  String? _notice;
  Timer? _noticeTimer;

  @override
  void dispose() {
    widget.filter.removeListener(_filtered);
    unawaited(_changes?.cancel());
    _scroll
      ..removeListener(_scrolled)
      ..dispose();
    _noticeTimer?.cancel();
    _marks.dispose();
    super.dispose();
  }

  void _show(String notice) {
    _noticeTimer?.cancel();
    setState(() => _notice = notice);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _notice = null);
      }
    });
  }

  // A record picked whole: no text stays selected, not even what the
  // gesture that picked it selected.
  void _mark(SpringLogRecord record) {
    _marks.toggle(record);
    scheduleMicrotask(() => _region.currentState?.clearSelection());
  }

  void _clear() {
    _held = null;
    _away = false;
    widget.buffer.clear();
    _marks.clear();
  }

  Future<void> _copy() async {
    final records = _marks.of(widget.buffer.records);
    await Clipboard.setData(
      ClipboardData(text: debugLogPlainLines(records, widget.pattern())),
    );
    _show(
      'Copied ${records.length} record${records.length == 1 ? '' : 's'}',
    );
  }

  Future<void> _run(DebugLogsAction action) async {
    final all = widget.buffer.records;
    final records = _marks.isEmpty
        ? [
            for (final record in all)
              if (widget.filter.matches(record)) record,
          ]
        : _marks.of(all);
    _show('${action.label}: ${records.length} records…');
    String notice;
    try {
      notice = await action.run(records);
    } on Object catch (error) {
      notice = '${action.label} failed: $error';
    }
    if (mounted) {
      _show(notice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final filter = widget.filter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: filter,
          builder: (context, _) => Wrap(
            children: [
              for (final (label, level) in debugLogLevels)
                DebugChip(
                  label,
                  selected: filter.level == level,
                  onTap: () => filter.level = level,
                ),
              DebugChip('Clear', onTap: _clear),
            ],
          ),
        ),
        DebugFilter(
          initial: filter.text,
          onChanged: (text) => filter.text = text,
        ),
        ListenableBuilder(
          listenable: _marks,
          builder: (context, _) {
            final picking = !_marks.isEmpty;
            if (!picking && widget.actions.isEmpty) {
              return const SizedBox.shrink();
            }
            return Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (picking) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 6),
                    child: Text(
                      '${_marks.count} marked',
                      style: style.text.copyWith(color: style.accent),
                    ),
                  ),
                  DebugChip('Copy', onTap: _copy),
                  DebugChip('Clear selection', onTap: _marks.clear),
                ],
                for (final action in widget.actions)
                  DebugChip(action.label, onTap: () => _run(action)),
              ],
            );
          },
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The selection's handles and menu float in this overlay:
              // the panel is over the app's navigator, outside its own.
              Overlay.wrap(child: _records(style)),
              if (_notice case final notice?)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: _Notice(notice),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _records(DebugStyle style) => ListenableBuilder(
    listenable: Listenable.merge([widget.filter, _marks]),
    builder: (context, _) => StreamBuilder<void>(
      stream: widget.buffer.onChange,
      builder: (context, _) {
        final fresh = [
          for (final record in widget.buffer.records)
            if (widget.filter.matches(record)) record,
        ];
        final records = _away && _held != null ? _held! : fresh;
        _held = records;
        _stickToBottom();
        if (records.isEmpty) {
          return Text('No records', style: style.text);
        }
        final picking = !_marks.isEmpty;
        final list = ListView.builder(
          controller: _scroll,
          itemCount: records.length,
          itemBuilder: (context, i) {
            final record = records[i];
            return _Record(
              record,
              style: style,
              marked: _marks.contains(record),
              picking: picking,
              onMark: () => _mark(record),
            );
          },
        );
        return SelectableRegion(
          key: _region,
          selectionControls: SpringTextSelectionControls.instance,
          contextMenuBuilder: debugLogSelectionMenu,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _metricsChanged,
            child: list,
          ),
        );
      },
    ),
  );
}

class _Record extends StatelessWidget {
  const _Record(
    this.record, {
    required this.style,
    required this.marked,
    required this.picking,
    required this.onMark,
  });

  final SpringLogRecord record;
  final DebugStyle style;
  final bool marked;
  final bool picking;
  final VoidCallback onMark;

  @override
  Widget build(BuildContext context) {
    final text = Text.rich(debugLogSpan(record, style.code, style));
    return Listener(
      // Outside the pick mode a click with ⇧, ⌘ or Ctrl marks; in it, a tap.
      onPointerDown: picking
          ? null
          : (event) {
              if (event.buttons == kPrimaryButton && debugLogPickKeys) {
                onMark();
              }
            },
      child: debugLogPickGestures(
        onPick: onMark,
        tap: picking,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: marked ? style.accent.withValues(alpha: 0.18) : null,
              border: Border(
                left: BorderSide(color: style.level(record.level), width: 2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: text,
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: style.background,
          border: Border.all(color: style.accent),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(text, style: style.text),
        ),
      ),
    );
  }
}
