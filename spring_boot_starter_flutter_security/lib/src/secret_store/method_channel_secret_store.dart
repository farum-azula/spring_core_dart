import 'package:flutter/services.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/platform_secret_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';

/// The channel of the plugin's secret store on Android, iOS and macOS.
///
/// Methods (arguments are maps of strings):
///
/// - `read` `{key}`: the value, or `null` when there is none;
/// - `write` `{key, value}`: `null`;
/// - `delete` `{key}`: `null`;
/// - `keys` (no arguments): the list of keys that have a value;
/// - `deleteAll` (no arguments): `null`.
///
/// Errors are `PlatformException`s whose code names the storage
/// (`keychain`, `keystore`) and whose message says what failed.
const secretStoreChannel = MethodChannel(
  'spring_boot_starter_flutter_security/secret_store',
);

/// The [PlatformSecretStore] of Android, iOS and macOS: the plugin's platform
/// code, called through [secretStoreChannel].
final class MethodChannelSecretStore implements SecretStore {
  /// The store; it holds no state.
  const MethodChannelSecretStore();

  @override
  Future<String?> read(String key) => _call<String>('read', {'key': key});

  @override
  Future<void> write(String key, String value) =>
      _call<void>('write', {'key': key, 'value': value});

  @override
  Future<void> delete(String key) => _call<void>('delete', {'key': key});

  @override
  Future<Set<String>> keys() async {
    final keys = await _call<List<Object?>>('keys');
    return {...?keys?.cast<String>()};
  }

  @override
  Future<void> deleteAll() => _call<void>('deleteAll');

  static Future<T?> _call<T>(
    String method, [
    Map<String, String>? arguments,
  ]) async {
    try {
      return await secretStoreChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw PlatformSecretStoreException(e.message ?? e.code, code: e.code);
    } on MissingPluginException {
      throw const PlatformSecretStoreException(
        'the platform code of spring_boot_starter_flutter_security is not '
        'registered (a Dart test without the app? mock the channel '
        "'spring_boot_starter_flutter_security/secret_store', or declare "
        'another SecretStore bean)',
        code: 'no_plugin',
      );
    }
  }
}
