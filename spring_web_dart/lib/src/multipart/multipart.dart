import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/streaming_body.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/media_type.dart';
import 'package:spring_web_dart/src/multipart/file_source_stub.dart'
    if (dart.library.io) 'package:spring_web_dart/src/multipart/file_source_io.dart'
    as file_source;

/// A file uploaded with a form (a `multipart/form-data` request): its
/// name, type, size and content.
///
/// A controller receives it as a parameter, with `@RequestPart('file')`,
/// `@RequestParam('file')` or no annotation at all (the parameter name is
/// then the field name); `List<MultipartFile>` takes every file of a
/// field. A nullable parameter makes the file optional. The web starter
/// writes the content of each file part to a temporary file while the
/// request is read, unless it fits under
/// `spring.web.multipart.file-size-threshold` (0 by default) or there
/// is no `dart:io` (then it stays in memory); the temporary files are
/// deleted when the request ends. Keep the content with [transferTo] or
/// by reading it during the request.
///
/// An HTTP service client sends a `MultipartFile` argument as a file part.
///
/// ```dart
/// // Saves an uploaded cover under its original name.
/// @PostMapping.of(path: '/covers', consumes: MediaType.multipartFormData)
/// Future<void> upload(@RequestPart('file') MultipartFile file) async {
///   await storage.save(file.originalFilename ?? 'cover', await file.bytes);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @PostMapping(path = "/covers",
///     consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
/// void upload(@RequestPart("file") MultipartFile file) throws IOException {
///   storage.save(file.getOriginalFilename(), file.getBytes());
/// }
/// ```
abstract interface class MultipartFile {
  /// The name of the form field the file was sent in (`name=` of the
  /// part), not the file name.
  String get name;

  /// The file name on the client's machine (`filename=` of the part), or
  /// `null` when it sent none. Do not use it as a path as it is: it comes
  /// from the client.
  String? get originalFilename;

  /// The `Content-Type` the client gave the part (`image/png`), or `null`
  /// when it sent none. It is the client's claim, not checked.
  String? get contentType;

  /// The size of the content, in bytes.
  int get size;

  /// Whether the content is empty, which is what a browser sends when no
  /// file was chosen in the form.
  bool get isEmpty;

  /// All the headers of the part, for anything besides the name and the
  /// type.
  HttpHeaders get headers;

  /// The whole content, loaded into memory; for a large file prefer
  /// [openRead] or [transferTo].
  Future<Uint8List> get bytes;

  /// The content as a stream of chunks, read from the temporary file
  /// without loading it whole; each call starts a new read.
  Stream<List<int>> openRead();

  /// Saves the content as the file at [path], like Spring's `transferTo`.
  /// A temporary file is moved there when possible (else copied), so call
  /// it once, after any other read. Needs `dart:io`; an
  /// [InMemoryMultipartFile] throws an `UnsupportedError`.
  Future<void> transferTo(String path);
}

/// A [MultipartFile] whose content is a list of bytes in memory.
///
/// Use it to pass a file to a controller method or an HTTP service client from
/// code (a test, a file produced on the fly), where no upload took place.
/// Tests usually use `MockMultipartFile`, which extends it with Spring's
/// argument order.
///
/// ```dart
/// // An HTTP service client uploads a generated report.
/// await archive.store(InMemoryMultipartFile.fromString(
///   'report',
///   csv,
///   originalFilename: 'report.csv',
///   contentType: 'text/csv',
/// ));
/// ```
///
/// Spring (Java): no direct equivalent; `MockMultipartFile` or a
/// `ByteArrayResource` play this part.
class InMemoryMultipartFile implements MultipartFile {
  /// A file for the form field [name] holding [content], with optional
  /// [originalFilename], [contentType] and part [headers]. The content is
  /// not copied when it is already a `Uint8List`.
  InMemoryMultipartFile(
    this.name,
    List<int> content, {
    this.originalFilename,
    this.contentType,
    HttpHeaders? headers,
  }) : _content = content is Uint8List ? content : Uint8List.fromList(content),
       headers = headers ?? HttpHeaders();

