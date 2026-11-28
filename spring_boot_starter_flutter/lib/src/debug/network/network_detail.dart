import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_entry.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_format.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_waterfall.dart';

/// One entry of the Network tab opened: the address, the status, the
/// timings and the sizes, the error, then for an HTTP exchange its phases
/// (the browser's on the web when it gives them; else the wait for the
/// headers and the body of a streamed one; else the whole), the request's
/// and the response's headers (masked) and bodies (JSON indented), for a
/// WebSocket its handshake time, uptime, reconnects, close, heartbeat
/// round trips, the handshake's headers, the channels joined and the
/// frames each way with their times. Back ([onBack]) returns to the list.
class NetworkDetail extends StatelessWidget {
  /// [entry] in full, what is in flight measured to [now] (the time it
  /// is built by default); [bodies] is whether bodies are recorded.
  const NetworkDetail({
    required this.entry,
    required this.onBack,
    this.now,
    this.bodies = true,
    super.key,
  });

  /// The entry.
  final NetworkEntry entry;

  /// Whether bodies are recorded (`spring.flutter.debug.network.bodies`):
  /// without, each body says so in its place.
  final bool bodies;

  /// The time what is in flight is measured to.
  final DateTime? now;

  /// Called by Back.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final entry = this.entry;
    final now = this.now ?? DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(children: [DebugChip('Back', onTap: onBack)]),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${entry.method} ',
                style: TextStyle(
                  color: NetworkFormat.method(entry.method, style),
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(text: '${entry.url}'),
            ],
          ),
          style: style.code,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: switch (entry) {
              final HttpCall exchange => _http(exchange, style, now),
              final WebSocketConnection connection => _webSocket(
                connection,
                style,
                now,
              ),
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _http(HttpCall exchange, DebugStyle style, DateTime now) {
    final browser = exchange.resourceTiming;
    final phases = exchange.phases(now);
    return [
      _Facts([
        (
          'Status',
          exchange.status,
          NetworkFormat.status(exchange.statusClass, style),
        ),
        ('State', exchange.state.name, null),
        ('Started', NetworkFormat.clock(exchange.started), null),
        if (exchange.firstByte case final firstByte?)
          (
            'First byte',
            '${NetworkFormat.duration(firstByte)}'
                '${exchange.headersTime == null ? ' (browser)' : ''}',
            null,
          ),
        ('Total', NetworkFormat.duration(exchange.totalTime), null),
        ('Sent', NetworkFormat.bytes(exchange.requestSize), null),
        ('Received', NetworkFormat.bytes(exchange.responseSize), null),
        if (exchange.streamed) ('Body', 'streamed', null),
        if (browser?.protocol case final protocol?)
          ('Protocol', protocol, null),
      ]),
      if (exchange.error case final error?)
        _Block('Error', error, color: style.bad),
      if (phases.length > 1) ...[_Title('Timing'), _Phases(phases)],
      if (browser != null && browser.restricted)
        _Note(
          'The browser hides the phases of this response: its origin sends '
          'no Timing-Allow-Origin',
        )
      else if (exchange.firstByte == null && exchange.isDone)
        _Note(
          'The first byte is measured for a streamed response, and on the '
          'web from the browser when it gives it; a whole response is '
          'handed over at once',
        ),
      _Headers('Request headers', exchange.requestHeaders),
      if (exchange.requestBody case final body?)
        _Body('Request body', body)
      else if (!bodies)
        const _NotRecorded(),
      _Headers('Response headers', exchange.responseHeaders),
      if (exchange.responseBody case final body?)
        _Body('Response body', body)
      else if (!bodies)
        const _NotRecorded(),
    ];
  }

  List<Widget> _webSocket(
    WebSocketConnection connection,
    DebugStyle style,
    DateTime now,
  ) => [
    _Facts([
      (
        'Status',
        connection.status,
        NetworkFormat.status(connection.statusClass, style),
      ),
      ('Started', NetworkFormat.clock(connection.started), null),
      if (connection.connectTime != null)
        ('Connect', NetworkFormat.duration(connection.connectTime), null),
      if (connection.connectedAt case final at?)
        ('Connected at', NetworkFormat.clock(at), null),
      if (connection.uptime(now) case final uptime?)
        (
          connection.closedAt == null ? 'Uptime' : 'Was up',
          NetworkFormat.uptime(uptime),
          null,
        ),
      (
        'Reconnects',
        connection.reconnects == 0
            ? 'none (the first connection to this address)'
            : '${connection.reconnects} (connection ${connection.attempt} '
                  'to this address)',
        null,
      ),
      if (connection.closedAt case final at?)
        ('Closed at', NetworkFormat.clock(at), null),
      if (connection.closeCode case final code?) ('Close code', '$code', null),
      if (connection.closeReason case final reason?) ('Reason', reason, null),
      if (connection.closeCode != null)
        (
          'Closed by',
          connection.closedByClient ? 'the app' : 'the server',
          null,
        ),
      if (connection.acceptedProtocol case final protocol?)
        ('Protocol', protocol, null),
      (
        'In',
        '${connection.framesIn} frames, '
            '${NetworkFormat.bytes(connection.bytesIn)}',
        null,
      ),
      (
        'Out',
        '${connection.framesOut} frames, '
            '${NetworkFormat.bytes(connection.bytesOut)}',
        null,
      ),
      if (connection.channels.isNotEmpty)
        ('Channels', connection.channels.join(', '), null),
      if (connection.lastLatency case final latency?)
        ('Heartbeat', NetworkFormat.duration(latency), null),
    ]),
    if (connection.error case final error?)
      _Block('Error', error, color: style.bad),
    if (connection.latencies.isNotEmpty) _Latencies(connection.latencies),
    _Headers('Handshake headers', connection.requestHeaders),
    _Title('Frames'),
    for (final frame in connection.frames.reversed)
      _Frame(frame, connection.timeOf(frame)),
  ];
}

