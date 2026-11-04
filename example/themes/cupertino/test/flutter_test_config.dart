// Runs before every test file of this folder: real fonts, so layouts are as
// wide as on a device and screenshots show letters instead of boxes (Roboto
// stands in for San Francisco, which the test engine does not have), the
// Cupertino icons, and a comparator that tolerates tiny anti-aliasing
// differences between macOS versions (goldens are made on macOS and CI
// compares them on a macOS runner; Linux draws the letters too differently
// for any tolerance).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Share of differing pixels a golden may have and still match. The
/// goldens are made on one Mac and compared on GitHub's macOS runner: the
/// letters are smoothed a little differently there, about half a percent on
/// a page that is mostly text; a moved widget or a changed color differs by
/// more.
const goldenTolerance = 0.01;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await _loadFonts();
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(
      comparator.basedir.resolve('golden_test.dart'),
    );
  }
  await testMain();
}

Future<void> _loadFonts() async {
  final fonts = _materialFontsDirectory();
  Future<void> load(String family, List<File> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  final roboto = [
    for (final name in [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
    ])
      File('${fonts.path}/$name'),
  ];
  // The two families a CupertinoApp's text uses, and the `code` style's.
  await load('CupertinoSystemText', roboto);
  await load('CupertinoSystemDisplay', roboto);
  await load('monospace', [roboto.first]);
  await load('packages/cupertino_icons/CupertinoIcons', [_cupertinoIcons()]);
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

/// The font file of the cupertino_icons package, found through the
/// package configuration of the app.
File _cupertinoIcons() {
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final package = (config['packages']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .firstWhere((p) => p['name'] == 'cupertino_icons');
  final text = package['rootUri']! as String;
  final root = Uri.parse(text.endsWith('/') ? text : '$text/');
  final base = Directory.current.uri.resolve('.dart_tool/').resolveUri(root);
  return File.fromUri(base.resolve('assets/CupertinoIcons.ttf'));
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
