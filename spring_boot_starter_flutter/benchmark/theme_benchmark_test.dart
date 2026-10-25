// Timings of the theme machinery (debug / JIT, so slower than a release
// build): start with many themes, the first and later ThemeData lookups,
// switching, a theme from a server, the font name table. Not part of the
// tests (outside test/); run with
//   flutter test benchmark

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

Map<String, String> properties(int themes) => {
  'seed-color': 'deepPurple',
  'typography.font-family': 'Inter',
  'typography.display.font-family': 'Playfair Display',
  'shape.medium': '16',
  'components.card.shape': 'large',
  'components.button.shape': 'full',
  'components.app-bar.center-title': 'true',
  'components.input.style': 'outline',
  for (var i = 0; i < themes - 2; i++) ...{
    'themes.t$i.seed-color':
        '#${(0x100000 + i * 7919).toRadixString(16).padLeft(6, '0')}',
    'themes.t$i.shape.large': '${20 + i % 10}',
    if (i.isOdd) 'themes.t$i.brightness': 'dark',
    if (i % 3 == 0 && i > 0) 'themes.t$i.extends': 't${i ~/ 2}',
  },
};

double ms(Stopwatch w) => w.elapsedMicroseconds / 1000;

void main() {
  for (final count in [6, 30, 100]) {
    test('$count themes', () {
      final props = properties(count);
      final start = Stopwatch()..start();
      final themes = SpringThemes(props);
      start.stop();

      final first = Stopwatch()..start();
      for (final name in themes.names) {
        themes.material(name);
      }
      first.stop();

      final again = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        themes.material(themes.names[i % themes.names.length]);
      }
      again.stop();

      final selection = ThemeSelection(themes);
      final switching = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        selection.select(themes.names[i % themes.names.length]);
      }
      switching.stop();

      final load = Stopwatch()..start();
      themes.loadYaml('themes:\n  remote:\n    seed-color: teal\n');
      load.stop();

      stdout.writeln(
        '$count themes: start (read + check all) ${ms(start).toStringAsFixed(1)} ms, '
        'every ThemeData after it ${ms(first).toStringAsFixed(1)} ms, '
        '1000 cached lookups ${ms(again).toStringAsFixed(2)} ms, '
        '1000 switches ${ms(switching).toStringAsFixed(2)} ms, '
        'loadYaml ${ms(load).toStringAsFixed(1)} ms',
      );
    });
  }

  test('font name table', () {
    var directory = File(Platform.resolvedExecutable).parent;
    while (!Directory('${directory.path}/material_fonts').existsSync() ||
        !directory.path.endsWith('artifacts')) {
      directory = directory.parent;
    }
    final bytes = File('${directory.path}/material_fonts/Roboto-Regular.ttf')
        .readAsBytesSync();
    final watch = Stopwatch()..start();
    for (var i = 0; i < 1000; i++) {
      ThemeFonts.familyName(bytes);
    }
    watch.stop();
    stdout.writeln(
      'font family from the name table: ${(watch.elapsedMicroseconds / 1000).toStringAsFixed(1)} µs per file '
      '(${bytes.length ~/ 1024} KB)',
    );
  });

  testWidgets('switching in the app: one frame', (tester) async {
    final themes = SpringThemes(properties(30));
    final selection = ThemeSelection(themes);
    final context = await SpringApplication([
      BeanModule(
        'm',
        [
          BeanDefinition<SpringThemes>(
            name: 'springThemes',
            types: const [SpringThemes],
            create: (_) => themes,
          ),
          BeanDefinition<ThemeSelection>(
            name: 'themeSelection',
            types: const [ThemeSelection],
            create: (_) => selection,
          ),
        ],
        resources: {
          'application.properties': const EmbeddedResource.text(
            'spring.flutter.app.type=material',
          ),
        },
      ),
    ], bannerMode: BannerMode.off).runAsync(const []);
    addTearDown(context.close);
    await tester.pumpWidget(
      SpringScope(
        applicationContext: context,
        child: SpringApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('t')),
            body: ListView(
              children: [
                for (var i = 0; i < 50; i++)
                  Card(child: ListTile(title: Text('$i'))),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final watch = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      selection.select(themes.names[i % themes.names.length]);
      await tester.pumpAndSettle();
    }
    watch.stop();
    stdout.writeln(
      'switch + rebuild + theme animation settled: ${(ms(watch) / 20).toStringAsFixed(1)} ms per switch (test clock frames included)',
    );
  });
}