  /// A file for the form field [name] holding [text] in UTF-8; its
  /// [contentType] is `text/plain; charset=utf-8` unless given.
  factory InMemoryMultipartFile.fromString(
    String name,
    String text, {
    String? originalFilename,
    String? contentType = 'text/plain; charset=utf-8',
  }) => InMemoryMultipartFile(
    name,
    utf8.encode(text),
    originalFilename: originalFilename,
    contentType: contentType,
  );

  final Uint8List _content;

  @override
  final String name;

  @override
  final String? originalFilename;

  @override
  final String? contentType;

  @override
  final HttpHeaders headers;

  @override
  int get size => _content.length;

  @override
  bool get isEmpty => _content.isEmpty;

  @override
  Future<Uint8List> get bytes async => _content;

  @override
  Stream<List<int>> openRead() => Stream.value(_content);

  @override
  Future<void> transferTo(String path) => throw UnsupportedError(
    'InMemoryMultipartFile.transferTo needs dart:io; write `await bytes` '
    'yourself',
  );

  @override
  String toString() =>
      'MultipartFile($name, ${originalFilename ?? '-'}, $size bytes)';
}

/// One part of a multipart body, as [MultipartParser] delivers it while
/// the body is read: its headers and its content as a stream.
///
/// The content must be read or drained before the next part can arrive,
/// because the parts come one after the other from the same body.
/// Applications rarely see it: the web starter turns the parts into
/// [MultipartFile]s and form fields.
final class MultipartPart {
  /// A part with its [headers] and its [content] stream.
  MultipartPart(this.headers, this.content);

  /// The headers of the part: `Content-Disposition`, often
  /// `Content-Type`.
  final HttpHeaders headers;

  /// The bytes of the part, delivered as they are read from the body.
  /// Read or drain it before the next part arrives.
  final Stream<List<int>> content;

  /// The `Content-Disposition` of the part parsed, or `null` when it has
  /// none.
  ContentDisposition? get disposition => headers.contentDisposition;

  /// The form field name (`name=`), or `null` when the part has none.
  String? get name => disposition?.name;

  /// The file name (`filename=`) of a file part, or `null` for a plain
  /// field.
  String? get filename => disposition?.filename;

  /// Whether the part is a file, which is decided by the presence of a
  /// `filename` (even an empty one).
  bool get isFile => filename != null;
}

/// Thrown by [MultipartParser] when a multipart body does not follow the
/// format: no boundary, a part that never ends, headers too large.
///
/// The web starter turns it into a 400 response, so a controller does
/// not need to catch it.
class MultipartException implements Exception {
  /// A malformed body, described by [message].
  MultipartException(this.message);

  /// What is wrong with the body, for the error response or the log.
  final String message;

  @override
  String toString() => 'MultipartException: $message';
}

/// Reads a `multipart/form-data` body (or any `multipart/*` body) part by
/// part, while it arrives.
///
/// The content of each part is delivered as a stream as soon as its bytes
/// are read, so a large upload never has to be in memory at once, and a
/// slow consumer slows the reading down. The web starter reads uploads
/// with it; use it yourself only to handle a multipart body by hand, for
/// example to stream an upload elsewhere without a temporary file.
///
/// ```dart
/// // A handler streams each uploaded file straight to storage.
/// final boundary = MultipartParser.boundaryOf(request.contentType!)!;
/// await for (final part in MultipartParser(boundary).bind(request.body)) {
///   if (part.isFile) {
///     await storage.write(part.filename!, part.content);
///   } else {
///     await part.content.drain<void>();
///   }
/// }
/// ```
///
/// Spring (Java): no public equivalent; the servlet container parses the
/// body behind `StandardServletMultipartResolver`.
final class MultipartParser {
  /// A parser for bodies whose parts are separated by [boundary], the
  /// `boundary` parameter of the `Content-Type` (see [boundaryOf]).
  /// [maxHeaderSize] limits the header block of each part.
  MultipartParser(String boundary, {this.maxHeaderSize = 16 * 1024})
    : _delimiter = ascii.encode('\r\n--$boundary'),
      _first = ascii.encode('--$boundary');

