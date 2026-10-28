import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/server/web_socket_handler.dart';
import 'package:spring_boot_starter_websocket/src/server/web_socket_handler_mapping.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client_factory.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_handshake.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _source =
    'package:spring_boot_starter_websocket#WebSocketAutoConfiguration';

/// The bean definitions this starter adds to every application that
/// depends on it. Applications do not use the list directly; the
/// generator adds it through `springBootStarterWebsocketAutoConfiguration`.
///
/// - `webSocketTransport`: `platformWebSocketTransport()` (`dart:io` on
///   the VM and in Flutter, the browser's `WebSocket` on the web), unless
///   the application declares its own [WebSocketTransport], as a test
///   does with a mock server.
/// - `webSocketClientFactory`: creates the `@WebSocketClient`
///   implementations with the `ObjectMapper`, the transport and every
///   [WebSocketHandshakeInterceptor] bean, and closes their connections
///   when the application stops.
/// - `webSocketSessionRegistry`: the open server sessions, for
///   broadcasting.
/// - `webSocketHandlerMapping`: routes the handshakes of the server
///   endpoints; the web starter's dispatcher uses it when
///   `spring_boot_starter_web` is a dependency, and nothing does
///   otherwise.
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
  // The server side (with spring_boot_starter_web): the open sessions and
  // the handshakes' mapping, which the web starter's dispatcher asks.
  BeanDefinition<WebSocketSessionRegistry>(
    name: 'webSocketSessionRegistry',
    source: _source,
    create: (_) => WebSocketSessionRegistry(),
  ),
  BeanDefinition<WebSocketHandlerMapping>(
    name: 'webSocketHandlerMapping',
    source: _source,
    types: const [
      WebSocketHandlerMapping,
      HandlerMapping,
      Ordered,
      SmartInitializingSingleton,
    ],
    create: (r) => WebSocketHandlerMapping(
      beanFactory: r.dependency<ListableBeanFactory>(),
      mapper:
          r.optionalDependency<ObjectMapper>() ??
          ObjectMapper(introspector: r.dependency<BeanIntrospector>()),
      sessions: r.dependency<WebSocketSessionRegistry>(),
      configurers:
          r.optionalDependencyList<WebSocketConfigurer>() ??
          const <WebSocketConfigurer>[],
    ),
  ),
];
