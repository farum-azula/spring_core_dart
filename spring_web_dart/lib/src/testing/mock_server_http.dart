import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';
import 'package:spring_web_dart/src/multipart/multipart.dart';
import 'package:spring_web_dart/src/server/server_http_request.dart';
import 'package:spring_web_dart/src/server/server_http_response.dart';
import 'package:spring_web_dart/src/sse/server_sent_event.dart';
import 'package:spring_web_dart/src/sse/sse_decoder.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// A [ServerHttpRequest] built in a test, like Spring's
/// `MockHttpServletRequest`: what `MockMvc` hands to the application.
///
/// ```dart
/// final request = MockServerHttpRequest(HttpMethod.post, '/api/books')
///   ..headers.contentType = 'application/json'
///   ..setBody('{"isbn": "978-0"}');
/// ```
final class MockServerHttpRequest implements ServerHttpRequest {
  /// A [method] request to [target] (a path with an optional query, or a
  /// full URL; `http://localhost` by default).
  MockServerHttpRequest(this.method, String target, {HttpHeaders? headers})
    : uri = Uri.parse('http://localhost').resolve(target),
      headers = headers ?? HttpHeaders();

  @override
  final HttpMethod method;

  @override
  Uri uri;

  @override
  String get path => uri.path.isEmpty ? '/' : uri.path;

  @override
  final HttpHeaders headers;

  @override
  Map<String, List<String>> get queryParameters => uri.queryParametersAll;

  @override
  Map<String, String> get cookies =>
      parseCookieHeader(headers.getAll(HttpHeaders.cookieHeader));

  @override
  String? remoteAddress = '127.0.0.1';

  @override
  bool get isSecure => uri.scheme == 'https' || uri.scheme == 'wss';

  @override
  final Map<String, Object?> attributes = {};

  @override
  Principal? principal;

  Uint8List _body = Uint8List(0);
  var _bodyRead = false;

  /// The body as bytes.
  Uint8List get bodyBytes => _body;

  /// Sets the body: a `String` (UTF-8) or bytes.
  void setBody(Object body) {
    _body = switch (body) {
      final String text => utf8.encode(text),
      final Uint8List bytes => bytes,
      final List<int> bytes => Uint8List.fromList(bytes),
      _ => throw ArgumentError.value(body, 'body', 'a String or bytes'),
    };
    headers.contentLength = _body.length;
  }

  /// Adds the query parameter [name]=[value].
  void addParameter(String name, String value) {
    final all = {
      for (final entry in uri.queryParametersAll.entries)
        entry.key: [...entry.value],
    };
    (all[name] ??= []).add(value);
    uri = uri.replace(queryParameters: all);
  }

  /// Adds the cookie [name]=[value].
  void addCookie(String name, String value) {
    final existing = headers[HttpHeaders.cookieHeader];
    headers.set(
      HttpHeaders.cookieHeader,
      existing == null ? '$name=$value' : '$existing; $name=$value',
    );
  }

  @override
  Stream<Uint8List> get body {
    if (_bodyRead) {
      throw StateError('The request body was read already');
    }
    _bodyRead = true;
    return _body.isEmpty ? const Stream.empty() : Stream.value(_body);
  }

  @override
  bool get isWebSocketUpgrade =>
      headers[HttpHeaders.upgradeHeader]?.toLowerCase() == 'websocket';

  final _client = Completer<WebSocketSession>();

  /// The client's end of the WebSocket once the application accepted the
  /// handshake ([upgradeToWebSocket]).
  Future<WebSocketSession> get webSocketClient => _client.future;

  @override
  Future<WebSocketSession> upgradeToWebSocket({String? protocol}) async {
    if (!isWebSocketUpgrade) {
      throw StateError('Not a WebSocket handshake');
    }
    final pair = WebSocketSessionPair(
      uri.replace(scheme: isSecure ? 'wss' : 'ws'),
      protocol: protocol,
    );
    _client.complete(pair.client);
    return pair.server;
  }
}

/// The response a test reads, like Spring's `MockHttpServletResponse`:
/// status, headers, cookies and body, with [committed] and [closed] to
/// follow a streamed answer.
final class MockServerHttpResponse implements ServerHttpResponse {
  @override
  int statusCode = 200;

  @override
  final HttpHeaders headers = HttpHeaders();

  /// The cookies set.
  final List<ResponseCookie> cookies = [];

