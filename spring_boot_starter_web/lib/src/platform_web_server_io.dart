import 'package:spring_boot_starter_web/src/io_web_server.dart';
import 'package:spring_boot_starter_web/src/web_server.dart';

/// The server factory where `dart:io` exists (the VM, Flutter on mobile
/// and desktop): an `IoWebServerFactory`. The starter picks this file or
/// the stub by a conditional import.
ConfigurableWebServerFactory createPlatformWebServerFactory() =>
    IoWebServerFactory();
