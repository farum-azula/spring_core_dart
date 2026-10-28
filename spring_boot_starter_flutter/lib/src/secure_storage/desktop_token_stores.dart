// The Windows and Linux token stores call the OS through dart:ffi, which
// a web build cannot import: there the stub stands in (never called, the
// web has no SecureTokenStore).
export 'package:spring_boot_starter_flutter/src/secure_storage/desktop_token_stores_stub.dart'
    if (dart.library.ffi) 'package:spring_boot_starter_flutter/src/secure_storage/desktop_token_stores_ffi.dart';
