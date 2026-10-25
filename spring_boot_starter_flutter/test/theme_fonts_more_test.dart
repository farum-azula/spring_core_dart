// The font name table in detail (made-up fonts), loading again after a
// restart, unreadable files, exclusion globs, and loadFor with its
// properties and warnings.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// A font file with only a `name` table holding [records]:
/// (platform, encoding, language, name id, text).
Uint8List font(
  List<(int, int, int, int, String)> records, {
  bool table = true,
}) {
  final strings = BytesBuilder();
  final entries = <(int, int, int, int, int, int)>[];
  for (final (platform, encoding, language, id, text) in records) {
    final bytes = platform == 1
        ? latin1.encode(text)
        : Uint8List.fromList([
            for (final c in text.codeUnits) ...[c >> 8, c & 0xFF],
          ]);
    entries.add((
      platform,
      encoding,
      language,
      id,
      bytes.length,
      strings.length,
    ));
    strings.add(bytes);
  }
  final name = ByteData(6 + entries.length * 12);
  name
    ..setUint16(0, 0)
    ..setUint16(2, entries.length)
    ..setUint16(4, 6 + entries.length * 12);
  for (final (i, (platform, encoding, language, id, length, offset))
      in entries.indexed) {
    final r = 6 + i * 12;
    name
      ..setUint16(r, platform)
      ..setUint16(r + 2, encoding)
      ..setUint16(r + 4, language)
      ..setUint16(r + 6, id)
      ..setUint16(r + 8, length)
      ..setUint16(r + 10, offset);
  }
  final nameTable = [...name.buffer.asUint8List(), ...strings.takeBytes()];
  final header = ByteData(12 + 16)
    ..setUint32(0, 0x00010000)
    ..setUint16(4, 1);
  final tag = table ? 'name' : 'head';
  for (var i = 0; i < 4; i++) {
    header.setUint8(12 + i, tag.codeUnitAt(i));
  }
  header
    ..setUint32(12 + 8, 28)
    ..setUint32(12 + 12, nameTable.length);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...nameTable]);
}

class Bundle extends CachingAssetBundle {
  Bundle(this.files);
  final Map<String, Uint8List> files;
  final loads = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    return switch (files[key]) {
      final bytes? => ByteData.sublistView(bytes),
      null => throw FlutterError('Unable to load asset: "$key".'),
    };
  }
}

File sdkFont(String name) {
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final file = File('${directory.path}/material_fonts/$name');
    if (directory.path.endsWith('artifacts') && file.existsSync()) {
      return file;
    }
    directory = directory.parent;
  }
  throw StateError('No material_fonts');
}

List<String> captureWarnings() {
  final warnings = <String>[];
  final stop = SpringLog.listen((record) {
    if (record.level == SpringLogLevel.warning &&
        record.loggerName.endsWith('ThemeFonts')) {
      warnings.add(record.message);
    }
  });
  addTearDown(stop);
  return warnings;
}

