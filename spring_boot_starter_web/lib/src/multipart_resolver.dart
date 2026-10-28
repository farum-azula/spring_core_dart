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

/// The limits and storage settings for file uploads, read from
/// `spring.servlet.multipart.*`.
///
/// Uploads are `multipart/form-data` requests. The limits keep a client
/// from filling the disk or memory; the threshold and location decide
/// where uploaded files wait while the request is handled. Applications
/// set the properties; the starter reads them with
/// [MultipartProperties.of] for its [MultipartResolver].
///
/// | Property | Default |
/// |---|---|
/// | `spring.servlet.multipart.enabled` | `true` |
/// | `spring.servlet.multipart.max-file-size` | `1MB` (`-1`: no limit) |
/// | `spring.servlet.multipart.max-request-size` | `10MB` (`-1`: no limit) |
/// | `spring.servlet.multipart.file-size-threshold` | `0B`: every file goes to a temporary file (in memory where there is no `dart:io`) |
/// | `spring.servlet.multipart.location` | the system's temporary directory |
///
/// ```properties
/// # Covers up to 5 MB each, at most 20 MB per request.
/// spring.servlet.multipart.max-file-size=5MB
/// spring.servlet.multipart.max-request-size=20MB
/// ```
///
/// The keys are Spring Boot's; `file-size-threshold` defaults to `0B`
/// here, as in Boot, so every file goes to disk.
final class MultipartProperties {
  /// Settings with the defaults of the table above.
  const MultipartProperties({
    this.enabled = true,
    this.maxFileSize = 1024 * 1024,
    this.maxRequestSize = 10 * 1024 * 1024,
    this.fileSizeThreshold = 0,
    this.location,
  });

  /// Reads `spring.servlet.multipart.*` from [environment]. Sizes take a
  /// unit (`512KB`, `5MB`); `-1` means no limit.
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

  /// Whether multipart requests are read; `true` by default. With
  /// `false`, they are not parsed at all, and a `@RequestPart` parameter
  /// gets a 400.
  final bool enabled;

  /// The largest file, or text part, in bytes; 1 MB by default, `-1` for
  /// no limit.
  final int maxFileSize;

  /// The largest multipart request as a whole, in bytes; 10 MB by
  /// default, `-1` for no limit. It replaces
  /// `server.max-http-request-body-size` for these requests.
  final int maxRequestSize;

  /// The size, in bytes, up to which an uploaded file stays in memory;
  /// larger files are written to a temporary file. 0 by default: every
  /// file with content goes to disk. Ignored without `dart:io`, where
  /// files always stay in memory.
  final int fileSizeThreshold;

  /// The directory for temporary files, created when missing; `null`
  /// uses the system's temporary directory.
  final String? location;
}

/// The error of an upload larger than `spring.servlet.multipart.max-file-size`
/// or `max-request-size`; it is answered with a 413.
///
/// The resolver stops reading as soon as a limit is passed and deletes
/// what it stored. Catch it in an `@ExceptionHandler` to answer in your
/// own words.
///
/// ```dart
/// @ExceptionHandler()
/// @ResponseStatus(HttpStatus.contentTooLarge)
/// ProblemDetail tooLarge(MaxUploadSizeExceededException e) =>
///     ProblemDetail.forStatusAndDetail(
///       HttpStatus.contentTooLarge,
///       'Covers may have ${e.maxUploadSize ~/ 1024} KB at most.',
///     );
/// ```
///
/// Spring (Java):
/// ```java
/// @ExceptionHandler
/// ProblemDetail tooLarge(MaxUploadSizeExceededException e) { ... }
/// ```
class MaxUploadSizeExceededException extends ErrorResponseException {
  /// The limit of [maxUploadSize] bytes was passed; [what] names what was
  /// too large (`request`, `file "cover"`) in the problem's detail.
  MaxUploadSizeExceededException(this.maxUploadSize, String what)
    : super(
        HttpStatus.contentTooLarge,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.contentTooLarge,
          'Maximum upload size exceeded: the $what is larger than '
          '$maxUploadSize bytes.',
        ),
      );

  /// The limit that was passed, in bytes.
  final int maxUploadSize;
}

