import 'package:flutter/services.dart';
import 'package:spring_boot_starter_flutter/src/secure_storage/secure_token_store.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// The channel of the plugin's token store on Android, iOS and macOS.
///
/// Methods (arguments are maps of strings):
///
/// - `read` `{key}`: the value, or `null` when there is none;
/// - `write` `{key, value}`: `null`;
/// - `delete` `{key}`: `null`.
///
/// Errors are `PlatformException`s whose code names the storage
/// (`keychain`, `keystore`) and whose message says what failed.
const tokenStoreChannel = MethodChannel(
  'spring_boot_starter_flutter/token_store',
);

/// The [SecureTokenStore] of Android, iOS and macOS: the plugin's platform
/// code, called through [tokenStoreChannel].
final class MethodChannelTokenStore implements TokenStore {
  /// The store; it holds no state.
  const MethodChannelTokenStore();

  @override
  Future<String?> read(String key) => _call<String>('read', {'key': key});

  @override
  Future<void> write(String key, String value) =>
      _call<void>('write', {'key': key, 'value': value});

  @override
  Future<void> delete(String key) => _call<void>('delete', {'key': key});

  static Future<T?> _call<T>(
    String method,
    Map<String, String> arguments,
  ) async {
    try {
      return await tokenStoreChannel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw SecureTokenStoreException(e.message ?? e.code, code: e.code);
    } on MissingPluginException {
      throw const SecureTokenStoreException(
        'the platform code of spring_boot_starter_flutter is not registered '
        '(a Dart test without the app? mock the channel '
        "'spring_boot_starter_flutter/token_store', or declare another "
        'TokenStore bean)',
        code: 'no_plugin',
      );
    }
  }
}
