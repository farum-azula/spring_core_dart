import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';

/// Without dart:ffi (the web) there is no Windows store.
SecretStore windowsSecretStore() =>
    throw UnsupportedError('DPAPI needs dart:ffi (Windows)');

/// Without dart:ffi (the web) there is no Linux store.
SecretStore linuxSecretStore() =>
    throw UnsupportedError('libsecret needs dart:ffi (Linux)');
