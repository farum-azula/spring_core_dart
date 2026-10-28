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

/// An HTTP request built in memory, to call the application in a test
/// without a server.
///
/// `MockMvc` builds one for every request it performs and hands it to the
/// application; a `RequestPostProcessor` receives it to add a user, a
/// header or a token. Build one yourself only to call an `HttpHandler`, a
/// `WebFilter` or a controller method directly. Unlike a real request,
/// everything can be set: headers, query parameters, cookies, body,
/// [remoteAddress], [principal].
///
/// ```dart
/// // Calls a WebFilter directly with a JSON POST.
/// final request = MockServerHttpRequest(HttpMethod.post, '/api/books')
///   ..headers.contentType = 'application/json'
///   ..setBody('{"isbn": "978-0"}');
/// await filter.doFilter(request, MockServerHttpResponse(), chain);
/// ```
///
/// Spring (Java):
/// ```java
/// MockHttpServletRequest request =
///     new MockHttpServletRequest("POST", "/api/books");
/// request.setContentType("application/json");
/// request.setContent("{\"isbn\": \"978-0\"}".getBytes());
/// ```
final class MockServerHttpRequest implements ServerHttpRequest {
  /// A [method] request to [target]: a path with an optional query
  /// (`/books?q=dune`), resolved against `http://localhost`, or a full URL
  /// (`https://shop.test/books`, which also makes [isSecure] true).
  /// [headers] start empty unless given.
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

  /// The body set with [setBody] (empty by default), readable any number
  /// of times, unlike [body].
  Uint8List get bodyBytes => _body;

  /// Sets the body to [body], a `String` (encoded in UTF-8) or a list of
  /// bytes, and sets `Content-Length` to match. Throws an `ArgumentError`
  /// for anything else. It does not set `Content-Type`.
  void setBody(Object body) {
    _body = switch (body) {
      final String text => utf8.encode(text),
      final Uint8List bytes => bytes,
      final List<int> bytes => Uint8List.fromList(bytes),
      _ => throw ArgumentError.value(body, 'body', 'a String or bytes'),
    };
    headers.contentLength = _body.length;
  }

  /// Adds [value] to the query parameter [name] of [uri] (the values
  /// already there stay).
  void addParameter(String name, String value) {
    final all = {
      for (final entry in uri.queryParametersAll.entries)
        entry.key: [...entry.value],
    };
    (all[name] ??= []).add(value);
    uri = uri.replace(queryParameters: all);
  }

  /// Adds the cookie [name]=[value] to the `Cookie` header.
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

  /// The client's end of the WebSocket, once the application accepted the
  /// handshake with [upgradeToWebSocket]; a test sends and receives
  /// messages through it. It never completes when the handshake is
  /// refused. `MockMvc.webSocket` returns it.
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

/// An HTTP response kept in memory, so a test can read what the
/// application answered: status, headers, cookies and body.
///
/// `MockMvc` passes one to the application for every request and the
/// test reads it from the result. Besides the full body ([bodyText],
/// [json]) it can follow an answer that is still being streamed:
/// [committed] and [closed] tell where the response is, [chunks] and
/// [eventStream] deliver the body as it is written, and [disconnect]
/// plays a client that goes away.
///
/// ```dart
/// // Calls the application directly and checks its answer.
/// final response = MockServerHttpResponse();
/// await handler.handle(
///   MockServerHttpRequest(HttpMethod.get, '/api/books/978-0'),
///   response,
/// );
/// expect(response.statusCode, 200);
/// expect((response.json! as Map)['title'], 'Dune');
/// ```
///
/// Spring (Java):
/// ```java
/// MockHttpServletResponse response = mockMvc.perform(get("/api/books/978-0"))
///     .andReturn().getResponse();
/// assertEquals(200, response.getStatus());
/// ```
final class MockServerHttpResponse implements ServerHttpResponse {
  @override
  int statusCode = 200;

  @override
  final HttpHeaders headers = HttpHeaders();

  /// The cookies the application set with [addCookie], in order.
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

