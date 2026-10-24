import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client_factory.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_handshake.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _source =
    'package:spring_boot_starter_websocket#WebSocketAutoConfiguration';

/// The beans of the WebSocket starter:
///
/// - `webSocketTransport` — `platformWebSocketTransport()` (`dart:io` on
///   the VM and in Flutter, the browser's `WebSocket` on the web), when the
///   application declares no [WebSocketTransport];
/// - `webSocketClientFactory` — creates the `@WebSocketClient`
///   implementations with the `ObjectMapper`, the transport and every
///   [WebSocketHandshakeInterceptor] bean, and closes their connections
///   when the application stops.
final webSocketAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<WebSocketTransport>(
    name: 'webSocketTransport',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'webSocketTransport',
    source: _source,
    conditions: const [
      ConditionGroup(_source, [ConditionalOnMissingBean(WebSocketTransport)]),
    ],
    create: (r) => platformWebSocketTransport(),
  ),
  BeanDefinition<WebSocketClientFactory>(
    name: 'webSocketClientFactory',
    source: _source,
    types: const [WebSocketClientFactory, InvocationHandlerFactory],
    create: (r) => WebSocketClientFactory(
      environment: r.dependency<Environment>(),
      mapper:
          r.optionalDependency<ObjectMapper>() ??
          ObjectMapper(introspector: r.dependency<BeanIntrospector>()),
      transport: r.dependency<WebSocketTransport>(),
      interceptors:
          r.optionalDependencyList<WebSocketHandshakeInterceptor>() ??
          const <WebSocketHandshakeInterceptor>[],
    ),
  ),
];
