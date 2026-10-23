// Process and isolate facts for log patterns (`${PID}`, `%thread`, ANSI
// detection); dart:io and dart:isolate are not available on the web.
export 'platform_stub.dart' if (dart.library.io) 'platform_io.dart';