  /// Completes when the response is committed: at the first body bytes, a
  /// [flush] or [close]. For a stream this is when its headers are out.
  Future<void> get committed => _committed.future;

  /// Completes when the application closed the response.
  Future<void> get closed => _closed.future;

  /// Whether the application closed the response. Writing after that
  /// throws a `StateError`.
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

  /// Plays a client that goes away: [done] completes, so an endless
  /// stream (server-sent events) stops writing. The response itself is
  /// not closed.
  void disconnect() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  /// Every body byte written so far.
  Uint8List get bodyBytes => _body.toBytes();

  /// The body written so far, decoded as UTF-8 (malformed bytes
  /// replaced).
  String get bodyText => utf8.decode(bodyBytes, allowMalformed: true);

  /// The body decoded as JSON; throws a `FormatException` when it is not
  /// JSON.
  Object? get json => jsonDecode(bodyText);

  /// The chunks written from now on, one event per write; the stream
  /// ends when the response is closed. Earlier chunks are not repeated.
  Stream<List<int>> get chunks => _chunks.stream;

  /// The server-sent events written so far, read from the body.
  List<ServerSentEvent<String?>> get events => SseDecoder.parse(bodyText);

  /// The server-sent events written from now on, as they arrive; ends
  /// when the response is closed.
  Stream<ServerSentEvent<String?>> get eventStream =>
      chunks.transform(const SseDecoder());
}

/// Two [WebSocketSession]s connected to each other in memory: what one
/// sends, the other receives, and closing one closes both.
///
/// It is the WebSocket a [MockServerHttpRequest] opens when the
/// application accepts a handshake: the [server] end goes to the
/// application, the [client] end to the test (`MockMvc.webSocket`). Use
/// it directly to test code that takes a session without any HTTP.
///
/// ```dart
/// // The code under test gets the server end; the test talks on the other.
/// final pair = WebSocketSessionPair(Uri.parse('ws://localhost/chat'));
/// startEcho(pair.server); // answers 'echo: <message>' to each message
/// pair.client.sendMessage('hello');
/// expect(await pair.client.messages.first, 'echo: hello');
/// ```
final class WebSocketSessionPair {
  /// Two connected sessions, both with [uri] and with [protocol] as their
  /// accepted sub-protocol.
  WebSocketSessionPair(Uri uri, {String? protocol}) {
    server = _PairedSession(uri, protocol);
    client = _PairedSession(uri, protocol);
    (server as _PairedSession)._peer = client as _PairedSession;
    (client as _PairedSession)._peer = server as _PairedSession;
  }

  /// The end the application uses.
  late final WebSocketSession server;

  /// The end the test uses.
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

/// An uploaded file made in a test, with its content in memory.
///
/// Pass it to `MockMvc.multipart` to send it as a part of a
/// `multipart/form-data` request, or straight to a controller method that
/// takes a [MultipartFile]. Without an original file name (`null`),
/// `MockMvc.multipart` sends it as a plain part; with `application/json`
/// it is then a JSON part for `@RequestPart`.
///
/// ```dart
/// // Uploads a cover image to the controller under test.
/// final cover = MockMultipartFile('cover', 'dune.png', 'image/png', bytes);
/// await mvc.multipart('/api/covers', files: [cover])
///     .andExpect(status: 201);
/// ```
///
/// Spring (Java):
/// ```java
/// MockMultipartFile cover =
///     new MockMultipartFile("cover", "dune.png", "image/png", bytes);
/// mockMvc.perform(multipart("/api/covers").file(cover))
///     .andExpect(status().isCreated());
/// ```
class MockMultipartFile extends InMemoryMultipartFile {
  /// A file for the form field [name], called [originalFilename] on the
  /// client (or `null`), of type [contentType] (or `null`), holding
  /// [content].
  MockMultipartFile(
    super.name,
    String? originalFilename,
    String? contentType,
    super.content,
  ) : super(originalFilename: originalFilename, contentType: contentType);
}
