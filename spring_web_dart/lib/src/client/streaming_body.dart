import 'dart:async';
import 'dart:typed_data';

import 'package:spring_core_dart/core.dart' show NonRetryableException;

/// A request body sent as a stream of chunks while it is read, instead of
/// a list of bytes held whole in memory: a large file, an upload passed
/// on, data produced while it is sent.
///
/// `HttpRequest.streamingBody` carries one. A transport sends it with
/// `Content-Length` when [length] is known, else in chunks (chunked
/// transfer encoding), and reads it as fast as the connection takes it:
/// an upload of any size costs a chunk or two of memory. A `RestClient`
/// gets one from `body(stream)`, `body(StreamingBody(...))` or a
/// `MultipartBody` with a streamed part.
///
/// A stream is read once. A body made from a stream ([StreamingBody.new])
/// is sent once: a second attempt (a retry, a redirect that sends the body
/// again, an interceptor that calls `execute` twice) throws a
/// [NonRepeatableBodyException] instead of sending what is left of the
/// stream. A body made with [StreamingBody.repeatable] opens its source
/// again for each attempt, as a file can.
///
/// ```dart
/// // A backup of any size, read from the disk while it is sent.
/// final file = File('backup.tar');
/// await rest.put()
///     .uri('/backups/{id}', {'id': id})
///     .body(
///       StreamingBody.repeatable(file.openRead, length: file.lengthSync()),
///     )
///     .retrieve()
///     .toBodilessEntity();
/// ```
///
/// Spring (Java): `StreamingHttpOutputMessage.Body`, which writes to an
/// `OutputStream` and says whether it can do so again (`repeatable()`):
/// ```java
/// restClient.put().uri("/backups/{id}", id)
///     .body(out -> Files.copy(path, out))
///     .retrieve().toBodilessEntity();
/// ```
final class StreamingBody {
  /// A body read once from [stream], which must be a single-subscription
  /// stream (a broadcast stream drops what it sends before it is
  /// listened to). [length] is the number of bytes [stream] gives, when it
  /// is known; it must be exact.
  StreamingBody(Stream<List<int>> stream, {this.length})
    : _stream = stream,
      _open = null,
      _parent = null {
    if (stream.isBroadcast) {
      throw ArgumentError.value(
        stream,
        'stream',
        'is a broadcast stream, which drops what it sends before it is '
            'listened to: pass a single-subscription stream',
      );
    }
    _checkLength(length);
  }

  /// A body whose source [open] gives anew for each attempt: a file
  /// (`file.openRead`), an object in storage, bytes produced again.
  /// [length] is the number of bytes each stream gives, when it is known;
  /// it must be exact.
  StreamingBody.repeatable(Stream<List<int>> Function() open, {this.length})
    : _open = open,
      _stream = null,
      _parent = null {
    _checkLength(length);
  }

  // A body read once that reads [_parent] ([observed]): sent when either
  // is.
  StreamingBody._readingOnce(StreamingBody parent, Stream<List<int>> stream)
    : _stream = stream,
      _open = null,
      _parent = parent,
      length = parent.length;

  final Stream<List<int>>? _stream;
  final Stream<List<int>> Function()? _open;
  final StreamingBody? _parent;

  /// The number of bytes of the body, or `null` when it is not known (then
  /// it goes in chunks, without `Content-Length`).
  final int? length;

  /// Whether the body can be sent more than once: made with
  /// [StreamingBody.repeatable].
  bool get isRepeatable => _open != null;

  /// Whether the stream of a body read once has been listened to: it
  /// cannot be sent again. Always `false` for a repeatable body.
  bool get isConsumed =>
      _stream != null &&
      (_listened ||
          (_listenedStreams[_stream] ?? false) ||
          (_parent?.isConsumed ?? false));

  bool _listened = false;

  // The streams a body has listened to, so that a new body made from the
  // same stream (a retried method that wraps its argument again) knows.
  static final _listenedStreams = Expando<bool>('listened');

