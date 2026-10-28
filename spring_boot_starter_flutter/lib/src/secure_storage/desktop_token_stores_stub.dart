import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// Without dart:ffi (the web) there is no Windows store.
TokenStore windowsTokenStore() =>
    throw UnsupportedError('DPAPI needs dart:ffi (Windows)');

/// Without dart:ffi (the web) there is no Linux store.
TokenStore linuxTokenStore() =>
    throw UnsupportedError('libsecret needs dart:ffi (Linux)');
