import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_edge/src/fetch/fetch_exchange.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

const _log = SpringLog('spring.edge.server');

/// The request attribute that holds the [FetchContext] of the request.
const fetchContextAttribute = 'spring.edge.fetchContext';

/// The [WebServer] of a function: it opens no socket, the platform calls
/// [fetch] for every request and sends what it returns.
///
/// The dispatcher, the filters, the security chain and the controllers
/// behind it are those of the `dart:io` server; they see the same
/// `ServerHttpRequest` and `ServerHttpResponse`.
///
/// What it does itself, as the built-in server does:
///
/// - a method it does not know is a 501, a path with an encoded `/`, `\`
///   or NUL, a `.` or `..` segment or a broken percent-escape a 400
///   ([requestTargetProblem]), before any filter;
/// - a body larger than `server.max-http-request-body-size` ends with a 413;
/// - an error nobody handled is a 500 without details, logged;
/// - a response is complete (with its `Content-Length`) unless the
///   handler flushed it or wrote a stream: then the body is sent while it
///   is produced (server-sent events, downloads);
/// - a `HEAD` request gets the headers of the answer without its body.
///
/// What the platform does instead of it: TLS, HTTP/2, compression,
/// connection limits, the address of the client.
///
/// Applications do not create one: `runFetchApplication` does, through
/// the [FetchWebServerFactory] bean.
final class FetchWebServer implements WebServer, WebServerActivity {
  /// A server that hands requests to [handler] with [settings]
  /// (`server.*`).
  FetchWebServer(this.handler, this.settings);

  /// The dispatcher of the application.
  final HttpHandler handler;

  /// `server.*`; the port, the address and TLS mean nothing here.
  final ServerProperties settings;

  var _running = false;
  var _active = 0;
  var _requests = 0;

  @override
  Future<void> start() async => _running = true;

  @override
  Future<void> stop({Duration? timeout}) async => _running = false;

  /// `0`: a function listens on no port.
  @override
  int get port => 0;

  @override
  int get activeRequests => _active;

  @override
  int get requestCount => _requests;

  @override
  int get refusedCount => 0;

  /// Whether the context started the server and has not stopped it.
  bool get isRunning => _running;

  /// Answers [request]. Completes when the status and the headers of the
  /// answer are decided: with the whole body, or with a body that is
  /// still being written. Never fails: what goes wrong is an answer.
  Future<FetchResponse> fetch(FetchRequest request) {
    final response = FetchServerHttpResponse(
      head: request.method.toUpperCase() == 'HEAD',
    );
    _active++;
    _requests++;
    unawaited(
      _serve(request, response).whenComplete(() => _active--),
    );
    return response.committed;
  }

  Future<void> _serve(
    FetchRequest request,
    FetchServerHttpResponse response,
  ) async {
    try {
      if (!_running) {
        await response.problem(
          HttpStatus.serviceUnavailable,
          'The application is stopping',
        );
        return;
      }
      final method = _method(request.method);
      if (method == null) {
        await response.problem(HttpStatus.notImplemented, 'Unsupported method');
        return;
      }
      if (requestTargetProblem(request.uri) case final problem?) {
        await response.problem(HttpStatus.badRequest, problem);
        return;
      }
      await handler.handle(
        FetchServerHttpRequest(request, method, settings),
        response,
      );
    } on Object catch (error, stackTrace) {
      _log.error(
        'Request ${request.method} ${request.uri.path} failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (response.isCommitted) {
        response.abort(error);
      } else {
        await response.problem(HttpStatus.internalServerError, null);
      }
    } finally {
      try {
        await response.close();
      } on Object catch (error, stackTrace) {
        // A status or a header the fetch API cannot send.
        _log.error(
          'Request ${request.method} ${request.uri.path} failed',
          error: error,
          stackTrace: stackTrace,
        );
        response.reset();
        await response.problem(HttpStatus.internalServerError, null);
      }
    }
  }

  static HttpMethod? _method(String value) {
    for (final method in HttpMethod.values) {
      if (method.value == value) {
        return method;
      }
    }
    return null;
  }
}

/// The request of a function as the dispatcher sees it.
final class FetchServerHttpRequest implements ServerHttpRequest {
  /// [source] with its [method] already known, and `server.*` for the
  /// size limit of its body.
  FetchServerHttpRequest(this.source, this.method, this._settings)
    : headers = HttpHeaders.readOnly(_headers(source.headers)) {
    attributes[fetchContextAttribute] = source.context;
  }

  /// What the platform gave.
  final FetchRequest source;

  final ServerProperties _settings;

  @override
  final HttpMethod method;

  @override
  final HttpHeaders headers;

  @override
  Uri get uri => source.uri;

  @override
  String get path => source.uri.path.isEmpty ? '/' : source.uri.path;

