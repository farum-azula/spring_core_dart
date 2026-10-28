import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// One client connected to the application's server: send it messages,
/// close it, and read what its handshake carried.
///
/// Endpoint methods and `WebSocketHandler`s receive it for each connection,
/// and [WebSocketSessionRegistry] lists the open ones. Besides what every
/// [WebSocketSession] does (send, close, the incoming messages), it has an
/// [id], the handshake's [handshakeHeaders], [principal] and
/// [pathVariables], [attributes] to keep per-connection state, and
/// [sendJson].
///
/// ```dart
/// // Greets the user and remembers the room for later messages.
/// @OnOpen()
/// void open(ServerWebSocketSession session, @PathVariable() String room) {
///   session.attributes['room'] = room;
///   session.sendJson({'welcome': session.principal?.name, 'room': room});
/// }
/// ```
///
/// Spring (Java): the server-side `WebSocketSession`.
abstract interface class ServerWebSocketSession implements WebSocketSession {
  /// An id of the connection, unique in this process; useful in logs and
  /// as a map key.
  String get id;

  /// The headers of the handshake request, read-only.
  HttpHeaders get handshakeHeaders;

  /// Values kept with this connection: those the `HandshakeInterceptor`s
  /// set, such as a token, and any the application adds. The place for
  /// per-connection state, as an endpoint is shared by all connections.
  Map<String, Object?> get attributes;

  /// The user the handshake request was authenticated as; `null` when
  /// anonymous.
  Principal? get principal;

  /// The values of the `{variables}` of the endpoint's path pattern for
  /// this connection, such as `{'room': 'neon'}`.
  Map<String, String> get pathVariables;

  /// Sends [value] as a JSON text message, written by the application's
  /// `ObjectMapper`.
  void sendJson(Object? value);
}

/// The object that handles the connections of a server path: it is told
/// when a connection opens, of each message, of errors and of the close.
///
/// It is Spring's low-level style. Register it for one or more paths with
/// a [WebSocketConfigurer]; extend [AbstractWebSocketHandler] or
/// [TextWebSocketHandler] rather than implementing every method.
/// `@WebSocketEndpoint` is the shorter way for most endpoints. The
/// messages of one connection are handled one after the other; an error
/// thrown by a method goes to [handleTransportError], and the connection
/// stays open unless the handler closes it.
///
/// Spring (Java): `WebSocketHandler`. Unlike Spring, an error a handler
/// throws does not close the connection by itself.
abstract interface class WebSocketHandler {
  /// Called when a connection has opened, before its first message.
  FutureOr<void> afterConnectionEstablished(ServerWebSocketSession session);

  /// Called with each message of [session], a `String` (text) or a
  /// `Uint8List` (binary); the next message waits until it returns.
  FutureOr<void> handleMessage(ServerWebSocketSession session, Object message);

  /// Called when the connection broke, or another method of this handler
  /// threw [error].
  FutureOr<void> handleTransportError(
    ServerWebSocketSession session,
    Object error,
  );

  /// Called when the connection has closed, from either side, with
  /// [status] (1005, no status code, when there was none).
  FutureOr<void> afterConnectionClosed(
    ServerWebSocketSession session,
    CloseStatus status,
  );
}

/// A [WebSocketHandler] to extend: every method does nothing until
/// overridden, and messages arrive in [handleTextMessage] or
/// [handleBinaryMessage] by kind.
///
/// Note that its [handleTransportError] ignores errors: override it to
/// log or close.
///
/// ```dart
/// // Sends every text message back.
/// final class EchoHandler extends AbstractWebSocketHandler {
///   @override
///   void handleTextMessage(ServerWebSocketSession session, String text) =>
///       session.sendMessage(text);
/// }
/// ```
///
/// Spring (Java): `AbstractWebSocketHandler`.
abstract class AbstractWebSocketHandler implements WebSocketHandler {
  @override
  FutureOr<void> afterConnectionEstablished(ServerWebSocketSession session) {}

  @override
  FutureOr<void> handleMessage(
    ServerWebSocketSession session,
    Object message,
  ) => switch (message) {
    final String text => handleTextMessage(session, text),
    final Uint8List bytes => handleBinaryMessage(session, bytes),
    _ => null,
  };

  /// Called with each text message; does nothing by default.
  FutureOr<void> handleTextMessage(
    ServerWebSocketSession session,
    String message,
  ) {}

  /// Called with each binary message; does nothing by default.
  FutureOr<void> handleBinaryMessage(
    ServerWebSocketSession session,
    Uint8List message,
  ) {}

  @override
  FutureOr<void> handleTransportError(
    ServerWebSocketSession session,
    Object error,
  ) {}

  @override
  FutureOr<void> afterConnectionClosed(
    ServerWebSocketSession session,
    CloseStatus status,
  ) {}
}

