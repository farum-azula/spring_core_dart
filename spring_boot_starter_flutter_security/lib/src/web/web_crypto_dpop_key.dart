import 'dart:typed_data';

import 'package:spring_boot_starter_flutter_security/src/web/browser_key_vault_stub.dart'
    if (dart.library.js_interop) 'package:spring_boot_starter_flutter_security/src/web/browser_key_vault_web.dart'
    as platform;
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

const _log = SpringLog('spring.security.oauth2.client.dpop');

/// The DPoP key of a Flutter web app: an ECDSA P-256 key pair made by the
/// browser's WebCrypto as non-extractable, so no script, the app's own
/// included, can read the private key; it can only ask the browser to
/// sign with it.
///
/// With DPoP (RFC 9449) the provider binds the tokens to the app's key: a
/// token stolen from the page (by an injected script, a browser
/// extension) is useless anywhere else, because every request with it
/// needs a proof signed by the key. A key made in Dart lives in the
/// page's memory, where an injected script can read it as easily as the
/// tokens; a WebCrypto key made with `extractable: false` cannot be
/// exported at all. An injected script can still sign with it while it
/// runs in the page (nothing in a browser stops that), but it cannot
/// carry the key, or the tokens, away.
///
/// The key pair is kept in the origin's IndexedDB as `CryptoKey` objects
/// (the browser stores the handle, never the key's bytes), so the page
/// uses the same key after a reload. Where IndexedDB is refused (some
/// private windows), the key lives as long as the page.
///
/// WebCrypto exists only in a secure context (`https:`, or
/// `http://localhost` in development): elsewhere [load] fails, and a
/// registration that uses DPoP cannot log in.
///
/// The package declares it as the `webCryptoDPoPKey` bean in spa mode, so
/// the OAuth2 client's token requests and the Feign interceptor sign
/// their proofs with it when a registration uses DPoP
/// (`spring.security.oauth2.client.registration.<id>.dpop=auto` or
/// `true`). The browser's WebCrypto is asynchronous, so the key is a
/// [LoadableDPoPKey]: made or read at its first use (`DPoPProofBuilder`
/// and `SpaOAuth2LoginService` call [load]), so an app whose providers do
/// not use DPoP never touches WebCrypto or IndexedDB; [publicJwk] throws
/// until then.
///
/// ```dart
/// final key = WebCryptoDPoPKey();
/// await key.load(); // the stored key, or a new one
/// final proof = await DPoPProofBuilder(key).build(
///   method: 'GET',
///   url: Uri.parse('https://api.neon.books/books'),
///   accessToken: token,
/// );
/// ```
///
/// Spring (Java): no such type; Java has no browser.
final class WebCryptoDPoPKey implements LoadableDPoPKey {
  /// Kept outside the program, so tokens bound to it survive a restart.
  @override
  bool get persistent => true;

  /// A key kept under [name] in [vault] (the browser's IndexedDB and
  /// WebCrypto by default; tests pass a fake).
  WebCryptoDPoPKey({this._vault, this.name = defaultName});

  /// `dpop`: the name the key is kept under.
  static const defaultName = 'dpop';

  /// The name the key pair is kept under in the vault.
  final String name;

  BrowserKeyVault? _vault;
  Future<void>? _loading;
  BrowserKeyPair? _pair;

  /// Whether [load] has completed: [publicJwk] is available.
  bool get isLoaded => _pair != null;

  /// Loads the stored key pair, or makes a new non-extractable one and
  /// stores it; once (later calls wait for the first).
  ///
  /// Throws an [UnsupportedError] where the browser has no WebCrypto (not
  /// a secure context) and outside a browser without a vault; the next
  /// call tries again.
  @override
  Future<void> load() => _loading ??= _load().catchError((Object error) {
    _loading = null; // a later call tries again
    throw error;
  });

  Future<void> _load() async {
    final vault = _vault ??= platform.createBrowserKeyVault();
    _pair = await vault.loadOrCreate(name);
    _log.debug('DPoP key ready: $this');
  }

  /// Forgets the key pair in the vault: tokens bound to it die with it.
  /// The next [load] makes a new one.
  Future<void> delete() async {
    final vault = _vault ??= platform.createBrowserKeyVault();
    await vault.delete(name);
    _pair = null;
    _loading = null;
  }

  @override
  String get algorithm => 'ES256';

  /// The public key as a JWK (`kty`, `crv`, `x`, `y`).
  ///
  /// Throws a [StateError] before [load] has completed.
  @override
  Map<String, Object?> get publicJwk =>
      (_pair ??
              (throw StateError(
                'The WebCrypto DPoP key is not loaded yet: await load() '
                'before its first use',
              )))
          .publicJwk;

  /// The RFC 7638 thumbprint of the public key: the `cnf.jkt` of the
  /// tokens bound to it.
  String get thumbprint => JwkThumbprint.of(publicJwk);

  /// Signs [input] in the browser (ECDSA with SHA-256); the raw `R || S`,
  /// 64 bytes, as JOSE wants it (WebCrypto writes that format; a DER
  /// signature would be converted). Loads the key first if needed.
  @override
  Future<Uint8List> sign(Uint8List input) async {
    await load();
    final signature = await _pair!.sign(input);
    return signature.length == 64
        ? signature
        : ECDSA.transcodeSignatureToConcat(signature, 64);
  }

  /// The algorithm and the public thumbprint; never anything secret.
  @override
  String toString() => _pair == null
      ? 'WebCryptoDPoPKey [alg=ES256, not loaded]'
      : 'WebCryptoDPoPKey [alg=ES256, jkt=$thumbprint]';
}

/// Where the browser keeps a [WebCryptoDPoPKey]: makes ECDSA P-256 key
/// pairs that cannot be exported and keeps their `CryptoKey` handles.
///
/// The browser's vault is WebCrypto with IndexedDB; tests pass a fake
/// (a [SoftwareDPoPKey] behind this interface).
abstract interface class BrowserKeyVault {
  /// The browser's vault.
  ///
  /// Throws an [UnsupportedError] outside a browser.
  factory BrowserKeyVault() => platform.createBrowserKeyVault();

  /// The key pair kept under [name]; a new non-extractable one, kept
  /// under [name], when there is none.
  ///
  /// Throws an [UnsupportedError] where the browser has no WebCrypto.
  Future<BrowserKeyPair> loadOrCreate(String name);

  /// Forgets the key pair kept under [name].
  Future<void> delete(String name);
}

/// A key pair of a [BrowserKeyVault]: its public JWK, and signatures by
/// its private key, which never leaves the vault.
abstract interface class BrowserKeyPair {
  /// The public key as a JWK (`kty`, `crv`, `x`, `y`; nothing private).
  Map<String, Object?> get publicJwk;

  /// The ECDSA SHA-256 signature of [input]: raw `R || S` (or DER, which
  /// [WebCryptoDPoPKey] converts).
  Future<Uint8List> sign(Uint8List input);
}
