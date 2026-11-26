import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

/// The class of an entry's status, which the Network tab colours and
/// filters by.
enum NetworkStatusClass {
  /// No answer yet.
  pending,

  /// `1xx`, and a WebSocket that is open or closed normally.
  informational,

  /// `2xx`.
  success,

  /// `3xx`.
  redirect,

  /// `4xx`, and a WebSocket closed by a policy or a protocol error.
  clientError,

  /// `5xx`.
  serverError,

  /// No answer at all: the connection failed, broke or timed out.
  failed;

  /// The class of the HTTP status [code].
  static NetworkStatusClass ofCode(int code) => switch (code) {
    < 200 => informational,
    < 300 => success,
    < 400 => redirect,
    < 500 => clientError,
    _ => serverError,
  };
}

/// One header as recorded: its value is already [NetworkMasking.masked]
/// when the name carries a credential, so the journal never holds it.
final class NetworkHeader {
  /// The header [name] with [value], [masked] or not.
  const NetworkHeader(this.name, this.value, {this.masked = false});

  /// The name, as sent or received.
  final String name;

  /// The value, or the mask.
  final String value;

  /// Whether [value] is the mask.
  final bool masked;
}

/// A body as recorded (with `spring.flutter.debug.network.bodies`): at
/// most `body-limit` bytes of it, decoded and with its secrets masked when
/// it is text; [length] is the whole body's.
final class NetworkBody {
  /// A body of [length] bytes, of which [text] was kept (`null` for a
  /// binary one), of [contentType].
  NetworkBody({
    required this.length,
    required this.kept,
    this.text,
    this.contentType,
  });

  /// The bytes of the whole body.
  final int length;

  /// The bytes kept, at most the limit.
  final int kept;

  /// The kept bytes as text, masked; `null` for a binary body.
  final String? text;

  /// The body's `Content-Type`, when it has one.
  final String? contentType;

  /// Whether the body was longer than what was kept.
  bool get truncated => kept < length;

  /// Whether the body reads as JSON: its type says so, or its text starts
  /// as an object or an array.
  bool get isJson {
    final type = contentType?.toLowerCase();
    if (type != null && type.contains('json')) {
      return true;
    }
    final start = text?.trimLeft();
    return start != null && (start.startsWith('{') || start.startsWith('['));
  }

  /// [text] indented when it is whole JSON; else [text] as it is. Worked
  /// out once, when first shown.
  late final String? pretty = _pretty();

  String? _pretty() {
    final text = this.text;
    if (text == null || truncated || !isJson) {
      return text;
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } on FormatException {
      return text;
    }
  }
}

/// An entry of the [DebugNetworkJournal]: an HTTP exchange or a WebSocket
/// connection. What the Network tab lists, and what a compact view (the
/// console's) reads; its fields change while it is in flight, and the
/// journal tells its listeners at most once a frame.
sealed class NetworkEntry {
  NetworkEntry({required this.id, required this.url, required this.started});

  /// Its number in the journal, increasing.
  final int id;

  /// The address, with the credentials of its query and user-info masked.
  final Uri url;

  /// When it started.
  final DateTime started;

  /// The method (`GET`), or `WS` for a WebSocket.
  String get method;

  /// Whether it is a WebSocket connection.
  bool get isWebSocket;

  /// The status as shown: the HTTP code, a WebSocket's close code, `…`
  /// while there is none, `ERR` when it failed.
  String get status;

  /// The class of [status].
  NetworkStatusClass get statusClass;

  /// How long it took; `null` while it is in flight.
  Duration? get duration;

  /// The bytes received (a response's body, a WebSocket's frames in).
  int get received;

  /// The bytes sent (a request's body, a WebSocket's frames out).
  int get sent;

  /// What went wrong, when it failed.
  String? get error;

  /// Whether it is over (answered, failed, cancelled or closed).
  bool get isDone;
}

/// A phase of a request: [name], from [start] (after the request's start)
/// for [duration].
@immutable
final class NetworkPhase {
  /// [name], from [start] for [duration].
  const NetworkPhase(this.name, this.start, this.duration);

  /// What it is (`DNS`, `Waiting`, `Download`).
  final String name;

  /// When it began, from the request's start.
  final Duration start;

  /// How long it took.
  final Duration duration;

  /// When it ended, from the request's start.
  Duration get end => start + duration;

  @override
  bool operator ==(Object other) =>
      other is NetworkPhase &&
      other.name == name &&
      other.start == start &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(name, start, duration);

  @override
  String toString() =>
      '$name +${start.inMicroseconds}µs ${duration.inMicroseconds}µs';
}

/// A request's phases as the browser measured them (Resource Timing,
/// `ResourceTimingReader`): name lookup, connection, TLS, waiting,
/// download. On the web only, and only "if available".
@immutable
final class ResourceTiming {
  /// [total], with [phases] unless [restricted].
  const ResourceTiming({
    required this.total,
    this.firstByte,
    this.protocol,
    this.phases = const [],
    this.restricted = false,
  });

  /// From the start until the last byte, by the browser's clock.
  final Duration total;

