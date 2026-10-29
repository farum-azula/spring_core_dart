// The Windows and Linux secret stores call the OS through dart:ffi, which
// a web build cannot import: there the stub stands in (never called, the
// web has no PlatformSecretStore).
export 'package:spring_boot_starter_flutter_security/src/secret_store/desktop_secret_stores_stub.dart'
    if (dart.library.ffi) 'package:spring_boot_starter_flutter_security/src/secret_store/desktop_secret_stores_ffi.dart';
