@TestOn('browser')
library;

// FileTemplate on the browser's IndexedDB (IndexedDbFileStore, dart:js_interop)
// in a real browser: `flutter test --platform chrome
// test/file_template_web_test.dart`. The VM run skips it.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/files/indexed_db_file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/platform_file_store.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_source.dart';

@JS('indexedDB.deleteDatabase')
external JSObject _deleteDatabase(String name);

@JS('Object.defineProperty')
external void _defineProperty(JSObject target, String name, JSObject spec);

@JS('Object.getOwnPropertyDescriptor')
external JSObject? _descriptor(JSObject target, String name);

@JS('Reflect.deleteProperty')
external bool _deleteProperty(JSObject target, String name);

@JS('globalThis')
external JSObject get _global;

@JS('Object.create')
external JSObject _plain(JSAny? prototype);

extension type _Spec._(JSObject _) implements JSObject {
  external set value(JSAny? value);
  external set configurable(bool value);
}

class _Server implements HttpTransport {
  final requests = <HttpRequest>[];

  @override
  Future<HttpResponse> send(HttpRequest request) =>
      throw UnimplementedError('only stream is used');

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    requests.add(request);
    return StreamedHttpResponse(
      200,
      headers: HttpHeaders({'ETag': '"v1"'}),
      body: Stream.value(
        Uint8List.fromList(
          utf8.encode('''
spring:
  flutter:
    theme:
      themes:
        ocean:
          colors.primary: '#FF0000'
'''),
        ),
      ),
      request: request,
    );
  }

  @override
  void close() {}
}

var _counter = 0;

