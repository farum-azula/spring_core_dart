/// A small store of secrets, such as the tokens of a login, kept by key.
///
/// The OAuth2 client keeps the tokens of the logged-in user in it, so an
/// app that restarts is still logged in. The default,
/// [InMemoryTokenStore], forgets everything when the app stops; the
/// Flutter starter replaces it with the platform's secure storage (the
/// Keychain on iOS and macOS, the Android Keystore, DPAPI on Windows, the
/// Secret Service on Linux). Replace it yourself by declaring a bean of
/// this type.
///
/// Values are strings; store JSON for anything bigger. Keys are short
/// names chosen by the caller, such as `oauth2.keycloak`.
///
/// Spring has no such type: a Java server keeps tokens in memory or in a
/// database (`OAuth2AuthorizedClientService`), and Java has no apps.
abstract interface class TokenStore {
  /// The value stored under [key], or `null` when there is none.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing the old value.
  Future<void> write(String key, String value);

  /// Removes the value of [key]; nothing happens when there is none.
  Future<void> delete(String key);
}

/// A [TokenStore] in memory: the values are lost when the program stops.
///
/// The default on servers and wherever no secure storage exists. Tests use
/// it too.
class InMemoryTokenStore implements TokenStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
