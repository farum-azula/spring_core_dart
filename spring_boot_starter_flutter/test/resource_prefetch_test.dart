// spring.resources.prefetch at run time: the file's files are in memory as
// resources once it is read; with stage: app it starts after the app is
// shown and its delay; off the web, nothing is read.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

final class _Bundle extends AssetBundle {
  int reads = 0;

  static final _text = [
    jsonEncode({'format': 1, 'files': 2}),
    jsonEncode({'prefetch_test/a.md': '# A'}),
    jsonEncode({'prefetch_test/b.md': '# B'}),
  ].join('\n');

  @override
  Future<ByteData> load(String key) async {
    reads++;
    return ByteData.sublistView(utf8.encode(_text));
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async => parser(await loadString(key));
}

void main() {
  tearDown(() => Resources.registerAll(const {}, owner: 'unused'));

  test('the files are resources once the file is read', () async {
    final prefetch = ResourcePrefetch(
      locations: const ['content/**'],
      bundle: _Bundle(),
      web: true,
    );
    await prefetch.load();
    expect(
      Resources.resolveEmbedded('prefetch_test/a.md').readAsStringSync(),
      '# A',
    );
    expect(
      Resources.resolveEmbedded('prefetch_test/b.md').readAsStringSync(),
      '# B',
    );
  });

  testWidgets('stage app: after the app is shown and the delay', (
    tester,
  ) async {
    final bundle = _Bundle();
    final prefetch = ResourcePrefetch(
      locations: const ['content/**'],
      delay: const Duration(seconds: 1),
      bundle: bundle,
      web: true,
    );
    expect(
      prefetch.supportsEvent(
        SplashStageEvent(Object(), stage: SplashStage.ready, at: Duration.zero),
      ),
      isFalse,
    );
    final shown = SplashStageEvent(
      Object(),
      stage: SplashStage.app,
      at: Duration.zero,
    );
    expect(prefetch.supportsEvent(shown), isTrue);
    prefetch.onApplicationEvent(shown);
    await tester.pump(const Duration(milliseconds: 900));
    expect(bundle.reads, 0);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() => prefetch.loaded!);
    expect(bundle.reads, 1);
  });

  test('off the web, or without locations, nothing is read', () async {
    for (final prefetch in [
      ResourcePrefetch(locations: const ['x'], bundle: _Bundle(), web: false),
      ResourcePrefetch(bundle: _Bundle(), web: true),
    ]) {
      await prefetch.load();
      expect((prefetch.bundle as _Bundle).reads, 0);
    }
  });
}
