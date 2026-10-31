// The Windows store's listing and clearing: they only read file names
// (the key in hexadecimal), so they run on any desktop; reading and
// writing need DPAPI and run on Windows only.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/windows_dpapi_secret_store.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show SpringLog, SpringLogLevel, SpringLogRecord;

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

  test('a long key is named by its hash; its key is in a header', () async {
    final long = 'app.${'x' * 100}';
    final name = WindowsDpapiSecretStore.fileName(long);
    expect(name, matches(RegExp(r'^k-[0-9a-f]{64}\.bin$')));
    expect(
      WindowsDpapiSecretStore.fileName('oauth2.login'),
      '${hex('oauth2.login')}.bin',
    );
    // 64 bytes keep the readable name, 65 are hashed.
    expect(WindowsDpapiSecretStore.fileName('a' * 64), '${hex('a' * 64)}.bin');
    expect(WindowsDpapiSecretStore.fileName('a' * 65), startsWith('k-'));

    // What write puts before the sealed bytes: "SSK1", the length, the key.
    final key = utf8.encode(long);
    File('${folder.path}/$name').writeAsBytesSync([
      ...'SSK1'.codeUnits,
      key.length >> 8,
      key.length & 0xff,
      ...key,
      1, 2, 3, // the sealed value
    ]);
    // A hashed name whose header names another key is no key of ours.
    File(
      '${folder.path}/${WindowsDpapiSecretStore.fileName('app.${'y' * 100}')}',
    ).writeAsBytesSync([...'SSK1'.codeUnits, 0, 1, 0x7a, 9]);
    final store = WindowsDpapiSecretStore(directory: folder);
    expect(await store.keys(), {long});
    await store.delete(long);
    expect(await store.keys(), isEmpty);
  });

  String name(FileSystemEntity entity) => entity.uri.pathSegments.last;

  List<String> record(Directory current) => File(
    '${current.path}/${WindowsDpapiSecretStore.migrationMarker}',
  ).readAsLinesSync();

  test('the 0.4.x folder is moved once, then never read again', () async {
    final legacy = Directory('${folder.path}/legacy')..createSync();
    final current = Directory('${folder.path}/current')..createSync();
    final long = 'oauth2.authorized-client.${'k' * 80}';
    // As 0.4.x wrote them: plain hexadecimal names, whatever the length.
    File('${legacy.path}/${hex('oauth2.login')}.bin').writeAsBytesSync([1, 2]);
    File('${legacy.path}/${hex('app.pin')}.bin').writeAsBytesSync([3]);
    File('${legacy.path}/${hex(long)}.bin').writeAsBytesSync([4, 5]);
    File('${legacy.path}/notes.txt').writeAsStringSync('x');
    // A value of this version wins over the old one.
    File('${current.path}/${hex('app.pin')}.bin').writeAsBytesSync([9]);
    final store = WindowsDpapiSecretStore(
      directory: current,
      legacyDirectory: legacy,
    );

    expect(await store.keys(), {'oauth2.login', 'app.pin', long});
    // Moved sealed, as they were: nothing is decrypted.
    expect(
      File('${current.path}/${hex('oauth2.login')}.bin').readAsBytesSync(),
      [1, 2],
    );
    expect(
      File('${current.path}/${hex('app.pin')}.bin').readAsBytesSync(),
      [9],
    );
    // The long key under its hash, the key in the header.
    final hashed = File(
      '${current.path}/${WindowsDpapiSecretStore.fileName(long)}',
    ).readAsBytesSync();
    expect(hashed.sublist(0, 4), 'SSK1'.codeUnits);
    expect(utf8.decode(hashed.sublist(6, hashed.length - 2)), long);
    expect(hashed.sublist(hashed.length - 2), [4, 5]);
    // The old folder keeps only what was never a value.
    expect(legacy.listSync().map(name), ['notes.txt']);
    expect(
      File(
        '${current.path}/${WindowsDpapiSecretStore.migrationMarker}',
      ).existsSync(),
      isTrue,
    );

    // Another app of the same executable name, still on 0.4.x, writes
    // there again; the next start of this one (the record found) never
    // reads, lists or deletes it.
    File('${legacy.path}/${hex('app.theme')}.bin').writeAsBytesSync([7]);
    WindowsDpapiSecretStore.debugForgetMigrations();
    final restarted = WindowsDpapiSecretStore(
      directory: current,
      legacyDirectory: legacy,
    );
    expect(await restarted.keys(), {'oauth2.login', 'app.pin', long});
    expect(await restarted.read('app.theme'), isNull);
    await restarted.delete('app.theme');
    await restarted.deleteAll();
    expect(await restarted.keys(), isEmpty);
    expect(
      File('${legacy.path}/${hex('app.theme')}.bin').readAsBytesSync(),
      [7],
    );
    // deleteAll() keeps the record: the move never runs twice.
    expect(current.listSync().map(name), [
      WindowsDpapiSecretStore.migrationMarker,
    ]);
    // The same folder twice is one folder: nothing to move.
    final same = WindowsDpapiSecretStore(
      directory: current,
      legacyDirectory: Directory(current.path),
    );
    File('${current.path}/${hex('app.pin')}.bin').writeAsStringSync('x');
    expect(await same.keys(), {'app.pin'});
  });

  test('movers in several isolates at once: none fails, every value '
      'moved', () async {
    final legacy = Directory('${folder.path}/legacy')..createSync();
    final current = Directory('${folder.path}/current')..createSync();
    for (var i = 0; i < 40; i++) {
      File('${legacy.path}/${hex('app.k$i')}.bin').writeAsBytesSync([i]);
    }
    // Each isolate has its own record of moves, as another engine or a
    // second instance of the app at the first start after the update.
    final legacyPath = legacy.path;
    final currentPath = current.path;
    final results = await Future.wait([
      for (var n = 0; n < 3; n++)
        Isolate.run(
          () => WindowsDpapiSecretStore(
            directory: Directory(currentPath),
            legacyDirectory: Directory(legacyPath),
          ).keys(),
        ),
    ]);
    for (final keys in results) {
      expect(keys, hasLength(40));
    }
    for (var i = 0; i < 40; i++) {
      expect(
        File('${current.path}/${hex('app.k$i')}.bin').readAsBytesSync(),
        [i],
      );
    }
    expect(legacy.listSync(), isEmpty);
  });

  // Windows refuses to delete or replace a file another process or
  // isolate has open (errors 32 and 5): the move threw, and the first
  // call after the update failed with it.
  test('a 0.4.x file in use is tried again, then left for the next start; '
      'no call fails', () async {
    final legacy = Directory('${folder.path}/legacy')..createSync();
    final current = Directory('${folder.path}/current')..createSync();
    for (final (key, value) in [
      ('oauth2.login', 1),
      ('app.pin', 2),
      ('app.theme', 3),
    ]) {
      File('${legacy.path}/${hex(key)}.bin').writeAsBytesSync([value]);
    }
    FileSystemException inUse(File file, int code) => FileSystemException(
      'Cannot delete file',
      file.path,
      OSError('The process cannot access the file', code),
    );
    final logs = <SpringLogRecord>[];
    final previousHandler = SpringLog.handler;
    SpringLog.handler = logs.add;
    addTearDown(() {
      SpringLog.handler = previousHandler;
      WindowsDpapiSecretStore.debugMoveOperation = null;
      WindowsDpapiSecretStore.debugForgetMigrations();
    });
    var busy = 2;
    final attempts = <String>[];
    WindowsDpapiSecretStore.debugMoveOperation = (operation, file) {
      final name = file.uri.pathSegments.last;
      attempts.add('$operation $name');
      // Open in another isolate for two tries, then closed.
      if (operation == 'delete' && name == '${hex('oauth2.login')}.bin') {
        if (busy-- > 0) throw inUse(file, 32);
      }
      // Always open: the value cannot be put in place, or the old file
      // cannot be deleted.
      if (operation == 'write' && name == '${hex('app.pin')}.bin') {
        throw inUse(file, 5);
      }
      if (operation == 'delete' && name == '${hex('app.theme')}.bin') {
        throw inUse(file, 32);
      }
    };
    final store = WindowsDpapiSecretStore(
      directory: current,
      legacyDirectory: legacy,
    );

    final stopwatch = Stopwatch()..start();
    // app.pin could not be put in place: missing until the next start.
    expect(await store.keys(), {'oauth2.login', 'app.theme'});
    await store.delete('app.other');
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    expect(
      attempts.where((a) => a == 'delete ${hex('oauth2.login')}.bin'),
      hasLength(3),
    );
    expect(
      attempts.where((a) => a == 'write ${hex('app.pin')}.bin').length,
      greaterThan(1),
      reason: 'tried again',
    );
    expect(legacy.listSync().map(name).toSet(), {
      '${hex('app.pin')}.bin',
      '${hex('app.theme')}.bin',
    });
    // Recorded with what is left: the next start copies app.pin and
    // only deletes the old app.theme.
    expect(record(current), [
      legacy.path,
      'copy ${hex('app.pin')}.bin',
      'delete ${hex('app.theme')}.bin',
    ]);
    expect(
      logs.map((r) => r.message),
      contains(contains('2 file(s) of 0.4.x in ${legacy.path} could not be')),
    );

    WindowsDpapiSecretStore.debugMoveOperation = null;
    WindowsDpapiSecretStore.debugForgetMigrations();
    final restarted = WindowsDpapiSecretStore(
      directory: current,
      legacyDirectory: legacy,
    );
    expect(await restarted.keys(), {'oauth2.login', 'app.pin', 'app.theme'});
    expect(
      File('${current.path}/${hex('app.pin')}.bin').readAsBytesSync(),
      [2],
    );
    expect(legacy.listSync(), isEmpty);
    expect(record(current), [legacy.path]);
  });

  FileSystemException inUse(File file) => FileSystemException(
    'Cannot open file',
    file.path,
    const OSError('The process cannot access the file', 32),
  );

  void hook(void Function(String operation, File file) operation) {
    WindowsDpapiSecretStore.debugMoveOperation = operation;
    addTearDown(() {
      WindowsDpapiSecretStore.debugMoveOperation = null;
      WindowsDpapiSecretStore.debugForgetMigrations();
    });
  }

  WindowsDpapiSecretStore restart(Directory current, Directory legacy) {
    WindowsDpapiSecretStore.debugForgetMigrations();
    return WindowsDpapiSecretStore(directory: current, legacyDirectory: legacy);
  }

  // A logout undone: the old file was copied but stayed (in use), the move
  // was not recorded, and the next start copied it again.
  test('a value deleted after its old file stayed never comes back', () async {
    final legacy = Directory('${folder.path}/legacy')..createSync();
    final current = Directory('${folder.path}/current');
    File('${legacy.path}/${hex('oauth2.login')}.bin').writeAsBytesSync([1]);
    File('${legacy.path}/${hex('app.pin')}.bin').writeAsBytesSync([2]);
    hook((operation, file) {
      if (operation == 'delete') throw inUse(file);
    });
    final store = restart(current, legacy);
    expect(await store.keys(), {'oauth2.login', 'app.pin'});
    await store.delete('oauth2.login');

    WindowsDpapiSecretStore.debugMoveOperation = null; // closed now
    final restarted = restart(current, legacy);
    expect(await restarted.keys(), {'app.pin'});
    // The old files are deleted, never copied again.
    expect(legacy.listSync(), isEmpty);
    expect(record(current), [legacy.path]);
  });

  // A copy that failed is tried again at the next start, unless the
  // value was deleted in between.
  test('a value whose copy failed is copied at the next start; delete and '
      'deleteAll cancel that', () async {
    final legacy = Directory('${folder.path}/legacy')..createSync();
    final current = Directory('${folder.path}/current');
    for (final (key, value) in [
      ('oauth2.login', 1),
      ('app.pin', 2),
      ('app.theme', 3),
    ]) {
      File('${legacy.path}/${hex(key)}.bin').writeAsBytesSync([value]);
    }
    hook((operation, file) {
      if (operation == 'read') throw inUse(file);
    });
    var store = restart(current, legacy);
    expect(await store.keys(), isEmpty);
    await store.delete('oauth2.login'); // a logout of one value

    WindowsDpapiSecretStore.debugMoveOperation = null;
    store = restart(current, legacy);
    expect(await store.keys(), {'app.pin', 'app.theme'});
    expect(legacy.listSync(), isEmpty);
    expect(record(current), [legacy.path]);

    // The same, cleared with deleteAll.
    current.deleteSync(recursive: true);
    for (final key in ['oauth2.login', 'app.pin']) {
      File('${legacy.path}/${hex(key)}.bin').writeAsBytesSync([1]);
    }
    WindowsDpapiSecretStore.debugMoveOperation = (operation, file) {
      if (operation == 'read') throw inUse(file);
    };
    store = restart(current, legacy);
    expect(await store.keys(), isEmpty);
    await store.deleteAll();
    // Still in use at the next start: the old files stay, nothing copied.
    WindowsDpapiSecretStore.debugMoveOperation = (operation, file) {
      throw inUse(file);
    };
    store = restart(current, legacy);
    expect(await store.keys(), isEmpty);
    WindowsDpapiSecretStore.debugMoveOperation = null;
    store = restart(current, legacy);
    expect(await store.keys(), isEmpty);
    expect(legacy.listSync(), isEmpty);
  });

  // A file stuck for good made the first call of every start wait about a
  // second, log a warning, and read the old folder again.
  test('a file stuck for good: tried once per start, without waiting; '
      'the old folder is not read again', () async {
    final legacy = Directory('${folder.path}/legacy')..createSync();
    final current = Directory('${folder.path}/current');
    for (var i = 0; i < 5; i++) {
      File('${legacy.path}/${hex('app.k$i')}.bin').writeAsBytesSync([i]);
    }
    final logs = <SpringLogRecord>[];
    final previousHandler = SpringLog.handler;
    SpringLog.handler = logs.add;
    addTearDown(() => SpringLog.handler = previousHandler);
    final operations = <String>[];
    hook((operation, file) {
      operations.add('$operation ${file.uri.pathSegments.last}');
      if (operation == 'delete') throw inUse(file);
    });
    final first = restart(current, legacy);
    expect(await first.keys(), hasLength(5));
    expect(logs.where((r) => r.level == SpringLogLevel.warning), hasLength(1));

    // Another app of the executable name, still on 0.4.x, writes there.
    File('${legacy.path}/${hex('app.theme')}.bin').writeAsBytesSync([7]);
    for (var start = 2; start <= 3; start++) {
      operations.clear();
      final store = restart(current, legacy);
      final stopwatch = Stopwatch()..start();
      expect(await store.read('app.missing'), isNull);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 300)));
      // One try to delete each file left; nothing read, nothing copied.
      expect(
        operations,
        unorderedEquals([
          for (var i = 0; i < 5; i++) 'delete ${hex('app.k$i')}.bin',
        ]),
      );
      expect(await store.keys(), hasLength(5));
    }
    expect(logs.where((r) => r.level == SpringLogLevel.warning), hasLength(1));

    WindowsDpapiSecretStore.debugMoveOperation = null; // closed at last
    final last = restart(current, legacy);
    expect(await last.keys(), hasLength(5));
    expect(legacy.listSync().map(name), ['${hex('app.theme')}.bin']);
    expect(record(current), [legacy.path]);
  });

  // The same without the test hook: an old file the user may not delete.
  test(
    'a 0.4.x file that cannot be deleted fails no call',
    () async {
      final legacy = Directory('${folder.path}/legacy')..createSync();
      final current = Directory('${folder.path}/current');
      File('${legacy.path}/${hex('oauth2.login')}.bin').writeAsBytesSync([1]);
      Process.runSync('chmod', ['555', legacy.path]);
      addTearDown(() => Process.runSync('chmod', ['755', legacy.path]));
      final probe = File('${legacy.path}/probe');
      try {
        probe.createSync();
        probe.deleteSync();
        markTestSkipped('the folder is still writable (root?)');
        return;
      } on FileSystemException {
        // Read-only, as wanted.
      }
      final store = WindowsDpapiSecretStore(
        directory: current,
        legacyDirectory: legacy,
      );
      addTearDown(WindowsDpapiSecretStore.debugForgetMigrations);
      expect(await store.keys(), {'oauth2.login'});
      await store.deleteAll(); // a logout
      expect(await store.keys(), isEmpty);
      expect(legacy.listSync().map(name), ['${hex('oauth2.login')}.bin']);

      // The next start does not undo the logout, and another app of the
      // executable name, still on 0.4.x, writes there: not taken in.
      Process.runSync('chmod', ['755', legacy.path]);
      File('${legacy.path}/${hex('app.theme')}.bin').writeAsBytesSync([7]);
      Process.runSync('chmod', ['555', legacy.path]);
      WindowsDpapiSecretStore.debugForgetMigrations();
      var restarted = WindowsDpapiSecretStore(
        directory: current,
        legacyDirectory: legacy,
      );
      expect(await restarted.keys(), isEmpty);

      // Writable again: the file left is deleted, the other one untouched.
      Process.runSync('chmod', ['755', legacy.path]);
      WindowsDpapiSecretStore.debugForgetMigrations();
      restarted = WindowsDpapiSecretStore(
        directory: current,
        legacyDirectory: legacy,
      );
      expect(await restarted.keys(), isEmpty);
      expect(legacy.listSync().map(name), ['${hex('app.theme')}.bin']);
    },
    skip: Platform.isWindows ? 'chmod is POSIX' : false,
  );

  test('a first start without a 0.4.x folder records that too', () async {
    final current = Directory('${folder.path}/current');
    final store = WindowsDpapiSecretStore(
      directory: current,
      legacyDirectory: Directory('${folder.path}/never'),
    );
    expect(await store.keys(), isEmpty);
    expect(current.listSync().map(name), [
      WindowsDpapiSecretStore.migrationMarker,
    ]);
  });

  test('a blank application id is none', () {
    expect(WindowsDpapiSecretStore(applicationId: '').applicationId, isNull);
    expect(WindowsDpapiSecretStore(applicationId: '  ').applicationId, isNull);
    expect(
      WindowsDpapiSecretStore(applicationId: 'neon').applicationId,
      'neon',
    );
  });

  test('the app id as a folder: no path tricks', () {
    String? name(String id) => WindowsDpapiSecretStore.folderName(id);
    expect(name('dev.farumazula.neon_books'), 'dev.farumazula.neon_books');
    expect(name(r'Farum Azula\NEON Books'), r'Farum Azula\NEON Books');
    expect(name('a/b:c*d?e"f<g>h|i'), 'a_b_c_d_e_f_g_h_i');
    expect(name(r'..\..\Windows'), 'Windows');
    expect(name('app. '), 'app');
    expect(name(r'.\.'), isNull);
    expect(name(''), isNull);
  });

  test('each write goes through a temporary file of its own', () async {
    final target = File('${folder.path}/${hex('app.pin')}.bin');
    await Future.wait([
      for (var i = 0; i < 20; i++)
        WindowsDpapiSecretStore.writeAtomically(target, [i]),
    ]);
    expect(target.readAsBytesSync(), hasLength(1));
    // No temporary file is left, and none was shared.
    expect(folder.listSync().map((f) => f.uri.pathSegments.last), [
      '${hex('app.pin')}.bin',
    ]);
  });

  test('no folder yet: no keys, nothing to delete', () async {
    final store = WindowsDpapiSecretStore(
      directory: Directory('${folder.path}/missing'),
    );
    expect(await store.keys(), isEmpty);
    await store.deleteAll();
  });
}