  /// The stream of the body, to send it. A repeatable body calls its
  /// source again; a body read once gives its stream, which counts as
  /// sent once listened to. Throws a [NonRepeatableBodyException] when the
  /// stream of a body read once was listened to already.
  Stream<List<int>> open() {
    if (_open case final open?) {
      return open();
    }
    if (isConsumed) {
      throw NonRepeatableBodyException(
        'The request body is a stream that was sent once already and '
        'cannot be sent again; make it with StreamingBody.repeatable (a '
        'file part opens its file again) to allow another attempt',
      );
    }
    return _ListenedOnce(this);
  }

  /// The whole body in memory, read from a new [open]: for code that needs
  /// the bytes (an interceptor of a `RestClient`, a transport that cannot
  /// stream). Throws a [StateError] when the stream does not give
  /// [length] bytes.
  Future<Uint8List> toBytes() async {
    final bytes = await open().fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (builder, chunk) => builder..add(chunk),
    );
    final expected = length;
    if (expected != null && bytes.length != expected) {
      throw StateError(
        'The request body gave ${bytes.length} bytes, its length says '
        '$expected',
      );
    }
    return bytes.takeBytes();
  }

  /// This body with [onChunk] told of every chunk as it is sent, unchanged:
  /// to count what goes out. It can be sent again when this one can, and
  /// opens this one only when it is opened itself.
  StreamingBody observed(void Function(List<int> chunk) onChunk) {
    Stream<List<int>> watched(Stream<List<int>> stream) => stream.map((chunk) {
      onChunk(chunk);
      return chunk;
    });
    if (isRepeatable) {
      return StreamingBody.repeatable(() => watched(open()), length: length);
    }
    return StreamingBody._readingOnce(this, _Deferred(() => watched(open())));
  }

  // Marks the stream listened to; false when it was already.
  bool _markListened() {
    if (isConsumed) {
      return false;
    }
    _listened = true;
    _listenedStreams[_stream!] = true;
    return true;
  }

  static void _checkLength(int? length) {
    if (length != null && length < 0) {
      throw ArgumentError.value(length, 'length', 'must not be negative');
    }
  }

  @override
  String toString() =>
      'StreamingBody(${length == null ? 'length unknown' : '$length bytes'}'
      '${isRepeatable ? ', repeatable' : ''})';
}

/// Thrown when a request body that can be read only once is to be sent a
/// second time: a retry, a redirect that sends the body again or an
/// interceptor that calls `execute` twice, with a [StreamingBody] made
/// from a stream (or a `MultipartBody` with such a part).
///
/// What is left of a stream that was read is never sent in its place, so
/// a half or empty body cannot reach the server. It is never retried
/// (a [NonRetryableException]): `@Retryable` and `RetryTemplate` stop at
/// it and throw it with the failure of the first attempt. To allow another
/// attempt, make the body with `StreamingBody.repeatable`, which opens its
/// source again (a file part does).
///
/// ```dart
/// try {
///   await uploads.send(StreamingBody(request.body));
/// } on NonRepeatableBodyException {
///   // The first attempt failed after it had read the upload.
/// }
/// ```
///
/// Spring (Java): no exception of Spring's own; Apache HttpClient throws
/// `NonRepeatableRequestException` for a body whose entity is not
/// repeatable.
final class NonRepeatableBodyException
    implements NonRetryableException, Exception {
  /// The failure described by [message].
  NonRepeatableBodyException(this.message);

  /// What could not be sent again, for people.
  final String message;

  @override
  String toString() => 'NonRepeatableBodyException: $message';
}

// The stream of a body read once: listening to it marks the body sent
// and listens to the source, with nothing in between.
final class _ListenedOnce extends Stream<List<int>> {
  _ListenedOnce(this._body);

  final StreamingBody _body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> chunk)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final source = _body._markListened()
        ? _body._stream!
        : Stream<List<int>>.error(
            NonRepeatableBodyException(
              'The request body is a stream that was sent once already and '
              'cannot be sent again',
            ),
          );
    return source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

// A stream made by [_make] when it is listened to.
final class _Deferred extends Stream<List<int>> {
  _Deferred(this._make);

  final Stream<List<int>> Function() _make;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> chunk)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    Stream<List<int>> source;
    try {
      source = _make();
    } on Object catch (error, stackTrace) {
      source = Stream<List<int>>.error(error, stackTrace);
    }
    return source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
