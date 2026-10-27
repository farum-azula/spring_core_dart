// Creating a directory needs dart:io, which release builds compiled to
// JavaScript (tool/release_check.dart) do not have: a conditional import,
// as the framework's own packages do it.
export 'directories_stub.dart' if (dart.library.io) 'directories_io.dart';