  final _body = BytesBuilder();
  final _chunks = StreamController<List<int>>.broadcast();
  final _committed = Completer<void>();
  final _closed = Completer<void>();
  final _done = Completer<void>();

  @override
  void addCookie(ResponseCookie cookie) => cookies.add(cookie);

  @override
  bool get isCommitted => _committed.isCompleted;

  /// Completes when the status and headers were sent.
  Future<void> get committed => _committed.future;

  /// Completes when the application ended the response.
  Future<void> get closed => _closed.future;

  /// Whether the application ended the response.
  bool get isClosed => _closed.isCompleted;

  void _commit() {
    if (!_committed.isCompleted) {
      _committed.complete();
    }
  }

  @override
  void add(List<int> bytes) {
    if (isClosed) {
      throw StateError('The response is closed');
    }
    _commit();
    _body.add(bytes);
    _chunks.add(bytes);
  }

  @override
  void write(String text) => add(utf8.encode(text));

  @override
  Future<void> flush() async => _commit();

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> close() async {
    _commit();
    if (!_closed.isCompleted) {
      _closed.complete();
      await _chunks.close();
    }
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> get done => _done.future;

  /// Ends the response from the client's side: an open stream stops.
  void disconnect() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  /// The body written so far.
  Uint8List get bodyBytes => _body.toBytes();

  /// The body as UTF-8 text.
  String get bodyText => utf8.decode(bodyBytes, allowMalformed: true);

  /// The body as JSON.
  Object? get json => jsonDecode(bodyText);

  /// The body's chunks from now on (until [close]).
  Stream<List<int>> get chunks => _chunks.stream;

  /// The server-sent events written so far.
  List<ServerSentEvent<String?>> get events => SseDecoder.parse(bodyText);

  /// The server-sent events written from now on.
  Stream<ServerSentEvent<String?>> get eventStream =>
      chunks.transform(const SseDecoder());
}

/// Two connected [WebSocketSession]s in memory: what one sends, the other
/// receives. `MockMvc` gives the [client] to a test and the [server] to
/// the application.
final class WebSocketSessionPair {
  /// A pair for [uri], with the agreed [protocol].
  WebSocketSessionPair(Uri uri, {String? protocol}) {
    server = _PairedSession(uri, protocol);
    client = _PairedSession(uri, protocol);
    (server as _PairedSession)._peer = client as _PairedSession;
    (client as _PairedSession)._peer = server as _PairedSession;
  }

  /// The application's end.
  late final WebSocketSession server;

  /// The test's end.
  late final WebSocketSession client;
}

final class _PairedSession implements WebSocketSession {
  _PairedSession(this.uri, this.acceptedProtocol);

  @override
  final Uri uri;

  @override
  final String? acceptedProtocol;

  late _PairedSession _peer;
  final _incoming = StreamController<Object>();
  CloseStatus? _status;

  @override
  Stream<Object> get messages => _incoming.stream;

  @override
  bool get isOpen => _status == null;

  @override
  CloseStatus? get closeStatus => _status;

  @override
  void sendMessage(Object message) {
    if (!isOpen) {
      throw WebSocketException('the connection is closed', url: uri);
    }
    final value = switch (message) {
      String() || Uint8List() => message,
      List<int>() => Uint8List.fromList(message),
      _ => throw ArgumentError.value(
        message,
        'message',
        'a String or a List<int>',
      ),
    };
    if (_peer.isOpen) {
      _peer._incoming.add(value);
    }
  }

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) async {
    if (!isOpen) {
      return;
    }
    _end(status);
    _peer._end(status);
  }

  void _end(CloseStatus status) {
    if (_status != null) {
      return;
    }
    _status = status;
    unawaited(_incoming.close());
  }
}

/// A [MultipartFile] for tests, like Spring's `MockMultipartFile`: pass it
/// to `MockMvc.multipart`, or straight to a controller method.
///
/// ```dart
/// final cover = MockMultipartFile('cover', 'dune.png', 'image/png', bytes);
/// ```
class MockMultipartFile extends InMemoryMultipartFile {
  /// A file of field [name] named [originalFilename], with [contentType]
  /// and [content].
  MockMultipartFile(
    super.name,
    String? originalFilename,
    String? contentType,
    super.content,
  ) : super(originalFilename: originalFilename, contentType: contentType);
}
