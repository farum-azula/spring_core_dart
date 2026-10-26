import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/media_type.dart';

/// An uploaded file of a `multipart/form-data` request, like Spring's
/// `MultipartFile`. A controller takes it with `@RequestPart('file')` (or
/// `@RequestParam('file')`); its content is in memory or, above
/// `spring.servlet.multipart.file-size-threshold`, in a temporary file
/// deleted after the request.
///
/// ```dart
/// @PostMapping.of(path: '/covers', consumes: MediaType.multipartFormData)
/// Future<void> upload(@RequestPart('file') MultipartFile file) async {
///   await storage.save(file.originalFilename ?? 'cover', await file.bytes);
/// }
/// ```
///
/// Spring (Java): `MultipartFile`.
abstract interface class MultipartFile {
  /// The name of the form field.
  String get name;

  /// The file name the client sent (`filename=` of the part), if any.
  String? get originalFilename;

  /// The part's `Content-Type`, if sent.
  String? get contentType;

  /// The size in bytes.
  int get size;

  /// Whether the file is empty (no file chosen in a browser form).
  bool get isEmpty;

  /// The part's headers.
  HttpHeaders get headers;

  /// The content.
  Future<Uint8List> get bytes;

  /// The content as a stream (read from the temporary file without loading
  /// it whole).
  Stream<List<int>> openRead();

  /// Writes the content to the file at [path] (`dart:io` only), like
  /// Spring's `transferTo`.
  Future<void> transferTo(String path);
}

/// A [MultipartFile] whose content is in memory: what a test passes to a
/// controller, or a small upload.
class InMemoryMultipartFile implements MultipartFile {
  /// A file of field [name] with [content].
  InMemoryMultipartFile(
    this.name,
    List<int> content, {
    this.originalFilename,
    this.contentType,
    HttpHeaders? headers,
  }) : _content = content is Uint8List ? content : Uint8List.fromList(content),
       headers = headers ?? HttpHeaders();

  /// A file of field [name] with UTF-8 [text].
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

/// One part of a multipart body while it is read: its headers and its
/// content as a stream (read it before the next part is delivered).
final class MultipartPart {
  /// A part with [headers] and [content].
  MultipartPart(this.headers, this.content);

  /// The part's headers.
  final HttpHeaders headers;

  /// The content; must be read (or drained) before the next part arrives.
  final Stream<List<int>> content;

  /// The `Content-Disposition` of the part.
  ContentDisposition? get disposition => headers.contentDisposition;

  /// The form field name (`name=`).
  String? get name => disposition?.name;

  /// The file name (`filename=`), for a file.
  String? get filename => disposition?.filename;

  /// Whether the part is a file (it has a `filename`).
  bool get isFile => filename != null;
}

/// A malformed multipart body.
class MultipartException implements Exception {
  /// The body is malformed because of [message].
  MultipartException(this.message);

  /// What is wrong.
  final String message;

  @override
  String toString() => 'MultipartException: $message';
}

/// Reads a `multipart/form-data` (or any `multipart/*`) body part by part,
/// streaming: the content of a part is delivered as it arrives, so a large
/// file never has to be in memory. Like the parsing behind Spring's
/// `StandardServletMultipartResolver`.
///
/// ```dart
/// final boundary = MultipartParser.boundaryOf(request.contentType!)!;
/// await for (final part in MultipartParser(boundary).bind(request.body)) {
///   print('${part.name}: ${(await part.content.toList()).length} chunks');
/// }
/// ```
final class MultipartParser {
  /// A parser for the [boundary] of the `Content-Type`.
  MultipartParser(String boundary, {this.maxHeaderSize = 16 * 1024})
    : _delimiter = ascii.encode('\r\n--$boundary'),
      _first = ascii.encode('--$boundary');

  /// The `boundary` parameter of a multipart [contentType], or `null`.
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

  /// The largest header block of one part, in bytes.
  final int maxHeaderSize;

  final Uint8List _delimiter;
  final Uint8List _first;

  /// The parts of [body], in order.
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

/// A part to send in a multipart body.
final class MultipartBodyPart {
  /// A plain form field [name] with [value].
  MultipartBodyPart.field(String name, String value)
    : headers = HttpHeaders({
        HttpHeaders.contentDispositionHeader: ContentDisposition(
          'form-data',
          name: name,
        ).toString(),
      }),
      body = utf8.encode(value);

  /// A file field [name] with [content], [filename] and [contentType].
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

  /// A part [name] holding [json] (`application/json`).
  MultipartBodyPart.json(String name, String json)
    : headers = HttpHeaders({
        HttpHeaders.contentDispositionHeader: ContentDisposition(
          'form-data',
          name: name,
        ).toString(),
        HttpHeaders.contentTypeHeader: MediaType.applicationJson,
      }),
      body = utf8.encode(json);

  /// The part's headers.
  final HttpHeaders headers;

  /// The content.
  final List<int> body;
}

/// Writes a `multipart/form-data` body, like Spring's
/// `MultipartBodyBuilder` with `FormHttpMessageWriter`.
///
/// ```dart
/// final body = MultipartBody([
///   MultipartBodyPart.field('title', 'Dune'),
///   MultipartBodyPart.file('cover', bytes, filename: 'dune.png'),
/// ]);
/// request.headers.contentType = body.contentType;
/// request.add(body.encode());
/// ```
final class MultipartBody {
  /// A body with [parts] (and a random [boundary] unless given).
  MultipartBody(this.parts, {String? boundary})
    : boundary = boundary ?? _randomBoundary();

  /// The parts.
  final List<MultipartBodyPart> parts;

  /// The boundary between the parts.
  final String boundary;

  /// The `Content-Type` to send.
  String get contentType =>
      '${MediaType.multipartFormData}; boundary=$boundary';

  /// The whole body.
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
    return 'spring-${List.generate(24, (_) => chars[random.nextInt(chars.length)]).join()}';
  }
}

/// The media type of a file from its name, like Spring's
/// `MediaTypeFactory`.
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

  /// The media type of [filename] by its extension, or `null`.
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
