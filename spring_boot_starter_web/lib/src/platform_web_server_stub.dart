import 'package:spring_boot_starter_web/src/web_server.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// No server where `dart:io` is missing (the web has no server sockets):
/// the factory exists, so `spring.main.web-application-type=none` (or a
/// mock web environment) still starts the application; creating a server
/// fails.
ConfigurableWebServerFactory createPlatformWebServerFactory() =>
    _NoWebServerFactory();

final class _NoWebServerFactory implements ConfigurableWebServerFactory {
  @override
  ServerProperties settings = const ServerProperties();

  @override
  WebServer getWebServer(HttpHandler handler) => throw UnsupportedError(
    'spring_boot_starter_web has no web server on this platform: the web '
    'has no server sockets. Run the server on the VM or in a Flutter app '
    'on mobile or desktop, or set spring.main.web-application-type=none.',
  );
}
