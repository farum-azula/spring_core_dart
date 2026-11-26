import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/debug_network_filter.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/debug_network_journal.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_detail.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_entry.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_format.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_waterfall.dart';

/// The Network tab's content: the chips of the [filter] (method, status),
/// Pause and Clear, the address filter, and the entries of [journal]
/// newest first, one row each (method, path, status, time, size) over its
/// bar in the waterfall of the entries shown ([NetworkWaterfall]); a
/// WebSocket's row adds its handshake time, uptime, last heartbeat round
/// trip and reconnects. A tap opens one ([NetworkDetail]), Back returns to
/// the list. It rebuilds at most once a frame, when the journal or the
/// filter changes, and once a second while an entry is in flight (the
/// uptimes and the bars of what is in flight grow).
class NetworkView extends StatefulWidget {
  /// The view of [journal] by [filter].
  const NetworkView({required this.journal, required this.filter, super.key});

  /// The traffic.
  final DebugNetworkJournal journal;

  /// Which entries show.
  final DebugNetworkFilter filter;

  /// The key of the row of the entry [id].
  static Key rowKey(int id) => ValueKey('debug-network-row-$id');

  /// The key of the waterfall bar of the entry [id].
  static Key barKey(int id) => ValueKey('debug-network-bar-$id');

  /// The key of the timings line of the WebSocket [id].
  static Key socketKey(int id) => ValueKey('debug-network-socket-$id');

  @override
  State<NetworkView> createState() => _NetworkViewState();
}

class _NetworkViewState extends State<NetworkView> {
  int? _selected;
  Timer? _tick;

  // Once a second while something is in flight, nothing otherwise.
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
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = widget.journal;
    final filter = widget.filter;
    return ListenableBuilder(
      listenable: Listenable.merge([journal, filter]),
      builder: (context, _) {
        final style = DebugStyle.of(context);
        final now = DateTime.now();
        _ticking(journal.entries.any((entry) => !entry.isDone));
        final selected = _selected == null
            ? null
            : journal.entries.where((e) => e.id == _selected).firstOrNull;
        if (selected != null) {
          return NetworkDetail(
            entry: selected,
            now: now,
            bodies: journal.bodies,
            onBack: () => setState(() => _selected = null),
          );
        }
        final entries = [
          for (final entry in journal.entries.reversed)
            if (filter.matches(entry)) entry,
        ];
        final waterfall = NetworkWaterfall(entries, now);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              children: [
                DebugChip(
                  'All',
                  selected: filter.method == null,
                  onTap: () => filter.method = null,
                ),
                for (final method in filter.methodsOf(journal.entries))
                  DebugChip(
                    method,
                    selected: filter.method == method,
                    onTap: () => filter.method = method,
                  ),
              ],
            ),
            Wrap(
              children: [
                for (final status in NetworkStatusFilter.values)
                  DebugChip(
                    status.label,
                    selected: filter.status == status,
                    onTap: () => filter.status = status,
                  ),
                DebugChip(
                  journal.paused ? 'Resume' : 'Pause',
                  selected: journal.paused,
                  onTap: () => journal.paused = !journal.paused,
                ),
                DebugChip('Clear', onTap: journal.clear),
              ],
            ),
            DebugFilter(
              initial: filter.text,
              onChanged: (text) => filter.text = text,
            ),
            Expanded(
              child: entries.isEmpty
                  ? Text(
                      journal.entries.isEmpty
                          ? 'No requests yet'
                          : 'No request matches',
                      style: style.text.copyWith(color: style.muted),
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, i) => _Row(
                        entries[i],
                        bar: waterfall.barOf(entries[i]),
                        now: now,
                        onTap: () => setState(() => _selected = entries[i].id),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  _Row(this.entry, {required this.bar, required this.now, required this.onTap})
    : super(key: NetworkView.rowKey(entry.id));

  final NetworkEntry entry;
  final WaterfallBar bar;
  final DateTime now;
  final VoidCallback onTap;

  String get _time => switch (entry) {
    final WebSocketConnection connection when connection.opened =>
      NetworkFormat.uptime(connection.uptime(now)),
    _ => NetworkFormat.duration(entry.duration),
  };

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final code = style.code;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: style.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _line(style, code),
            if (entry case final WebSocketConnection connection)
              Padding(
                padding: const EdgeInsets.only(left: 58, top: 1),
                child: Text(
                  _socketTimings(connection),
                  key: NetworkView.socketKey(entry.id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: code.copyWith(color: style.muted),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: SizedBox(
                height: 3,
                child: CustomPaint(
                  key: NetworkView.barKey(entry.id),
                  painter: WaterfallBarPainter(bar, style),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The handshake, the uptime, the last heartbeat and the reconnects.
  String _socketTimings(WebSocketConnection connection) => [
    'connect ${NetworkFormat.duration(connection.connectTime)}',
    if (connection.opened)
      '${connection.isDone ? 'was up' : 'up'} '
          '${NetworkFormat.uptime(connection.uptime(now))}',
    if (connection.lastLatency case final latency?)
      'heartbeat ${NetworkFormat.duration(latency)}',
    if (connection.reconnects > 0) 'reconnect ${connection.reconnects}',
  ].join(' · ');

  Widget _line(DebugStyle style, TextStyle code) => Row(
    children: [
      SizedBox(
        width: 58,
        child: Text(
          entry.method,
          style: code.copyWith(
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
          style: code,
        ),
      ),
      SizedBox(
        width: 44,
        child: Text(
          entry.status,
          textAlign: TextAlign.right,
          style: code.copyWith(
            color: NetworkFormat.status(entry.statusClass, style),
          ),
        ),
      ),
      SizedBox(
        width: 70,
        child: Text(
          _time,
          textAlign: TextAlign.right,
          style: code.copyWith(color: style.muted),
        ),
      ),
      SizedBox(
        width: 70,
        child: Text(
          entry.isDone || entry.received > 0
              ? NetworkFormat.bytes(entry.received)
              : '…',
          textAlign: TextAlign.right,
          style: code.copyWith(color: style.muted),
        ),
      ),
    ],
  );
}
