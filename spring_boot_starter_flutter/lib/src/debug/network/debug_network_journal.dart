import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_entry.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_masking.dart';
import 'package:spring_web_dart/spring_web_dart.dart' show HttpResponse;

/// The network traffic the recorder saw (the `debugNetworkJournal` bean):
/// the last [maxEntries] HTTP exchanges and WebSocket connections, oldest
/// first, what the debug panel's Network tab lists and what a compact view
/// (the console's) reads through [entries] and [summary].
///
/// It tells its listeners at most once a frame, and only while it has
/// any: with nothing showing it, recording is a few fields written per
/// request. [paused] stops new entries; [clear] empties it.
///
/// What is recorded is masked before it gets here ([masking]); bodies only
/// with `spring.flutter.debug.network.bodies` ([bodies]), each cut at
/// [bodyLimit] bytes, all of them together at most [bodyBudget] bytes.
class DebugNetworkJournal extends ChangeNotifier {
  /// A journal of the last [maxEntries] entries; [bodies] up to
  /// [bodyLimit] bytes each (at most [maxBodyLimit]) and [bodyBudget]
  /// bytes in all; the last [maxFrames] frames of each WebSocket.
  /// [schedule] runs its notification (the next frame's start by default).
  DebugNetworkJournal({
    this.maxEntries = 200,
    this.bodies = false,
    int bodyLimit = 64 * 1024,
    this.bodyBudget = defaultBodyBudget,
    this.maxFrames = 200,
    this.masking = const NetworkMasking(),
    void Function(VoidCallback notify)? schedule,
  }) : bodyLimit = bodyLimit.clamp(0, maxBodyLimit),
       _schedule = schedule ?? _nextFrame;

  /// The most a body limit can be: 1 MB.
  static const maxBodyLimit = 1024 * 1024;

  /// The bytes of bodies kept in all by default: 4 MB.
  static const defaultBodyBudget = 4 * 1024 * 1024;

  /// How many entries are kept; the oldest goes first.
  final int maxEntries;

  /// Whether bodies and frame payloads are kept.
  final bool bodies;

  /// The most bytes of a body or a payload kept.
  final int bodyLimit;

  /// The most bytes of bodies and payloads kept in all: past it, a new
  /// one keeps its size only, until old entries go.
  final int bodyBudget;

  // The bytes kept, counted as bodies are kept; at most what the entries
  // hold (frames dropped by their connection are not taken off), worked
  // out exactly again when it would pass the budget.
  var _bodyBytes = 0;

  /// How many frames of each WebSocket are kept.
  final int maxFrames;

  /// What is masked before an entry is kept.
  final NetworkMasking masking;

  final void Function(VoidCallback notify) _schedule;
  final _entries = ListQueue<NetworkEntry>();
  final _connections = <String, int>{};
  var _nextId = 1;
  var _version = 0;
  var _paused = false;
  var _scheduled = false;

  static void _nextFrame(VoidCallback notify) =>
      SchedulerBinding.instance.scheduleFrameCallback((_) => notify());

  /// The entries kept, oldest first.
  List<NetworkEntry> get entries => List.unmodifiable(_entries);

  /// Increases at every change: an entry added or updated, a clear.
  int get version => _version;

  /// Whether new traffic is left out; what is in flight still completes.
  bool get paused => _paused;

  set paused(bool value) {
    if (value != _paused) {
      _paused = value;
      changed();
    }
  }

  /// Whether the recorder keeps new traffic.
  bool get isRecording => !_paused;

  /// The next entry's number.
  int nextId() => _nextId++;

  /// Counts a WebSocket connection to [url] (masked) and gives its
  /// number: `1` for the first since the start or the last [clear], `2`
  /// for the first reconnect.
  int connectionNumber(Uri url) =>
      _connections.update('$url', (count) => count + 1, ifAbsent: () => 1);

  /// Keeps [entry], dropping the oldest past [maxEntries].
  T add<T extends NetworkEntry>(T entry) {
    if (maxEntries > 0) {
      while (_entries.length >= maxEntries) {
        _bodyBytes -= _keptBy(_entries.removeFirst());
      }
      _entries.addLast(entry);
    }
    changed();
    return entry;
  }

  /// Empties the journal.
  void clear() {
    _entries.clear();
    _bodyBytes = 0;
    _connections.clear();
    changed();
  }

  /// Notes a change: the listeners hear of it at the next frame, once
  /// however many changes come before.
  void changed() {
    _version++;
    if (_scheduled || !hasListeners) {
      return;
    }
    _scheduled = true;
    _schedule(_notify);
  }

  void _notify() {
    _scheduled = false;
    notifyListeners();
  }