  /// From the start until the first byte; `null` when [restricted].
  final Duration? firstByte;

  /// The protocol (`h2`); `null` when hidden.
  final String? protocol;

  /// The phases, each from the start, in order.
  final List<NetworkPhase> phases;

  /// Whether the browser hid the phases: a response from another origin
  /// without `Timing-Allow-Origin`.
  final bool restricted;
}

/// Where an HTTP exchange is.
enum HttpExchangeState {
  /// Sent, no answer yet.
  waiting,

  /// The status and headers have arrived; a streamed body is coming.
  receiving,

  /// The whole response has arrived.
  done,

  /// The caller stopped reading a streamed body.
  cancelled,

  /// No answer, or the streamed body broke.
  failed,
}

/// An HTTP exchange of an `HttpTransport`: the request, then the
/// response or the failure.
final class HttpExchange extends NetworkEntry {
  /// An exchange of [method] to [url], sent with [requestHeaders] and
  /// [requestSize] bytes of body, of which [requestBody] was kept.
  HttpExchange({
    required super.id,
    required super.url,
    required super.started,
    required this.method,
    required this.requestHeaders,
    required this.requestSize,
    this.requestBody,
    this.streamed = false,
  });

  @override
  final String method;

  /// The request's headers, masked.
  final List<NetworkHeader> requestHeaders;

  /// The request's body bytes.
  final int requestSize;

  /// The request's body as kept; `null` without bodies or without one.
  final NetworkBody? requestBody;

  /// Whether the response is read as a stream (`HttpTransport.stream`).
  final bool streamed;

  /// Where it is.
  HttpExchangeState state = HttpExchangeState.waiting;

  /// The status code, once the headers have arrived.
  int? statusCode;

  /// The response's headers, masked.
  List<NetworkHeader> responseHeaders = const [];

  /// The response's body as kept.
  NetworkBody? responseBody;

  /// The response's body bytes, counted as they arrive.
  int responseSize = 0;

  /// From the start until the status and headers arrived, as measured: a
  /// streamed response only. `HttpTransport.send` hands the response over
  /// whole, and no transport tells when its headers came; implementing it
  /// over `stream` would change its timeouts (they cover the whole
  /// exchange of `send`, the headers only of `stream`) and its errors.
  Duration? headersTime;

  /// From the start until the whole response arrived, or the failure.
  Duration? totalTime;

  /// The browser's phases of this request (Resource Timing), when it gave
  /// them: on the web only, once the response is done.
  ResourceTiming? resourceTiming;

  /// The time to the first byte: [headersTime], else the browser's.
  Duration? get firstByte => headersTime ?? resourceTiming?.firstByte;

  /// The phases, each from the start: the browser's when it gave them;
  /// else the wait for the headers and the body, when [firstByte] is
  /// known; else the whole. An exchange in flight is measured to [now].
  List<NetworkPhase> phases(DateTime now) {
    if (resourceTiming
        case ResourceTiming(
          restricted: false,
          :final phases,
        )
        when phases.isNotEmpty) {
      return phases;
    }
    final total = totalTime ?? now.difference(started);
    return switch (firstByte) {
      final firstByte? => [
        NetworkPhase('Waiting', Duration.zero, firstByte),
        NetworkPhase('Body', firstByte, total - firstByte),
      ],
      null => [NetworkPhase('Total', Duration.zero, total)],
    };
  }

  @override
  String? error;

  /// Whether the failure was a time limit running out.
  bool timeout = false;

  @override
  bool get isWebSocket => false;

  @override
  String get status => switch (statusCode) {
    final code? => '$code',
    null => state == HttpExchangeState.failed ? 'ERR' : '…',
  };

  @override
  NetworkStatusClass get statusClass => switch (statusCode) {
    _ when state == HttpExchangeState.failed && statusCode == null =>
      NetworkStatusClass.failed,
    final code? => NetworkStatusClass.ofCode(code),
    null => NetworkStatusClass.pending,
  };

  @override
  Duration? get duration => totalTime;

  @override
  int get received => responseSize;

  @override
  int get sent => requestSize;

  @override
  bool get isDone =>
      state != HttpExchangeState.waiting &&
      state != HttpExchangeState.receiving;
}

/// Which way a WebSocket frame went.
enum WebSocketDirection {
  /// From the server.
  incoming,

  /// To the server.
  outgoing,
}

/// A frame of a [WebSocketConnection].
final class WebSocketFrame {
  /// A frame of [size] bytes going [direction] at [time].
  const WebSocketFrame({
    required this.direction,
    required this.time,
    required this.size,
    required this.binary,
    this.label,
    this.payload,
  });

  /// Which way it went.
  final WebSocketDirection direction;

  /// When, from the connection's start.
  final Duration time;

  /// Its bytes (a text frame's in UTF-8).
  final int size;

  /// Whether it is a binary frame.
  final bool binary;

  /// What it is, when a `WebSocketFrameLabeler` knows (a Phoenix
  /// `join room:lobby`).
  final String? label;