  /// The `boundary` parameter of [contentType], or `null` when the type is
  /// not `multipart/*` or the boundary is missing, empty or longer than
  /// the 70 characters the format allows.
  static String? boundaryOf(MediaType contentType) {
    if (contentType.type != 'multipart') {
      return null;
    }
    final boundary = contentType.getParameter('boundary');
    if (boundary == null || boundary.isEmpty || boundary.length > 70) {
      return null;
    }
    return boundary;
  }

  /// The largest header block of one part, in bytes (16 KB by default);
  /// a larger one is a [MultipartException].
  final int maxHeaderSize;

  final Uint8List _delimiter;
  final Uint8List _first;

  /// The parts of [body], in order, read when the returned stream is
  /// listened to. A malformed body ends the stream with a
  /// [MultipartException]; an error of [body] itself (a size limit, a
  /// client that went away) is passed on as it is. An error in the middle
  /// of a part also ends that part's [MultipartPart.content] with the
  /// error, so code reading the part never waits for bytes that cannot
  /// come. Cancelling the subscription stops reading [body]. The preamble
  /// before the first boundary and the epilogue after the last are
  /// skipped.
  Stream<MultipartPart> bind(Stream<List<int>> body) {
    final run = _ParserRun();
    final parts = StreamController<MultipartPart>();
    parts
      ..onListen = () {
        run.reader = _ByteReader(body);
        unawaited(_run(run, parts));
      }
      ..onCancel = run.partsCancelled;
    return parts.stream;
  }

  Future<void> _run(
    _ParserRun run,
    StreamController<MultipartPart> parts,
  ) async {
    final reader = run.reader;
    try {
      // The preamble up to the first boundary (it starts the body, or
      // follows a CRLF).
      if (!await reader.skipPast(_first)) {
        throw MultipartException('no boundary found');
      }
      while (!run.stopped) {
        // After a boundary: "--" ends the body, CRLF starts a part.
        final after = await reader.take(2);
        if (after == null) {
          throw MultipartException('the body ends inside a boundary');
        }
        if (after[0] == 0x2D && after[1] == 0x2D) {
          break;
        }
        if (after[0] != 0x0D || after[1] != 0x0A) {
          // Transport padding (spaces) before the CRLF is allowed.
          if (!await reader.skipPast(const [0x0D, 0x0A])) {
            throw MultipartException('malformed boundary line');
          }
        }
        final headerBytes = await reader.readUntil(const [
          0x0D,
          0x0A,
          0x0D,
          0x0A,
        ], limit: maxHeaderSize);
        if (headerBytes == null) {
          throw MultipartException('part headers too large or unfinished');
        }
        final headers = _parseHeaders(
          utf8.decode(headerBytes, allowMalformed: true),
        );
        final content = run.current = StreamController<List<int>>(
          onCancel: run.partCancelled,
        );
        parts.add(MultipartPart(headers, content.stream));
        final found = await reader.pipeUntil(_delimiter, content);
        if (run.stopped) {
          break;
        }
        if (!found) {
          throw MultipartException('the body ends inside a part');
        }
        run.current = null;
        // Completes once the reader of the part took its last bytes: the
        // next part comes after it.
        await content.close();
      }
      if (run.stopped) {
        await reader.cancel();
      } else {
        await reader.drain();
      }
      unawaited(parts.close());
    } on Object catch (error, stackTrace) {
      // Errors of the body itself (a size limit, a client gone) pass
      // through as they are: to the part being read, whose reader would
      // otherwise wait forever, and to the stream of parts.
      if (run.current case final content? when !content.isClosed) {
        content.addError(error, stackTrace);
        unawaited(content.close());
      }
      if (!parts.isClosed) {
        parts.addError(error, stackTrace);
        unawaited(parts.close());
      }
      await reader.cancel();
    }
  }