  /// The counts a compact view shows.
  NetworkSummary get summary {
    var inFlight = 0;
    var requestsInFlight = 0;
    Duration? socketLatency;
    var failed = 0;
    var errors = 0;
    var received = 0;
    var sent = 0;
    var sockets = 0;
    for (final entry in _entries) {
      if (!entry.isDone) {
        inFlight++;
      }
      switch (entry) {
        case WebSocketConnection(:final lastLatency, :final isDone)
            when !isDone && entry.error == null:
          sockets++;
          socketLatency = lastLatency ?? socketLatency;
        case HttpExchange(:final isDone) when !isDone:
          requestsInFlight++;
        default:
      }
      switch (entry.statusClass) {
        case NetworkStatusClass.failed:
          failed++;
        case NetworkStatusClass.clientError || NetworkStatusClass.serverError:
          errors++;
        default:
      }
      received += entry.received;
      sent += entry.sent;
    }
    return NetworkSummary(
      entries: _entries.length,
      inFlight: inFlight,
      requestsInFlight: requestsInFlight,
      lastSocketLatency: socketLatency,
      failed: failed,
      errors: errors,
      received: received,
      sent: sent,
      openSockets: sockets,
    );
  }

  /// [bytes] of a body of [length] bytes and [contentType] as kept: `null`
  /// without [bodies]; else at most [bodyLimit] bytes, decoded and masked
  /// when it is text.
  NetworkBody? body(List<int>? bytes, int length, String? contentType) {
    if (!bodies || bytes == null || length == 0) {
      return null;
    }
    final kept = bytes.length > bodyLimit ? bytes.sublist(0, bodyLimit) : bytes;
    if (!_admit(kept.length)) {
      return NetworkBody(length: length, kept: 0, contentType: contentType);
    }
    return NetworkBody(
      length: length,
      kept: kept.length,
      contentType: contentType,
      text: isText(contentType, kept)
          ? masking.body(
              HttpResponse.decodeBody(kept, contentType),
              contentType,
            )
          : null,
    );
  }

  /// A text frame's [text] as kept: `null` without [bodies]; else at most
  /// [bodyLimit] bytes of it, masked.
  NetworkBody? textPayload(String text, int size) {
    if (!bodies) {
      return null;
    }
    if (!_admit(size > bodyLimit ? bodyLimit : size)) {
      return NetworkBody(length: size, kept: 0);
    }
    final kept = size > bodyLimit
        ? utf8.decode(
            utf8.encode(text).sublist(0, bodyLimit),
            allowMalformed: true,
          )
        : text;
    return NetworkBody(
      length: size,
      kept: size > bodyLimit ? bodyLimit : size,
      text: masking.body(kept, null),
    );
  }

  // Whether [bytes] more fit in the budget; counted when they do.
  bool _admit(int bytes) {
    if (_bodyBytes + bytes > bodyBudget) {
      _bodyBytes = _entries.fold(0, (sum, entry) => sum + _keptBy(entry));
      if (_bodyBytes + bytes > bodyBudget) {
        return false;
      }
    }
    _bodyBytes += bytes;
    return true;
  }

  static int _keptBy(NetworkEntry entry) => switch (entry) {
    HttpExchange(:final requestBody, :final responseBody) =>
      (requestBody?.kept ?? 0) + (responseBody?.kept ?? 0),
    WebSocketConnection(:final frames) => frames.fold(
      0,
      (sum, frame) => sum + (frame.payload?.kept ?? 0),
    ),
  };

  /// A binary frame of [size] bytes as kept: its size only.
  NetworkBody? binaryPayload(int size) =>
      bodies ? NetworkBody(length: size, kept: 0) : null;

  /// Whether a body of [contentType] reads as text: a textual type, or
  /// none with bytes that decode as UTF-8.
  static bool isText(String? contentType, List<int> bytes) {
    final type = contentType?.toLowerCase();
    if (type == null || type.isEmpty) {
      try {
        utf8.decode(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
        return true;
      } on FormatException {
        return false;
      }
    }
    return type.startsWith('text/') ||
        type.contains('json') ||
        type.contains('xml') ||
        type.contains('javascript') ||
        type.contains('x-www-form-urlencoded') ||
        type.contains('graphql') ||
        type.contains('yaml');
  }
}

/// The counts of a [DebugNetworkJournal], for a compact view.
@immutable
final class NetworkSummary {
  /// Counts of these values.
  const NetworkSummary({
    required this.entries,
    required this.inFlight,
    required this.failed,
    this.errors = 0,
    this.requestsInFlight = 0,
    this.lastSocketLatency,
    required this.received,
    required this.sent,
    required this.openSockets,
  });

  /// The entries kept.
  final int entries;

  /// Those not over yet: the requests waiting or receiving, and the
  /// WebSockets open or opening.
  final int inFlight;

  /// The HTTP requests not over yet.
  final int requestsInFlight;

  /// The last heartbeat round trip of the newest open WebSocket that has
  /// one; `null` when none has.
  final Duration? lastSocketLatency;

  /// Those that got no response at all: the connection failed, broke,
  /// timed out or was aborted. A `4xx` or `5xx` is a response, counted in
  /// [errors].
  final int failed;

  /// Those answered with a `4xx` or `5xx` (a WebSocket closed by a policy
  /// or a protocol error too).
  final int errors;

  /// The bytes they received.
  final int received;

  /// The bytes they sent.
  final int sent;

  /// The WebSockets open.
  final int openSockets;
}
