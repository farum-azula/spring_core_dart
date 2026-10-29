/// A small store of secrets: strings kept by key, such as the tokens of a
/// login, a PIN or an API key.
///
/// The app login keeps the tokens of the logged-in user in it (under keys
/// starting with `oauth2.`: `OAuth2LoginService` and
/// `SecretStoreOAuth2AuthorizedClientService`), so an app that restarts
/// is still logged in. An app may keep its own secrets here too;
/// `SecretTemplate` does that with objects and keeps the app's keys apart
/// from the login's.
///
/// The package's auto-configuration declares the platform's secure
/// storage as this bean (`PlatformSecretStore`: the Keychain on iOS and
/// macOS, the Android Keystore, DPAPI on Windows, the Secret Service on
/// Linux), and an [InMemorySecretStore] where there is none (the web).
/// Replace it by declaring a bean of this type.
///
/// It is for small secrets, not data: the Keychain and the Keystore are no
/// database, and every call may be slow. To protect much data (a local
/// database, files), encrypt it and keep only its key here.
///
/// Keys are short names chosen by the caller, such as `oauth2.login` or
/// `app.pin`; values are strings (store JSON for anything bigger).
///
/// Spring has no such type: a Java server keeps tokens in memory or in a
/// database (`OAuth2AuthorizedClientService`) and other secrets in a
/// vault (Spring Vault), and Java has no apps.
abstract interface class SecretStore {
  /// The value stored under [key], or `null` when there is none.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing the old value.
  Future<void> write(String key, String value);

  /// Removes the value of [key]; nothing happens when there is none.
  Future<void> delete(String key);

  /// The keys that have a value, in no particular order.
  ///
  /// Only the keys of this app: the platform stores never list another
  /// app's secrets.
  Future<Set<String>> keys();

  /// Removes every value of this store: the login's tokens and the app's
  /// own secrets. Call it to forget everything, for example
  /// when the user resets the app; a logout needs only
  /// `OAuth2LoginService.logout`.
  Future<void> deleteAll();
}

/// A [SecretStore] in memory: the values are lost when the program stops.
///
/// The package's `SecretStore` bean where the platform has no secure
/// storage (the web, where nothing is kept in it: the app login and
/// `SecretTemplate` refuse to run there). Tests use it too.
class InMemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<Set<String>> keys() async => _values.keys.toSet();

  @override
  Future<void> deleteAll() async => _values.clear();
}
