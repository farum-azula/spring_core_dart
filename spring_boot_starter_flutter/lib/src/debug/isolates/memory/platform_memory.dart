export 'package:spring_boot_starter_flutter/src/debug/isolates/memory/platform_memory_stub.dart'
    if (dart.library.io) 'package:spring_boot_starter_flutter/src/debug/isolates/memory/platform_memory_io.dart'
    if (dart.library.js_interop) 'package:spring_boot_starter_flutter/src/debug/isolates/memory/platform_memory_web.dart';
