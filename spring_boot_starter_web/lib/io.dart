/// The `dart:io` HTTP server of the web starter, which runs on the VM and
/// in Flutter apps on mobile and desktop.
///
/// The main library does not export it, so that applications for the
/// browser still compile. Import it for `IoWebServerFactory` and
/// `IoWebServer`: to wrap the default server in a factory of your own,
/// or to start a server outside the application context.
library;

export 'src/io_web_server.dart';
