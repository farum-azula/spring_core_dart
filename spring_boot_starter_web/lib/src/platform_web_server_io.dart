import 'package:spring_boot_starter_web/src/io_web_server.dart';
import 'package:spring_boot_starter_web/src/web_server.dart';

/// `dart:io`'s server (the VM, Flutter on mobile and desktop).
ConfigurableWebServerFactory createPlatformWebServerFactory() =>
    IoWebServerFactory();
