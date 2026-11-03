import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_boot_starter_websocket/src/config/config.dart';

/// What the starter does at startup: binds `spring.websocket.client.*` of
/// [environment] and makes the settings of the client [name].
WebSocketClientConfig configOf(
  ConfigurableEnvironment environment,
  String name,
) {
  ConfigurationPropertySources.attach(environment);
  final binder = ConfigurationPropertiesBinder(
    environment,
    BeanIntrospector(introspections: webSocketConfigBeans.introspections),
  );
  final properties = binder.postProcessBeforeInitialization(
    WebSocketProperties(),
    'webSocketProperties',
  ) as WebSocketProperties;
  return WebSocketClientConfig.of(properties, name);
}
