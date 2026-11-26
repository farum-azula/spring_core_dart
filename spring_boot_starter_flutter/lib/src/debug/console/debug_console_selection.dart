import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_logs_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_logs_action.dart';

/// The selection of the debug console's `logs` pane, at the right of the
/// console's header while the pane shows: `Select` while the pane lets
/// every tap through; while it selects ([LogsPane.selecting]), `N marked · Copy` (the marked
/// records, as the console prints them, without colours), a word per
/// action (`.log`, `.jsonl`: the log export of the marked records, else of
/// those the filter shows) and `Clear`, which ends it. What a copy or an
/// action tells shows in their place for a few seconds.
class DebugConsoleSelectionBar extends StatefulWidget {
  /// The bar of [pane] in [style].
  const DebugConsoleSelectionBar({
    required this.pane,
    required this.style,
    super.key,
  });

  /// The pane.
  final LogsPane pane;

  /// The header's text style.
  final TextStyle style;

  @override
  State<DebugConsoleSelectionBar> createState() =>
      _DebugConsoleSelectionBarState();
}

class _DebugConsoleSelectionBarState extends State<DebugConsoleSelectionBar> {
  String? _notice;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _show(String notice) {
    if (!mounted) {
      return;
    }
    _timer?.cancel();
    setState(() => _notice = notice);
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _notice = null);
      }
    });
  }

  Future<void> _copy() async {
    final pane = widget.pane;
    final records = pane.marks.of(pane.buffer?.records ?? const []);
    await Clipboard.setData(ClipboardData(text: pane.plainText(records)));
    _show('copied ${records.length}');
  }

  Future<void> _run(DebugLogsAction action) async {
    _show('${action.short}…');
    String notice;
    try {
      notice = await action.run(widget.pane.chosenRecords);
    } on Object catch (error) {
      notice = '${action.short} failed: $error';
    }
    _show(notice);
  }

  void _clear() => widget.pane.selecting = false;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final pane = widget.pane;
    final muted = widget.style.copyWith(color: style.muted);
    final active = widget.style.copyWith(color: style.accent);
    Widget word(String text, VoidCallback onTap, {Key? key}) => GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(text, style: active),
    );
    final dot = Text(' · ', style: muted);
    if (_notice case final notice?) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Text(
          notice,
          key: const ValueKey('debug-console-selection-notice'),
          style: muted,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (!pane.selecting) {
      return word(
        'Select',
        () => pane.selecting = true,
        key: const ValueKey('debug-console-select'),
      );
    }
    final count = pane.marks.count;
    return Row(
      key: const ValueKey('debug-console-selection'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count > 0) ...[
          Text('$count marked', style: muted),
          dot,
          word('Copy', _copy),
          dot,
        ],
        for (final action in pane.actions) ...[
          word(action.short, () => _run(action)),
          dot,
        ],
        word('Clear', _clear),
      ],
    );
  }
}
