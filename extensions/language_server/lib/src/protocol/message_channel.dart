import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The JSON-RPC messages of the Language Server Protocol over a byte
/// stream and a sink, each framed by a `Content-Length` header:
/// `Content-Length: n\r\n\r\n` and then n bytes of JSON.
final class MessageChannel {
  /// A channel that reads a byte stream (such as stdin) and writes to a
  /// sink (such as stdout).
  MessageChannel(this._input, this._output);

  final Stream<List<int>> _input;
  final IOSink _output;

  /// The messages as they arrive, decoded; done when the input ends.
  Stream<Map<String, Object?>> get messages async* {
    final pending = BytesBuilder(copy: false);
    await for (final chunk in _input) {
      pending.add(chunk);
      var bytes = pending.takeBytes();
      while (true) {
        final message = _frame(bytes);
        if (message == null) {
          break;
        }
        bytes = Uint8List.sublistView(bytes, message.end);
        if (message.body case final body?) {
          yield jsonDecode(utf8.decode(body)) as Map<String, Object?>;
        }
      }
      pending.add(bytes);
    }
  }

  /// Sends [message], with its `jsonrpc` version.
  void send(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode({'jsonrpc': '2.0', ...message}));
    _output
      ..add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'))
      ..add(body);
  }

  static final _contentLength = RegExp(
    r'Content-Length:\s*(\d+)',
    caseSensitive: false,
  );

  /// The first message framed in [bytes]: its body (null for a header
  /// without a length, which is skipped) and where it ends; null while the
  /// message is incomplete.
  static ({Uint8List? body, int end})? _frame(Uint8List bytes) {
    final headerEnd = _headerEnd(bytes);
    if (headerEnd < 0) {
      return null;
    }
    final headers = ascii.decode(
      Uint8List.sublistView(bytes, 0, headerEnd),
      allowInvalid: true,
    );
    final start = headerEnd + 4;
    final length = _contentLength.firstMatch(headers)?.group(1);
    if (length == null) {
      return (body: null, end: start);
    }
    final end = start + int.parse(length);
    if (bytes.length < end) {
      return null;
    }
    return (body: Uint8List.sublistView(bytes, start, end), end: end);
  }

  static int _headerEnd(Uint8List bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }
}