  /// Its content as kept, masked; `null` without bodies.
  final NetworkBody? payload;
}

/// A WebSocket connection of a `WebSocketTransport`: the handshake, the
/// frames each way and the close.
final class WebSocketConnection extends NetworkEntry {
  /// A connection to [url], offering [protocols], keeping the last
  /// [maxFrames] frames and [maxLatencies] latencies; the [attempt]th
  /// connection to [url] the journal has seen.
  WebSocketConnection({
    required super.id,
    required super.url,
    required super.started,
    required this.requestHeaders,
    this.protocols = const [],
    this.maxFrames = 200,
    this.maxLatencies = 60,
    this.attempt = 1,
  });

  /// Which connection to its address this is, from `1`: a client that
  /// reconnects opens a new one each time.
  final int attempt;

  /// How many connections to its address came before this one.
  int get reconnects => attempt - 1;

  /// How many latencies are kept.
  final int maxLatencies;

  /// The handshake's headers, masked.
  final List<NetworkHeader> requestHeaders;

  /// The subprotocols offered.
  final List<String> protocols;

  /// How many frames are kept; the counts go on past it.
  final int maxFrames;

  /// The subprotocol the server picked.
  String? acceptedProtocol;

  /// Whether the handshake succeeded.
  bool opened = false;

  /// From the start until the handshake succeeded.
  Duration? connectTime;

  /// From the start until it closed.
  Duration? closedAfter;

  /// When the handshake succeeded.
  DateTime? get connectedAt => switch (connectTime) {
    final time? when opened => started.add(time),
    _ => null,
  };

  /// When it closed.
  DateTime? get closedAt => switch (closedAfter) {
    final time? => started.add(time),
    null => null,
  };

  /// How long it has been open, until [now] or its close; `null` before
  /// the handshake succeeded.
  Duration? uptime(DateTime now) {
    final connectedAt = this.connectedAt;
    if (connectedAt == null) {
      return null;
    }
    final end = closedAt ?? now;
    return end.isBefore(connectedAt)
        ? Duration.zero
        : end.difference(connectedAt);
  }

  /// When [frame] went, by the clock.
  DateTime timeOf(WebSocketFrame frame) => started.add(frame.time);

  final ListQueue<Duration> _latencies = ListQueue();

  /// The round trips of the heartbeats answered (a Phoenix `heartbeat`
  /// and its reply), the last [maxLatencies], oldest first.
  List<Duration> get latencies => List.unmodifiable(_latencies);

  /// The last round trip; `null` before the first.
  Duration? get lastLatency => _latencies.isEmpty ? null : _latencies.last;

  /// Adds a round trip, dropping the oldest past [maxLatencies].
  void addLatency(Duration latency) {
    if (maxLatencies <= 0) {
      return;
    }
    if (_latencies.length >= maxLatencies) {
      _latencies.removeFirst();
    }
    _latencies.addLast(latency);
  }

  /// The close code, once closed.
  int? closeCode;

  /// The close reason, when the close frame had one.
  String? closeReason;

  /// Whether this side closed it.
  bool closedByClient = false;

  @override
  String? error;

  /// The frames received.
  int framesIn = 0;

  /// The frames sent.
  int framesOut = 0;

  /// The bytes received.
  int bytesIn = 0;

  /// The bytes sent.
  int bytesOut = 0;

  /// The channels joined and not left, by their labels (Phoenix topics).
  final Set<String> channels = {};

  final ListQueue<WebSocketFrame> _frames = ListQueue();

  /// The last [maxFrames] frames, oldest first.
  List<WebSocketFrame> get frames => List.unmodifiable(_frames);

  /// Adds [frame], dropping the oldest past [maxFrames].
  void addFrame(WebSocketFrame frame) {
    switch (frame.direction) {
      case WebSocketDirection.incoming:
        framesIn++;
        bytesIn += frame.size;
      case WebSocketDirection.outgoing:
        framesOut++;
        bytesOut += frame.size;
    }
    if (maxFrames <= 0) {
      return;
    }
    if (_frames.length >= maxFrames) {
      _frames.removeFirst();
    }
    _frames.addLast(frame);
  }

  @override
  String get method => 'WS';

  @override
  bool get isWebSocket => true;

  @override
  String get status => switch (closeCode) {
    final code? => '$code',
    null when error != null => 'ERR',
    null => opened ? '101' : '…',
  };

  @override
  NetworkStatusClass get statusClass => switch (closeCode) {
    null when error != null => NetworkStatusClass.failed,
    null =>
      opened ? NetworkStatusClass.informational : NetworkStatusClass.pending,
    1000 || 1001 || 1005 => NetworkStatusClass.informational,
    1006 => NetworkStatusClass.failed,
    1011 || 1012 || 1013 || 1014 => NetworkStatusClass.serverError,
    _ => NetworkStatusClass.clientError,
  };

  @override
  Duration? get duration => closedAfter;

  @override
  int get received => bytesIn;

  @override
  int get sent => bytesOut;

  @override
  bool get isDone => closeCode != null || (error != null && !opened);
}
