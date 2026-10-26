import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// A connection accepted by the server, like Spring's server-side
/// `WebSocketSession`: an id, the handshake's headers, attributes and
/// user, and [sendJson] besides what every [WebSocketSession] does.
abstract interface class ServerWebSocketSession implements WebSocketSession {
  /// A unique id of the connection.
  String get id;

  /// The headers of the handshake request.
  HttpHeaders get handshakeHeaders;

  /// Attributes: those the `HandshakeInterceptor`s set, and the
  /// application's own.
  Map<String, Object?> get attributes;

  /// The user of the handshake, if authenticated.
  Principal? get principal;

  /// The path variables of the endpoint's pattern.
  Map<String, String> get pathVariables;

  /// Sends [value] as a JSON text message (the `ObjectMapper`).
  void sendJson(Object? value);
}

/// Handles the connections of a path, like Spring's `WebSocketHandler`.
/// Register it with a `WebSocketConfigurer`, or use `@WebSocketEndpoint`.
abstract interface class WebSocketHandler {
  /// A connection opened.
  FutureOr<void> afterConnectionEstablished(ServerWebSocketSession session);

  /// A message arrived: a `String` (text) or `Uint8List` (binary).
  FutureOr<void> handleMessage(ServerWebSocketSession session, Object message);

  /// The connection broke, or a handler threw [error].
  FutureOr<void> handleTransportError(
    ServerWebSocketSession session,
    Object error,
  );

  /// The connection closed with [status].
  FutureOr<void> afterConnectionClosed(
    ServerWebSocketSession session,
    CloseStatus status,
  );
}

/// A [WebSocketHandler] doing nothing by default, with text and binary
/// messages apart, like Spring's `AbstractWebSocketHandler`.
///
/// ```dart
/// final class EchoHandler extends AbstractWebSocketHandler {
///   @override
///   void handleTextMessage(ServerWebSocketSession session, String text) =>
///       session.sendMessage(text);
/// }
/// ```
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

  /// A text message arrived.
  FutureOr<void> handleTextMessage(
    ServerWebSocketSession session,
    String message,
  ) {}

  /// A binary message arrived.
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

/// A [WebSocketHandler] for text messages, like Spring's
/// `TextWebSocketHandler`: a binary message closes the connection (1003).
abstract class TextWebSocketHandler extends AbstractWebSocketHandler {
  @override
  FutureOr<void> handleBinaryMessage(
    ServerWebSocketSession session,
    Uint8List message,
  ) => session.close(
    CloseStatus.notAcceptable.withReason('Binary messages not supported'),
  );
}

/// Runs around the handshake, like Spring's `HandshakeInterceptor`:
/// [beforeHandshake] may refuse it (answering through the response) or put
/// attributes on the session.
abstract mixin class HandshakeInterceptor {
  /// Before the upgrade; `false` refuses it (403 unless answered).
  FutureOr<bool> beforeHandshake(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Map<String, Object?> attributes,
  ) => true;

  /// After the upgrade (or its failure, [error]).
  FutureOr<void> afterHandshake(ServerHttpRequest request, Object? error) {}
}

/// Registers [WebSocketHandler]s, like Spring's `WebSocketConfigurer`:
/// declare beans implementing it.
///
/// ```dart
/// @Configuration()
/// class WsConfig implements WebSocketConfigurer {
///   @override
///   void registerWebSocketHandlers(WebSocketHandlerRegistry registry) =>
///       registry
///           .addHandler(EchoHandler(), ['/ws/echo'])
///           .setAllowedOrigins(['https://shop.example']);
/// }
/// ```
abstract interface class WebSocketConfigurer {
  /// Adds handlers to [registry].
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry);
}

/// The handlers of the [WebSocketConfigurer]s, like Spring's
/// `WebSocketHandlerRegistry`.
final class WebSocketHandlerRegistry {
  final _registrations = <WebSocketHandlerRegistration>[];

  /// Maps [handler] to [paths] (path patterns).
  WebSocketHandlerRegistration addHandler(
    WebSocketHandler handler,
    List<String> paths,
  ) {
    final registration = WebSocketHandlerRegistration._(handler, paths);
    _registrations.add(registration);
    return registration;
  }

  /// The registrations.
  List<WebSocketHandlerRegistration> get registrations =>
      List.unmodifiable(_registrations);
}

/// One handler of a [WebSocketHandlerRegistry].
final class WebSocketHandlerRegistration {
  WebSocketHandlerRegistration._(this.handler, this.paths);

  /// The handler.
  final WebSocketHandler handler;

  /// Its paths.
  final List<String> paths;

  /// Origins allowed besides the server's own.
  final allowedOrigins = <String>[];

  /// Origin patterns allowed.
  final allowedOriginPatterns = <String>[];

  /// Sub-protocols spoken.
  final protocols = <String>[];

  /// Handshake interceptors.
  final interceptors = <HandshakeInterceptor>[];

  /// Allows [origins] (`*` for any).
  WebSocketHandlerRegistration setAllowedOrigins(List<String> origins) {
    allowedOrigins.addAll(origins);
    return this;
  }

  /// Allows origin [patterns].
  WebSocketHandlerRegistration setAllowedOriginPatterns(List<String> patterns) {
    allowedOriginPatterns.addAll(patterns);
    return this;
  }

  /// Speaks [values] (`Sec-WebSocket-Protocol`).
  WebSocketHandlerRegistration setSupportedProtocols(List<String> values) {
    protocols.addAll(values);
    return this;
  }

  /// Adds handshake [values].
  WebSocketHandlerRegistration addInterceptors(
    List<HandshakeInterceptor> values,
  ) {
    interceptors.addAll(values);
    return this;
  }
}

/// The open server connections, by endpoint path pattern: for
/// broadcasting.
///
/// ```dart
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

  /// The open sessions of the endpoint mapped to [pattern] (as written on
  /// the endpoint), or of every endpoint.
  List<ServerWebSocketSession> sessions([String? pattern]) => [
    if (pattern == null)
      for (final set in _sessions.values) ...set.where((s) => s.isOpen)
    else
      ...?_sessions[pattern]?.where((s) => s.isOpen),
  ];

  /// Sends [message] (a `String`, bytes, or an object as JSON) to every
  /// open session of [pattern] (or of every endpoint).
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

  /// Adds [session] of [pattern]; it is removed when it closes.
  void register(String pattern, ServerWebSocketSession session) =>
      (_sessions[pattern] ??= {}).add(session);

  /// Removes [session].
  void unregister(String pattern, ServerWebSocketSession session) =>
      _sessions[pattern]?.remove(session);
}

/// A [ServerWebSocketSession] around the connection a server accepted.
final class DefaultServerWebSocketSession implements ServerWebSocketSession {
  /// Wraps [delegate], accepted for the handshake [request].
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

  /// The connection.
  final WebSocketSession delegate;

  /// Writes JSON.
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
