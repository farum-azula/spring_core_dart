import 'package:spring_boot_starter_flutter_security/src/web/web_crypto_dpop_key.dart';

/// Outside a browser there is no WebCrypto: throws an [UnsupportedError].
BrowserKeyVault createBrowserKeyVault() => throw UnsupportedError(
  'No WebCrypto outside the web: a WebCryptoDPoPKey needs a browser (pass '
  'a BrowserKeyVault in tests)',
);
