// The directories of the app that SQLite and FileTemplate share: what each
// platform maps `support`, `cache` and `documents` to, from a fake
// PathProviderPlatform and a pretended platform.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:spring_boot_starter_flutter/src/app_directories.dart';
import 'package:spring_boot_starter_flutter/src/files/file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/platform_file_store.dart';
import 'package:spring_boot_starter_flutter/src/sqlite_directories.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.support, this.cache, this.documents);

  final String support;
  final String cache;
  final String documents;

  @override
  Future<String?> getApplicationSupportPath() async => support;

  @override
  Future<String?> getApplicationCachePath() async => cache;

  @override
  Future<String?> getApplicationDocumentsPath() async => documents;
}

void main() {
  late PathProviderPlatform original;

  setUp(() => original = PathProviderPlatform.instance);
  tearDown(() {
    PathProviderPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });

  const roaming = r'C:\Users\u\AppData\Roaming\Acme\Books';
  const local = r'C:\Users\u\AppData\Local\Acme\Books';

  group('the mapping', () {
    test('Windows: support is the local directory, cache a folder in it', () {
      expect(
        appSupportDirectory(
          TargetPlatform.windows,
          support: roaming,
          cache: local,
        ),
        local,
      );
      expect(
        appCacheDirectory(TargetPlatform.windows, cache: local),
        '$local\\cache',
      );
      expect(appCacheDirectory(TargetPlatform.windows), isNull);
      expect(
        appSupportDirectory(TargetPlatform.windows, support: roaming),
        isNull,
      );
    });

    test('the other platforms take path_provider as it is', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(
          appSupportDirectory(platform, support: '/s', cache: '/c'),
          '/s',
          reason: '$platform',
        );
        expect(appCacheDirectory(platform, cache: '/c'), '/c');
      }
    });
  });

  group('read from path_provider', () {
    Future<(String, String, String)> read(TargetPlatform platform) async {
      PathProviderPlatform.instance = _FakePaths(
        platform == TargetPlatform.windows ? roaming : '/support',
        platform == TargetPlatform.windows ? local : '/cache',
        platform == TargetPlatform.windows ? r'C:\Users\u\Documents' : '/docs',
      );
      debugDefaultTargetPlatformOverride = platform;
      return (
        await readAppSupportDirectory(),
        await readAppCacheDirectory(),
        await readAppDocumentsDirectory(),
      );
    }

    test('Windows', () async {
      expect(await read(TargetPlatform.windows), (
        local,
        '$local\\cache',
        r'C:\Users\u\Documents',
      ));
    });

    test('Android, iOS, macOS, Linux', () async {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(
          await read(platform),
          ('/support', '/cache', '/docs'),
          reason: '$platform',
        );
      }
    });
  });

  test('SQLite and FileTemplate agree on support on every platform', () async {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      PathProviderPlatform.instance = _FakePaths(roaming, local, '/docs');
      debugDefaultTargetPlatformOverride = platform;
      final sqlite = (await SqliteDirectories.resolve())!;
      expect(
        sqlite.of(SqliteLocation.support),
        await readAppSupportDirectory(),
        reason: '$platform',
      );
      expect(
        sqlite.of(SqliteLocation.cache),
        await readAppCacheDirectory(),
        reason: '$platform',
      );
    }
  });

  test('the platform file store writes to these directories', () async {
    final root = await _tempRoot();
    PathProviderPlatform.instance = _FakePaths(
      '$root/support',
      '$root/cache',
      '$root/docs',
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final store = createPlatformFileStore();
    addTearDown(store.close);
    await store.write(FilePlace.support, 'a.txt', [1]);
    await store.write(FilePlace.cache, 'b.txt', [2]);
    expect(await store.list(FilePlace.support, ''), ['a.txt']);
    expect(await store.list(FilePlace.cache, ''), ['b.txt']);
  });
}

Future<String> _tempRoot() async {
  final directory = Directory.systemTemp.createTempSync('app_directories_');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory.path;
}