  static HttpHeaders _parseHeaders(String text) {
    final headers = HttpHeaders();
    String? name;
    final value = StringBuffer();
    void flush() {
      if (name != null) {
        headers.add(name!, value.toString().trim());
      }
      name = null;
      value.clear();
    }

    for (final line in text.split('\r\n')) {
      if (line.isEmpty) {
        continue;
      }
      if ((line.startsWith(' ') || line.startsWith('\t')) && name != null) {
        value.write(' ${line.trim()}');
        continue;
      }
      flush();
      final colon = line.indexOf(':');
      if (colon <= 0) {
        throw MultipartException('malformed part header "$line"');
      }
      name = line.substring(0, colon).trim();
      value.write(line.substring(colon + 1));
    }
    flush();
    return headers;
  }
}

// The state of one [MultipartParser.bind]: once nobody listens to the
// parts any more and nobody reads the current part, reading the body
// stops (a consumer that gave up, for example at a size limit).
final class _ParserRun {
  late final _ByteReader reader;
  StreamController<List<int>>? current;
  var _partsCancelled = false;
  bool stopped = false;

  void partsCancelled() {
    _partsCancelled = true;
    if (current == null || !current!.hasListener) {
      _stop();
    }
  }

  void partCancelled() {
    if (_partsCancelled) {
      _stop();
    }
  }

  void _stop() {
    if (!stopped) {
      stopped = true;
      unawaited(reader.cancel());
    }
  }
}

// Reads a byte stream with look-ahead: searches for delimiters across
// chunk boundaries.
final class _ByteReader {
  _ByteReader(Stream<List<int>> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<List<int>> _iterator;
  Uint8List _buffer = Uint8List(0);
  var _done = false;

  Future<bool> _fill() async {
    if (_done) {
      return false;
    }
    if (!await _iterator.moveNext()) {
      _done = true;
      return false;
    }
    final chunk = _iterator.current;
    final merged = Uint8List(_buffer.length + chunk.length)
      ..setRange(0, _buffer.length, _buffer)
      ..setRange(_buffer.length, _buffer.length + chunk.length, chunk);
    _buffer = merged;
    return true;
  }

  Future<Uint8List?> take(int count) async {
    while (_buffer.length < count) {
      if (!await _fill()) {
        return null;
      }
    }
    final result = Uint8List.sublistView(_buffer, 0, count);
    _buffer = Uint8List.sublistView(_buffer, count);
    return Uint8List.fromList(result);
  }

  // Skips everything up to and including [pattern]; false at the end.
  Future<bool> skipPast(List<int> pattern) async {
    while (true) {
      final index = _indexOf(_buffer, pattern);
      if (index >= 0) {
        _buffer = Uint8List.sublistView(_buffer, index + pattern.length);
        return true;
      }
      final keep = min(_buffer.length, pattern.length - 1);
      _buffer = Uint8List.sublistView(_buffer, _buffer.length - keep);
      if (!await _fill()) {
        return false;
      }
    }
  }

  // The bytes before [pattern] (consumed with it), or null past [limit] or
  // at the end.
  Future<Uint8List?> readUntil(List<int> pattern, {required int limit}) async {
    while (true) {
      final index = _indexOf(_buffer, pattern);
      if (index >= 0) {
        final result = Uint8List.fromList(
          Uint8List.sublistView(_buffer, 0, index),
        );
        _buffer = Uint8List.sublistView(_buffer, index + pattern.length);
        return result;
      }
      if (_buffer.length > limit + pattern.length) {
        return null;
      }
      if (!await _fill()) {
        return null;
      }
    }
  }

  // Sends the bytes before [pattern] to [sink] as they come (consuming
  // the pattern); false when the stream ended first.
  Future<bool> pipeUntil(
    List<int> pattern,
    StreamController<List<int>> sink,
  ) async {
    while (true) {
      final index = _indexOf(_buffer, pattern);
      if (index >= 0) {
        if (index > 0) {
          await _emit(sink, Uint8List.fromList(_buffer.sublist(0, index)));
        }
        _buffer = Uint8List.sublistView(_buffer, index + pattern.length);
        return true;
      }
      // Everything except a possible beginning of the pattern.
      final safe = _buffer.length - (pattern.length - 1);
      if (safe > 0) {
        await _emit(sink, Uint8List.fromList(_buffer.sublist(0, safe)));
        _buffer = Uint8List.sublistView(_buffer, safe);
      }
      if (!await _fill()) {
        return false;
      }
    }
  }

  // Adds [bytes] and waits while the listener is paused, so a slow
  // consumer slows the reading (back pressure). A part nobody listens to
  // is buffered by its controller.
  static Future<void> _emit(
    StreamController<List<int>> sink,
    List<int> bytes,
  ) async {
    sink.add(bytes);
    while (sink.hasListener && sink.isPaused) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<void> drain() async {
    _buffer = Uint8List(0);
    while (await _fill()) {
      _buffer = Uint8List(0);
    }
  }

  Future<void> cancel() => _iterator.cancel();

  static int _indexOf(Uint8List data, List<int> pattern) {
    final last = data.length - pattern.length;
    outer:
    for (var i = 0; i <= last; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          continue outer;
        }
      }
      return i;
    }
    return -1;
  }
}

