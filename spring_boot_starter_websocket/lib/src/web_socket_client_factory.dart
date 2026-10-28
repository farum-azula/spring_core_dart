import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client_config.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_handshake.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_invocation_handler.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The bean that builds the implementation of every `@WebSocketClient`
/// interface and closes their connections when the application stops.
///
/// The starter registers it as `webSocketClientFactory`; applications do
/// not use it directly. When the container creates a client bean, the
/// factory makes its [WebSocketInvocationHandler] with the client's
/// settings ([WebSocketClientConfig]) and the application's
/// [ObjectMapper], [WebSocketTransport] and
/// [WebSocketHandshakeInterceptor] beans.
///
/// Differs from Spring: Spring has no declarative WebSocket client, so no
/// such factory; you create `WebSocketClient` / `WebSocketStompClient`
/// beans yourself.
final class WebSocketClientFactory
    implements InvocationHandlerFactory, DisposableBean {
  /// A factory reading the client settings from [environment], with the
  /// given [mapper], [transport] and [interceptors].
  WebSocketClientFactory({
    required this.environment,
    required this.mapper,
    required this.transport,
    this.interceptors = const [],
  });

  /// Where the `spring.websocket.client.config.*` properties and the
  /// `${...}` of the URLs are read.
  final Environment environment;

  /// Reads and writes the JSON messages.
  final ObjectMapper mapper;

  /// Opens the connections: `dart:io` or the browser, or a mock in tests.
  final WebSocketTransport transport;

  /// Called on every handshake of every client, in this order.
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

  /// Closes every client's connection when the application stops; later
  /// use of a client fails with a [StateError]. With open connections it
  /// returns a future that completes once they are closed, which
  /// `closeAsync()` awaits.
  @override
  FutureOr<void> destroy() {
    final handlers = [..._handlers];
    _handlers.clear();
    final closing = <Future<void>>[];
    for (final handler in handlers) {
      final manager = handler.connectionManager;
      if (manager.isConnected) {
        closing.add(manager.dispose());
      } else {
        // Nothing to wait for: no connection to close.
        unawaited(manager.dispose());
      }
    }
    if (closing.isNotEmpty) {
      return Future.wait(closing).then((_) {});
    }
  }
}