/// A [WebSocketHandler] for endpoints that speak text only: a binary
/// message closes the connection with 1003 (not acceptable). Override
/// [handleTextMessage].
///
/// Spring (Java): `TextWebSocketHandler`.
abstract class TextWebSocketHandler extends AbstractWebSocketHandler {
  @override
  FutureOr<void> handleBinaryMessage(
    ServerWebSocketSession session,
    Uint8List message,
  ) => session.close(
    CloseStatus.notAcceptable.withReason('Binary messages not supported'),
  );
}

/// Code that runs before and after the handshake of a handler registered
/// with a [WebSocketConfigurer]: it may refuse the connection or put
/// values on the new session.
///
/// Use it to check a token in the URL, or to copy facts of the request
/// into `session.attributes`. Add it with
/// [WebSocketHandlerRegistration.addInterceptors]. It does not apply to
/// `@WebSocketEndpoint`s; a web filter covers both.
///
/// ```dart
/// // Only clients with a token connect; the handler finds it in
/// // session.attributes['token'].
/// final class TokenInterceptor with HandshakeInterceptor {
///   @override
///   bool beforeHandshake(request, response, attributes) {
///     final token = request.queryParameters['token']?.firstOrNull;
///     if (token == null) return false; // 403
///     attributes['token'] = token;
///     return true;
///   }
/// }
/// ```
///
/// Spring (Java): `HandshakeInterceptor`.
abstract mixin class HandshakeInterceptor {
  /// Called before the connection is accepted, with the request, the
  /// response and the future session's [attributes]. Return `false` to
  /// refuse: the client gets a 403, unless this method answered through
  /// [response] itself. Returns `true` by default.
  FutureOr<bool> beforeHandshake(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Map<String, Object?> attributes,
  ) => true;

  /// Called after the connection was accepted, or with [error] when
  /// accepting it failed. Does nothing by default.
  FutureOr<void> afterHandshake(ServerHttpRequest request, Object? error) {}
}

/// A bean that maps [WebSocketHandler]s to server paths, with their
/// origins, protocols and handshake interceptors.
///
/// Implement it on a `@Configuration()` class; every such bean is asked
/// once, at startup. Use it for Spring-style handlers;
/// `@WebSocketEndpoint` needs no configurer.
///
/// ```dart
/// // The echo handler answers on /ws/echo, for the shop's pages only.
/// @Configuration()
/// class WsConfig implements WebSocketConfigurer {
///   @override
///   void registerWebSocketHandlers(WebSocketHandlerRegistry registry) =>
///       registry
///           .addHandler(EchoHandler(), ['/ws/echo'])
///           .setAllowedOrigins(['https://shop.example']);
/// }
/// ```
///
/// Spring (Java): `WebSocketConfigurer`, on an `@EnableWebSocket` class;
/// here no `@EnableWebSocket` is needed.
abstract interface class WebSocketConfigurer {
  /// Maps handlers to paths with [WebSocketHandlerRegistry.addHandler].
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry);
}

/// The list a [WebSocketConfigurer] adds its handlers to, each with its
/// paths and options. The starter creates it and passes it to every
/// configurer at startup.
///
/// Spring (Java): `WebSocketHandlerRegistry`.
final class WebSocketHandlerRegistry {
  final _registrations = <WebSocketHandlerRegistration>[];

  /// Maps [handler] to [paths], path patterns as on controllers, and
  /// returns the registration, for setting its origins, protocols and
  /// interceptors. Two handlers on one path stop the start.
  WebSocketHandlerRegistration addHandler(
    WebSocketHandler handler,
    List<String> paths,
  ) {
    final registration = WebSocketHandlerRegistration._(handler, paths);
    _registrations.add(registration);
    return registration;
  }

  /// The handlers added so far, in order.
  List<WebSocketHandlerRegistration> get registrations =>
      List.unmodifiable(_registrations);
}

/// One handler added to a [WebSocketHandlerRegistry], with its paths and
/// options; its methods set the options and return it, so calls chain.
final class WebSocketHandlerRegistration {
  WebSocketHandlerRegistration._(this.handler, this.paths);

  /// The handler of the connections.
  final WebSocketHandler handler;

  /// The path patterns it answers.
  final List<String> paths;

  /// The browser origins allowed besides the server's own (`*`: any).
  final allowedOrigins = <String>[];

  /// Origin patterns allowed, where `*` stands for any text.
  final allowedOriginPatterns = <String>[];

  /// The subprotocols spoken; the first one the client offers is chosen.
  final protocols = <String>[];

  /// Called around each handshake, in this order.
  final interceptors = <HandshakeInterceptor>[];

  /// Allows browsers from [origins], such as `https://shop.example`, or
  /// any with `*`. Adds to the origins set before.
  WebSocketHandlerRegistration setAllowedOrigins(List<String> origins) {
    allowedOrigins.addAll(origins);
    return this;
  }