void main() {
  group('family name', () {
    test('typographic family (16) before family (1)', () {
      expect(
        ThemeFonts.familyName(
          font([
            (3, 1, 0x409, 1, 'Inter SemiBold'),
            (3, 1, 0x409, 16, 'Inter'),
          ]),
        ),
        'Inter',
      );
      expect(ThemeFonts.familyName(font([(3, 1, 0x409, 1, 'Inter')])), 'Inter');
    });

    test('Windows English first, then any Windows / Unicode, then Mac', () {
      expect(
        ThemeFonts.familyName(
          font([(3, 1, 0x411, 1, 'インター'), (3, 1, 0x409, 1, 'Inter')]),
        ),
        'Inter',
      );
      expect(ThemeFonts.familyName(font([(3, 1, 0x411, 1, 'インター')])), 'インター');
      expect(
        ThemeFonts.familyName(font([(0, 3, 0, 1, 'Unicode Sans')])),
        'Unicode Sans',
      );
      expect(
        ThemeFonts.familyName(
          font([(1, 0, 0, 1, 'Mac Sans'), (3, 10, 0x409, 1, 'Win Sans')]),
        ),
        'Win Sans',
      );
      expect(
        ThemeFonts.familyName(font([(1, 0, 0, 1, 'Mac Sans')])),
        'Mac Sans',
      );
      expect(
        ThemeFonts.familyName(font([(3, 1, 0x409, 1, '  Spaced  ')])),
        'Spaced',
      );
    });

    test('no readable name: null', () {
      expect(
        ThemeFonts.familyName(font([(3, 1, 0x409, 2, 'Regular')])),
        isNull,
      );
      expect(ThemeFonts.familyName(font([(3, 1, 0x409, 1, '   ')])), isNull);
      expect(
        ThemeFonts.familyName(font([(2, 0, 0, 1, 'ISO')])),
        isNull,
      ); // unsupported platform
      expect(
        ThemeFonts.familyName(font([(3, 1, 0x409, 1, 'X')], table: false)),
        isNull,
      );
      final whole = font([(3, 1, 0x409, 1, 'Inter')]);
      expect(
        ThemeFonts.familyName(Uint8List.sublistView(whole, 0, 40)),
        isNull,
      ); // truncated
    });
  });

  group('load', () {
    final regular = sdkFont('Roboto-Regular.ttf').readAsBytesSync();
    final condensed = sdkFont('RobotoCondensed-Regular.ttf').readAsBytesSync();

    testWidgets('a restart loads only new files', (tester) async {
      final bundle = Bundle({'f/Roboto-Regular.ttf': regular});
      await tester.runAsync(() => ThemeFonts.load(bundle, bundle.files.keys));
      bundle.files['f/RobotoCondensed-Regular.ttf'] = condensed;
      bundle.loads.clear();
      final families = await tester.runAsync(
        () => ThemeFonts.load(bundle, bundle.files.keys),
      );
      expect(families, {
        'Roboto': ['f/Roboto-Regular.ttf'],
        'Roboto Condensed': ['f/RobotoCondensed-Regular.ttf'],
      });
      expect(bundle.loads, ['f/RobotoCondensed-Regular.ttf']);
    });

    testWidgets('unreadable files are skipped with a warning', (tester) async {
      final warnings = captureWarnings();
      final bundle = Bundle({
        'f/broken.ttf': Uint8List.fromList(List.filled(64, 7)),
      });
      final families = await tester.runAsync(
        () => ThemeFonts.load(bundle, ['f/broken.ttf', 'f/missing.otf']),
      );
      expect(families, isEmpty);
      expect(warnings, [
        contains('f/broken.ttf has no readable family name'),
        contains('f/missing.otf could not be read'),
      ]);
    });

    testWidgets('exclude: * within a directory, ** across', (tester) async {
      final bundle = Bundle({
        'a/x.ttf': regular,
        'a/b/y.ttf': regular,
        'c/d/e/z.ttf': regular,
      });
      Future<List<String>> loaded(List<String> exclude) async => [
        ...?(await tester.runAsync(
          () => ThemeFonts.load(bundle, bundle.files.keys, exclude: exclude),
        ))?['Roboto'],
      ];
      expect(await loaded(['a/*']), ['a/b/y.ttf', 'c/d/e/z.ttf']);
      expect(await loaded(['a/**']), ['c/d/e/z.ttf']);
      expect(await loaded(['**/z.ttf']), ['a/x.ttf', 'a/b/y.ttf']);
    });
  });

  group('loadFor', () {
    Future<ConfigurableApplicationContext> context(String properties) =>
        SpringApplication([
          BeanModule(
            'm',
            const [],
            resources: {'application.yml': EmbeddedResource.text(properties)},
          ),
        ], bannerMode: BannerMode.off).runAsync(const []);

    testWidgets('auto-load false: nothing is read', (tester) async {
      final app = (await tester.runAsync(
        () => context('spring.flutter.fonts.auto-load: false'),
      ))!;
      addTearDown(app.close);
      final bundle = Bundle({'x/Roboto-Regular.ttf': Uint8List(0)});
      await tester.runAsync(
        () => ThemeFonts.loadFor(app, bundle, bundle.files.keys),
      );
      expect(bundle.loads, isEmpty);
    });

    testWidgets('exclude from the properties; missing families warned once', (
      tester,
    ) async {
      final warnings = captureWarnings();
      final app = (await tester.runAsync(
        () => context('''
spring.flutter.fonts.exclude: [pdf/**]
'''),
      ))!;
      addTearDown(app.close);
      final regular = sdkFont('Roboto-Regular.ttf').readAsBytesSync();
      final bundle = Bundle({
        'fonts/Roboto-Regular.ttf': regular,
        'pdf/Roboto-Regular.ttf': regular,
        'FontManifest.json': Uint8List.fromList(
          utf8.encode('[{"family":"Declared"}]'),
        ),
      });
      await tester.runAsync(
        () => ThemeFonts.loadFor(
          app,
          bundle,
          ['fonts/Roboto-Regular.ttf', 'pdf/Roboto-Regular.ttf'],
          themeFamilies: {
            'Roboto',
            'Declared',
            'Inter',
            '.SF UI Text',
            'monospace',
          },
        ),
      );
      expect(bundle.loads, ['fonts/Roboto-Regular.ttf', 'FontManifest.json']);
      expect(warnings, [
        allOf(
          contains(': Inter (found: Roboto)'),
          isNot(contains('Declared')),
          isNot(contains('.SF')),
        ),
      ]);
    });

    testWidgets('no warning when every family is there', (tester) async {
      final warnings = captureWarnings();
      final app = (await tester.runAsync(() => context('a: 1')))!;
      addTearDown(app.close);
      await tester.runAsync(
        () => ThemeFonts.loadFor(
          app,
          Bundle(const {}),
          const [],
          themeFamilies: {'monospace'},
        ),
      );
      expect(warnings, isEmpty);
    });
  });
}
