import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The JSON-RPC messages of the Language Server Protocol over a byte
/// stream and a sink, each framed by a `Content-Length` header:
/// `Content-Length: n\r\n\r\n` and then n bytes of JSON.
///
/// A frame that cannot be read does not end the channel: a body that is not
/// JSON gets a parse error (-32700), a body that is not an object, or one
/// longer than [maxContentLength], an invalid request (-32600); the bytes of
/// a body that is too long are skipped as they arrive, never buffered. A
/// header longer than [maxHeaderLength] is dropped.
final class MessageChannel {
  /// A channel that reads a byte stream (such as stdin) and writes to a
  /// sink (such as stdout).
  MessageChannel(
    this._input,
    this._output, {
    this.maxContentLength = 64 << 20,
    this.maxHeaderLength = 8 << 10,
  });

  final Stream<List<int>> _input;
  final IOSink _output;

  /// The longest body read, in bytes.
  final int maxContentLength;

  /// The longest header read, in bytes.
  final int maxHeaderLength;

  /// The protocol's code for a body that is not JSON.
  static const parseError = -32700;

  /// The protocol's code for a message that is not a request.
  static const invalidRequest = -32600;

  /// The messages as they arrive, decoded; done when the input ends.
  Stream<Map<String, Object?>> get messages async* {
    final frames = _FrameReader(maxContentLength, maxHeaderLength);
    await for (final chunk in _input) {
      for (final frame in frames.add(chunk)) {
        if (_decode(frame) case final message?) {
          yield message;
        }
      }
    }
  }

  /// Sends [message], with its `jsonrpc` version.
  void send(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode({'jsonrpc': '2.0', ...message}));
    _output
      ..add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'))
      ..add(body);
  }

  Map<String, Object?>? _decode(Uint8List? body) {
    if (body == null) {
      _reject(invalidRequest, 'Content-Length over $maxContentLength bytes');
      return null;
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(body));
    } on FormatException catch (error) {
      _reject(parseError, 'Parse error: ${error.message}');
      return null;
    }
    if (json is! Map<String, Object?>) {
      _reject(invalidRequest, 'Invalid request: not an object');
      return null;
    }
    return json;
  }

  void _reject(int code, String message) => send({
    'id': null,
    'error': {'code': code, 'message': message},
  });
}

/// Cuts a byte stream into the bodies of its frames, in time linear in the
/// bytes: a read offset into one buffer, and the header end searched only
/// in bytes not searched before.
final class _FrameReader {
  _FrameReader(this._maxContentLength, this._maxHeaderLength);

  final int _maxContentLength;
  final int _maxHeaderLength;
  var _buffer = Uint8List(4096);
  var _start = 0;
  var _end = 0;
  var _searched = 0;
  int? _bodyLength;
  var _skipping = 0;

  static final _contentLength = RegExp(
    r'Content-Length:[ \t]*([0-9]+)',
    caseSensitive: false,
  );

  /// The frames [chunk] completes: each body, or null for one too long.
  List<Uint8List?> add(List<int> chunk) {
    var offset = 0;
    if (_skipping > 0) {
      offset = _skipping < chunk.length ? _skipping : chunk.length;
      _skipping -= offset;
    }
    _append(chunk, offset);
    final frames = <Uint8List?>[];
    while (true) {
      if (_bodyLength case final length?) {
        if (_end - _start < length) {
          break;
        }
        frames.add(
          Uint8List.fromList(_buffer.sublist(_start, _start + length)),
        );
        _start += length;
        _searched = _start;
        _bodyLength = null;
        continue;
      }
      final headerEnd = _headerEnd();
      if (headerEnd < 0) {
        if (_end - _start > _maxHeaderLength) {
          _start = _searched = _end;
        }
        break;
      }
      final headers = ascii.decode(
        Uint8List.sublistView(_buffer, _start, headerEnd),
        allowInvalid: true,
      );
      _start = _searched = headerEnd + 4;
      final digits = _contentLength.firstMatch(headers)?.group(1);
      if (digits == null) {
        continue;
      }
      final length = int.tryParse(digits);
      if (length == null || length > _maxContentLength) {
        frames.add(null);
        _skip(length ?? -1);
        continue;
      }
      _bodyLength = length;
    }
    return frames;
  }

  /// Drops the next [length] bytes (all that follow for a negative one
  /// that overflowed: the stream cannot be resynchronised).
  void _skip(int length) {
    final available = _end - _start;
    final skipped = length < 0 || length > available ? available : length;
    _start += skipped;
    _searched = _start;
    _skipping = length < 0 ? 1 << 62 : length - skipped;
  }

  int _headerEnd() {
    var i = _searched - 3 < _start ? _start : _searched - 3;
    for (; i + 3 < _end; i++) {
      if (_buffer[i] == 13 &&
          _buffer[i + 1] == 10 &&
          _buffer[i + 2] == 13 &&
          _buffer[i + 3] == 10) {
        return i;
      }
    }
    _searched = _end;
    return -1;
  }

  void _append(List<int> chunk, int from) {
    final length = chunk.length - from;
    if (length <= 0) {
      return;
    }
    if (_start == _end) {
      _start = _end = _searched = 0;
      if (_buffer.length > 1 << 20) {
        _buffer = Uint8List(4096);
      }
    }
    if (_end + length > _buffer.length) {
      final live = _end - _start;
      var capacity = _buffer.length;
      while (capacity < live + length) {
        capacity *= 2;
      }
      final buffer =
          (capacity == _buffer.length ? _buffer : Uint8List(capacity))
            ..setRange(0, live, _buffer, _start);
      _searched -= _start;
      _buffer = buffer;
      _start = 0;
      _end = live;
    }
    _buffer.setRange(_end, _end + length, chunk, from);
    _end += length;
  }
}
