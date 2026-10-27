// The documentation has Markdown table rows, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/multipart_store_stub.dart'
    if (dart.library.io) 'package:spring_boot_starter_web/src/multipart_store_io.dart'
    as store;
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.multipart');

/// The `spring.servlet.multipart.*` properties, like Spring Boot's
/// `MultipartProperties`.
///
/// | Property | Default |
/// |---|---|
/// | `spring.servlet.multipart.enabled` | `true` |
/// | `spring.servlet.multipart.max-file-size` | `1MB` (`-1`: no limit) |
/// | `spring.servlet.multipart.max-request-size` | `10MB` (`-1`: no limit) |
/// | `spring.servlet.multipart.file-size-threshold` | `0B`: every file goes to a temporary file (in memory where there is no `dart:io`) |
/// | `spring.servlet.multipart.location` | the system's temporary directory |
final class MultipartProperties {
  /// The settings; see the table above for the defaults.
  const MultipartProperties({
    this.enabled = true,
    this.maxFileSize = 1024 * 1024,
    this.maxRequestSize = 10 * 1024 * 1024,
    this.fileSizeThreshold = 0,
    this.location,
  });

  /// Reads `spring.servlet.multipart.*` from [environment].
  factory MultipartProperties.of(PropertyResolver environment) {
    String? text(String key) {
      final value = environment
          .getProperty('spring.servlet.multipart.$key')
          ?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    int size(String key, int fallback) => switch (text(key)) {
      null => fallback,
      '-1' => -1,
      final value => DataSize.parse(value).toBytes(),
    };

    return MultipartProperties(
      enabled: text('enabled')?.toLowerCase() != 'false',
      maxFileSize: size('max-file-size', 1024 * 1024),
      maxRequestSize: size('max-request-size', 10 * 1024 * 1024),
      fileSizeThreshold: size('file-size-threshold', 0),
      location: text('location'),
    );
  }

  /// Whether multipart requests are parsed.
  final bool enabled;

  /// The largest file part, in bytes (`-1`: no limit).
  final int maxFileSize;

  /// The largest multipart request, in bytes (`-1`: no limit).
  final int maxRequestSize;

  /// Files above this size go to a temporary file.
  final int fileSizeThreshold;

  /// The directory of the temporary files (`null`: the system's).
  final String? location;
}

/// The upload is larger than `spring.servlet.multipart.max-file-size` or
/// `max-request-size`: 413, like Spring's `MaxUploadSizeExceededException`.
class MaxUploadSizeExceededException extends ErrorResponseException {
  /// The limit of [maxUploadSize] bytes was exceeded.
  MaxUploadSizeExceededException(this.maxUploadSize, String what)
    : super(
        HttpStatus.contentTooLarge,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.contentTooLarge,
          'Maximum upload size exceeded: the $what is larger than '
          '$maxUploadSize bytes.',
        ),
      );

  /// The limit, in bytes.
  final int maxUploadSize;
}

/// A malformed multipart request: 400, like Spring's
/// `MultipartException`.
class MultipartRequestException extends ErrorResponseException {
  /// The request is malformed because of [reason].
  MultipartRequestException(String reason)
    : super(
        HttpStatus.badRequest,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.badRequest,
          'Failed to parse multipart request: $reason',
        ),
      );
}

/// The parts of a `multipart/form-data` request.
final class MultipartRequest {
  MultipartRequest._(this.files, this.fields, this._parts, this._cleanup);

  /// The file parts (with a `filename`), by field name.
  final Map<String, List<MultipartFile>> files;

  /// The text parts (without a `filename`), by field name.
  final Map<String, List<String>> fields;

  final Map<String, List<(HttpHeaders, Uint8List)>> _parts;
  final Future<void> Function() _cleanup;

  /// The raw content and headers of the non-file part [name] (a JSON part
  /// read into an object).
  (HttpHeaders, Uint8List)? part(String name) => _parts[name]?.firstOrNull;

  /// Deletes the temporary files.
  Future<void> cleanup() => _cleanup();
}

/// Reads `multipart/form-data` requests once per request, like Spring's
/// `StandardServletMultipartResolver`: files above the threshold go to
/// temporary files, deleted when the request ends.
final class MultipartResolver {
  /// A resolver with [properties].
  MultipartResolver([this.properties = const MultipartProperties()]);

  /// The settings.
  final MultipartProperties properties;

  static const _attribute = 'spring.web.multipartRequest';

  /// Whether [request] is a multipart request this resolver reads.
  bool isMultipart(ServerHttpRequest request) {
    final type = request.contentType;
    return properties.enabled &&
        type != null &&
        type.type == 'multipart' &&
        request.method != HttpMethod.get;
  }

