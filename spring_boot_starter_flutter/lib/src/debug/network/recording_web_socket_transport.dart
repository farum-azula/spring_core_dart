import 'dart:async';

import 'package:spring_boot_starter_flutter/src/debug/network/debug_network_journal.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_entry.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/web_socket_frame_labeler.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/web_socket_ping_matcher.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// A [WebSocketTransport] that connects through [delegate] unchanged and
/// writes each connection into [journal]: the handshake (its headers
/// masked), every frame each way (its size and time, its payload with
/// `spring.flutter.debug.network.bodies`, a label from [labelers], such as
/// a Phoenix join), and the close with its code, reason and time. It
/// times the handshake, counts the connections to each address (the
/// reconnects), and measures the round trip of each heartbeat answered
/// ([pingMatchers]: Phoenix's by default).
///
/// The session the caller gets sends and receives exactly what
/// [delegate]'s does: a frame received is counted as it is passed on, one
/// sent is counted before it goes. The debug network recorder puts it
/// around the `WebSocketTransport` beans; with the journal
/// [DebugNetworkJournal.paused], new connections are not recorded.
final class RecordingWebSocketTransport implements WebSocketTransport {
  /// [delegate], recorded into [journal], frames labelled by [labelers],
  /// heartbeats found by [pingMatchers].
  RecordingWebSocketTransport(
    this.delegate,
    this.journal, {
    this.labelers = const [PhoenixFrameLabeler()],
    this.pingMatchers = const [PhoenixHeartbeatMatcher()],
  });

  /// The transport that connects.
  final WebSocketTransport delegate;

  /// Where the connections go.
  final DebugNetworkJournal journal;

  /// What names a frame, the first that knows it.
  final List<WebSocketFrameLabeler> labelers;

  /// What finds a heartbeat and its reply, the first that knows a frame.
  final List<WebSocketPingMatcher> pingMatchers;

  @override
  Future<WebSocketSession> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
    int? maxTextMessageSize,
    int? maxBinaryMessageSize,
  }) async {
    Future<WebSocketSession> open() => delegate.connect(
      url,
      headers: headers,
      protocols: protocols,
      timeout: timeout,
      maxTextMessageSize: maxTextMessageSize,
      maxBinaryMessageSize: maxBinaryMessageSize,
    );
    if (!journal.isRecording) {
      return open();
    }
    final masked = journal.masking.url(url);
    final connection = journal.add(
      WebSocketConnection(
        id: journal.nextId(),
        url: masked,
        started: DateTime.now(),
        requestHeaders: journal.masking.headers(headers),
        protocols: journal.masking.protocols(protocols),
        maxFrames: journal.maxFrames,
        attempt: journal.connectionNumber(masked),
      ),
    );
    final clock = Stopwatch()..start();
    final WebSocketSession session;
    try {
      session = await open();
    } on Object catch (error) {
      connection
        ..error = journal.masking.text(
          error is WebSocketException ? error.message : '$error',
        )
        ..closedAfter = clock.elapsed;
      journal.changed();
      rethrow;
    }
    connection
      ..opened = true
      ..acceptedProtocol = switch (session.acceptedProtocol) {
        final accepted? => journal.masking.protocols([accepted]).single,
        null => null,
      }
      ..connectTime = clock.elapsed;
    journal.changed();
    return RecordingWebSocketSession(session, connection, this, clock);
  }

  /// [message]'s frame going [direction] at [time]: its size, [label]
  /// and, with bodies, payload.
  WebSocketFrame frameOf(
    Object message,
    WebSocketDirection direction,
    Duration time, {
    WebSocketFrameLabel? label,
  }) {
    if (message is String) {
      final size = utf8Length(message);
      return WebSocketFrame(
        direction: direction,
        time: time,
        size: size,
        binary: false,
        label: label?.text,
        payload: journal.textPayload(message, size),
      );
    }
    final size = message is List<int> ? message.length : 0;
    return WebSocketFrame(
      direction: direction,
      time: time,
      size: size,
      binary: true,
      payload: journal.binaryPayload(size),
    );
  }

  /// [text]'s label by the first of [labelers] that knows it.
  WebSocketFrameLabel? labelOf(String text) {
    for (final labeler in labelers) {
      if (labeler.label(text) case final label?) {
        return label;
      }
    }
    return null;
  }

  /// The bytes of [text] in UTF-8, counted without encoding it.
  static int utf8Length(String text) {
    var bytes = 0;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit < 0x80) {
        bytes += 1;
      } else if (unit < 0x800) {
        bytes += 2;
      } else if (unit >= 0xD800 && unit < 0xDC00 && i + 1 < text.length) {
        bytes += 4;
        i++;
      } else {
        bytes += 3;
      }
    }
    return bytes;
  }
}

