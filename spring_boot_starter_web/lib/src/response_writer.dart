import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/cors.dart' show addVary;
import 'package:spring_boot_starter_web/src/handler_method.dart';
import 'package:spring_boot_starter_web/src/sse_emitter.dart';
import 'package:spring_boot_starter_web/src/web_exceptions.dart';
import 'package:spring_boot_starter_web/src/web_server.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.mvc');

/// Turns what a controller method returns, or an error, into the HTTP
/// response: status, headers and body.
///
/// The router hands it the result of each handler and of each
/// `@ExceptionHandler`, and the dispatcher hands it the errors no
/// exception handler answered. The result's type decides the response,
/// and the mapping's `produces` and the request's `Accept` header decide
/// the media type (a 406 when they do not meet).
/// `@ResponseStatus(value)` sets the status of a normal answer;
/// `@ResponseStatus(value, reason: ...)` turns any result into a problem
/// with that detail.
///
/// | Result | Response |
/// |---|---|
/// | `null`, `void` | the status (200, or `@ResponseStatus`), no body |
/// | `ResponseEntity<T>` | its status and headers, the body as if alone |
/// | `ProblemDetail`, an `ErrorResponse` | `application/problem+json` |
/// | `String` | `text/plain` (or the mapping's `produces`) |
/// | `Uint8List` | `application/octet-stream` |
/// | `EventStream<T>`, `Stream<T>` | `text/event-stream` (NDJSON with `produces: application/x-ndjson`) |
/// | `Stream<Uint8List>`, `Stream<List<int>>` (declared so), `StreamingResponseBody` | the bytes as they come (`application/octet-stream` or `produces`) |
/// | `Resource`, `ResponseEntity<Resource>` | the content, with `Range` (206/416), `Last-Modified` (304) |
/// | `SseEmitter` | `text/event-stream`, events as they are sent |
/// | anything else | JSON through the `ObjectMapper` |
///
/// The headers of a `ResponseEntity` or an `ErrorResponse` replace those
/// of the same name, except `Vary`: its names join those already there
/// (the CORS processing's), as in Spring.
///
/// The starter declares it as the `responseWriter` bean, with the
/// application's `ObjectMapper` and `MessageSource`. Applications return
/// values from handlers; they do not call the writer. A filter or a
/// handler mapping of your own may use it to answer the same way, for
/// example with [writeError]. Spring spreads this work over its
/// `HttpMessageConverter`s and return value handlers.
final class ResponseWriter {
  /// A writer that writes JSON with [mapper]. [messageSource] resolves
  /// the messages of validation errors, [asyncTimeout] is the timeout of
  /// an [SseEmitter] that sets none, and [sseHeartbeat] the interval of
  /// keep-alive comments in event streams; both `null` by default (no
  /// timeout, no comments).
  ResponseWriter({
    required this.mapper,
    this.messageSource,
    this.asyncTimeout,
    this.sseHeartbeat,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Gives the current time, for the rate of the warnings of [writeError];
  /// tests replace it.
  final DateTime Function() clock;

  /// Writes objects as JSON, and the data of server-sent events.
  final ObjectMapper mapper;

  /// Turns the codes of validation errors into messages in the `errors`
  /// of a 400; without it, the default messages are used.
  final MessageSource? messageSource;

  /// How long an [SseEmitter] without its own timeout stays open
  /// (`spring.mvc.async.request-timeout`); `null` for no limit.
  final Duration? asyncTimeout;

  /// The interval at which an event stream gets an empty comment line,
  /// so proxies keep an idle stream open
  /// (`spring.mvc.sse.heartbeat-interval`); `null` for none.
  final Duration? sseHeartbeat;

  /// Writes [result], the value [handler] returned, and closes the
  /// response; see the table above. [produces] are the media types of
  /// the mapping. Completes when the body is written; for a stream, when
  /// it ends or the client goes away. Throws an
  /// `HttpMediaTypeNotAcceptableException` when the client accepts no
  /// type the result can be written as.
  Future<void> writeResult(
    Object? result,
    ServerHttpRequest request,
    ServerHttpResponse response, {
    HandlerMethod? handler,
    List<MediaType> produces = const [],
  }) async {
    if (response.isCommitted && result == null) {
      return await response.close();
    }
    final status = handler?.annotation<ResponseStatus>();
    if (status?.reason case final reason?) {
      return await writeProblem(
        ProblemDetail.forStatusAndDetail(status!.value, reason),
        request,
        response,
      );
    }
    switch (result) {
      case null:
        response.statusCode = status?.value ?? 200;
        return await response.close();
      case final ResponseEntity<Object?> entity:
        response.statusCode = entity.statusCode;
        _copyHeaders(entity.headers, response);
        // The body goes the way it would alone, with the entity's status
        // and headers (Spring's ResponseEntity<SseEmitter> and
        // ResponseEntity<Flux<T>>).
        return await switch (entity.body) {
          final SseEmitter emitter => _writeEmitter(
            emitter,
            request,
            response,
            status: entity.statusCode,
          ),
          final EventStream<Object?> stream => _writeStream(
            stream.events,
            request,
            response,
            produces,
            status: entity.statusCode,
          ),
          final Stream<Object?> stream when stream is! Stream<List<int>> =>
            _writeStream(
              stream,
              request,
              response,
              produces,
              status: entity.statusCode,
            ),
          final body => _writeEntityBody(
            entity,
            body,
            request,
            response,
            produces,
          ),
        };
      case final ProblemDetail problem:
        if (status != null) {
          problem.status = status.value;
        }
        return await writeProblem(problem, request, response);
      case final ErrorResponse error:
        return await writeErrorResponse(error, request, response);
      case final SseEmitter emitter:
        return await _writeEmitter(emitter, request, response);
      case final EventStream<Object?> stream:
        return await _writeStream(stream.events, request, response, produces);
      case final Stream<Object?> stream when _isByteStream(handler):
        response.statusCode = status?.value ?? 200;
        return await _writeByteStream(
          stream.cast<List<int>>(),
          response,
          produces,
        );
      case final Stream<Object?> stream:
        return await _writeStream(stream, request, response, produces);
      case final StreamingResponseBody body:
        response.statusCode = status?.value ?? 200;
        return await _writeStreaming(body, response, produces);
      case final Resource resource:
        response.statusCode = status?.value ?? 200;
        return await writeResource(resource, request, response);
      default:
        response.statusCode = status?.value ?? 200;
        return await _writeBody(result, request, response, produces);
    }
  }

  // The body of a ResponseEntity, after the request's conditions are
  // checked against its ETag and Last-Modified as Spring's
  // HttpEntityMethodProcessor checks them: only for a 200 to a GET or HEAD
  // (not for a body written as it comes, as Spring's
  // StreamingResponseBodyReturnValueHandler).
  Future<void> _writeEntityBody(
    ResponseEntity<Object?> entity,
    Object? body,
    ServerHttpRequest request,
    ServerHttpResponse response,
    List<MediaType> produces,
  ) async {
    if (entity.statusCode == HttpStatus.ok &&
        (request.method == HttpMethod.get ||
            request.method == HttpMethod.head) &&
        body is! StreamingResponseBody &&
        body is! Stream<List<int>> &&
        _checkNotModified(request, response)) {
      return await response.close();
    }
    return await _writeBody(body, request, response, produces);
  }

  Future<void> _writeBody(
    Object? body,
    ServerHttpRequest request,
    ServerHttpResponse response,
    List<MediaType> produces,
  ) async {
    if (body == null) {
      return await response.close();
    }
    if (body is Resource) {
      return await writeResource(body, request, response);
    }
    if (body is StreamingResponseBody) {
      return await _writeStreaming(body, response, produces);
    }
    if (body is Stream<List<int>>) {
      return await _writeByteStream(body, response, produces);
    }
    if (body is ProblemDetail) {
      body.instance ??= Uri.parse(request.path);
      return await _writeBytes(
        response,
        utf8.encode(jsonEncode(body.toJson())),
        response.headers.contentType ?? MediaType.applicationProblemJson,
      );
    }
    final accept = _accept(request);
    final declared = response.headers.contentType;
    if (body is String) {
      final type =
          declared ??
          _choose(produces, accept, const [MediaType.textPlain]) ??
          '${MediaType.textPlain};charset=UTF-8';
      return await _writeBytes(response, utf8.encode(body), _withCharset(type));
    }
    if (body is Uint8List) {
      final type =
          declared ??
          _choose(produces, accept, const [MediaType.applicationOctetStream]) ??
          MediaType.applicationOctetStream;
      return await _writeBytes(response, body, type);
    }
    final type =
        declared ??
        _choose(produces, accept, const [MediaType.applicationJson]) ??
        (throw HttpMediaTypeNotAcceptableException(const [
          MediaType.applicationJson,
        ]));
    final json = jsonEncode(mapper.valueToTree(body));
    return await _writeBytes(response, utf8.encode(json), type);
  }

  // The media type to write: one of [produces] (or [supported]) the
  // client accepts, or `null` when it accepts none.
  static String? _choose(
    List<MediaType> produces,
    List<MediaType> accept,
    List<String> supported,
  ) {
    final candidates = produces.isNotEmpty
        ? produces
        : [for (final s in supported) MediaType.parse(s)];
    for (final acceptable in accept) {
      for (final candidate in candidates) {
        if (acceptable.isCompatibleWith(candidate)) {
          return candidate.isWildcardType || candidate.isWildcardSubtype
              ? supported.first
              : '$candidate';
        }
      }
    }
    return null;
  }

  static String _withCharset(String type) =>
      type.toLowerCase().contains('charset') ? type : '$type;charset=UTF-8';

  static List<MediaType> _accept(ServerHttpRequest request) {
    try {
      final types = MediaType.parseMediaTypes(
        request.headers.getAll(HttpHeaders.acceptHeader).join(','),
      );
      if (types.isEmpty) {
        return [MediaType.parse(MediaType.all)];
      }
      // Highest quality first (stable).
      final indexed = types.indexed.toList()
        ..sort((a, b) {
          final byQuality = _quality(b.$2).compareTo(_quality(a.$2));
          return byQuality != 0 ? byQuality : a.$1.compareTo(b.$1);
        });
      return [for (final (_, type) in indexed) type];
    } on InvalidMediaTypeException {
      return [MediaType.parse(MediaType.all)];
    }
  }

  static double _quality(MediaType type) =>
      double.tryParse(type.getParameter('q') ?? '') ?? 1;

  Future<void> _writeBytes(
    ServerHttpResponse response,
    List<int> bytes,
    String contentType,
  ) {
    response.headers
      ..contentType = contentType
      ..contentLength = bytes.length;
    response.add(bytes);
    return response.close();
  }

  /// Writes [problem] as `application/problem+json` with its status, and
  /// closes the response. A problem without `instance` gets the request
  /// path.
  Future<void> writeProblem(
    ProblemDetail problem,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    problem.instance ??= Uri.parse(request.path);
    response
      ..statusCode = problem.status
      ..headers.contentType = MediaType.applicationProblemJson;
    final bytes = utf8.encode(jsonEncode(problem.toJson()));
    response.headers.contentLength = bytes.length;
    response.add(bytes);
    return response.close();
  }

  /// Writes an [ErrorResponse]: its status, its headers, and its problem
  /// as `application/problem+json`. For a validation failure the problem
  /// gets an `errors` list, one entry per field (`field`, `message`,
  /// `rejectedValue`) or object error, with messages from the
  /// [messageSource].
  Future<void> writeErrorResponse(
    ErrorResponse error,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    _copyHeaders(error.headers, response);
    final problem = error.body..status = error.statusCode;
    if (error is MethodArgumentNotValidException) {
      problem.setProperty('errors', [
        for (final fieldError in error.bindingResult.fieldErrors())
          {
            'field': fieldError.field,
            'message': _message(fieldError),
            'rejectedValue': _plain(fieldError.rejectedValue),
          },
        for (final globalError in error.bindingResult.globalErrors)
          {'object': globalError.objectName, 'message': _message(globalError)},
      ]);
    }
    return writeProblem(problem, request, response);
  }

  // Spring's ServletWebRequest.checkNotModified for a GET or HEAD with a
  // status of 200, against the ETag and Last-Modified already on
  // [response]; true when the answer is then complete without a body,
  // its status set:
  // - If-Unmodified-Since before Last-Modified (whole seconds): 412,
  //   without ETag and Last-Modified; at or after it, the full answer,
  //   whatever the other headers say (as Spring).
  // - If-None-Match with the ETag (compared weakly; a list, several
  //   headers): 304; `*` does not match a GET, as in Spring.
  // - Without If-None-Match, If-Modified-Since at or after Last-Modified:
  //   304.
  // The other headers stay (Cache-Control, Vary, CORS); the ETag is
  // quoted, a Last-Modified that is not an HTTP date removed.
  static bool _checkNotModified(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    final headers = response.headers;
    final eTag = headers.eTag;
    final lastModified = headers.lastModified?.millisecondsSinceEpoch ?? -1;
    // HTTP dates have whole seconds.
    final seconds = lastModified ~/ 1000 * 1000;
    // If-Match counts only for other methods than GET and HEAD.
    if (lastModified >= 0) {
      if (_dateHeader(request, HttpHeaders.ifUnmodifiedSinceHeader)
          case final since?) {
        if (since < seconds) {
          response.statusCode = HttpStatus.preconditionFailed;
          headers
            ..remove(HttpHeaders.etagHeader)
            ..remove(HttpHeaders.lastModifiedHeader);
          return true;
        }
        _cachingHeaders(headers, eTag, lastModified);
        return false;
      }
    }
    var notModified = false;
    final noneMatch = request.headers.getAll(HttpHeaders.ifNoneMatchHeader);
    if (noneMatch.isNotEmpty) {
      notModified = _matchesETag(noneMatch, eTag);
    } else if (lastModified >= 0) {
      if (_dateHeader(request, HttpHeaders.ifModifiedSinceHeader)
          case final since?) {
        notModified = since >= seconds;
      }
    }
    if (notModified) {
      response.statusCode = HttpStatus.notModified;
    }
    _cachingHeaders(headers, eTag, lastModified);
    return notModified;
  }

  // The ETag and Last-Modified as Spring's addCachingResponseHeaders puts
  // them back: the tag quoted, the date as an HTTP date (none when it is
  // not one, or not after 1970).
  static void _cachingHeaders(
    HttpHeaders headers,
    String? eTag,
    int lastModified,
  ) {
    if (lastModified > 0) {
      final date = HttpHeaders.formatDate(
        DateTime.fromMillisecondsSinceEpoch(lastModified, isUtc: true),
      );
      final present = headers.getAll(HttpHeaders.lastModifiedHeader);
      if (present.length != 1 || present.single != date) {
        headers.set(HttpHeaders.lastModifiedHeader, date);
      }
    } else {
      headers.remove(HttpHeaders.lastModifiedHeader);
    }
    if (eTag == null || eTag.isEmpty) {
      headers.remove(HttpHeaders.etagHeader);
    } else if (_quoteETag(eTag) != eTag) {
      headers.set(HttpHeaders.etagHeader, _quoteETag(eTag));
    }
  }

  // Spring's ETag.quoteETagIfNecessary.
  static String _quoteETag(String tag) {
    if (tag.startsWith('W/"')) {
      if (tag.length > 3 && tag.endsWith('"')) {
        return tag;
      }
    } else if (tag.startsWith('"')) {
      if (tag.length > 1 && tag.endsWith('"')) {
        return tag;
      }
    }
    return '"$tag"';
  }

  // Whether a tag of the If-None-Match [values] is [eTag], compared weakly
  // (Spring's ETag.create, ETag.parse and compare).
  static bool _matchesETag(List<String> values, String? eTag) {
    if (eTag == null || eTag.isEmpty) {
      return false;
    }
    var tag = eTag.startsWith('W/') ? eTag.substring(2) : eTag;
    if (tag.length > 2 && tag.startsWith('"') && tag.endsWith('"')) {
      tag = tag.substring(1, tag.length - 1);
    }
    return tag.isNotEmpty &&
        values.any((value) => _parseETags(value).contains(tag));
  }

  // Spring's ETag.parse: the tags of a value, without quotes nor `W/`
  // (`*` for the wildcard); what is not a tag is skipped.
  static List<String> _parseETags(String source) {
    final tags = <String>[];
    const before = 0;
    const inQuotes = 1;
    const after = 2;
    var state = before;
    var start = -1;
    for (var i = 0; i < source.length; i++) {
      final c = source[i];
      if (state == inQuotes) {
        if (c == '"') {
          final tag = source.substring(start, i);
          if (tag.trim().isNotEmpty) {
            tags.add(tag);
          }
          state = after;
        }
        continue;
      }
      if (c == ' ' || c == '\t') {
        continue;
      }
      if (c == ',') {
        state = before;
        continue;
      }
      if (state == before) {
        if (c == '*') {
          tags.add('*');
          state = after;
        } else if (c == '"') {
          state = inQuotes;
          start = i + 1;
        } else if (c == 'W' &&
            source.length > i + 2 &&
            source[i + 1] == '/' &&
            source[i + 2] == '"') {
          state = inQuotes;
          i += 2;
          start = i + 1;
        }
      }
    }
    return tags;
  }

  // A date header of [request] in milliseconds, as Spring reads it: an
  // HTTP date, or one followed by `; length=...` (old Internet Explorer);
  // `null` when absent or not a date.
  static int? _dateHeader(ServerHttpRequest request, String name) {
    final value = request.headers[name];
    if (value == null) {
      return null;
    }
    var date = HttpHeaders.parseDate(value);
    final separator = value.indexOf(';');
    if (date == null && separator >= 0) {
      date = HttpHeaders.parseDate(value.substring(0, separator));
    }
    return date?.millisecondsSinceEpoch;
  }

  // A handler's headers (of a ResponseEntity or an ErrorResponse) replace
  // those of the same name on the response, except Vary: its names join
  // those already there (the CORS processing's), as Spring's
  // HttpEntityMethodProcessor merges them.
  static void _copyHeaders(HttpHeaders headers, ServerHttpResponse response) {
    headers.forEach((name, values) {
      if (_same(name, HttpHeaders.varyHeader) &&
          response.headers.contains(HttpHeaders.varyHeader)) {
        addVary(response.headers, values);
        return;
      }
      response.headers.remove(name);
      for (final value in values) {
        response.headers.add(name, value);
      }
    });
  }

  static bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();

  String? _message(ObjectError error) {
    final source = messageSource;
    if (source != null) {
      try {
        return source.getMessageFromResolvable(error);
      } on Object {
        // Fall back to the default message.
      }
    }
    return error.defaultMessage;
  }

  static Object? _plain(Object? value) => switch (value) {
    null || String() || num() || bool() => value,
    _ => '$value',
  };

  /// Writes the default answer to an exception that no
  /// `@ExceptionHandler` handled.
  ///
  /// An [ErrorResponse] (such as a `ResponseStatusException`, or the 503
  /// of a refused session) answers with its own status and problem; from
  /// status 500 on it is logged as a warning without a stack trace, at
  /// most once per [warningInterval] for the same type and status (the
  /// others at debug level), below 500 at debug level. A request body
  /// above the size limit is a 413. Anything else is an unexpected error:
  /// a 500 without details for the client, and the exception logged as an
  /// error with its stack trace under `spring.web.mvc`. When the response
  /// is already committed, the error is only logged, the request marked
  /// with [responseFailedAttribute] and the response closed: the server
  /// then drops the connection instead of finishing the response, as
  /// Tomcat does.
  Future<void> writeError(
    Object error,
    StackTrace stackTrace,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    if (response.isCommitted) {
      _log.warning(
        'Request ${request.method.value} ${request.path} failed after the '
        'response was committed',
        error: error,
        stackTrace: stackTrace,
      );
      request.attributes[responseFailedAttribute] = error;
      return await response.close().catchError((_) {});
    }
    switch (error) {
      case final ErrorResponse errorResponse:
        if (errorResponse.statusCode >= 500) {
          _warnRateLimited(errorResponse, request);
        } else {
          _log.debug('Resolved [$error]');
        }
        return await writeErrorResponse(errorResponse, request, response);
      case PayloadTooLargeException(:final maxLength):
        return await writeErrorResponse(
          PayloadTooLargeErrorException(maxLength),
          request,
          response,
        );
      default:
        _log.error(
          'Request ${request.method.value} ${request.path} failed',
          error: error,
          stackTrace: stackTrace,
        );
        return await writeProblem(
          ProblemDetail.forStatus(HttpStatus.internalServerError),
          request,
          response,
        );
    }
  }

  // When each kind of 5xx answer (its type and status) was last logged,
  // and how many were left out since.
  final _lastWarnings = <String, (DateTime, int)>{};

  /// How often one kind of 5xx error answer is logged as a warning.
  static const warningInterval = Duration(seconds: 10);

  // A 5xx answer an exception asked for (a ResponseStatusException, a
  // refused session): logged as a warning without a stack trace, as
  // Spring logs resolved exceptions, and at most once per
  // [warningInterval] for the same kind, so a flood of refused requests
  // does not flood the log. The ones left out are counted in the next
  // line (and logged at debug level).
  void _warnRateLimited(ErrorResponse error, ServerHttpRequest request) {
    final key = '${error.runtimeType} ${error.statusCode}';
    final now = clock();
    final (last, skipped) = _lastWarnings[key] ?? (null, 0);
    if (last != null && now.difference(last) < warningInterval) {
      _lastWarnings[key] = (last, skipped + 1);
      _log.debug(
        'Request ${request.method.value} ${request.path} answered with '
        '$error',
      );
      return;
    }
    _lastWarnings[key] = (now, 0);
    _log.warning(
      'Request ${request.method.value} ${request.path} answered with $error'
      '${skipped == 0 ? '' : ' ($skipped more of these not logged since '
                'the last warning)'}',
    );
  }

  // ---------------------------------------------------------------------
  // Bytes: resources, byte streams, StreamingResponseBody
  // ---------------------------------------------------------------------

  // A handler declared to return `Stream<List<int>>` / `Stream<Uint8List>`
  // writes bytes, not server-sent events.
  static bool _isByteStream(HandlerMethod? handler) {
    final type = handler?.method.returnTypeInfo;
    if (type is! GenericType<Object?> || !type.isSubtypeOf<Stream<Object?>>()) {
      return false;
    }
    final element = type.arguments.firstOrNull;
    return element != null &&
        (element.type == Uint8List ||
            (element is ListType<Object?> && element.element.type == int));
  }

  String _bytesType(ServerHttpResponse response, List<MediaType> produces) =>
      response.headers.contentType ??
      (produces.isEmpty
          ? MediaType.applicationOctetStream
          : '${produces.first}');

  Future<void> _writeByteStream(
    Stream<List<int>> stream,
    ServerHttpResponse response,
    List<MediaType> produces,
  ) async {
    response.headers.contentType = _bytesType(response, produces);
    await response.addStream(stream);
    await response.close();
  }

  Future<void> _writeStreaming(
    StreamingResponseBody body,
    ServerHttpResponse response,
    List<MediaType> produces,
  ) async {
    response.headers.contentType = _bytesType(response, produces);
    await body.writeTo(ResponseBodySink._(response));
    await response.close();
  }

  /// Writes [resource] as a download and closes the response.
  ///
  /// - `Content-Type` comes from the file name (unless already set),
  ///   `application/octet-stream` when unknown; `Content-Length` and
  ///   `Accept-Ranges: bytes` are set.
  /// - A `FileSystemResource` is streamed from the file, never read whole,
  ///   and gets `Last-Modified`: a `GET` or `HEAD` with an
  ///   `If-Modified-Since` at or after it is a 304 without a body.
  /// - One byte range (`Range: bytes=0-99`) is a 206 with
  ///   `Content-Range`; a range past the end is a 416. Several ranges or
  ///   a malformed header get the whole content. `If-Range` with a date
  ///   applies the range only when the file has that `Last-Modified`.
  /// - A resource that does not exist or cannot be read is a 404.
  ///
  /// Spring's counterparts are `ResourceHttpMessageConverter` and
  /// `ResourceRegionHttpMessageConverter`.
  Future<void> writeResource(
    Resource resource,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    if (!resource.exists() || !resource.isReadable) {
      return await writeProblem(
        ProblemDetail.forStatusAndDetail(
          HttpStatus.notFound,
          'No resource ${resource.filename ?? ''}'.trim(),
        ),
        request,
        response,
      );
    }
    final file = resource is FileSystemResource ? resource : null;
    Uint8List? bytes;
    final int length;
    if (file != null) {
      length = file.contentLength();
    } else {
      bytes = await resource.readAsBytes();
      length = bytes.length;
    }
    final headers = response.headers
      ..contentType ??=
          MediaTypeFactory.getMediaType(resource.filename) ??
          MediaType.applicationOctetStream
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');
    final modified = file?.lastModified().toUtc();
    if (modified != null) {
      headers.lastModified = modified;
      final since =
          switch (request.headers[HttpHeaders.ifModifiedSinceHeader]) {
            final value? => HttpHeaders.parseDate(value),
            null => null,
          };
      // HTTP dates have whole seconds.
      final seconds = modified.millisecondsSinceEpoch ~/ 1000;
      if (since != null &&
          response.statusCode == 200 &&
          (request.method == HttpMethod.get ||
              request.method == HttpMethod.head) &&
          seconds <= since.millisecondsSinceEpoch ~/ 1000) {
        response.statusCode = HttpStatus.notModified;
        headers.remove(HttpHeaders.contentTypeHeader);
        return await response.close();
      }
    }
    var start = 0;
    var end = length; // exclusive
    final range = request.headers[HttpHeaders.rangeHeader];
    if (range != null &&
        response.statusCode == 200 &&
        _ifRangeMatches(request, modified)) {
      final parsed = _parseRange(range, length);
      if (parsed == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        headers
          ..set(HttpHeaders.contentRangeHeader, 'bytes */$length')
          ..remove(HttpHeaders.contentTypeHeader)
          ..contentLength = 0;
        return await response.close();
      }
      if (parsed case (final int from, final int to)) {
        start = from;
        end = to + 1;
        response.statusCode = HttpStatus.partialContent;
        headers.set(HttpHeaders.contentRangeHeader, 'bytes $from-$to/$length');
      }
    }
    headers.contentLength = end - start;
    if (request.method == HttpMethod.head) {
      return await response.close();
    }
    if (file != null) {
      await response.addStream(file.openRead(start, end));
    } else if (end > start) {
      response.add(Uint8List.sublistView(bytes!, start, end));
    }
    return await response.close();
  }

  // `If-Range` with a date: the range applies only to that version.
  static bool _ifRangeMatches(ServerHttpRequest request, DateTime? modified) {
    final ifRange = request.headers['If-Range'];
    if (ifRange == null) {
      return true;
    }
    final date = HttpHeaders.parseDate(ifRange);
    return date != null &&
        modified != null &&
        modified.millisecondsSinceEpoch ~/ 1000 ==
            date.millisecondsSinceEpoch ~/ 1000;
  }

  // One `bytes=` range of [length] bytes as (first, last) inclusive;
  // `null` when it cannot be satisfied; `()` (not a record of two) when
  // the header is malformed or has several ranges, which is answered
  // with the whole content (RFC 9110 allows ignoring Range).
  static Object? _parseRange(String header, int length) {
    final value = header.trim();
    if (!value.toLowerCase().startsWith('bytes=')) {
      return ();
    }
    final spec = value.substring(6).trim();
    if (spec.contains(',')) {
      return ();
    }
    final dash = spec.indexOf('-');
    if (dash < 0) {
      return ();
    }
    final first = spec.substring(0, dash).trim();
    final last = spec.substring(dash + 1).trim();
    if (first.isEmpty) {
      // The last N bytes.
      final suffix = int.tryParse(last);
      if (suffix == null) {
        return ();
      }
      if (suffix == 0 || length == 0) {
        return null;
      }
      return (length - (suffix > length ? length : suffix), length - 1);
    }
    final from = int.tryParse(first);
    final to = last.isEmpty ? length - 1 : int.tryParse(last);
    if (from == null || to == null || to < from) {
      return ();
    }
    if (from >= length) {
      return null;
    }
    return (from, to >= length ? length - 1 : to);
  }

  // ---------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------

  String _eventData(Object? data) => switch (data) {
    final String text => text,
    _ => jsonEncode(mapper.valueToTree(data)),
  };

  // The headers go out with the first body bytes (`dart:io` sends none
  // before), so the stream starts with a comment line, which clients
  // ignore: the client sees the response before the first event.
  Future<void> _startEvents(
    ServerHttpResponse response, {
    int status = 200,
  }) async {
    response
      ..statusCode = status
      ..headers.contentType = '${MediaType.textEventStream};charset=UTF-8'
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..write(':\n\n');
    await response.flush();
  }

  // Back pressure: the source is paused while an item is being written
  // and flushed, so a client that reads slowly (or not at all) slows the
  // source down instead of filling the server's memory.
  Future<void> _writeStream(
    Stream<Object?> stream,
    ServerHttpRequest request,
    ServerHttpResponse response,
    List<MediaType> produces, {
    int status = 200,
  }) async {
    final ndjson = produces.any(
      (p) => p.type == 'application' && p.subtype == 'x-ndjson',
    );
    if (ndjson) {
      response
        ..statusCode = status
        ..headers.contentType = MediaType.applicationNdjson;
    } else {
      await _startEvents(response, status: status);
    }
    final finished = Completer<void>();
    final out = _SerialWriter(response);
    Timer? heartbeat;
    late final StreamSubscription<Object?> subscription;
    Future<void> end() async {
      heartbeat?.cancel();
      if (!finished.isCompleted) {
        finished.complete();
      }
      await subscription.cancel();
    }

    out.onFailure = end;
    subscription = stream.listen(
      (item) {
        final String text;
        if (ndjson) {
          final data = item is ServerSentEvent<Object?> ? item.data : item;
          text = '${jsonEncode(mapper.valueToTree(data))}\n';
        } else {
          final event = item is ServerSentEvent<Object?>
              ? item
              : ServerSentEvent<Object?>(item);
          text = event.encode(_eventData);
        }
        subscription.pause();
        unawaited(out.write(text).whenComplete(subscription.resume));
      },
      onError: (Object error, StackTrace stackTrace) {
        _log.warning(
          'The stream of ${request.method.value} ${request.path} failed',
          error: error,
          stackTrace: stackTrace,
        );
        unawaited(end());
      },
      onDone: () => unawaited(out.idle.then((_) => end())),
    );
    final interval = sseHeartbeat;
    if (!ndjson && interval != null && interval > Duration.zero) {
      heartbeat = Timer.periodic(interval, (_) {
        // A stream still writing is not idle: no comment piles up behind
        // a client that does not read.
        if (out.isIdle) {
          unawaited(out.write(':\n\n'));
        }
      });
    }
    unawaited(response.done.then((_) => end()));
    await finished.future;
    await out.idle;
    await response.close().catchError((_) {});
  }

  Future<void> _writeEmitter(
    SseEmitter emitter,
    ServerHttpRequest request,
    ServerHttpResponse response, {
    int status = 200,
  }) async {
    final handler = _EmitterHandler(this, response);
    await _startEvents(response, status: status);
    final interval = sseHeartbeat;
    Timer? heartbeat;
    if (interval != null && interval > Duration.zero) {
      heartbeat = Timer.periodic(interval, (_) {
        if (!handler.isDone && handler.out.isIdle) {
          unawaited(handler.comment());
        }
      });
    }
    await emitter.initialize(handler, defaultTimeout: asyncTimeout);
    await handler.finished;
    heartbeat?.cancel();
  }
}

/// Writes and flushes the pieces of an event stream one after the other,
/// because `dart:io` refuses a write while a flush is pending. After a
/// failed write (the client went away), it calls [onFailure] once and
/// drops the rest.
final class _SerialWriter {
  _SerialWriter(this.response);

  /// The most writes an `SseEmitter` may have waiting for a client that
  /// does not read; past it the emitter fails ([_EmitterHandler.send]).
  static const maxPending = 1000;

  final ServerHttpResponse response;
  Future<void> _last = Future.value();
  Future<void> Function()? onFailure;
  var _failed = false;
  var _pending = 0;

  /// Completes when everything written so far is flushed (or dropped).
  Future<void> get idle => _last;

  /// Whether no write is waiting or in progress.
  bool get isIdle => _pending == 0;

  /// The writes waiting or in progress.
  int get pending => _pending;

  /// Drops every later write, as after a failed one.
  void fail() => _failed = true;

  Future<void> write(String text) {
    _pending++;
    return _last = _last.then((_) async {
      try {
        if (_failed) {
          return;
        }
        response.write(text);
        await response.flush();
      } on Object {
        _failed = true;
        await onFailure?.call();
      } finally {
        _pending--;
      }
    });
  }
}

final class _EmitterHandler implements SseEmitterHandler {
  _EmitterHandler(this.writer, this.response) : out = _SerialWriter(response) {
    unawaited(response.done.then((_) => _finish()));
    out.onFailure = () async => _finish();
  }

  final ResponseWriter writer;
  final ServerHttpResponse response;
  final _SerialWriter out;
  final _finished = Completer<void>();

  bool get isDone => _finished.isCompleted;

  Future<void> get finished => _finished.future;

  void _finish() {
    if (!_finished.isCompleted) {
      _finished.complete();
    }
  }

  @override
  Future<void> get done => _finished.future;

  @override
  Future<void> send(ServerSentEvent<Object?> event) async {
    if (isDone) {
      throw StateError('The client went away');
    }
    if (out.pending >= _SerialWriter.maxPending) {
      // A client that reads nothing while sends are not awaited: give up
      // instead of queueing without bound.
      out.fail();
      _finish();
      throw StateError(
        'The client does not read the event stream: '
        '${_SerialWriter.maxPending} events are waiting',
      );
    }
    await out.write(event.encode(writer._eventData));
  }

  Future<void> comment() => out.write(':\n\n');

  @override
  Future<void> complete() async {
    if (isDone) {
      return;
    }
    await out.idle;
    await response.close().catchError((_) {});
    _finish();
  }

  @override
  Future<void> completeWithError(Object error) async {
    _log.warning('SseEmitter completed with an error', error: error);
    await complete();
  }
}

/// The response the router gives a `GET` handler when it answers a `HEAD`
/// request: the handler writes as usual, but no body goes out.
///
/// `HEAD` asks for the headers a `GET` would get, without the body. This
/// wrapper lets every `GET` mapping answer `HEAD` without code of its own:
/// it drops what is written and, when the handler did not set
/// `Content-Length`, sets it from the first piece written. Applications
/// do not use it.
final class HeadResponse extends ServerHttpResponseDecorator {
  /// Wraps [delegate], the real response of a `HEAD` request.
  HeadResponse(super.delegate);

  @override
  void add(List<int> bytes) {
    if (!headers.contains(HttpHeaders.contentLengthHeader)) {
      headers.contentLength = bytes.length;
    }
  }

  @override
  void write(String text) => add(utf8.encode(text));

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();
}

/// A response body that the handler writes piece by piece, as it is
/// produced.
///
/// Return it, or put it in a `ResponseEntity`, for an export or a
/// download made on the fly, such as a CSV of every book: the first rows
/// reach the client while the rest is still being read, and the whole
/// file is never held in memory. Its function receives a
/// [ResponseBodySink] to write to; the response ends when the function's
/// `Future` completes. The media type is `application/octet-stream`
/// unless the mapping's `produces` or the entity's headers say otherwise.
///
/// ```dart
/// // Every book as a CSV line, sent as soon as it is read.
/// @GetMapping.of(path: '/export.csv', produces: 'text/csv')
/// StreamingResponseBody export() => StreamingResponseBody((out) async {
///   await for (final book in books.all()) {
///     out.write('${book.isbn},${book.title}\n');
///     await out.flush();
///   }
/// });
/// ```
///
/// Spring (Java):
/// ```java
/// @GetMapping(path = "/export.csv", produces = "text/csv")
/// StreamingResponseBody export() {
///   return out -> books.all().forEach(book -> ...);
/// }
/// ```
final class StreamingResponseBody {
  /// A body written by [writeTo].
  const StreamingResponseBody(this.writeTo);

  /// The function that writes the body to `out`; the response ends when
  /// its `Future` completes.
  final Future<void> Function(ResponseBodySink out) writeTo;
}

/// The output a [StreamingResponseBody] writes its body to.
///
/// What is written is buffered; call [flush] to send it to the client
/// now, for example after each row of an export.
final class ResponseBodySink {
  ResponseBodySink._(this._response);

  final ServerHttpResponse _response;

  /// Adds [bytes] to the body.
  void add(List<int> bytes) => _response.add(bytes);

  /// Adds [text] to the body, encoded as UTF-8.
  void write(String text) => _response.write(text);

  /// Sends what was written so far to the client; wait for it before
  /// writing more.
  Future<void> flush() => _response.flush();

  /// Adds every chunk of [stream] to the body; completes when the stream
  /// is done.
  Future<void> addStream(Stream<List<int>> stream) =>
      _response.addStream(stream);
}
