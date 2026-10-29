// The Windows store's listing and clearing: they only read file names
// (the key in hexadecimal), so they run on any desktop; reading and
// writing need DPAPI and run on Windows only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/windows_dpapi_secret_store.dart';

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('dpapi_'));
  tearDown(() => folder.deleteSync(recursive: true));

  String hex(String key) => [
    for (final unit in key.codeUnits) unit.toRadixString(16).padLeft(2, '0'),
  ].join();

  test('keys are the file names; other files are left alone', () async {
    File('${folder.path}/${hex('oauth2.login')}.bin').writeAsStringSync('x');
    File('${folder.path}/${hex('app.pin')}.bin').writeAsStringSync('x');
    File('${folder.path}/${hex('app.pin')}.bin.tmp').writeAsStringSync('x');
    File('${folder.path}/notes.txt').writeAsStringSync('x');
    final store = WindowsDpapiSecretStore(directory: folder);

    expect(await store.keys(), {'oauth2.login', 'app.pin'});

    await store.deleteAll();
    expect(await store.keys(), isEmpty);
    expect(
      folder.listSync().map((f) => f.uri.pathSegments.last).toSet(),
      {'${hex('app.pin')}.bin.tmp', 'notes.txt'},
    );
  });

  test('no folder yet: no keys, nothing to delete', () async {
    final store = WindowsDpapiSecretStore(
      directory: Directory('${folder.path}/missing'),
    );
    expect(await store.keys(), isEmpty);
    await store.deleteAll();
  });
}
