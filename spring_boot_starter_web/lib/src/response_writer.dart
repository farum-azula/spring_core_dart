import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/handler_method.dart';
import 'package:spring_boot_starter_web/src/sse_emitter.dart';
import 'package:spring_boot_starter_web/src/web_exceptions.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.mvc');

/// Writes what handlers return, and errors, to the response, like
/// Spring's `HttpMessageConverter`s and return value handlers:
///
/// | Result | Response |
/// |---|---|
/// | `null`, `void` | the status (200, or `@ResponseStatus`), no body |
/// | `ResponseEntity<T>` | its status, headers and body |
/// | `ProblemDetail`, an `ErrorResponse` | `application/problem+json` |
/// | `String` | `text/plain` (or the mapping's `produces`) |
/// | `Uint8List` | `application/octet-stream` |
/// | `EventStream<T>`, `Stream<T>` | `text/event-stream` (NDJSON with `produces: application/x-ndjson`) |
/// | `Stream<Uint8List>`, `Stream<List<int>>` (declared so), `StreamingResponseBody` | the bytes as they come (`application/octet-stream` or `produces`) |
/// | `Resource`, `ResponseEntity<Resource>` | the content, with `Range` (206/416), `Last-Modified` (304) |
/// | `SseEmitter` | `text/event-stream`, events as they are sent |
/// | anything else | JSON through the `ObjectMapper` |
final class ResponseWriter {
  /// A writer with [mapper]; [messageSource] resolves validation messages,
  /// [asyncTimeout] is the default `SseEmitter` timeout, [sseHeartbeat] the
  /// interval of keep-alive comments in event streams.
  ResponseWriter({
    required this.mapper,
    this.messageSource,
    this.asyncTimeout,
    this.sseHeartbeat,
  });

  /// Writes JSON.
  final ObjectMapper mapper;

  /// Resolves the messages of validation errors.
  final MessageSource? messageSource;

  /// The default timeout of an [SseEmitter].
  final Duration? asyncTimeout;

  /// Keep-alive comments in event streams (`null`: none).
  final Duration? sseHeartbeat;

  /// Writes [result] of [handler] (and closes the response).
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
        entity.headers.forEach((name, values) {
          response.headers.remove(name);
          for (final value in values) {
            response.headers.add(name, value);
          }
        });
        return await _writeBody(entity.body, request, response, produces);
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

  /// Writes [problem] as `application/problem+json` with its status.
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

  /// Writes an [ErrorResponse]: its status, headers and problem (with the
  /// field errors of a validation failure).
  Future<void> writeErrorResponse(
    ErrorResponse error,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    error.headers.forEach((name, values) {
      response.headers.remove(name);
      for (final value in values) {
        response.headers.add(name, value);
      }
    });
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

  /// The answer to an exception no `@ExceptionHandler` handled:
  /// [ErrorResponse]s answer with their problem, anything else is a 500
  /// (logged, without details for the client).
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
      return await response.close().catchError((_) {});
    }
    switch (error) {
      case final ErrorResponse errorResponse:
        if (errorResponse.statusCode >= 500) {
          _log.error(
            'Request ${request.method.value} ${request.path} failed',
            error: error,
            stackTrace: stackTrace,
          );
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

  /// Writes [resource] like Spring's `ResourceHttpMessageConverter` and
  /// `ResourceRegionHttpMessageConverter`: the media type from the file
  /// name (unless set), `Content-Length`, `Last-Modified` with
  /// `If-Modified-Since` (304), `Accept-Ranges` and one `Range` (206, or
  /// 416 when it cannot be satisfied); a resource that does not exist is a
  /// 404. A `FileSystemResource` is streamed from the file.
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
  Future<void> _startEvents(ServerHttpResponse response) async {
    response
      ..statusCode = 200
      ..headers.contentType = '${MediaType.textEventStream};charset=UTF-8'
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..write(':\n\n');
    await response.flush();
  }

  Future<void> _writeStream(
    Stream<Object?> stream,
    ServerHttpRequest request,
    ServerHttpResponse response,
    List<MediaType> produces,
  ) async {
    final ndjson = produces.any(
      (p) => p.type == 'application' && p.subtype == 'x-ndjson',
    );
    if (ndjson) {
      response
        ..statusCode = 200
        ..headers.contentType = MediaType.applicationNdjson;
    } else {
      await _startEvents(response);
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
        unawaited(out.write(text));
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
      heartbeat = Timer.periodic(
        interval,
        (_) => unawaited(out.write(':\n\n')),
      );
    }
    unawaited(response.done.then((_) => end()));
    await finished.future;
    await out.idle;
    await response.close().catchError((_) {});
  }

  Future<void> _writeEmitter(
    SseEmitter emitter,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    final handler = _EmitterHandler(this, response);
    await _startEvents(response);
    final interval = sseHeartbeat;
    Timer? heartbeat;
    if (interval != null && interval > Duration.zero) {
      heartbeat = Timer.periodic(interval, (_) {
        if (!handler.isDone) {
          unawaited(handler.comment());
        }
      });
    }
    await emitter.initialize(handler, defaultTimeout: asyncTimeout);
    await handler.finished;
    heartbeat?.cancel();
  }
}

/// Writes and flushes one piece after the other (`dart:io` refuses a
/// write while a flush is pending).
final class _SerialWriter {
  _SerialWriter(this.response);

  final ServerHttpResponse response;
  Future<void> _last = Future.value();
  Future<void> Function()? onFailure;
  var _failed = false;

  /// Completes when everything written so far is flushed.
  Future<void> get idle => _last;

  Future<void> write(String text) => _last = _last.then((_) async {
    if (_failed) {
      return;
    }
    try {
      response.write(text);
      await response.flush();
    } on Object {
      _failed = true;
      await onFailure?.call();
    }
  });
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

/// The response of a `HEAD` request: headers (with the length the body
/// would have), without the body.
final class HeadResponse extends ServerHttpResponseDecorator {
  /// Wraps the response of a `HEAD` request.
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

/// A body the handler writes itself, like Spring's
/// `StreamingResponseBody`: return it (or put it in a `ResponseEntity`)
/// for an export or a download produced on the fly. `application/octet-stream`
/// unless the mapping's `produces` or the entity's headers say otherwise.
///
/// ```dart
/// @GetMapping.of(path: '/export.csv', produces: 'text/csv')
/// StreamingResponseBody export() => StreamingResponseBody((out) async {
///   await for (final book in books.all()) {
///     out.write('${book.isbn},${book.title}\n');
///     await out.flush();
///   }
/// });
/// ```
final class StreamingResponseBody {
  /// A body written by [writeTo].
  const StreamingResponseBody(this.writeTo);

  /// Writes the body.
  final Future<void> Function(ResponseBodySink out) writeTo;
}

/// Where a [StreamingResponseBody] writes.
final class ResponseBodySink {
  ResponseBodySink._(this._response);

  final ServerHttpResponse _response;

  /// Writes [bytes].
  void add(List<int> bytes) => _response.add(bytes);

  /// Writes [text] in UTF-8.
  void write(String text) => _response.write(text);

  /// Sends what was written so far.
  Future<void> flush() => _response.flush();

  /// Writes every chunk of [stream].
  Future<void> addStream(Stream<List<int>> stream) =>
      _response.addStream(stream);
}
