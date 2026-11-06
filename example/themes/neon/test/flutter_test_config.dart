// Runs before every test file of this folder: a comparator that tolerates
// tiny anti-aliasing differences between macOS versions (goldens are made
// on macOS and CI compares them on a macOS runner; Linux draws the letters
// too differently for any tolerance). The fonts are neon_ui's own, loaded
// from the package, so screenshots show the real letters.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/neon_ui_files.dart';

/// Share of differing pixels a golden may have and still match. The
/// goldens are made on one Mac and compared on GitHub's macOS runner: the
/// letters are smoothed a little differently there, about half a percent on
/// a page that is mostly text; a moved widget or a changed color differs by
/// more.
const goldenTolerance = 0.01;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await _loadNeonFonts();
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(
      comparator.basedir.resolve('golden_test.dart'),
    );
  }
  await testMain();
}

/// neon_ui's fonts under the names the theme uses (`packages/neon_ui/...`):
/// the test engine does not register fonts of a package by itself.
Future<void> _loadNeonFonts() async {
  const fonts = {
    'packages/neon_ui/JetBrains Mono': [
      'JetBrainsMono-Regular.ttf',
      'JetBrainsMono-Medium.ttf',
      'JetBrainsMono-SemiBold.ttf',
      'JetBrainsMono-Bold.ttf',
    ],
    'packages/neon_ui/Space Grotesk': [
      'SpaceGrotesk-Regular.ttf',
      'SpaceGrotesk-Medium.ttf',
      'SpaceGrotesk-SemiBold.ttf',
      'SpaceGrotesk-Bold.ttf',
    ],
  };
  for (final MapEntry(:key, :value) in fonts.entries) {
    final loader = FontLoader(key);
    for (final file in value) {
      final bytes = neonUiFile('assets/fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
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