/// A [WebSocketSession] of a [RecordingWebSocketTransport]: [delegate]'s,
/// its frames and its close written into [connection].
final class RecordingWebSocketSession implements WebSocketSession {
  /// [delegate], recorded into [connection] by [transport].
  RecordingWebSocketSession(
    this.delegate,
    this.connection,
    this.transport,
    this._clock,
  );

  /// The session that sends and receives.
  final WebSocketSession delegate;

  /// Where its frames go.
  final WebSocketConnection connection;

  /// The transport that opened it.
  final RecordingWebSocketTransport transport;

  final Stopwatch _clock;

  // The heartbeats sent and not answered yet: their keys, by matcher, and
  // when they went. At most [_maxPending]: a server that never answers
  // leaves no growing map.
  final Map<(WebSocketPingMatcher, String), Duration> _pending = {};
  static const _maxPending = 16;

  DebugNetworkJournal get _journal => transport.journal;

  @override
  Uri get uri => delegate.uri;

  @override
  String? get acceptedProtocol => delegate.acceptedProtocol;

  @override
  bool get isOpen => delegate.isOpen;

  @override
  CloseStatus? get closeStatus => delegate.closeStatus;

  @override
  late final Stream<Object> messages = delegate.messages.transform(
    StreamTransformer.fromHandlers(
      handleData: (message, sink) {
        _record(message, WebSocketDirection.incoming);
        sink.add(message);
      },
      handleDone: (sink) {
        _closed();
        sink.close();
      },
    ),
  );

  @override
  void sendMessage(Object message) {
    delegate.sendMessage(message);
    _record(message, WebSocketDirection.outgoing);
  }

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) async {
    if (connection.closeCode == null) {
      connection.closedByClient = true;
    }
    await delegate.close(status);
    _closed(status);
  }

  void _record(Object message, WebSocketDirection direction) {
    final time = _clock.elapsed;
    var label = message is String ? transport.labelOf(message) : null;
    if (message is String && transport.pingMatchers.isNotEmpty) {
      label = _heartbeat(message, direction, time) ?? label;
    }
    if (label?.channel case final channel?) {
      switch (label!.joins) {
        case true:
          connection.channels.add(channel);
        case false:
          connection.channels.remove(channel);
        case null:
      }
    }
    connection.addFrame(
      transport.frameOf(message, direction, time, label: label),
    );
    _journal.changed();
  }

  // A heartbeat sent is kept until its reply; the reply's round trip goes
  // to the connection. Both frames are labelled, the reply with its time.
  WebSocketFrameLabel? _heartbeat(
    String text,
    WebSocketDirection direction,
    Duration time,
  ) {
    for (final matcher in transport.pingMatchers) {
      switch (direction) {
        case WebSocketDirection.outgoing:
          if (matcher.ping(text) case final key?) {
            if (_pending.length >= _maxPending) {
              _pending.remove(_pending.keys.first);
            }
            _pending[(matcher, key)] = time;
            return WebSocketFrameLabel(matcher.name);
          }
        case WebSocketDirection.incoming:
          if (matcher.pong(text) case final key?) {
            final sent = _pending.remove((matcher, key));
            if (sent == null) {
              continue;
            }
            final latency = time - sent;
            connection.addLatency(latency);
            return WebSocketFrameLabel(
              '${matcher.name} reply ${_milliseconds(latency)}',
            );
          }
      }
    }
    return null;
  }

  static String _milliseconds(Duration duration) =>
      '${(duration.inMicroseconds / 1000).toStringAsFixed(1)} ms';

  void _closed([CloseStatus? sent]) {
    if (connection.closeCode != null) {
      return;
    }
    final status = delegate.closeStatus ?? sent;
    connection
      ..closeCode = status?.code ?? CloseStatus.noStatusCode.code
      ..closeReason = status?.reason
      ..closedAfter = _clock.elapsed;
    _journal.changed();
  }
}
