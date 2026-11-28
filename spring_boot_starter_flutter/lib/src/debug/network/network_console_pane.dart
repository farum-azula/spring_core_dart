import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_pane.dart';
import 'package:spring_boot_starter_flutter/src/debug/console/debug_console_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/debug_network_journal.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_entry.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_format.dart';

/// `network`, the debug console's pane of the network recorder
/// (`networkPane`, order 30): one line per request, newest at the bottom
/// (`GET  /api/user  200  120 ms  1.2 KB`), the method in the debug
/// theme's `method-read` or `method-write`, the status good, warning or
/// bad, a time of a second or more in the warning colour; a WebSocket on
/// one line with its uptime and last heartbeat round trip. Scrolled up it
/// stops following and keeps the lines read; scrolled back to the bottom
/// it follows again. A tap on a line shows it in one line under them,
/// with a hint to the panel's Network tab when the build has it.
///
/// Built only while shown, it listens to [journal] only then, and draws
/// at most once a frame (once a second more while something is in
/// flight). In the build only with the console,
/// `spring.flutter.debug.console.panes` naming `network` (or `*`) and
/// `spring.flutter.debug.network.enabled: true`.
final class NetworkConsolePane extends DebugConsolePane {
  /// The pane of [journal]; [hasNetworkTab] when the panel has the
  /// Network tab.
  const NetworkConsolePane(this.journal, {this.hasNetworkTab = false});

  /// The traffic recorded.
  final DebugNetworkJournal journal;

  /// Whether the debug panel has the Network tab, for the hint.
  final bool hasNetworkTab;

  @override
  String get title => 'Network';

  @override
  Widget build(BuildContext context, DebugConsole console) =>
      NetworkConsoleView(journal: journal, hasNetworkTab: hasNetworkTab);
}

/// The lines of the `network` pane ([NetworkConsolePane]).
class NetworkConsoleView extends StatefulWidget {
  /// The lines of [journal].
  const NetworkConsoleView({
    required this.journal,
    this.hasNetworkTab = false,
    super.key,
  });

  /// The traffic recorded.
  final DebugNetworkJournal journal;

  /// Whether the debug panel has the Network tab.
  final bool hasNetworkTab;

  /// A line's height.
  static const double lineExtent = DebugConsoleView.lineHeight + 2;

  /// A time this long or longer is drawn as a warning.
  static const slowAfter = Duration(seconds: 1);

  /// The key of the line of the entry [id].
  static Key lineKey(int id) => ValueKey('debug-console-network-$id');

  /// The key of the line under the list: a line tapped, or the pause.
  static const Key statusKey = ValueKey('debug-console-network-status');

  @override
  State<NetworkConsoleView> createState() => _NetworkConsoleViewState();
}

class _NetworkConsoleViewState extends State<NetworkConsoleView> {
  final _scroll = ScrollController();
  Timer? _tick;
  bool _following = true;
  int? _selected;

  // The entries shown, newest first; kept while scrolled up.
  List<NetworkEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _scrolled() {
    final following = _scroll.offset <= 1;
    if (following != _following) {
      setState(() => _following = following);
    }
  }

  // Once a second while following something in flight, nothing otherwise.
  void _ticking(bool live) {
    if (live && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (!live && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.journal,
    builder: (context, _) {
      final style = DebugStyle.of(context);
      final text = style.code.copyWith(
        height: 1.25,
        decoration: TextDecoration.none,
      );
      final now = DateTime.now();
      final entries = _following || _entries == null
          ? _entries = widget.journal.entries.reversed.toList(growable: false)
          : _entries!;
      _ticking(_following && entries.any((entry) => !entry.isDone));
      final selected = _selected == null
          ? null
          : entries.where((entry) => entry.id == _selected).firstOrNull;
      final status = selected != null
          ? _detail(selected, now)
          : _following
          ? null
          : 'paused: scroll to the bottom to follow';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: entries.isEmpty
                ? Text(
                    'No requests yet',
                    style: text.copyWith(color: style.muted),
                  )
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    itemExtent: NetworkConsoleView.lineExtent,
                    itemCount: entries.length,
                    itemBuilder: (context, i) => _Line(
                      entries[i],
                      now: now,
                      text: text,
                      selected: entries[i].id == _selected,
                      onTap: () => setState(
                        () => _selected = _selected == entries[i].id
                            ? null
                            : entries[i].id,
                      ),
                    ),
                  ),
          ),
          if (status != null)
            Text(
              status,
              key: NetworkConsoleView.statusKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.copyWith(color: style.muted),
            ),
        ],
      );
    },
  );

  // A line tapped, in one line.
  String _detail(NetworkEntry entry, DateTime now) {
    final parts = switch (entry) {
      final HttpCall exchange => [
        '${exchange.method} ${exchange.url}',
        exchange.status,
        if (exchange.firstByte case final firstByte?)
          'first byte ${NetworkFormat.duration(firstByte)}',
        'total ${NetworkFormat.duration(exchange.totalTime)}',
        'sent ${NetworkFormat.bytes(exchange.requestSize)}',
        'received ${NetworkFormat.bytes(exchange.responseSize)}',
        ?exchange.error,
      ],
      final WebSocketConnection connection => [
        'WS ${connection.url}',
        connection.status,
        'connect ${NetworkFormat.duration(connection.connectTime)}',
        if (connection.uptime(now) case final uptime?)
          'up ${NetworkFormat.uptime(uptime)}',
        if (connection.lastLatency case final latency?)
          'heartbeat ${NetworkFormat.duration(latency)}',
        if (connection.reconnects > 0) 'reconnect ${connection.reconnects}',
        '${connection.framesIn} in, ${connection.framesOut} out',
        ?connection.closeReason,
        ?connection.error,
      ],
    };
    return [
      ...parts,
      if (widget.hasNetworkTab) 'more in the panel\'s Network tab',
    ].join(' · ');
  }
}

class _Line extends StatelessWidget {
  _Line(
    this.entry, {
    required this.now,
    required this.text,
    required this.selected,
    required this.onTap,
  }) : super(key: NetworkConsoleView.lineKey(entry.id));

  final NetworkEntry entry;
  final DateTime now;
  final TextStyle text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final (time, slow, last) = switch (entry) {
      final WebSocketConnection connection => (
        connection.opened
            ? NetworkFormat.uptime(connection.uptime(now))
            : NetworkFormat.duration(connection.duration),
        false,
        switch (connection.lastLatency) {
          final latency? => '${NetworkFormat.duration(latency)} ws',
          null => NetworkFormat.bytes(connection.received),
        },
      ),
      final exchange => (
        NetworkFormat.duration(exchange.duration),
        (exchange.duration ?? Duration.zero) >= NetworkConsoleView.slowAfter,
        exchange.isDone || exchange.received > 0
            ? NetworkFormat.bytes(exchange.received)
            : '…',
      ),
    };
    Widget cell(String value, double width, Color color) => SizedBox(
      width: width,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.right,
        style: text.copyWith(color: color),
      ),
    );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: selected ? style.line : const Color(0x00000000),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                entry.method,
                maxLines: 1,
                style: text.copyWith(
                  color: NetworkFormat.method(entry.method, style),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                NetworkFormat.path(entry),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.copyWith(color: style.foreground),
              ),
            ),
            cell(
              entry.status,
              36,
              NetworkFormat.status(entry.statusClass, style),
            ),
            cell(time, 64, slow ? style.warning : style.muted),
            cell(last, 72, style.muted),
          ],
        ),
      ),
    );
  }
}
