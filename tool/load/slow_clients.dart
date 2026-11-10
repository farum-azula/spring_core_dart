// The misbehaving clients of the checks `slow-headers`, `slow-body` and
// `big-body` of tool/load.dart: plain sockets that send a request slowly,
// or more of it than the server takes, and note what the server does.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'checks.dart';

/// How a request is sent after its first bytes.
enum Pace {
  /// Nothing more is sent.
  stall,

  /// A little more every half second, for as long as the server listens.
  trickle,

  /// As fast as the socket takes it.
  flood,
}

/// Sends one request to 127.0.0.1:[port] and watches it for [watch].
///
/// [head] is written at once: the request line and the headers (without
/// the blank line that ends them, to leave the headers open). Then, by
/// [pace]: nothing, [drip] every half second, or [body] bytes in chunks
/// of 64 KB as fast as the socket takes them ([chunked]: as HTTP chunks,
/// without the chunk that ends the body unless [endChunks]).
///
/// The result says what came back: the status of an answer and when, when
/// the server closed the connection, and how many bytes the client had
/// written when the answer came.
Future<ClientResult> slowRequest(
  int port, {
  required String head,
  required Pace pace,
  required Duration watch,
  String drip = 'a',
  int body = 0,
  bool chunked = false,
  bool endChunks = true,
}) async {
  final clock = Stopwatch()..start();
  final Socket socket;
  try {
    socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 5),
    );
  } on Object {
    // Refused or timed out: the server closed the door at once.
    return (
      status: null,
      answeredAfter: null,
      closedAfter: clock.elapsed,
      bytesSent: 0,
      sentAll: false,
    );
  }
  var sent = 0;
  int? sentAtAnswer;
  int? status;
  Duration? answered;
  Duration? closed;
  var sentAll = false;
  final answer = BytesBuilder();
  final done = Completer<void>();
  void finish() {
    closed ??= clock.elapsed;
    if (!done.isCompleted) {
      done.complete();
    }
  }

  socket.listen(
    (bytes) {
      if (status != null) {
        return;
      }
      answer.add(bytes);
      final match = RegExp(
        r'^HTTP/1\.[01] (\d{3})',
      ).firstMatch(latin1.decode(answer.toBytes(), allowInvalid: true));
      if (match != null) {
        status = int.parse(match[1]!);
        answered = clock.elapsed;
        sentAtAnswer = sent;
      }
    },
    onDone: finish,
    onError: (Object _) => finish(),
    cancelOnError: true,
  );

  // A write fails once the server has closed its side: that ends the
  // sending, not the reading. The answer the server sent before may
  // still be on its way, so the connection gets a moment to deliver it.
  Future<bool> write(List<int> bytes) async {
    if (done.isCompleted || closed != null) {
      return false;
    }
    try {
      socket.add(bytes);
      await socket.flush();
      sent += bytes.length;
      return true;
    } on Object {
      closed ??= clock.elapsed;
      Timer(const Duration(seconds: 1), finish);
      return false;
    }
  }

  Future<void> send() async {
    if (!await write(latin1.encode(head))) {
      return;
    }
    switch (pace) {
      case Pace.stall:
        sentAll = true;
      case Pace.trickle:
        while (!done.isCompleted && clock.elapsed < watch) {
          await Future.any([
            done.future,
            Future<void>.delayed(const Duration(milliseconds: 500)),
          ]);
          if (!await write(latin1.encode(drip))) {
            return;
          }
        }
      case Pace.flood:
        final chunk = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 0x20);
        for (var left = body; left > 0; left -= chunk.length) {
          final part = left < chunk.length
              ? Uint8List.sublistView(chunk, 0, left)
              : chunk;
          final size = latin1.encode('${part.length.toRadixString(16)}\r\n');
          if (chunked && !await write(size) ||
              !await write(part) ||
              chunked && !await write(const [13, 10])) {
            return;
          }
        }
        if (chunked && endChunks && !await write(latin1.encode('0\r\n\r\n'))) {
          return;
        }
        sentAll = true;
    }
  }

  final sending = send();
  await Future.any([done.future, Future<void>.delayed(watch)]);
  final stillOpen = !done.isCompleted;
  finish();
  socket.destroy();
  // A write the server never read ends with the socket; not waited for
  // longer.
  await sending.timeout(const Duration(seconds: 1), onTimeout: () {});
  return (
    status: status,
    answeredAfter: answered,
    closedAfter: stillOpen ? null : closed,
    bytesSent: sentAtAnswer ?? sent,
    sentAll: sentAll,
  );
}
