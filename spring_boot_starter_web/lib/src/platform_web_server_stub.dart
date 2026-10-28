import 'package:spring_boot_starter_web/src/web_server.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The server factory where `dart:io` is missing, as in a browser, which
/// cannot open server sockets.
///
/// The factory exists so that an application with the starter still
/// starts there when it runs no server
/// (`spring.main.web-application-type=none`, or a mock web environment in
/// tests). Creating a server throws an [UnsupportedError] that says so.
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
