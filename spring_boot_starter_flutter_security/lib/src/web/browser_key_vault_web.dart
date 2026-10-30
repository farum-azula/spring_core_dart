// The browser's key vault: WebCrypto keys that cannot be exported, their
// CryptoKey handles kept in IndexedDB. Through dart:js_interop (no
// package).
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:spring_boot_starter_flutter_security/src/web/web_crypto_dpop_key.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show SpringLog;

const _log = SpringLog('spring.security.oauth2.client.dpop');

const _database = 'spring_boot_starter_flutter_security';
const _store = 'keys';

@JS('crypto')
external _Crypto? get _crypto;

@JS('indexedDB')
external _IdbFactory? get _indexedDb;

extension type _Crypto._(JSObject _) implements JSObject {
  // Undefined outside a secure context.
  external _SubtleCrypto? get subtle;
}

extension type _SubtleCrypto._(JSObject _) implements JSObject {
  external JSPromise<_CryptoKeyPair> generateKey(
    JSObject algorithm,
    bool extractable,
    JSArray<JSString> keyUsages,
  );

  external JSPromise<JSArrayBuffer> sign(
    JSObject algorithm,
    _CryptoKey key,
    JSUint8Array data,
  );

  external JSPromise<JSObject> exportKey(String format, _CryptoKey key);
}

extension type _CryptoKey._(JSObject _) implements JSObject {
  external bool get extractable;
  external String get type;
  external JSObject get algorithm;
  external JSArray<JSString> get usages;
}

extension type _CryptoKeyPair._(JSObject _) implements JSObject {
  external _CryptoKey? get privateKey;
  external _CryptoKey? get publicKey;
}

extension type _IdbFactory._(JSObject _) implements JSObject {
  external _IdbOpenRequest open(String name, int version);
}

extension type _IdbRequest._(JSObject _) implements JSObject {
  external JSObject? get error;
  external set onsuccess(JSFunction? handler);
  external set onerror(JSFunction? handler);
}

extension type _IdbOpenRequest._(JSObject _) implements _IdbRequest {
  external _IdbDatabase get result;
  external set onupgradeneeded(JSFunction? handler);
  external set onblocked(JSFunction? handler);
}

extension type _IdbGetRequest._(JSObject _) implements _IdbRequest {
  external _CryptoKeyPair? get result;
}

extension type _IdbDatabase._(JSObject _) implements JSObject {
  external JSObject createObjectStore(String name);
  external _IdbTransaction transaction(String storeNames, String mode);
  external void close();
}

extension type _IdbTransaction._(JSObject _) implements JSObject {
  external _IdbObjectStore objectStore(String name);
  external set oncomplete(JSFunction? handler);
  external set onerror(JSFunction? handler);
  external set onabort(JSFunction? handler);
}

extension type _IdbObjectStore._(JSObject _) implements JSObject {
  external _IdbGetRequest get(String key);
  external _IdbRequest put(JSAny value, String key);
  external _IdbRequest delete(String key);
}

/// The vault of WebCrypto and IndexedDB.
BrowserKeyVault createBrowserKeyVault() => _WebCryptoVault();

final class _WebCryptoVault implements BrowserKeyVault {
  _WebCryptoVault();

  // A key pair made while IndexedDB was refused: this page's only.
  final Map<String, _CryptoKeyPair> _memory = {};

  static _SubtleCrypto _subtle() =>
      _crypto?.subtle ??
      (throw UnsupportedError(
        'WebCrypto is not available: the page is not a secure context. '
        'DPoP in the browser needs https (or http://localhost in '
        'development)',
      ));

  @override
  Future<BrowserKeyPair> loadOrCreate(String name) async {
    final subtle = _subtle();
    _IdbDatabase? database;
    try {
      database = await _open();
    } on Object catch (e) {
      _log.debug(
        'IndexedDB refused (${e.runtimeType}): the DPoP key lives as long '
        'as the page',
      );
    }
    if (database == null) {
      final pair = _memory[name] ??= await _generate(subtle);
      return _pair(subtle, pair);
    }
    try {
      final stored = await _get(database, name);
      if (stored != null) {
        if (_usable(stored)) {
          return await _pair(subtle, stored);
        }
        _log.info(
          'The stored DPoP key is not a non-extractable ECDSA P-256 signing '
          'key: replacing it with a new one',
        );
      }
      final pair = await _generate(subtle);
      await _put(database, name, pair);
      return await _pair(subtle, pair);
    } finally {
      database.close();
    }
  }

  @override
  Future<void> delete(String name) async {
    _memory.remove(name);
    final _IdbDatabase database;
    try {
      database = await _open();
    } on Object {
      return;
    }
    try {
      final transaction = database.transaction(_store, 'readwrite');
      final done = _transaction(transaction);
      transaction.objectStore(_store).delete(name);
      await done;
    } finally {
      database.close();
    }
  }

