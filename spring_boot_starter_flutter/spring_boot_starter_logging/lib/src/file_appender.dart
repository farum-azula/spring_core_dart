// The file appender needs dart:io; on the web a stub keeps the API and
// FileAppender.isSupported is false.
export 'file_appender_stub.dart' if (dart.library.io) 'file_appender_io.dart';
