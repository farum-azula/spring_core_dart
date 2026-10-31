import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';

/// The app's own secrets as objects: a PIN's settings, an API key with
/// its expiry, the key of an encrypted local database, written as JSON to
/// the [SecretStore].
///
/// The [SecretStore] keeps strings by key; this template turns objects
/// into JSON and back with the application's [ObjectMapper] (the class
/// needs `@Introspected()` or a JSON serializer, as for any JSON), and
/// puts every key under its [namespace] (`app.` by default), so the app's
/// keys never meet the login's (`oauth2.`). It is a bean of every app with
/// this package (`secretTemplate`); inject it where a secret is kept.
///
/// ```dart
/// @Introspected()
/// class PinSettings {
///   const PinSettings({required this.hash, required this.attempts});
///   final String hash;
///   final int attempts;
/// }
///
/// @Service()
/// class Pin {
///   Pin(this._secrets);
///   final SecretTemplate _secrets;
///
///   // Stored as {"attempts":0,"hash":"..."} under the key app.pin.
///   Future<void> save(String hash) =>
///       _secrets.write('pin', PinSettings(hash: hash, attempts: 0));
///   Future<PinSettings?> current() => _secrets.read<PinSettings>('pin');
///   Future<void> forget() => _secrets.delete('pin');
/// }
/// ```
///
/// The limits:
///
/// - **Small secrets, not data.** Each value goes to the Keychain, the
///   Keystore, DPAPI or the Secret Service, which are no database: a few
///   hundred values of a few kilobytes at most, every call slow. To
///   protect much data (a local database, files), encrypt it and keep
///   only its encryption key here.
/// - **No web.** A browser has no secure storage: everything a page keeps
///   (memory, `localStorage`, IndexedDB) is readable by any script of the
///   page. On the web every method fails with an [UnsupportedError]
///   instead of keeping the secret somewhere unsafe; there the server
///   keeps secrets. Errors always come in the returned `Future`, never
///   from the call itself.
///
/// Spring has no such type for apps; it is shaped like Spring Vault's
/// `VaultTemplate` (secrets by path) and Spring Data Redis'
/// `RedisTemplate` (objects through a serializer).
///
/// Spring (Java), the nearest:
/// ```java
/// vaultTemplate.write("secret/app/pin", new PinSettings(hash, 0));
/// PinSettings pin =
///     vaultTemplate.read("secret/app/pin", PinSettings.class).getData();
/// ```
class SecretTemplate {
  /// A template writing to [secretStore] under [namespace], with
  /// [objectMapper] (a default [ObjectMapper] when omitted; the bean
  /// gets the application's).
  ///
  /// [namespace] is a word without dots, not `oauth2` (the login's): two
  /// templates with different namespaces never see each other's keys. Throws an [ArgumentError] for any other value.
  SecretTemplate(
    this.secretStore, {
    ObjectMapper? objectMapper,
    this.namespace = 'app',
  }) : objectMapper = objectMapper ?? ObjectMapper() {
    if (namespace.isEmpty || namespace.contains('.')) {
      throw ArgumentError.value(
        namespace,
        'namespace',
        'must be a non-empty word without dots',
      );
    }
    if (namespace == reservedNamespace) {
      throw ArgumentError.value(
        namespace,
        'namespace',
        "is the login's; choose another",
      );
    }
  }

  /// The namespace of the login's tokens, which no template may use.
  static const reservedNamespace = 'oauth2';

  /// Where the JSON goes.
  final SecretStore secretStore;

  /// Turns objects into JSON and back.
  final ObjectMapper objectMapper;

  /// The first part of every key in the store: `pin` is kept as
  /// `<namespace>.pin`.
  final String namespace;

  String get _prefix => '$namespace.';

  /// Writes [value] as JSON under [key], replacing what was there.
  ///
  /// Fails with a [JsonMappingException] when [value] cannot be written
  /// as JSON, an [ArgumentError] for an empty [key], an
  /// [UnsupportedError] on the web (always in the returned `Future`,
  /// never thrown by the call itself).
  Future<void> write(String key, Object value) async {
    final stored = _key(key);
    await secretStore.write(stored, objectMapper.writeValueAsString(value));
  }

  /// The object stored under [key], or `null` when there is none.
  ///
  /// Pass [type] for generic types (`ListType<String>(...)`), as for
  /// `ObjectMapper.readValue`. Throws a [JsonMappingException] when the
  /// stored JSON does not fit [T] (its message never shows the value),
  /// an [UnsupportedError] on the web.
  Future<T?> read<T>(String key, [TypeInfo<T>? type]) async {
    final json = await secretStore.read(_key(key));
    if (json == null) {
      return null;
    }
    try {
      return objectMapper.readValue<T>(json, type);
    } on JsonMappingException catch (error) {
      // The cause and the message may quote the secret: neither is kept.
      throw JsonMappingException(
        'the secret "$key" of "$namespace" does not read as $T',
        path: error.path,
      );
    }
  }

  /// Removes the secret of [key]; nothing happens when there is none.
  ///
  /// Fails with an [ArgumentError] for an empty [key], an
  /// [UnsupportedError] on the web.
  Future<void> delete(String key) async {
    await secretStore.delete(_key(key));
  }

  /// The keys of this template's namespace that have a value, without
  /// the namespace (`pin`, not `app.pin`).
  ///
  /// Fails with an [UnsupportedError] on the web.
  Future<Set<String>> keys() async {
    _checkPlatform();
    return {
      for (final key in await secretStore.keys())
        if (key.startsWith(_prefix)) key.substring(_prefix.length),
    };
  }

  /// Removes every secret of this template's namespace; the login's
  /// tokens and other namespaces stay.
  ///
  /// Fails with an [UnsupportedError] on the web.
  Future<void> deleteAll() async {
    _checkPlatform();
    for (final key in await secretStore.keys()) {
      if (key.startsWith(_prefix)) {
        await secretStore.delete(key);
      }
    }
  }

  String _key(String key) {
    _checkPlatform();
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
    return '$_prefix$key';
  }

  static void _checkPlatform() {
    if (kIsWeb) {
      throw UnsupportedError(
        'SecretTemplate: a browser has no secure storage, so the web keeps '
        'no secrets (memory and localStorage are readable by any script of '
        'the page). Keep them on the server, or call this only outside the '
        'web.',
      );
    }
  }
}
