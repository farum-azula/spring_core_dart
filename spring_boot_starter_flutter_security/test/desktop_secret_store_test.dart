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
import 'dart:ffi';
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

  test('a long key round-trips (Windows: a hashed file name)', () async {
    final long = 'oauth2.authorized-client.${'k' * 120}.user-1';
    await store.write(long, 'tokens');
    expect(await store.read(long), 'tokens');
    expect(await store.keys(), contains(long));
    await store.delete(long);
    expect(await store.read(long), isNull);
  }, skip: skip);

  test('Windows: the app folder from the id, the version resource or the '
      'executable', () {
    expect(
      WindowsDpapiSecretStore.applicationFolder(r'Farum Azula\NEON Books'),
      r'Farum Azula\NEON Books',
    );
    // The test's executable (flutter_tester): its version resource, read
    // through version.dll, or its name.
    final folder = WindowsDpapiSecretStore.applicationFolder(null);
    expect(folder, isNotEmpty);
    expect(folder, isNot(contains(RegExp(r'[<>:"/|?*]'))));
  }, skip: Platform.isWindows ? null : 'version.dll is Windows only');

  test('Windows: the values of the 0.4.x folder are moved once', () async {
    final legacy = Directory('${folder.path}\\legacy')..createSync();
    final current = Directory('${folder.path}\\current');
    // As 0.4.x wrote it (the old folder's store, plain hex names).
    await WindowsDpapiSecretStore(directory: legacy).write('app.pin', '1234');
    final updated = WindowsDpapiSecretStore(
      directory: current,
      legacyDirectory: legacy,
    );
    expect(await updated.keys(), {'app.pin'});
    expect(await updated.read('app.pin'), '1234');
    expect(legacy.listSync(), isEmpty, reason: 'moved');
    // Written again there (another app of that name, on 0.4.x): ignored.
    await WindowsDpapiSecretStore(directory: legacy).write('app.pin', 'x');
    WindowsDpapiSecretStore.debugForgetMigrations(); // a new start
    expect(
      await WindowsDpapiSecretStore(
        directory: current,
        legacyDirectory: legacy,
      ).read('app.pin'),
      '1234',
    );
  }, skip: Platform.isWindows ? null : 'DPAPI is Windows only');

  test(
    'Linux: the items of 0.4.x (the executable name) are moved once',
    () async {
      final legacy = LinuxSecretServiceStore(application: 'spring-ci-legacy');
      LinuxSecretServiceStore start() => LinuxSecretServiceStore(
        application: 'spring-ci-secret-store',
        legacyApplication: 'spring-ci-legacy',
      );
      // The keyring outlives the run: no record of an earlier one.
      await start().debugForgetMigration();
      addTearDown(() => start().debugForgetMigration());
      addTearDown(legacy.deleteAll);
      await legacy.write('app.pin', '1234');
      await legacy.write('app.theme', 'dark');
      // A value of this version wins over the old one.
      await store.write('app.theme', 'light');

      final updated = start();
      expect(await updated.keys(), {'app.pin', 'app.theme'});
      expect(await legacy.keys(), isEmpty, reason: 'moved');
      expect(await updated.read('app.pin'), '1234');
      expect(await updated.read('app.theme'), 'light');

      // Another app of that executable name, still on 0.4.x, writes
      // there again: the next start of this one (the record found)
      // never reads, lists or deletes it.
      await legacy.write('app.other', 'theirs');
      LinuxSecretServiceStore.debugForgetMigrations();
      final restarted = start();
      expect(await restarted.keys(), {'app.pin', 'app.theme'});
      expect(await restarted.read('app.other'), isNull);
      await restarted.delete('app.other');
      await restarted.deleteAll();
      expect(await restarted.keys(), isEmpty);
      expect(await legacy.read('app.other'), 'theirs');
    },
    skip: Platform.isLinux ? skip : 'libsecret is Linux only',
  );

  test(
    'Linux: a read during the first write of its key is never "locked"',
    () async {
      // The lookup finds nothing, the write lands, the check for a locked
      // item finds it: before the fix the read called the keyring locked.
      // Four readers read the key without pause while it is written for
      // the first time, so some read straddles the write.
      var locked = 0;
      for (var round = 0; round < 30; round++) {
        final key = 'app.race-$round';
        Future<bool> reader() async {
          var calledLocked = false;
          for (var i = 0; i < 300; i++) {
            try {
              final value = await store.read(key);
              if (value != null) {
                expect(value, 'v$round');
                break;
              }
            } on PlatformSecretStoreException catch (e) {
              if (e.code != 'libsecret_locked') rethrow;
              calledLocked = true;
            }
          }
          return calledLocked;
        }

        final readers = [for (var i = 0; i < 4; i++) reader()];
        await Future<void>.delayed(Duration(milliseconds: 5 + round % 7));
        await store.write(key, 'v$round');
        if ((await Future.wait(readers)).contains(true)) {
          locked++;
        }
      }
      // ignore: avoid_print
      print('rounds with a read called locked: $locked/30');
      expect(locked, 0);
    },
    skip: Platform.isLinux ? skip : 'libsecret is Linux only',
  );

  // Runs where `skip` is null: the CI job with the Secret Service has GIO.
  test("Linux: the default app id is the running GTK application's", () {
    // Flutter's runner is a GtkApplication with the APPLICATION_ID of
    // linux/CMakeLists.txt; a test process has none until it makes one.
    expect(
      LinuxSecretServiceStore.defaultApplication(),
      LinuxSecretServiceStore.executableName(),
    );
    final gio = DynamicLibrary.open('libgio-2.0.so.0');
    final create = gio
        .lookupFunction<
          Pointer<Void> Function(Pointer<Utf8Char>, Int32),
          Pointer<Void> Function(Pointer<Utf8Char>, int)
        >('g_application_new');
    final setDefault = gio
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('g_application_set_default');
    final id = 'dev.farumazula.ci_app\u0000'.codeUnits;
    final name = _cString(id);
    final app = create(name, 0);
    setDefault(app);
    addTearDown(() => setDefault(nullptr));
    expect(
      LinuxSecretServiceStore.defaultApplication(),
      'dev.farumazula.ci_app',
    );
    expect(LinuxSecretServiceStore().application, 'dev.farumazula.ci_app');
  }, skip: Platform.isLinux ? skip : 'GIO is Linux only');

  // Last: it locks the keyring, then unlocks it with the session's
  // password (DESKTOP_SECRET_STORE_PASSWORD, `ci` as in CI) by replacing
  // the daemon.
  test(
    'Linux: a locked keyring whose prompt is dismissed fails the read, '
    'the write and the deletes; missing keys and keys() still answer',
    () async {
      await store.write('oauth2.dpop-key', '{"kty":"EC"}');
      await store.write('app.pin', '1234');
      final locked = await Process.run('gdbus', [
        'call',
        '--session',
        '--dest',
        'org.freedesktop.secrets',
        '--object-path',
        '/org/freedesktop/secrets',
        '--method',
        'org.freedesktop.Secret.Service.Lock',
        '["/org/freedesktop/secrets/aliases/default"]',
      ]);
      expect(locked.exitCode, 0, reason: '${locked.stderr}');
      var unlocked = false;
      Future<void> unlock() async {
        if (unlocked) return;
        unlocked = true;
        final password =
            Platform.environment['DESKTOP_SECRET_STORE_PASSWORD'] ?? 'ci';
        final daemon = await Process.start('gnome-keyring-daemon', [
          '--replace',
          '--unlock',
          '--components=secrets',
        ]);
        daemon.stdin.write(password);
        await daemon.stdin.close();
        await daemon.exitCode;
        await Future<void>.delayed(const Duration(seconds: 1));
        // libsecret keeps one connection per process, to the replaced
        // daemon: dropped, the next call connects to the new one.
        DynamicLibrary.open('libsecret-1.so.0')
            .lookupFunction<Void Function(), void Function()>(
              'secret_service_disconnect',
            )();
      }

      addTearDown(unlock);
      final isLocked = throwsA(
        isA<PlatformSecretStoreException>().having(
          (e) => e.code,
          'code',
          'libsecret_locked',
        ),
      );
      // No display, no prompter: the unlock prompt fails at once, as a
      // dismissed one does. The value exists: never "no value".
      await expectLater(store.read('oauth2.dpop-key'), isLocked);
      await expectLater(store.write('app.new', 'x'), isLocked);
      // libsecret deletes unlocked items only and said nothing: the
      // deletes returned, and the values were still there after the
      // unlock (a logout that kept the tokens).
      await expectLater(store.delete('oauth2.dpop-key'), isLocked);
      await expectLater(store.deleteAll(), isLocked);
      // What the Secret Service still tells of a locked keyring (the
      // attributes are not encrypted): a key that is truly missing reads
      // as none, deleting it does nothing, and keys() lists the keys.
      expect(await store.read('app.missing'), isNull);
      await store.delete('app.missing');
      expect(await store.keys(), {'oauth2.dpop-key', 'app.pin'});

      await unlock();
      expect(await store.read('oauth2.dpop-key'), '{"kty":"EC"}');
      expect(await store.keys(), {'oauth2.dpop-key', 'app.pin'});
      await store.delete('oauth2.dpop-key');
      expect(await store.keys(), {'app.pin'});
    },
    skip: Platform.isLinux ? skip : 'libsecret is Linux only',
  );
}

// [units] (with its terminating zero) in C memory, never freed (a test).
Pointer<Utf8Char> _cString(List<int> units) {
  final memory = _malloc(units.length);
  memory.cast<Uint8>().asTypedList(units.length).setAll(0, units);
  return memory.cast();
}

final _malloc = DynamicLibrary.open('libglib-2.0.so.0')
    .lookupFunction<
      Pointer<Void> Function(UintPtr),
      Pointer<Void> Function(int)
    >('g_malloc0');

final class Utf8Char extends Opaque {}
