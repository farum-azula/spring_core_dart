// Runs before every test file of this folder: loads the package's own fonts
// under the names the theme uses (`packages/neon_ui/...`), since the test
// engine does not register the fonts of a package by itself. Without them
// the tests that draw the title would show boxes instead of letters.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
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
      final bytes = File('assets/fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  await testMain();
}
