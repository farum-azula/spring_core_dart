// The platform's side of the built-in file exports: a file in the
// Downloads folder where dart:io exists, a download in a browser.
export 'debug_file_platform_stub.dart'
    if (dart.library.io) 'debug_file_platform_io.dart'
    if (dart.library.js_interop) 'debug_file_platform_web.dart';