/// One part of a multipart body to send: a form field, a file or a JSON
/// value, with its headers.
///
/// Parts are put together into a [MultipartBody]. An HTTP service client
/// builds them from its `@RequestPart` parameters; build them yourself
/// only to send a multipart body by hand.
///
/// A part holds its content in memory ([MultipartBodyPart.field],
/// [MultipartBodyPart.file], [MultipartBodyPart.json]) or reads it while
/// the body is sent ([MultipartBodyPart.stream],
/// [MultipartBodyPart.streaming], [MultipartBodyPart.fromPath],
/// [MultipartBodyPart.multipartFile]): a file of any size then costs a
/// chunk or two of memory.
///
/// ```dart
/// final parts = [
///   MultipartBodyPart.field('title', 'Dune'),
///   MultipartBodyPart.json('meta', '{"pages": 412}'),
///   MultipartBodyPart.file('cover', bytes, filename: 'dune.png'),
///   // Read from the disk while it is sent.
///   MultipartBodyPart.fromPath('scan', '/var/scans/dune.pdf'),
/// ];
/// ```
final class MultipartBodyPart {
  /// A text field [name] holding [value], sent in UTF-8 without a
  /// `Content-Type`, as a browser sends a text input.
  MultipartBodyPart.field(String name, String value)
    : headers = HttpHeaders({
        HttpHeaders.contentDispositionHeader: ContentDisposition(
          'form-data',
          name: name,
        ).toString(),
      }),
      _bytes = utf8.encode(value),
      _streaming = null;

  /// A file field [name] holding [content], with an optional [filename].
  /// [contentType] defaults to the type guessed from the [filename]
  /// extension ([MediaTypeFactory]), else `application/octet-stream`.
  /// Without a [filename] the receiver sees a plain part, not a file.
  MultipartBodyPart.file(
    String name,
    List<int> content, {
    String? filename,
    String? contentType,
  }) : headers = _fileHeaders(name, filename, contentType),
       _bytes = content,
       _streaming = null;

  /// A file field [name] whose content is read from [stream] while the
  /// body is sent, once: a body with this part cannot be sent again (see
  /// [StreamingBody]). [length] is the number of bytes of [stream] when it
  /// is known (exact): with the lengths of all its parts known, the body
  /// goes with `Content-Length`, else in chunks. [filename] and
  /// [contentType] as for [MultipartBodyPart.file].
  ///
  /// ```dart
  /// // Passes on a download without keeping it.
  /// final scan = await transport.stream(request);
  /// final length = scan.headers.contentLength; // -1 when not sent
  /// final part = MultipartBodyPart.stream(
  ///   'scan',
  ///   scan.body,
  ///   length: length < 0 ? null : length,
  ///   filename: 'scan.pdf',
  /// );
  /// ```
  MultipartBodyPart.stream(
    String name,
    Stream<List<int>> stream, {
    int? length,
    String? filename,
    String? contentType,
  }) : this.streaming(
         name,
         StreamingBody(stream, length: length),
         filename: filename,
         contentType: contentType,
       );

