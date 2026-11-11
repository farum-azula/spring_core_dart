import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/config/web_socket_properties.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_channel.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_channel_factory.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_serializer.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_socket_factory.dart';
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
///   does with a mock server. On `dart:io` its sessions receive messages
///   of at most `spring.websocket.client.max-text-message-size` and
///   `max-binary-message-size` (8 KB each, `-1` for no limit), unless a
///   client has limits of its own
///   (`spring.websocket.client.config.<name>.max-text-message-size`),
///   which its connections ask the transport for.
/// - `webSocketClientFactory`: creates the `@WebSocketClient`
///   implementations with the `ObjectMapper`, the transport and every
///   [WebSocketHandshakeInterceptor] bean, and closes their connections
///   when the application stops.
/// - `phoenixSocketFactory`: makes the Phoenix sockets with the
///   transport, every [WebSocketHandshakeInterceptor] bean and every
///   [PhoenixSerializer] bean, and closes them when the application
///   stops; unless the application declares its own
///   [PhoenixSocketFactory].
/// - `phoenixChannelFactory`: creates the `@PhoenixChannel`
///   implementations over those sockets, with the `ObjectMapper` and
///   every [PhoenixJoinInterceptor] bean.
///
/// The server side is [webSocketServerAutoConfiguration].
final webSocketAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<WebSocketTransport>(
    name: 'webSocketTransport',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'webSocketTransport',
    source: _source,
    conditions: const [
      ConditionGroup(_source, [ConditionalOnMissingBean(WebSocketTransport)]),
    ],
    create: (r) {
      final properties = r.dependency<WebSocketProperties>();
      return platformWebSocketTransport(
        maxTextMessageSize: properties.maxTextMessageSize.toBytes(),
        maxBinaryMessageSize: properties.maxBinaryMessageSize.toBytes(),
      );
    },
  ),
  BeanDefinition<WebSocketClientFactory>(
    name: 'webSocketClientFactory',
    source: _source,
    types: const [WebSocketClientFactory, InvocationHandlerFactory],
    create: (r) => WebSocketClientFactory(
      environment: r.dependency<Environment>(),
      properties: r.dependency<WebSocketProperties>(),
      mapper:
          r.optionalDependency<ObjectMapper>() ??
          ObjectMapper(introspector: r.dependency<BeanIntrospector>()),
      transport: r.dependency<WebSocketTransport>(),
      interceptors:
          r.optionalDependencyList<WebSocketHandshakeInterceptor>() ??
          const <WebSocketHandshakeInterceptor>[],
    ),
  ),
  BeanDefinition<PhoenixSocketFactory>(
    name: 'phoenixSocketFactory',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'phoenixSocketFactory',
    source: _source,
    conditions: const [
      // A key of its own: the transport's decision is not this bean's.
      ConditionGroup('$_source.phoenixSocketFactory', [
        ConditionalOnMissingBean(PhoenixSocketFactory),
      ]),
    ],
    create: (r) => PhoenixSocketFactory(
      environment: r.dependency<Environment>(),
      properties: r.dependency<WebSocketProperties>(),
      transport: r.dependency<WebSocketTransport>(),
      interceptors:
          r.optionalDependencyList<WebSocketHandshakeInterceptor>() ??
          const <WebSocketHandshakeInterceptor>[],
      serializers:
          r.optionalDependencyList<PhoenixSerializer>() ??
          const <PhoenixSerializer>[],
    ),
  ),
  BeanDefinition<PhoenixChannelFactory>(
    name: 'phoenixChannelFactory',
    source: _source,
    types: const [PhoenixChannelFactory, InvocationHandlerFactory],
    create: (r) => PhoenixChannelFactory(
      environment: r.dependency<Environment>(),
      mapper:
          r.optionalDependency<ObjectMapper>() ??
          ObjectMapper(introspector: r.dependency<BeanIntrospector>()),
      sockets: r.dependency<PhoenixSocketFactory>(),
      interceptors:
          r.optionalDependencyList<PhoenixJoinInterceptor>() ??
          const <PhoenixJoinInterceptor>[],
    ),
  ),
];

/// The server side of the starter, in
/// `springBootStarterWebsocketServerAutoConfiguration`, a module only where
/// a server can run:
///
/// - `webSocketSessionRegistry`: the open server sessions, for
///   broadcasting.
/// - `webSocketHandlerMapping`: routes the handshakes of the server
///   endpoints; the web starter's dispatcher uses it when
///   `spring_boot_starter_web` is a dependency, and nothing does
///   otherwise.
final webSocketServerAutoConfiguration = <BeanDefinition<Object>>[
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
