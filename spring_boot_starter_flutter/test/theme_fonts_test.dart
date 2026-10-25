// Font files among the app's assets, wherever they are: the family from
// the font's own name table, loaded with FontLoader, minus excluded ones.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// `bin/cache/artifacts/material_fonts` of the SDK running the tests.
File sdkFont(String name) {
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final file = File('${directory.path}/material_fonts/$name');
    if (directory.path.endsWith('artifacts') && file.existsSync()) {
      return file;
    }
    directory = directory.parent;
  }
  throw StateError('No material_fonts; run `flutter precache`.');
}

class Bundle extends CachingAssetBundle {
  Bundle(this.files);
  final Map<String, Uint8List> files;

  @override
  Future<ByteData> load(String key) async => switch (files[key]) {
    final bytes? => ByteData.sublistView(bytes),
    null => throw FlutterError('Unable to load asset: "$key".'),
  };
}

void main() {
  final regular = sdkFont('Roboto-Regular.ttf').readAsBytesSync();
  final bold = sdkFont('Roboto-Bold.ttf').readAsBytesSync();

  test('the family comes from the name table', () {
    expect(ThemeFonts.familyName(regular), 'Roboto');
    expect(ThemeFonts.familyName(bold), 'Roboto');
    expect(
      ThemeFonts.familyName(
        Uint8List.fromList('ttcf'.codeUnits + List.filled(20, 0)),
      ),
      isNull,
    );
    expect(ThemeFonts.familyName(Uint8List(3)), isNull);
  });

  testWidgets('fonts in any asset directory, by family, minus excluded', (
    tester,
  ) async {
    final bundle = Bundle({
      'res/typography/Roboto-Regular.ttf': regular,
      'assets/brand/Roboto-Bold.TTF': bold,
      'assets/pdf/Roboto-Regular.ttf': regular,
      'packages/icons/Roboto-Regular.ttf': regular,
      'assets/images/logo.png': Uint8List(4),
    });
    final families = await tester.runAsync(
      () => ThemeFonts.load(
        bundle,
        bundle.files.keys,
        exclude: ['assets/pdf/**'],
      ),
    );
    expect(families, {
      'Roboto': [
        'res/typography/Roboto-Regular.ttf',
        'assets/brand/Roboto-Bold.TTF',
      ],
    });
  });

  test('families of flutter: fonts:', () async {
    final bundle = Bundle({
      'FontManifest.json': Uint8List.fromList(
        '[{"family":"Inter","fonts":[{"asset":"fonts/Inter.ttf"}]}]'.codeUnits,
      ),
    });
    expect(await ThemeFonts.declaredFamilies(bundle), {'Inter'});
    expect(await ThemeFonts.declaredFamilies(Bundle(const {})), isEmpty);
  });
}