void main() {
  late String name;

  setUp(() => name = 'spring_files_test_${_counter++}');
  tearDown(() => _deleteDatabase(name));

  FileTemplate templateOf() => FileTemplate(IndexedDbFileStore(name: name));

  group('IndexedDbFileStore in the browser', () {
    test('text, bytes and JSON round-trip', () async {
      final files = templateOf();
      await files.write('notes/today.txt', 'héllo ✓');
      expect(await files.read<String>('notes/today.txt'), 'héllo ✓');
      expect(await files.support.readString('notes/today.txt'), 'héllo ✓');

      final bytes = Uint8List.fromList([0, 1, 2, 254, 255]);
      await files.write('bin/data.bin', bytes);
      expect(await files.support.readBytes('bin/data.bin'), bytes);
      expect(await files.read<List<int>>('bin/data.bin'), bytes);

      await files.write('map.json', {
        'a': 1,
        'b': ['x', 'y'],
      });
      expect(await files.read<Map<String, Object?>>('map.json'), {
        'a': 1,
        'b': ['x', 'y'],
      });
      expect(await files.read<String>('missing.txt'), isNull);
      // Overwriting replaces.
      await files.write('notes/today.txt', 'new');
      expect(await files.read<String>('notes/today.txt'), 'new');
    });

    test('exists, delete (file and folder), list, modifiedAt', () async {
      final files = templateOf();
      final before = DateTime.now().subtract(const Duration(seconds: 2));
      await files.write('a/one.txt', '1');
      await files.write('a/two.txt', '2');
      await files.write('a/deep/three.txt', '3');
      await files.write('b.txt', '4');
      await files.write('thumb-1.png', [1]);
      await files.write('thumb-2.png', [2]);

      expect(await files.exists('a/one.txt'), isTrue);
      expect(await files.exists('a/nope.txt'), isFalse);
      expect(await files.exists('a'), isFalse, reason: 'a folder is no file');

      expect(await files.list(), [
        'a/deep/three.txt',
        'a/one.txt',
        'a/two.txt',
        'b.txt',
        'thumb-1.png',
        'thumb-2.png',
      ]);
      expect(await files.list('a/'), [
        'a/deep/three.txt',
        'a/one.txt',
        'a/two.txt',
      ]);
      expect(await files.list('thumb-'), ['thumb-1.png', 'thumb-2.png']);
      expect(await files.list('zzz/'), isEmpty);

      final modified = await files.modifiedAt('a/one.txt');
      expect(modified, isNotNull);
      expect(modified!.isAfter(before), isTrue);
      expect(
        modified.isAfter(DateTime.now().add(const Duration(seconds: 2))),
        isFalse,
      );
      expect(await files.modifiedAt('nope'), isNull);

      expect(await files.delete('a/one.txt'), isTrue);
      expect(await files.delete('a/one.txt'), isFalse);
      expect(await files.delete('a'), isTrue);
      expect(await files.list(), ['b.txt', 'thumb-1.png', 'thumb-2.png']);
      // "a" does not take "ab.txt" with it.
      await files.write('ab.txt', 'x');
      await files.write('c/x.txt', 'x');
      expect(await files.delete('c'), isTrue);
      expect(await files.exists('ab.txt'), isTrue);
    });

    test('paths stay in their place', () async {
      final files = templateOf();
      await expectLater(files.write('../x', 'x'), throwsArgumentError);
      await expectLater(files.read<String>('/etc/hosts'), throwsArgumentError);
    });

    test('the places are apart', () async {
      final files = templateOf();
      await files.write('same.txt', 'support');
      await files.cache.write('same.txt', 'cache');
      await files.documents.write('same.txt', 'documents');
      expect(await files.support.read<String>('same.txt'), 'support');
      expect(await files.cache.read<String>('same.txt'), 'cache');
      expect(await files.documents.read<String>('same.txt'), 'documents');
      await files.cache.delete('same.txt');
      expect(await files.cache.exists('same.txt'), isFalse);
      expect(await files.exists('same.txt'), isTrue);
      expect(await files.documents.list(), ['same.txt']);
      expect(await files.cache.list(), isEmpty);
    });

    test(
      'files outlive the store: a new store reads what was written',
      () async {
        final first = templateOf();
        await first.write('kept.txt', 'kept');
        await first.cache.write('c/kept.bin', [9, 8, 7]);
        await first.close();

        final second = templateOf();
        expect(await second.read<String>('kept.txt'), 'kept');
        expect(await second.cache.readBytes('c/kept.bin'), [9, 8, 7]);
        expect(await second.list(), ['kept.txt']);
        expect(await second.modifiedAt('kept.txt'), isNotNull);
        await second.delete('kept.txt');
        expect(await templateOf().exists('kept.txt'), isFalse);
      },
    );

    test('concurrent writes all land', () async {
      final files = templateOf();
      await Future.wait([
        for (var i = 0; i < 20; i++) files.write('many/$i.txt', 'v$i'),
      ]);
      expect(await files.list('many/'), hasLength(20));
      expect(await files.read<String>('many/13.txt'), 'v13');
    });

    test('temporary files are in memory, with no path', () async {
      final files = templateOf();
      final value = await files.temp(suffix: '.png', (file) async {
        await file.writeAsString('abc');
        expect(await file.exists(), isTrue);
        expect(() => file.path, throwsUnsupportedError);
        await file.writeAsBytes([1, 2, 3]);
        return file.readAsBytes();
      });
      expect(value, [1, 2, 3]);
      await expectLater(files.tempDir((_) {}), throwsUnsupportedError);
      await expectLater(files.createTempDir(), throwsUnsupportedError);
      final kept = await files.createTemp();
      await kept.writeAsString('x');
      await kept.delete();
      expect(await kept.exists(), isFalse);
      // Temporary files are not in IndexedDB.
      expect(await files.list(), isEmpty);
    });

    test('the platform store of the browser is this one', () async {
      final store = createPlatformFileStore();
      expect(store, isA<IndexedDbFileStore>());
      await store.close();
    });
  });

  group('without IndexedDB', () {
    late JSObject? original;

    // Hides window.indexedDB for the length of the test.
    void hide() {
      original = _descriptor(_global, 'indexedDB');
      final spec = _Spec._(_plain(null))
        ..value = null
        ..configurable = true;
      _defineProperty(_global, 'indexedDB', spec);
    }

    void restore() {
      // Removes the shadowing own property: the one of the prototype shows.
      _deleteProperty(_global, 'indexedDB');
      if (original != null && _descriptor(_global, 'indexedDB') == null) {
        _defineProperty(_global, 'indexedDB', original!);
      }
    }

    test('the files stay in memory', () async {
      hide();
      addTearDown(restore);
      final files = FileTemplate(IndexedDbFileStore(name: '${name}_none'));
      await files.write('a.txt', 'in memory');
      expect(await files.read<String>('a.txt'), 'in memory');
      expect(await files.exists('a.txt'), isTrue);
      expect(await files.list(), ['a.txt']);
      expect(await files.modifiedAt('a.txt'), isNotNull);
      expect(await files.delete('a.txt'), isTrue);
      expect(await files.exists('a.txt'), isFalse);
      // Another store has nothing: it was memory only.
      await files.write('b.txt', 'b');
      expect(
        await FileTemplate(
          IndexedDbFileStore(name: '${name}_none'),
        ).exists('b.txt'),
        isFalse,
      );
    });
  });

  group('the theme from a URL on the web store', () {
    test('is cached in IndexedDB and survives a restart', () async {
      const url =
          'https://raw.githubusercontent.com/neon/themes/main/ocean.yml';
      final properties = {
        'active': 'ocean',
        'themes.ocean.source': url,
        'themes.ocean.colors.primary': '#00FF00',
      };
      final server = _Server();

      Future<SpringThemes> start() async {
        final themes = SpringThemes(properties);
        final loader = ThemeSourceLoader(
          themes: themes,
          files: templateOf(),
          sources: ThemeSource.read(properties, themes),
          transport: server,
        );
        await loader.run(ApplicationArguments(const []));
        return themes;
      }

      final first = await start();
      expect(server.requests, hasLength(1));
      // The downloaded color, over the one of the app's own files.
      final primary = first.data('ocean').colorScheme.primary;
      expect(primary.toARGB32(), 0xFFFF0000);
      expect(
        SpringThemes(properties).data('ocean').colorScheme.primary.toARGB32(),
        0xFF00FF00,
      );

      final key = ThemeSource.read(properties, first).single.cacheKey;
      final files = templateOf();
      expect(await files.exists('spring/themes/$key/theme.yml'), isTrue);
      expect(await files.exists('spring/themes/$key/meta.json'), isTrue);

      // A restart: a new store over the same IndexedDB asks nobody.
      final second = await start();
      expect(server.requests, hasLength(1));
      expect(second.data('ocean').colorScheme.primary, primary);
    });
  });
}
