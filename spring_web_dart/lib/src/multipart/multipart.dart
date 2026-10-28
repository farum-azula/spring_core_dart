import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/media_type.dart';

/// A file uploaded with a form (a `multipart/form-data` request): its
/// name, type, size and content.
///
/// A controller receives it as a parameter, with `@RequestPart('file')`,
/// `@RequestParam('file')` or no annotation at all (the parameter name is
/// then the field name); `List<MultipartFile>` takes every file of a
/// field. A nullable parameter makes the file optional. The web starter
/// writes the content of each file part to a temporary file while the
/// request is read, unless it fits under
/// `spring.servlet.multipart.file-size-threshold` (0 by default) or there
/// is no `dart:io` (then it stays in memory); the temporary files are
/// deleted when the request ends. Keep the content with [transferTo] or
/// by reading it during the request.
///
/// A Feign client sends a `MultipartFile` argument as a file part.
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
/// Use it to pass a file to a controller method or a Feign client from
/// code (a test, a file produced on the fly), where no upload took place.
/// Tests usually use `MockMultipartFile`, which extends it with Spring's
/// argument order.
///
/// ```dart
/// // A Feign client uploads a generated report.
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
  /// [MultipartException]; an error of [body] itself (a size limit) is
  /// passed on as it is. The preamble before the first boundary and the
  /// epilogue after the last are skipped.
  Stream<MultipartPart> bind(Stream<List<int>> body) {
    final parts = StreamController<MultipartPart>();
    parts.onListen = () => _run(body, parts);
    return parts.stream;
  }

  Future<void> _run(
    Stream<List<int>> body,
    StreamController<MultipartPart> parts,
  ) async {
    final reader = _ByteReader(body);
    try {
      // The preamble up to the first boundary (it starts the body, or
      // follows a CRLF).
      if (!await reader.skipPast(_first)) {
        throw MultipartException('no boundary found');
      }
      while (true) {
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
        final content = StreamController<List<int>>();
        parts.add(MultipartPart(headers, content.stream));
        final found = await reader.pipeUntil(_delimiter, content);
        await content.close();
        if (!found) {
          throw MultipartException('the body ends inside a part');
        }
      }
      await reader.drain();
      await parts.close();
    } on Object catch (error, stackTrace) {
      // Errors of the body itself (a size limit) pass through as they are.
      parts.addError(error, stackTrace);
      await parts.close();
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
/// Parts are put together into a [MultipartBody]. A Feign client builds
/// them from its `@RequestPart` parameters; build them yourself only to
/// send a multipart body by hand.
///
/// ```dart
/// final parts = [
///   MultipartBodyPart.field('title', 'Dune'),
///   MultipartBodyPart.json('meta', '{"pages": 412}'),
///   MultipartBodyPart.file('cover', bytes, filename: 'dune.png'),
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
      body = utf8.encode(value);

  /// A file field [name] holding [content], with an optional [filename].
  /// [contentType] defaults to the type guessed from the [filename]
  /// extension ([MediaTypeFactory]), else `application/octet-stream`.
  /// Without a [filename] the receiver sees a plain part, not a file.
  MultipartBodyPart.file(
    String name,
    List<int> content, {
    String? filename,
    String? contentType,
  }) : headers = HttpHeaders({
         HttpHeaders.contentDispositionHeader: ContentDisposition(
           'form-data',
           name: name,
           filename: filename,
         ).toString(),
         HttpHeaders.contentTypeHeader:
             contentType ??
             MediaTypeFactory.getMediaType(filename) ??
             MediaType.applicationOctetStream,
       }),
       body = content;

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
      body = utf8.encode(json);

  /// The headers of the part: `Content-Disposition`, and `Content-Type`
  /// for a file or JSON part.
  final HttpHeaders headers;

  /// The bytes of the part.
  final List<int> body;
}

/// A `multipart/form-data` body to send: the parts and the boundary that
/// separates them, encoded into bytes by [encode].
///
/// It is how a client uploads files together with form fields. Feign
/// clients and `MockMvc.multipart` build one for you; use it directly to
/// send an upload through an `HttpTransport`.
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
/// `FormHttpMessageWriter`:
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

  /// The whole body as bytes, ready to send; each call encodes it again.
  Uint8List encode() {
    final out = BytesBuilder(copy: false);
    for (final part in parts) {
      out.add(ascii.encode('--$boundary\r\n'));
      part.headers.forEach((name, values) {
        for (final value in values) {
          out.add(utf8.encode('$name: $value\r\n'));
        }
      });
      out
        ..add(const [0x0D, 0x0A])
        ..add(part.body)
        ..add(const [0x0D, 0x0A]);
    }
    out.add(ascii.encode('--$boundary--\r\n'));
    return out.takeBytes();
  }

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
