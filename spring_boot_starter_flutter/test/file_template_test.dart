// FileTemplate over the local file store (real folders under a temporary
// directory) and the in-memory store: values, atomic writes, paths that
// stay in their place, places, listings, temporary files and their
// cleaning.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/files/file_paths.dart';
import 'package:spring_boot_starter_flutter/src/files/local_file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/sha256.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('file_template_'));
  tearDown(() => root.deleteSync(recursive: true));

  LocalFileStore storeOf() => LocalFileStore(
    directory: (place) async => '${root.path}/places/${place.name}',
    runsDirectory: Directory('${root.path}/runs'),
  );

  group('FileTemplate on the local store', () {
    late LocalFileStore store;
    late FileTemplate files;

    setUp(() {
      store = storeOf();
      files = FileTemplate(store);
    });

    tearDown(() => store.close());

    test('text, bytes and JSON objects round-trip', () async {
      await files.write('notes/today.txt', 'héllo');
      expect(await files.read<String>('notes/today.txt'), 'héllo');
      expect(
        await files.read<Uint8List>('notes/today.txt'),
        utf8.encode('héllo'),
      );

      await files.write('blob.bin', Uint8List.fromList([0, 1, 255]));
      expect(await files.read<Uint8List>('blob.bin'), [0, 1, 255]);

      await files.write('map.json', {
        'title': 'Dune',
        'tags': ['sf'],
      });
      expect(
        await files.read<String>('map.json'),
        '{"title":"Dune","tags":["sf"]}',
      );
      expect(await files.read<Map<String, Object?>>('map.json'), {
        'title': 'Dune',
        'tags': ['sf'],
      });
      await files.write('list.json', ['a', 'b']);
      expect(
        await files.read<List<String>>(
          'list.json',
          const ListType<String>(ClassType<String>()),
        ),
        ['a', 'b'],
      );
    });

    test('a missing file reads as null, exists is false', () async {
      expect(await files.read<String>('nope.txt'), isNull);
      expect(await files.exists('nope.txt'), isFalse);
      expect(await files.modifiedAt('nope.txt'), isNull);
      expect(await files.delete('nope.txt'), isFalse);
      await files.write('a/b.txt', 'x');
      // A folder is not a file.
      expect(await files.read<String>('a'), isNull);
    });

    test('write replaces; delete removes a file or a folder', () async {
      await files.write('d/one.txt', '1');
      await files.write('d/one.txt', '11');
      await files.write('d/deeper/two.txt', '2');
      expect(await files.read<String>('d/one.txt'), '11');
      expect(await files.exists('d/one.txt'), isTrue);
      expect(await files.modifiedAt('d/one.txt'), isA<DateTime>());
      expect(await files.delete('d/one.txt'), isTrue);
      expect(await files.exists('d/one.txt'), isFalse);
      expect(await files.delete('d'), isTrue);
      expect(await files.list(), isEmpty);
    });

    test(
      'a failed write keeps the old file and leaves nothing behind',
      () async {
        await files.write('x/data.txt', 'old');
        // The target of the rename is a folder: the rename fails.
        await files.write('x/dir/inner.txt', 'inner');
        await expectLater(
          files.write('x/dir', 'new'),
          throwsA(isA<FileSystemException>()),
        );
        expect(await files.read<String>('x/dir/inner.txt'), 'inner');
        expect(await files.read<String>('x/data.txt'), 'old');
        final left = Directory('${root.path}/places/support/x')
            .listSync(recursive: true)
            .where((e) => e.path.endsWith(atomicWriteSuffix));
        expect(left, isEmpty);
      },
    );

    test('a write goes through a temporary file and a rename', () async {
      await files.write('big.txt', 'a' * 100000);
      final directory = Directory('${root.path}/places/support');
      expect(
        directory.listSync().map((e) => e.path.split('/').last),
        ['big.txt'],
      );
      await files.write('big.txt', 'b' * 10);
      expect(await files.read<String>('big.txt'), 'b' * 10);
    });

    test('paths stay inside their place', () async {
      for (final bad in [
        '../outside.txt',
        'a/../../outside.txt',
        '/etc/hosts',
        r'\windows',
        r'C:\x.txt',
        'c:/x.txt',
        '..',
        '',
        'a/../..',
        'nul\u0000.txt',
      ]) {
        await expectLater(
          files.write(bad, 'x'),
          throwsArgumentError,
          reason: bad,
        );
        await expectLater(
          files.read<String>(bad),
          throwsArgumentError,
          reason: bad,
        );
        await expectLater(files.delete(bad), throwsArgumentError, reason: bad);
        await expectLater(
          files.cache.exists(bad),
          throwsArgumentError,
          reason: bad,
        );
      }
      await expectLater(files.list('../'), throwsArgumentError);
      expect(File('${root.path}/places/outside.txt').existsSync(), isFalse);
      expect(File('${root.path}/outside.txt').existsSync(), isFalse);
      // Dots and backslashes that stay inside are fine.
      await files.write('./a//b.txt', 'ok');
      expect(await files.read<String>('a/b.txt'), 'ok');
      await files.write(r'sub\win.txt', 'w');
      expect(await files.read<String>('sub/win.txt'), 'w');
    });

    test('places are separate: support, cache, documents', () async {
      await files.write('same.txt', 'support');
      await files.cache.write('same.txt', 'cache');
      await files.documents.write('same.txt', 'documents');
      expect(await files.support.read<String>('same.txt'), 'support');
      expect(await files.read<String>('same.txt'), 'support');
      expect(await files.cache.read<String>('same.txt'), 'cache');
      expect(await files.documents.read<String>('same.txt'), 'documents');
      expect(File('${root.path}/places/cache/same.txt').existsSync(), isTrue);
      expect(
        File('${root.path}/places/documents/same.txt').existsSync(),
        isTrue,
      );
      await files.cache.delete('same.txt');
      expect(await files.cache.exists('same.txt'), isFalse);
      expect(await files.exists('same.txt'), isTrue);
    });

    test(
      'list: a folder, or the start of a path; sorted; no leftovers',
      () async {
        await files.write('thumbs/a.png', 'a');
        await files.write('thumbs/b.png', 'b');
        await files.write('thumbs/sub/c.png', 'c');
        await files.write('thumbs-old/d.png', 'd');
        await files.write('thumb-1.png', '1');
        await files.write('thumb-2.png', '2');
        expect(await files.list('thumbs/'), [
          'thumbs/a.png',
          'thumbs/b.png',
          'thumbs/sub/c.png',
        ]);
        expect(await files.list('thumb-'), ['thumb-1.png', 'thumb-2.png']);
        expect(await files.list('thumbs'), [
          'thumbs-old/d.png',
          'thumbs/a.png',
          'thumbs/b.png',
          'thumbs/sub/c.png',
        ]);
        expect((await files.list()).length, 6);
        expect(await files.list('missing/'), isEmpty);
        // An interrupted write's file is not listed.
        File('${root.path}/places/support/thumbs/x.png.1$atomicWriteSuffix')
            .writeAsStringSync('half');
        expect(await files.list('thumbs/'), hasLength(3));
      },
    );

    test('temp: a new file per call, deleted after the block', () async {
      late String first;
      final result = await files.temp(suffix: '.png', (file) async {
        first = file.path;
        expect(first, endsWith('.png'));
        expect(File(first).existsSync(), isTrue);
        await file.writeAsBytes([1, 2, 3]);
        expect(await file.readAsBytes(), [1, 2, 3]);
        await file.writeAsString('text');
        expect(await file.readAsString(), 'text');
        return 42;
      });
      expect(result, 42);
      expect(File(first).existsSync(), isFalse);
      expect(first, startsWith('${root.path}/runs/'));

      late String second;
      await files.temp((file) => second = file.path);
      expect(second, isNot(first));
    });

    test(
      'temp: deleted after an error too, and the error is rethrown',
      () async {
        late String path;
        await expectLater(
          files.temp((file) async {
            path = file.path;
            throw StateError('boom');
          }),
          throwsA(
            isA<StateError>().having((e) => e.message, 'message', 'boom'),
          ),
        );
        expect(File(path).existsSync(), isFalse);
      },
    );

    test(
      'tempDir: a folder deleted with its content, also after an error',
      () async {
        late String path;
        final value = await files.tempDir((dir) async {
          path = dir.path;
          File('$path/inner/file.txt')
            ..createSync(recursive: true)
            ..writeAsStringSync('x');
          return 'done';
        });
        expect(value, 'done');
        expect(Directory(path).existsSync(), isFalse);

        await expectLater(
          files.tempDir((dir) async {
            path = dir.path;
            throw ArgumentError('bad');
          }),
          throwsArgumentError,
        );
        expect(Directory(path).existsSync(), isFalse);
      },
    );

    test('createTemp is the caller\'s; close removes what is left', () async {
      final keep = await files.createTemp(suffix: '.zip');
      final dir = await files.createTempDir();
      File('${dir.path}/f').writeAsStringSync('x');
      expect(File(keep.path).existsSync(), isTrue);
      final run = File(keep.path).parent;
      expect(run.existsSync(), isTrue);
      await files.close();
      expect(File(keep.path).existsSync(), isFalse);
      expect(Directory(dir.path).existsSync(), isFalse);
      expect(run.existsSync(), isFalse);
      // The files of the places are not touched.
      await files.write('kept.txt', 'k');
      await files.close();
      expect(await files.read<String>('kept.txt'), 'k');
    });

    test('a temp suffix cannot leave the folder', () async {
      await expectLater(files.createTemp(suffix: '/../x'), throwsArgumentError);
    });

    test(
      'a start removes the folders of runs that died, not a live one',
      () async {
        final live = await files.createTemp();
        final dead = Directory('${root.path}/runs/dead-run')
          ..createSync(recursive: true);
        File('${dead.path}/.lock').writeAsStringSync('');
        File('${dead.path}/left.tmp').writeAsStringSync('x');
        final foreign = Directory('${root.path}/runs/no-lock')..createSync();

        final next = storeOf(); // the next start
        final nextFiles = FileTemplate(next);
        final mine = await nextFiles.createTemp();
        expect(dead.existsSync(), isFalse);
        expect(File(live.path).existsSync(), isTrue);
        expect(File(mine.path).existsSync(), isTrue);
        // A folder with no lock file might be a run starting: left alone.
        expect(foreign.existsSync(), isTrue);
        await next.close();
      },
    );
  });

  group('InMemoryFileStore', () {
    test('keeps files by place, lists and deletes', () async {
      final clock = DateTime.utc(2026, 11);
      final files = FileTemplate(InMemoryFileStore(clock: () => clock));
      await files.write('a/b.txt', 'hi');
      await files.cache.write('a/b.txt', 'cached');
      expect(await files.read<String>('a/b.txt'), 'hi');
      expect(await files.cache.read<String>('a/b.txt'), 'cached');
      expect(await files.modifiedAt('a/b.txt'), clock);
      expect(await files.list('a/'), ['a/b.txt']);
      expect(await files.delete('a'), isTrue);
      expect(await files.exists('a/b.txt'), isFalse);
      await expectLater(files.write('../x', 'x'), throwsArgumentError);
    });

    test(
      'temporary files live in memory; a real path is unsupported',
      () async {
        final files = FileTemplate(InMemoryFileStore());
        final value = await files.temp((file) async {
          await file.writeAsString('abc');
          expect(() => file.path, throwsUnsupportedError);
          return file.readAsString();
        });
        expect(value, 'abc');
        await expectLater(files.tempDir((_) {}), throwsUnsupportedError);
      },
    );
  });

  group('sha256', () {
    test('known digests', () {
      expect(
        sha256HexOfString(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        sha256HexOfString('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        sha256HexOfString(
          'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
        ),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      );
      expect(
        sha256Hex(List.filled(1000000, 0x61)),
        'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      );
    });
  });
}
