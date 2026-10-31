// A reinstalled iOS app starts logged out: iOS keeps an app's Keychain
// items when the app is deleted, so the package removes the secret
// store's values (and the DPoP key) at the first start after a reinstall,
// and never at an update. Three runs, driven by reinstall_test.sh:
//   write — a value and the DPoP key are stored;
//   kept  — the app's preferences cleared (UserDefaults) and the app
//           installed again over itself (an update): both are still
//           there;
//   gone  — after `xcrun simctl uninstall`: both are gone.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

const _phase = String.fromEnvironment('SPRING_TEST_PHASE');
const _key = 'neon_books.integration_test.reinstall';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Keychain after a reinstall ($_phase)', (_) async {
    final store = PlatformSecretStore();
    final key = PlatformDPoPKey(store);
    switch (_phase) {
      case 'write':
        await store.write(_key, 'the last user');
        await key.load();
        // The thumbprint, for the next runs.
        await store.write(
          '$_key.jkt',
          JwkThumbprint.of(key.publicJwk),
        );
      case 'kept':
        expect(await store.read(_key), 'the last user');
        await key.load();
        expect(
          JwkThumbprint.of(key.publicJwk),
          await store.read('$_key.jkt'),
        );
      case 'gone':
        expect(await store.read(_key), isNull);
        expect(await store.keys(), isEmpty);
        // A new key: the old one was removed with the values.
        await key.load();
        await key.delete();
      default:
        fail('set --dart-define=SPRING_TEST_PHASE=write|kept|gone');
    }
  }, skip: _phase.isEmpty);
}