  /// A file field [name] whose content [body] gives while the body is
  /// sent; a [StreamingBody.repeatable] opens it again for another
  /// attempt. [filename] and [contentType] as for
  /// [MultipartBodyPart.file].
  MultipartBodyPart.streaming(
    String name,
    StreamingBody body, {
    String? filename,
    String? contentType,
  }) : headers = _fileHeaders(name, filename, contentType),
       _bytes = null,
       _streaming = body;

  /// A file field [name] holding the file at [path], read from the disk
  /// while the body is sent and opened again for another attempt. Its
  /// length is read now (a `FileSystemException` when the file cannot be
  /// read). [filename] defaults to the file's name, [contentType] to the
  /// type guessed from it. Needs `dart:io`: in a browser it throws an
  /// [UnsupportedError].
  ///
  /// Spring (Java): a `FileSystemResource` as a part,
  /// `builder.part("scan", new FileSystemResource(path))`.
  factory MultipartBodyPart.fromPath(
    String name,
    String path, {
    String? filename,
    String? contentType,
  }) {
    final source = file_source.fileSource(path);
    return MultipartBodyPart.streaming(
      name,
      source.body,
      filename: filename ?? source.filename,
      contentType: contentType,
    );
  }

  /// A file field [name] holding the uploaded [file], read through
  /// [MultipartFile.openRead] while the body is sent instead of loaded
  /// whole (`await file.bytes`), with its size, original name and type:
  /// how a server passes an upload on to another service. Each attempt
  /// reads the file again.
  ///
  /// ```dart
  /// @PostMapping.of(path: '/covers', consumes: MediaType.multipartFormData)
  /// Future<void> upload(@RequestPart('file') MultipartFile file) =>
  ///     rest.post().uri('/archive').body(MultipartBody([
  ///       MultipartBodyPart.multipartFile('file', file),
  ///     ])).retrieve().toBodilessEntity();
  /// ```
  ///
  /// Spring (Java): `builder.part("file", file.getResource())`.
  MultipartBodyPart.multipartFile(String name, MultipartFile file)
    : this.streaming(
        name,
        StreamingBody.repeatable(file.openRead, length: file.size),
        filename: file.originalFilename,
        contentType: file.contentType,
      );

  /// A part [name] holding the JSON text [json], with
  /// `Content-Type: application/json`; a server reads it into an object
  /// for an `@RequestPart` parameter.
  MultipartBodyPart.json(String name, String json)
    : headers = HttpHeaders({
        HttpHeaders.contentDispositionHeader: ContentDisposition(
          'form-data',
          name: name,
        ).toString(),
        HttpHeaders.contentTypeHeader: MediaType.applicationJson,
      }),
      _bytes = utf8.encode(json),
      _streaming = null;

  static HttpHeaders _fileHeaders(
    String name,
    String? filename,
    String? contentType,
  ) => HttpHeaders({
    HttpHeaders.contentDispositionHeader: ContentDisposition(
      'form-data',
      name: name,
      filename: filename,
    ).toString(),
    HttpHeaders.contentTypeHeader:
        contentType ??
        MediaTypeFactory.getMediaType(filename) ??
        MediaType.applicationOctetStream,
  });

  /// The headers of the part: `Content-Disposition`, and `Content-Type`
  /// for a file or JSON part.
  final HttpHeaders headers;

  final List<int>? _bytes;
  final StreamingBody? _streaming;

  /// The bytes of the part. A streamed part has none in memory: it throws
  /// a [StateError] (read [open] instead).
  List<int> get body =>
      _bytes ??
      (throw StateError(
        'A streamed multipart part has no bytes in memory; read open()',
      ));