  // Whether the stored value is a key pair this vault would have made:
  // checked again at each load, as anything of the origin can write to
  // its IndexedDB.
  static bool _usable(_CryptoKeyPair stored) {
    try {
      final private = stored.privateKey;
      final public = stored.publicKey;
      if (private == null || public == null) {
        return false;
      }
      return storedKeyPairUsable((
        privateExtractable: private.extractable,
        privateType: private.type,
        publicType: public.type,
        privateAlgorithm: private.algorithm.dartify(),
        publicAlgorithm: public.algorithm.dartify(),
        privateUsages: [
          for (final usage in private.usages.toDart) usage.toDart,
        ],
      ));
    } on Object {
      // Not CryptoKey objects at all.
      return false;
    }
  }

  // A new ECDSA P-256 key pair whose private key cannot be exported (the
  // public key always can).
  static Future<_CryptoKeyPair> _generate(_SubtleCrypto subtle) async {
    final pair = await subtle
        .generateKey(
          {'name': 'ECDSA', 'namedCurve': 'P-256'}.jsify()! as JSObject,
          false,
          ['sign'.toJS, 'verify'.toJS].toJS,
        )
        .toDart;
    if (pair.privateKey?.extractable ?? true) {
      throw StateError('WebCrypto made an extractable DPoP key');
    }
    return pair;
  }

  static Future<BrowserKeyPair> _pair(
    _SubtleCrypto subtle,
    _CryptoKeyPair pair,
  ) async {
    final jwk = (await subtle.exportKey('jwk', pair.publicKey!).toDart)
        .dartify();
    if (jwk case {
      'kty': 'EC',
      'crv': 'P-256',
      'x': final String x,
      'y': final String y,
    }) {
      return _WebCryptoKeyPair(subtle, pair.privateKey!, {
        'kty': 'EC',
        'crv': 'P-256',
        'x': x,
        'y': y,
      });
    }
    throw StateError('WebCrypto exported no EC P-256 public key');
  }

  static Future<_IdbDatabase> _open() {
    final factory =
        _indexedDb ?? (throw UnsupportedError('IndexedDB is not available'));
    final request = factory.open(_database, 1);
    final completer = Completer<_IdbDatabase>();
    request
      ..onupgradeneeded = ((JSAny? _) {
        request.result.createObjectStore(_store);
      }).toJS
      ..onsuccess = ((JSAny? _) {
        if (!completer.isCompleted) {
          completer.complete(request.result);
        }
      }).toJS
      ..onerror = ((JSAny? _) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('IndexedDB could not be opened'));
        }
      }).toJS
      ..onblocked = ((JSAny? _) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('IndexedDB is blocked'));
        }
      }).toJS;
    return completer.future;
  }

  static Future<_CryptoKeyPair?> _get(_IdbDatabase database, String name) {
    final request = database
        .transaction(_store, 'readonly')
        .objectStore(_store)
        .get(name);
    final completer = Completer<_CryptoKeyPair?>();
    request
      ..onsuccess = ((JSAny? _) => completer.complete(request.result)).toJS
      ..onerror = ((JSAny? _) => completer.completeError(
        StateError('IndexedDB could not read the DPoP key'),
      )).toJS;
    return completer.future;
  }

  static Future<void> _put(
    _IdbDatabase database,
    String name,
    _CryptoKeyPair pair,
  ) {
    final transaction = database.transaction(_store, 'readwrite');
    final done = _transaction(transaction);
    // The CryptoKey objects, structured-cloned by the browser; the
    // private key stays non-extractable there too.
    transaction.objectStore(_store).put(pair, name);
    return done;
  }

  static Future<void> _transaction(_IdbTransaction transaction) {
    final completer = Completer<void>();
    void fail(JSAny? _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IndexedDB transaction failed'));
      }
    }

    transaction
      ..oncomplete = ((JSAny? _) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }).toJS
      ..onerror = fail.toJS
      ..onabort = fail.toJS;
    return completer.future;
  }
}

final class _WebCryptoKeyPair implements BrowserKeyPair {
  _WebCryptoKeyPair(this._subtle, this._privateKey, this.publicJwk);

  final _SubtleCrypto _subtle;
  final _CryptoKey _privateKey;

  @override
  final Map<String, Object?> publicJwk;

  // WebCrypto's ECDSA signature is already the raw R || S (IEEE P1363),
  // 64 bytes for P-256, not DER.
  @override
  Future<Uint8List> sign(Uint8List input) async {
    final signature = await _subtle
        .sign(
          {'name': 'ECDSA', 'hash': 'SHA-256'}.jsify()! as JSObject,
          _privateKey,
          input.toJS,
        )
        .toDart;
    return signature.toDart.asUint8List();
  }
}
