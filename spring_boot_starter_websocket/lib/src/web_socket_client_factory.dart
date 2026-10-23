import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client_config.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_handshake.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_invocation_handler.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Creates the handlers of `@WebSocketClient` interfaces (the bean
/// `webSocketClientFactory` of the starter), with the application's
/// [ObjectMapper], [WebSocketTransport] and
/// [WebSocketHandshakeInterceptor] beans. Closes every connection when the
/// application stops.
///
/// Differs from Spring: Spring has no declarative WebSocket client, so no
/// such factory; you create `WebSocketClient` / `WebSocketStompClient`
/// beans yourself.
final class WebSocketClientFactory
    implements InvocationHandlerFactory, DisposableBean {
  /// A factory using these collaborators.
  WebSocketClientFactory({
    required this.environment,
    required this.mapper,
    required this.transport,
    this.interceptors = const [],
  });

  /// Configuration and placeholders.
  final Environment environment;

  /// JSON messages.
  final ObjectMapper mapper;

  /// Opens the connections.
  final WebSocketTransport transport;

  /// Applied to every handshake.
  final List<WebSocketHandshakeInterceptor> interceptors;

  final _handlers = <WebSocketInvocationHandler>[];

  @override
  bool supports(InterfaceMetadata<Object> metadata) =>
      metadata.annotation<WebSocketClient>() != null;

  @override
  InvocationHandler create(InterfaceMetadata<Object> metadata) {
    final client = metadata.annotation<WebSocketClient>()!;
    final handler = WebSocketInvocationHandler(
      metadata: metadata,
      client: client,
      config: WebSocketClientConfig.of(environment, client.name),
      environment: environment,
      mapper: mapper,
      transport: transport,
      interceptors: interceptors,
    );
    _handlers.add(handler);
    return handler;
  }

  @override
  void destroy() {
    for (final handler in _handlers) {
      unawaited(handler.connectionManager.dispose());
    }
    _handlers.clear();
  }
}
