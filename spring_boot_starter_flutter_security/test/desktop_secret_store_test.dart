// The secret stores of Windows (DPAPI) and Linux (the Secret Service
// through libsecret) against the real operating system: dart:ffi calls
// from the test's own process, no app to build. CI's job "Secret stores on
// Windows and Linux" runs it on GitHub's runners (Linux with an unlocked
// GNOME Keyring in a D-Bus session) with DESKTOP_SECRET_STORE_REQUIRED
// set; elsewhere it runs on Windows and is skipped on Linux (a Secret
// Service may be missing or locked) and on other systems.
//
//   flutter test test/desktop_secret_store_test.dart
@TestOn('windows || linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/linux_secret_service_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/windows_dpapi_secret_store.dart';

void main() {
  final required = Platform.environment.containsKey(
    'DESKTOP_SECRET_STORE_REQUIRED',
  );
  final skip = Platform.isLinux && !required
      ? 'Needs an unlocked Secret Service (set DESKTOP_SECRET_STORE_REQUIRED)'
      : null;

  late Directory folder;
  // The stores of two apps: their keys must stay apart.
  late SecretStore store;
  late SecretStore otherApp;

  setUp(() async {
    if (Platform.isWindows) {
      folder = Directory.systemTemp.createTempSync('dpapi_');
      store = WindowsDpapiSecretStore(directory: folder);
      otherApp = WindowsDpapiSecretStore(
        directory: Directory('${folder.path}\\other')..createSync(),
      );
    } else {
      store = LinuxSecretServiceStore(application: 'spring-ci-secret-store');
      otherApp = LinuxSecretServiceStore(application: 'spring-ci-other-app');
      if (skip == null) {
        // The keyring outlives the test run: start from nothing, whatever
        // an earlier run left.
        await store.deleteAll();
        await otherApp.deleteAll();
      }
    }
  });

  tearDown(() async {
    await store.deleteAll();
    await otherApp.deleteAll();
    if (Platform.isWindows) {
      folder.deleteSync(recursive: true);
    }
  });

  test('writes, reads, replaces and deletes', () async {
    expect(await store.read('oauth2.login'), isNull);
    await store.write('oauth2.login', 'first');
    expect(await store.read('oauth2.login'), 'first');
    // A token response with non-ASCII text, as the login stores it.
    const json = '{"access_token":"eyJ.ü.€","refresh_token":"r-1","x":"日本"}';
    await store.write('oauth2.login', json);
    expect(await store.read('oauth2.login'), json);
    await store.delete('oauth2.login');
    expect(await store.read('oauth2.login'), isNull);
    await store.delete('oauth2.login'); // deleting again is fine
  }, skip: skip);

  test('long and empty values, keys kept apart', () async {
    final long = List.filled(20000, 'a').join();
    await store.write('app.long', long);
    await store.write('app.empty', '');
    expect(await store.read('app.long'), long);
    expect(await store.read('app.empty'), '');
    await store.delete('app.empty');
    expect(await store.read('app.long'), long);
  }, skip: skip);

  test("keys() and deleteAll() see this app's keys only", () async {
    await store.write('oauth2.login', 'one');
    await store.write('app.pin', 'two');
    await otherApp.write('app.pin', 'theirs');
    expect(await store.keys(), {'oauth2.login', 'app.pin'});

    await store.deleteAll();
    expect(await store.keys(), isEmpty);
    expect(await store.read('app.pin'), isNull);
    expect(await otherApp.read('app.pin'), 'theirs');
    expect(await otherApp.keys(), {'app.pin'});
  }, skip: skip);

  test('Windows: the file holds no plain text', () async {
    const secret = 'a-refresh-token-that-must-not-be-readable';
    await store.write('oauth2.login', secret);
    final files = folder.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    final bytes = files.single.readAsBytesSync();
    expect(latin1.decode(bytes, allowInvalid: true), isNot(contains(secret)));
    expect(
      utf8.decode(bytes, allowMalformed: true),
      isNot(contains(secret)),
    );
  }, skip: Platform.isWindows ? null : 'DPAPI is Windows only');

  test('the DPoP key survives a restart (a new key object)', () async {
    final first = SecretStoreDPoPKey(store);
    await first.load();
    final thumbprint = JwkThumbprint.of(first.publicJwk);
    final signature = await first.sign(Uint8List.fromList([1, 2, 3]));
    expect(signature, hasLength(64)); // raw R || S

    final again = SecretStoreDPoPKey(store);
    await again.load();
    expect(JwkThumbprint.of(again.publicJwk), thumbprint);

    await again.delete();
    expect(await store.read(SecretStoreDPoPKey.defaultKey), isNull);
  }, skip: skip);
}
