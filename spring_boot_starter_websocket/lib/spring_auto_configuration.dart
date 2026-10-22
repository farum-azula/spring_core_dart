/// Discovered by the generator of every application that depends on
/// `spring_boot_starter_websocket` (see `AutoConfigurationModule`).
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_auto_configuration.dart';

/// The WebSocket transport and the factory of the `@WebSocketClient`
/// beans.
@AutoConfigurationModule()
final BeanModule springBootStarterWebsocketAutoConfiguration = BeanModule(
  'springBootStarterWebsocketAutoConfiguration',
  [...webSocketAutoConfiguration],
);