  /// The parts of [request] (read on the first call).
  Future<MultipartRequest> resolve(ServerHttpRequest request) {
    final cached = request.attributes[_attribute];
    if (cached is Future<MultipartRequest>) {
      return cached;
    }
    final future = _read(request);
    request.attributes[_attribute] = future;
    return future;
  }

  /// Deletes the temporary files of [request], if it was read.
  Future<void> cleanup(ServerHttpRequest request) async {
    final cached = request.attributes.remove(_attribute);
    if (cached is Future<MultipartRequest>) {
      try {
        await (await cached).cleanup();
      } on Object catch (error) {
        _log.debug('Could not delete the temporary files: $error');
      }
    }
  }

  Future<MultipartRequest> _read(ServerHttpRequest request) async {
    final contentType = request.contentType;
    final boundary = contentType == null
        ? null
        : MultipartParser.boundaryOf(contentType);
    if (boundary == null) {
      throw MultipartRequestException('no boundary in the Content-Type');
    }
    final files = <String, List<MultipartFile>>{};
    final fields = <String, List<String>>{};
    final parts = <String, List<(HttpHeaders, Uint8List)>>{};
    final temporary = <store.StoredFile>[];
    Future<void> cleanup() async {
      for (final file in temporary) {
        await file.delete();
      }
    }

    final maxRequest = properties.maxRequestSize;
    final maxFile = properties.maxFileSize;
    var total = 0;
    final body = request.body.map((chunk) {
      total += chunk.length;
      if (maxRequest >= 0 && total > maxRequest) {
        throw MaxUploadSizeExceededException(maxRequest, 'request');
      }
      return chunk;
    });
    try {
      await for (final part in MultipartParser(boundary).bind(body)) {
        final name = part.name;
        if (name == null) {
          await part.content.drain<void>();
          continue;
        }
        if (part.isFile) {
          final writer = store.FileWriter(
            threshold: properties.fileSizeThreshold,
            location: properties.location,
          );
          var size = 0;
          await for (final chunk in part.content) {
            size += chunk.length;
            if (maxFile >= 0 && size > maxFile) {
              await writer.abort();
              throw MaxUploadSizeExceededException(maxFile, 'file "$name"');
            }
            await writer.add(chunk);
          }
          final stored = await writer.close();
          if (stored.isTemporary) {
            temporary.add(stored);
          }
          (files[name] ??= []).add(
            _StoredMultipartFile(
              name,
              part.filename,
              part.headers.contentType,
              part.headers,
              stored,
            ),
          );
        } else {
          final out = BytesBuilder(copy: false);
          await for (final chunk in part.content) {
            out.add(chunk);
            if (maxFile >= 0 && out.length > maxFile) {
              throw MaxUploadSizeExceededException(maxFile, 'part "$name"');
            }
          }
          final bytes = out.takeBytes();
          (parts[name] ??= []).add((part.headers, bytes));
          (fields[name] ??= []).add(_text(part.headers, bytes));
        }
      }
    } on MaxUploadSizeExceededException {
      await cleanup();
      rethrow;
    } on MultipartException catch (error) {
      await cleanup();
      throw MultipartRequestException(error.message);
    } on PayloadTooLargeException catch (error) {
      await cleanup();
      throw MaxUploadSizeExceededException(error.maxLength, 'request');
    }
    return MultipartRequest._(files, fields, parts, cleanup);
  }

  static String _text(HttpHeaders headers, Uint8List bytes) {
    final charset = switch (headers.contentType) {
      final type? => _charset(type),
      null => null,
    };
    return charset == 'iso-8859-1' || charset == 'latin1'
        ? latin1.decode(bytes)
        : utf8.decode(bytes, allowMalformed: true);
  }

  static String? _charset(String type) {
    try {
      return MediaType.parse(type).getParameter('charset')?.toLowerCase();
    } on InvalidMediaTypeException {
      return null;
    }
  }
}

final class _StoredMultipartFile implements MultipartFile {
  _StoredMultipartFile(
    this.name,
    this.originalFilename,
    this.contentType,
    this.headers,
    this._stored,
  );

  @override
  final String name;

  @override
  final String? originalFilename;

  @override
  final String? contentType;

  @override
  final HttpHeaders headers;

  final store.StoredFile _stored;

  @override
  int get size => _stored.size;

  @override
  bool get isEmpty => _stored.size == 0;

  @override
  Future<Uint8List> get bytes => _stored.readBytes();

  @override
  Stream<List<int>> openRead() => _stored.openRead();

  @override
  Future<void> transferTo(String path) => _stored.copyTo(path);

  @override
  String toString() =>
      'MultipartFile($name, ${originalFilename ?? '-'}, $size bytes)';
}