  /// Whether the content is read while the body is sent, not held in
  /// memory.
  bool get isStreamed => _streaming != null;

  /// Whether the part can be sent again: always for one in memory, for a
  /// streamed one when its source opens again.
  bool get isRepeatable => _streaming?.isRepeatable ?? true;

  /// The number of bytes of the content, or `null` for a stream whose
  /// length is not known.
  int? get length => _bytes?.length ?? _streaming!.length;

  /// The content as a stream: the bytes in one chunk, or the stream of a
  /// streamed part (see [StreamingBody.open]).
  Stream<List<int>> open() => switch (_bytes) {
    final bytes? => Stream.value(bytes),
    null => _streaming!.open(),
  };

  bool get _isConsumed => _streaming?.isConsumed ?? false;
}

/// A `multipart/form-data` body to send: the parts and the boundary that
/// separates them, encoded into bytes by [encode], or written as a stream
/// by [toStreamingBody] when a part is streamed.
///
/// It is how a client uploads files together with form fields. HTTP
/// service clients and `MockMvc.multipart` build one for you; use it
/// directly to send an upload through a `RestClient` or an
/// `HttpTransport`. A `RestClient` sends it whole when its parts are in
/// memory, and as a stream when one of them is streamed (a file of any
/// size then costs a chunk or two of memory): with `Content-Length` when
/// the length of every part is known, else in chunks.
///
/// ```dart
/// // Uploads a book with its cover to another service.
/// final body = MultipartBody([
///   MultipartBodyPart.field('title', 'Dune'),
///   MultipartBodyPart.file('cover', bytes, filename: 'dune.png'),
/// ]);
/// final response = await transport.send(HttpRequest(
///   method: HttpMethod.post,
///   url: Uri.parse('https://api.neon.books/books'),
///   headers: HttpHeaders({HttpHeaders.contentTypeHeader: body.contentType}),
///   body: body.encode(),
/// ));
/// ```
///
/// Spring (Java): `MultipartBodyBuilder`, written by
/// `FormHttpMessageConverter`:
/// ```java
/// MultipartBodyBuilder builder = new MultipartBodyBuilder();
/// builder.part("title", "Dune");
/// builder.part("cover", new ByteArrayResource(bytes) {
///   @Override public String getFilename() { return "dune.png"; }
/// });
/// webClient.post().uri("/books")
///     .body(BodyInserters.fromMultipartData(builder.build())).retrieve();
/// ```
final class MultipartBody {
  /// A body with [parts], in order. The [boundary] is random
  /// (`spring-` and 24 letters or digits) unless given; give one only to
  /// get the same bytes every time, as a test may.
  MultipartBody(this.parts, {String? boundary})
    : boundary = boundary ?? _randomBoundary();

  /// The parts, in the order they are written.
  final List<MultipartBodyPart> parts;

  /// The text that separates the parts in the body; it must not appear in
  /// any part.
  final String boundary;

  /// The `Content-Type` to send with the body:
  /// `multipart/form-data; boundary=...`. Without it the receiver cannot
  /// split the parts.
  String get contentType =>
      '${MediaType.multipartFormData}; boundary=$boundary';

  /// Whether a part is streamed: the body is then sent through
  /// [toStreamingBody], not [encode].
  bool get isStreamed => parts.any((part) => part.isStreamed);

  /// The exact number of bytes of the body, or `null` when the length of
  /// a streamed part is not known.
  int? get contentLength {
    var total = _closing.length;
    for (final part in parts) {
      final length = part.length;
      if (length == null) {
        return null;
      }
      total += _head(part).length + length + 2;
    }
    return total;
  }

  /// The whole body as bytes, ready to send; each call encodes it again.
  /// Throws a [StateError] when a part is streamed ([isStreamed]): send
  /// [toStreamingBody] instead.
  Uint8List encode() {
    if (isStreamed) {
      throw StateError(
        'The multipart body has a streamed part: send toStreamingBody(), '
        'not encode()',
      );
    }
    final out = BytesBuilder(copy: false);
    for (final part in parts) {
      out
        ..add(_head(part))
        ..add(part.body)
        ..add(const [0x0D, 0x0A]);
    }
    out.add(_closing);
    return out.takeBytes();
  }

