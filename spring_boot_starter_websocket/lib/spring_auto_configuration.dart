/// The starter's auto-configuration. Applications never import it: the
/// generator finds this file in every dependency and adds its module to
/// the generated application, which is what makes the dependency alone
/// enough. A test that builds a context by hand can name it.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/config/config.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_auto_configuration.dart';

// The auto-configurations this starter builds on (logging, and through it
// spring_boot_dart's), so a test of an application that lists only this
// starter can name them.
export 'package:spring_boot_starter_logging/spring_auto_configuration.dart';

/// The beans behind `@WebSocketClient` interfaces (the transport and the
/// client factory) and behind server endpoints (the handshake mapping and
/// the registry of open sessions).
@AutoConfigurationModule()
final BeanModule springBootStarterWebsocketAutoConfiguration = BeanModule(
  'springBootStarterWebsocketAutoConfiguration',
  [...webSocketAutoConfiguration],
  imports: [webSocketConfigBeans],
);

/// The server side: the open sessions and the mapping of the endpoints'
/// handshakes, which the web starter's dispatcher asks. Only where a
/// server can run ([ModulePlatform.native]): a Flutter web app that uses
/// the starter for its `@WebSocketClient`s carries none of it.
@AutoConfigurationModule(platform: ModulePlatform.native)
final BeanModule springBootStarterWebsocketServerAutoConfiguration = BeanModule(
  'springBootStarterWebsocketServerAutoConfiguration',
  [...webSocketServerAutoConfiguration],
);
