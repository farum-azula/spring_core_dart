// Secrets in the platform's secure storage (the Keychain, the Android
// Keystore), through the plugin's own platform code: run on a device,
// simulator or desktop with
//   flutter test integration_test -d macos
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Keys of this test only, removed at the end.
  const key = 'neon_books.integration_test.token';
  const other = 'neon_books.integration_test.other';
  final store = PlatformSecretStore();
  tearDown(() async {
    await store.delete(key);
    await store.delete(other);
  });

  testWidgets('writes, reads, replaces and deletes a value', (_) async {
    await store.delete(key);
    expect(await store.read(key), isNull);

    await store.write(key, 'first');
    expect(await store.read(key), 'first');

    // A JSON token response with non-ASCII text, as the OAuth2 client
    // stores it.
    const json = '{"access_token":"eyJ.ü.€","refresh_token":"r-1","x":"日本"}';
    await store.write(key, json);
    expect(await store.read(key), json);

    await store.delete(key);
    expect(await store.read(key), isNull);
    // Deleting again is fine.
    await store.delete(key);
  });

  testWidgets('keeps keys apart and stores long and empty values', (_) async {
    final long = List.filled(20000, 'a').join();
    await store.write(key, long);
    await store.write(other, '');
    expect(await store.read(key), long);
    expect(await store.read(other), '');

    await store.delete(other);
    expect(await store.read(key), long);
  });

  testWidgets('lists and deletes all of the app\'s keys', (_) async {
    await store.write(key, 'one');
    await store.write(other, 'two');
    expect(await store.keys(), containsAll(<String>[key, other]));

    await store.deleteAll();
    expect(await store.keys(), isEmpty);
    expect(await store.read(key), isNull);
  });

  testWidgets('a SecretTemplate keeps objects under its namespace', (_) async {
    final secrets = SecretTemplate(store, namespace: 'neon_it');
    await secrets.write('pin', {'hash': 'h', 'attempts': 1});
    expect(await store.keys(), contains('neon_it.pin'));
    expect(await secrets.read<Map<String, dynamic>>('pin'), {
      'hash': 'h',
      'attempts': 1,
    });
    await secrets.deleteAll();
    expect(await secrets.keys(), isEmpty);
  });

  testWidgets('the application gets it as its SecretStore bean', (_) async {
    final context = await SpringApplication(
      const [],
      autoConfigurations: [springBootStarterFlutterSecurityAutoConfiguration],
      bannerMode: BannerMode.off,
      // Only the classpath: on Android the working directory is `/`, and
      // listing its unreadable `config/` fails the default
      // `file:./config/*/` location.
    ).runAsync(const ['--spring.config.location=optional:classpath:/']);
    addTearDown(context.close);

    final bean = context.getBean<SecretStore>();
    expect(bean, isA<PlatformSecretStore>());
    await bean.write(key, 'from the bean');
    expect(await store.read(key), 'from the bean');

    // The login window of the platform: its own, or the default browser
    // with a loopback redirect on Windows and Linux.
    expect(
      context.getBeanNamesForType(AuthorizationWindow),
      defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux
          ? ['loopbackAuthorizationWindow']
          : ['platformAuthorizationWindow'],
    );
  });
}