  @override
  late final Map<String, List<String>> queryParameters = Map.unmodifiable(
    source.uri.queryParametersAll,
  );

  @override
  late final Map<String, String> cookies = Map.unmodifiable(
    parseCookieHeader(headers.getAll(HttpHeaders.cookieHeader)),
  );

  /// The address the platform names ([FetchContext.remoteAddress]), never
  /// a header's.
  @override
  String? get remoteAddress => source.context.remoteAddress;

  @override
  bool get isSecure => source.uri.isScheme('https');

  @override
  final Map<String, Object?> attributes = {};

  @override
  Principal? principal;

  var _bodyRead = false;

  @override
  Stream<Uint8List> get body {
    if (_bodyRead) {
      throw StateError('The request body was read already');
    }
    _bodyRead = true;
    final body = source.body;
    if (body == null) {
      return const Stream.empty();
    }
    // The server's limit for every body, whatever its type; the multipart
    // resolver reads uploads with its own (maxRequestBodySizeAttribute).
    final limit = switch (attributes[maxRequestBodySizeAttribute]) {
      final int own => own,
      _ => _settings.maxRequestBodySize,
    };
    if (limit < 0) {
      return body;
    }
    final declared = int.tryParse(
      headers[HttpHeaders.contentLengthHeader] ?? '',
    );
    if (declared != null && declared > limit) {
      return Stream.error(PayloadTooLargeException(limit));
    }
    var read = 0;
    return body.transform(
      StreamTransformer<Uint8List, Uint8List>.fromHandlers(
        handleData: (chunk, sink) {
          read += chunk.length;
          if (read > limit) {
            sink
              ..addError(PayloadTooLargeException(limit))
              ..close();
          } else {
            sink.add(chunk);
          }
        },
      ),
    );
  }

  @override
  bool get isWebSocketUpgrade => false;

  @override
  Future<WebSocketSession> upgradeToWebSocket({String? protocol}) =>
      throw UnsupportedError(
        'A function does not accept WebSocket connections: it answers '
        'requests through the fetch API. Run the WebSocket endpoints on a '
        'server.',
      );

  static HttpHeaders _headers(List<(String, String)> source) {
    final headers = HttpHeaders();
    for (final (name, value) in source) {
      headers.add(name, value);
    }
    return headers;
  }
}

/// The response of a function as the dispatcher writes it.
///
/// What is written stays in memory until the response is closed, and is
/// then one body with its length. [flush] and [addStream] send the status
/// and the headers at once and the body from then on as it is written.
final class FetchServerHttpResponse implements ServerHttpResponse {
  /// A response; [head] when it answers a `HEAD` request and so has no
  /// body.
  FetchServerHttpResponse({this.head = false});

  /// Whether the request was a `HEAD`.
  final bool head;

  @override
  int statusCode = 200;

  @override
  final HttpHeaders headers = HttpHeaders();

  final _cookies = <ResponseCookie>[];
  final _buffer = BytesBuilder(copy: false);
  final _committed = Completer<FetchResponse>();
  final _done = Completer<void>();
  StreamController<Uint8List>? _stream;
  var _closed = false;
  var _bodiless = false;

  /// The answer, once its status and headers are decided.
  Future<FetchResponse> get committed => _committed.future;

  @override
  bool get isCommitted => _committed.isCompleted;

  @override
  Future<void> get done => _done.future;

  @override
  void addCookie(ResponseCookie cookie) => _cookies.add(cookie);

  /// Sends [status] with a problem body ([detail] when given) and closes;
  /// for the answers the server gives before the handler.
  Future<void> problem(int status, String? detail) {
    final problem = detail == null
        ? ProblemDetail.forStatus(status)
        : ProblemDetail.forStatusAndDetail(status, detail);
    statusCode = status;
    headers
      ..remove(HttpHeaders.contentLengthHeader)
      ..contentType = MediaType.applicationProblemJson;
    _buffer.clear();
    add(utf8.encode(jsonEncode(problem.toJson())));
    return close();
  }

  // The fetch API refuses these (a TypeError from `new Headers`); they
  // fail here, before anything is sent, and the header is dropped so the
  // error answer that follows can be written.
  void _checkHeaders() {
    for (final name in headers.names.toList()) {
      if (!_isToken(name)) {
        headers.remove(name);
        throw FormatException('Invalid response header name "$name"');
      }
      for (final value in headers.getAll(name)) {
        if (!_isFieldValue(value)) {
          headers.remove(name);
          // The value is not shown: it may be a secret.
          throw FormatException(
            'Invalid value of the response header "$name": only visible '
            'US-ASCII characters, spaces and tabs can be sent',
          );
        }
      }
    }
    for (final cookie in _cookies.toList()) {
      if (!_isFieldValue(cookie.toString())) {
        _cookies.remove(cookie);
        throw FormatException('Invalid cookie "${cookie.name}"');
      }
    }
  }