/// The error of a multipart request that cannot be read, answered with a
/// 400.
///
/// It is thrown for a body that is not valid `multipart/form-data` (no
/// boundary, a broken part), and when a `@RequestPart` parameter meets a
/// request that is not multipart. Spring's counterpart is
/// `MultipartException`.
class MultipartRequestException extends ErrorResponseException {
  /// The request cannot be read because of [reason], which ends up in
  /// the problem's detail.
  MultipartRequestException(String reason)
    : super(
        HttpStatus.badRequest,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.badRequest,
          'Failed to parse multipart request: $reason',
        ),
      );
}

/// The parts of an uploaded `multipart/form-data` request, read and
/// sorted into files and text fields.
///
/// Controllers usually get the parts through `@RequestPart` and
/// `@RequestParam` parameters. A filter or an argument resolver that
/// needs them asks the [MultipartResolver] bean, which reads the request
/// once and hands out the same result to every caller.
///
/// ```dart
/// // A filter that rejects uploads without a file named `cover`.
/// final parts = await multipartResolver.resolve(request);
/// if (parts.files['cover'] == null) {
///   return response.send(400, 'A cover is required');
/// }
/// ```
final class MultipartRequest {
  MultipartRequest._(this.files, this.fields, this._parts, this._cleanup);

  /// The file parts (those with a `filename`), by field name; a name may
  /// carry several files.
  final Map<String, List<MultipartFile>> files;

  /// The text of the other parts, by field name, decoded as UTF-8 (or
  /// Latin-1 when the part says so).
  final Map<String, List<String>> fields;

  final Map<String, List<(HttpHeaders, Uint8List)>> _parts;
  final Future<void> Function() _cleanup;

  /// The headers and raw bytes of the first part named [name] that is
  /// not a file, or `null`; how a JSON part is read into an object.
  (HttpHeaders, Uint8List)? part(String name) => _parts[name]?.firstOrNull;

  /// Deletes the temporary files of the uploads. The starter calls it
  /// when the request ends; files moved away with `transferTo` are kept.
  Future<void> cleanup() => _cleanup();
}

/// Reads the uploads of a multipart request: it splits the body into
/// files and text fields, and keeps big files on disk instead of in
/// memory.
///
/// The starter declares it as the `multipartResolver` bean, configured
/// from `spring.servlet.multipart.*`, and uses it for `@RequestPart`
/// parameters and for `@RequestParam` on a multipart request. A request
/// is read at most once, whoever asks first; files are streamed to
/// temporary files as they arrive, checked against the limits, and
/// deleted when the request ends. Declare a `MultipartResolver` bean of
/// your own to give it other properties than the configuration's; the
/// default then backs off.
///
/// ```dart
/// // Uploads of the admin application may be large.
/// @Bean()
/// MultipartResolver multipartResolver() => MultipartResolver(
///   const MultipartProperties(maxFileSize: -1, maxRequestSize: -1),
/// );
/// ```
///
/// Spring's counterpart is `StandardServletMultipartResolver`, which
/// leaves the parsing to the servlet container.
final class MultipartResolver {
  /// A resolver with [properties]; Spring Boot's defaults when none are
  /// given.
  MultipartResolver([this.properties = const MultipartProperties()]);

  /// The limits and storage settings.
  final MultipartProperties properties;

  static const _attribute = 'spring.web.multipartRequest';

  /// Whether this resolver reads [request]: it is enabled, and the
  /// request is not a `GET` and has a `multipart/*` content type.
  bool isMultipart(ServerHttpRequest request) {
    final type = request.contentType;
    return properties.enabled &&
        type != null &&
        type.type == 'multipart' &&
        request.method != HttpMethod.get;
  }

  /// The parts of [request]. The first call reads the body; later calls
  /// return the same result. Fails with a [MaxUploadSizeExceededException]
  /// above a limit, and with a [MultipartRequestException] for a body
  /// that cannot be parsed.
  Future<MultipartRequest> resolve(ServerHttpRequest request) {
    final cached = request.attributes[_attribute];
    if (cached is Future<MultipartRequest>) {
      return cached;
    }
    final future = _read(request);
    request.attributes[_attribute] = future;
    return future;
  }

  /// Deletes the temporary files of [request], if it was read; a failure
  /// is only logged. The starter calls it when the request ends.
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