class _Title extends StatelessWidget {
  const _Title(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        title,
        style: style.text.copyWith(
          color: style.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts(this.facts);

  final List<(String, String, Color?)> facts;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (name, value, color) in facts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    name,
                    style: style.code.copyWith(color: style.muted),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: style.code.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Headers extends StatelessWidget {
  const _Headers(this.title, this.headers);

  final String title;
  final List<NetworkHeader> headers;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title(title),
        if (headers.isEmpty)
          Text('none', style: style.code.copyWith(color: style.muted)),
        for (final header in headers)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${header.name}: ',
                  style: TextStyle(color: style.logger),
                ),
                TextSpan(
                  text: header.value,
                  style: header.masked ? TextStyle(color: style.muted) : null,
                ),
              ],
            ),
            style: style.code,
          ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.title, this.body);

  final String title;
  final NetworkBody body;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final text = body.pretty;
    final size = body.truncated
        ? '${NetworkFormat.bytes(body.kept)} of ${NetworkFormat.bytes(body.length)}'
        : NetworkFormat.bytes(body.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title('$title ($size)'),
        Text(
          text ?? 'binary',
          style: style.code.copyWith(color: text == null ? style.muted : null),
        ),
      ],
    );
  }
}

class _NotRecorded extends StatelessWidget {
  const _NotRecorded();

  @override
  Widget build(BuildContext context) =>
      const _Note('Body — not recorded (spring.flutter.debug.network.bodies)');
}

class _Block extends StatelessWidget {
  const _Block(this.title, this.text, {this.color});

  final String title;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title(title),
        Text(text, style: style.code.copyWith(color: color)),
      ],
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame(this.frame, this.at);

  final WebSocketFrame frame;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final incoming = frame.direction == WebSocketDirection.incoming;
    final payload = frame.payload?.pretty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: style.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: incoming ? '↓ ' : '↑ ',
                  style: TextStyle(
                    color: incoming ? style.methodRead : style.methodWrite,
                  ),
                ),
                TextSpan(
                  text:
                      '+${NetworkFormat.duration(frame.time)}  '
                      '${NetworkFormat.clock(at)}  '
                      '${NetworkFormat.bytes(frame.size)}'
                      '${frame.binary ? '  binary' : ''}',
                  style: TextStyle(color: style.muted),
                ),
                if (frame.label case final label?)
                  TextSpan(
                    text: '  $label',
                    style: TextStyle(color: style.accent),
                  ),
              ],
            ),
            style: style.code,
          ),
          if (payload != null) Text(payload, style: style.code),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text, style: style.text.copyWith(color: style.muted)),
    );
  }
}

// Each phase on one line: its name, its length, and its bar on the scale
// of the whole request.
class _Phases extends StatelessWidget {
  const _Phases(this.phases);

  final List<NetworkPhase> phases;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    var total = Duration.zero;
    for (final phase in phases) {
      if (phase.end > total) {
        total = phase.end;
      }
    }
    double at(Duration time) => total <= Duration.zero
        ? 0
        : (time.inMicroseconds / total.inMicroseconds).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final phase in phases)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    phase.name,
                    style: style.code.copyWith(color: style.muted),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    NetworkFormat.duration(phase.duration),
                    style: style.code,
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 6,
                    child: CustomPaint(
                      painter: WaterfallBarPainter(
                        WaterfallBar(
                          start: math.min(
                            at(phase.start),
                            1 - NetworkWaterfall.minWidth,
                          ),
                          end: math.max(
                            at(phase.end),
                            math.min(
                              at(phase.start) + NetworkWaterfall.minWidth,
                              1.0,
                            ),
                          ),
                        ),
                        style,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// The heartbeat round trips kept, as bars oldest to newest, with the
// last, the least, the mean and the most.
class _Latencies extends StatelessWidget {
  const _Latencies(this.latencies);

  final List<Duration> latencies;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    var least = latencies.first;
    var most = latencies.first;
    var sum = Duration.zero;
    for (final latency in latencies) {
      if (latency < least) {
        least = latency;
      }
      if (latency > most) {
        most = latency;
      }
      sum += latency;
    }
    final mean = sum ~/ latencies.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title('Heartbeat round trips (${latencies.length})'),
        SizedBox(
          height: 32,
          child: CustomPaint(
            painter: _LatencyPainter(latencies, most, style.accent),
          ),
        ),
        Text(
          'last ${NetworkFormat.duration(latencies.last)} · '
          'min ${NetworkFormat.duration(least)} · '
          'avg ${NetworkFormat.duration(mean)} · '
          'max ${NetworkFormat.duration(most)}',
          style: style.code.copyWith(color: style.muted),
        ),
      ],
    );
  }
}

class _LatencyPainter extends CustomPainter {
  _LatencyPainter(this.latencies, this.most, this.color);

  final List<Duration> latencies;
  final Duration most;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (latencies.isEmpty || most <= Duration.zero) {
      return;
    }
    final paint = Paint()..color = color;
    final step = size.width / latencies.length;
    final width = step > 2 ? step - 1 : step;
    for (var i = 0; i < latencies.length; i++) {
      final height =
          size.height * latencies[i].inMicroseconds / most.inMicroseconds;
      canvas.drawRect(
        Rect.fromLTWH(i * step, size.height - height, width, height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LatencyPainter old) =>
      old.latencies != latencies || old.most != most || old.color != color;
}