  static bool _isToken(String name) =>
      name.isNotEmpty &&
      name.codeUnits.every(
        (c) =>
            c > 0x20 && c < 0x7F && !r'"(),/:;<=>?@[\]{}'.codeUnits.contains(c),
      );

  static bool _isFieldValue(String value) =>
      value.codeUnits.every((c) => (c >= 0x20 && c < 0x7F) || c == 0x09);

  // The status and the headers as they go out. [length] is the size of a
  // complete body, `null` for one that is still written.
  (int, List<(String, String)>) _head(int? length) {
    _checkHeaders();
    // The fetch API has no answer below 200 and none above 599.
    if (statusCode < 200 || statusCode > 599) {
      throw StateError('A function cannot answer with status $statusCode');
    }
    // The statuses the fetch API allows no body for.
    _bodiless =
        statusCode == HttpStatus.noContent ||
        statusCode == HttpStatus.resetContent ||
        statusCode == HttpStatus.notModified;
    final typed = !_bodiless || statusCode == HttpStatus.noContent;
    final out = <(String, String)>[];
    var hasLength = false;
    headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == 'content-type' && !typed) {
        return;
      }
      if (lower == 'content-length') {
        if (_bodiless) {
          return;
        }
        hasLength = true;
      }
      for (final value in values) {
        out.add((name, value));
      }
    });
    if (!hasLength && length != null && !_bodiless && !head) {
      out.add((HttpHeaders.contentLengthHeader, '$length'));
    }
    for (final cookie in _cookies) {
      out.add((HttpHeaders.setCookieHeader, cookie.toString()));
    }
    return (statusCode, out);
  }

  // Sends the status and the headers now, the body from here on as it is
  // written.
  StreamController<Uint8List> _streaming() {
    if (_stream case final stream?) {
      return stream;
    }
    final (status, out) = _head(null);
    final controller = StreamController<Uint8List>(
      onCancel: () {
        // The client went away: nothing more is wanted.
        _closed = true;
        if (!_done.isCompleted) {
          _done.complete();
        }
      },
    );
    _stream = controller;
    final pending = _buffer.takeBytes();
    final silent = _bodiless || head;
    if (pending.isNotEmpty && !silent) {
      controller.add(pending);
    }
    _committed.complete(
      FetchResponse(status, out, stream: silent ? null : controller.stream),
    );
    if (silent) {
      // Nobody reads it: what is written is dropped.
      controller.stream.drain<void>().ignore();
    }
    return controller;
  }

  @override
  void add(List<int> bytes) {
    if (_closed) {
      return;
    }
    final chunk = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (_stream case final stream?) {
      if (!stream.isClosed) {
        stream.add(chunk);
      }
    } else {
      _buffer.add(chunk);
    }
  }

  @override
  void write(String text) => add(utf8.encode(text));

  @override
  Future<void> flush() async {
    if (!_closed) {
      _streaming();
    }
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    if (_closed) {
      return await stream.drain<void>();
    }
    final controller = _streaming();
    try {
      await for (final chunk in stream) {
        if (_closed || controller.isClosed) {
          break;
        }
        controller.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
      }
    } on Object catch (error, stackTrace) {
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
      rethrow;
    }
  }

  /// Drops what was written and set, for an error answer in its place;
  /// only before the response is committed.
  void reset() {
    if (isCommitted) {
      return;
    }
    _closed = false;
    _cookies.clear();
    _buffer.clear();
    headers.names.toList().forEach(headers.remove);
  }

  /// Cuts a response whose status was sent already: its body ends with
  /// [error], which the platform turns into a broken response.
  void abort(Object error) {
    final stream = _stream;
    if (stream != null && !stream.isClosed && !_closed) {
      stream.addError(error);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    if (_stream case final stream?) {
      _closed = true;
      unawaited(stream.close());
    } else {
      final (status, out) = _head(_buffer.length);
      _closed = true;
      final body = _buffer.takeBytes();
      _committed.complete(
        FetchResponse(
          status,
          out,
          bytes: _bodiless || head || body.isEmpty ? null : body,
        ),
      );
    }
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

/// The `webServerFactory` of a function: its server is a
/// [FetchWebServer], kept in [server] for the platform's entry.
///
/// The starter declares it when the application was started by
/// `runFetchApplication` on a fetch platform (`spring.edge.runtime` is
/// set); started as an ordinary program, the application keeps the web
/// starter's `dart:io` server.
final class FetchWebServerFactory implements ConfigurableWebServerFactory {
  /// A factory with [settings] (`server.*`).
  FetchWebServerFactory([this.settings = const ServerProperties()]);

  @override
  ServerProperties settings;

  /// The server of the application, once the context created it.
  FetchWebServer? server;

  @override
  WebServer getWebServer(HttpHandler handler) =>
      server = FetchWebServer(handler, settings);
}
