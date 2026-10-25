// Runs before every test file of this folder: the Material icons for the
// golden screenshots, and a comparator that tolerates tiny anti-aliasing
// differences between macOS versions (goldens are made on macOS and CI
// compares them on a macOS runner; Linux draws the letters too differently
// for any tolerance).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Share of differing pixels a golden may have and still match.
const goldenTolerance = 0.005;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await _loadMaterialFonts();
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(
      comparator.basedir.resolve('golden_test.dart'),
    );
  }
  await testMain();
}

/// The Material icons from the Flutter SDK, so screenshots show icons
/// instead of boxes. The text fonts (Roboto, Roboto Condensed) are the
/// app's assets, loaded by the starter like on a device.
Future<void> _loadMaterialFonts() async {
  final fonts = _materialFontsDirectory();
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('${fonts.path}/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// `bin/cache/artifacts/material_fonts` of the SDK running the tests.
Directory _materialFontsDirectory() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (directory.parent.path != directory.path) {
    final fonts = Directory('${directory.path}/material_fonts');
    if (directory.path.endsWith('artifacts') && fonts.existsSync()) {
      return fonts;
    }
    directory = directory.parent;
  }
  throw StateError(
    'No material_fonts next to ${Platform.resolvedExecutable}; '
    'run `flutter precache`.',
  );
}

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= goldenTolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