  /// Allows browsers from origins matching [patterns], such as
  /// `https://*.example`. Adds to the patterns set before.
  WebSocketHandlerRegistration setAllowedOriginPatterns(List<String> patterns) {
    allowedOriginPatterns.addAll(patterns);
    return this;
  }

  /// Declares the subprotocols the handler speaks
  /// (`Sec-WebSocket-Protocol`). Adds to those set before.
  WebSocketHandlerRegistration setSupportedProtocols(List<String> values) {
    protocols.addAll(values);
    return this;
  }

  /// Adds the handshake interceptors [values], called in order.
  WebSocketHandlerRegistration addInterceptors(
    List<HandshakeInterceptor> values,
  ) {
    interceptors.addAll(values);
    return this;
  }
}

/// The open connections of the application's WebSocket server, grouped by
/// endpoint path: use it to send one message to everyone connected.
///
/// It is a bean (`webSocketSessionRegistry`); inject it into a service that
/// pushes news, or into an endpoint that relays a message to every member.
/// A session joins when its handshake succeeds and leaves when it closes.
/// There is no Spring counterpart: a Spring application keeps such a list
/// itself.
///
/// ```dart
/// // Every client of /ws/chat gets the announcement.
/// @Service()
/// class Announcer {
///   Announcer(this.sessions);
///   final WebSocketSessionRegistry sessions;
///
///   void announce(String text) => sessions.broadcast('/ws/chat', text);
/// }
/// ```
final class WebSocketSessionRegistry {
  final _sessions = <String, Set<ServerWebSocketSession>>{};

  /// The open sessions of the endpoint mapped to [pattern], written as on
  /// the endpoint (`/ws/rooms/{room}`, not `/ws/rooms/neon`); with no
  /// [pattern], those of every endpoint.
  List<ServerWebSocketSession> sessions([String? pattern]) => [
    if (pattern == null)
      for (final set in _sessions.values) ...set.where((s) => s.isOpen)
    else
      ...?_sessions[pattern]?.where((s) => s.isOpen),
  ];

  /// Sends [message] to every open session of [pattern] (written as on
  /// the endpoint), or of every endpoint when it is `null`. A `String` is
  /// sent as text, bytes as binary, anything else as JSON. A session that
  /// closed meanwhile is skipped.
  void broadcast(String? pattern, Object message) {
    for (final session in sessions(pattern)) {
      try {
        switch (message) {
          case String() || List<int>():
            session.sendMessage(message);
          default:
            session.sendJson(message);
        }
      } on WebSocketException {
        // Closed meanwhile.
      }
    }
  }

  /// Adds [session] to the sessions of [pattern]. The starter calls it
  /// after each handshake.
  void register(String pattern, ServerWebSocketSession session) =>
      (_sessions[pattern] ??= {}).add(session);

  /// Removes [session] from the sessions of [pattern]. The starter calls
  /// it when the session closes.
  void unregister(String pattern, ServerWebSocketSession session) =>
      _sessions[pattern]?.remove(session);
}

/// The [ServerWebSocketSession] the starter creates for each accepted
/// connection: the connection, plus what the handshake carried.
/// Applications use it through [ServerWebSocketSession].
final class DefaultServerWebSocketSession implements ServerWebSocketSession {
  /// Wraps [delegate], accepted for the handshake [request], whose
  /// headers and user it keeps.
  DefaultServerWebSocketSession(
    this.delegate,
    ServerHttpRequest request, {
    required this.mapper,
    required this.pathVariables,
    Map<String, Object?>? attributes,
  }) : id = '${++_ids}',
       handshakeHeaders = HttpHeaders.readOnly(request.headers.copy()),
       principal = request.principal,
       attributes = attributes ?? {};

  static var _ids = 0;

  /// The underlying connection.
  final WebSocketSession delegate;

  /// Writes the messages of [sendJson].
  final ObjectMapper mapper;

  @override
  final String id;

  @override
  final HttpHeaders handshakeHeaders;

  @override
  final Map<String, Object?> attributes;

  @override
  final Principal? principal;

  @override
  final Map<String, String> pathVariables;

  @override
  Uri get uri => delegate.uri;

  @override
  Stream<Object> get messages => delegate.messages;

  @override
  String? get acceptedProtocol => delegate.acceptedProtocol;

  @override
  bool get isOpen => delegate.isOpen;

  @override
  CloseStatus? get closeStatus => delegate.closeStatus;

  @override
  void sendMessage(Object message) => delegate.sendMessage(message);

  @override
  void sendJson(Object? value) =>
      delegate.sendMessage(jsonEncode(mapper.valueToTree(value)));

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) =>
      delegate.close(status);

  @override
  String toString() => 'ServerWebSocketSession[$id, $uri]';
}