  /// The body as a [StreamingBody] that writes the parts one after the
  /// other while it is read, the streamed ones as they arrive, with the
  /// exact [contentLength] when it is known. It can be sent again when
  /// every streamed part can (see [MultipartBodyPart.isRepeatable]). Throws
  /// a [NonRepeatableBodyException] when a part read once has been sent
  /// already.
  StreamingBody toStreamingBody() {
    _checkNotSent();
    final length = contentLength;
    return parts.every((part) => part.isRepeatable)
        ? StreamingBody.repeatable(_write, length: length)
        : StreamingBody(_write(), length: length);
  }

  void _checkNotSent() {
    if (parts.any((part) => part._isConsumed)) {
      throw NonRepeatableBodyException(
        'A part of the multipart body is a stream that was sent once '
        'already and cannot be sent again; make it with '
        'MultipartBodyPart.streaming and StreamingBody.repeatable, '
        'MultipartBodyPart.fromPath or MultipartBodyPart.multipartFile to '
        'allow another attempt',
      );
    }
  }

  Stream<List<int>> _write() async* {
    // Nothing goes out when a part cannot be sent whole.
    _checkNotSent();
    for (final part in parts) {
      yield _head(part);
      yield* part.open();
      yield const [0x0D, 0x0A];
    }
    yield _closing;
  }

  // The boundary line and the headers of [part], up to its content.
  Uint8List _head(MultipartBodyPart part) {
    final out = BytesBuilder(copy: false)..add(ascii.encode('--$boundary\r\n'));
    part.headers.forEach((name, values) {
      for (final value in values) {
        out.add(utf8.encode('$name: $value\r\n'));
      }
    });
    out.add(const [0x0D, 0x0A]);
    return out.takeBytes();
  }

  List<int> get _closing => ascii.encode('--$boundary--\r\n');

  static String _randomBoundary() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    final suffix = List.generate(
      24,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    return 'spring-$suffix';
  }
}

/// Guesses the media type of a file from the extension of its name
/// (`cover.png` is `image/png`).
///
/// It fills in the `Content-Type` when only a file name is known: a file
/// part sent without a type, a file a controller returns for download.
/// It knows the common text, image, audio, video, font, archive and web
/// types.
///
/// ```dart
/// MediaTypeFactory.getMediaType('dune.png'); // 'image/png'
/// MediaTypeFactory.getMediaType('notes'); // null
/// ```
///
/// Spring (Java): `MediaTypeFactory.getMediaType("dune.png")`, which
/// returns an `Optional<MediaType>`.
abstract final class MediaTypeFactory {
  static const _types = {
    'txt': 'text/plain',
    'html': 'text/html',
    'htm': 'text/html',
    'css': 'text/css',
    'csv': 'text/csv',
    'md': 'text/markdown',
    'xml': 'application/xml',
    'js': 'text/javascript',
    'mjs': 'text/javascript',
    'json': 'application/json',
    'map': 'application/json',
    'webmanifest': 'application/manifest+json',
    'wasm': 'application/wasm',
    'pdf': 'application/pdf',
    'zip': 'application/zip',
    'gz': 'application/gzip',
    'tar': 'application/x-tar',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'avif': 'image/avif',
    'svg': 'image/svg+xml',
    'ico': 'image/vnd.microsoft.icon',
    'bmp': 'image/bmp',
    'mp3': 'audio/mpeg',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'yaml': 'application/yaml',
    'yml': 'application/yaml',
  };

  /// The media type for the extension of [filename], in any case, or
  /// `null` when [filename] is `null`, has no extension or an unknown one.
  static String? getMediaType(String? filename) {
    if (filename == null) {
      return null;
    }
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) {
      return null;
    }
    return _types[filename.substring(dot + 1).toLowerCase()];
  }
}
