// CSS pieces are adjacent strings without spaces.
// ignore_for_file: missing_whitespace_between_adjacent_strings
// The page loader of the splash: the block in web/index.html (markers,
// rewrite, removal), its CSS from the theme, and the escaping of theme texts.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_key_files.dart';
import 'package:spring_core_dart_generator/src/theme_references.dart';
import 'package:spring_core_dart_generator/src/typed_theme_keys.dart';
import 'package:spring_core_dart_generator/src/web_page_loader.dart';
import 'package:spring_core_dart_generator/src/web_page_loader_builder.dart';
import 'package:test/test.dart';

const _page = '''
<!DOCTYPE html>
<html>
<head>
  <title>App</title>
</head>
<body class="x">
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

({String? block, KeysDiagnostics diagnostics}) _block(
  String yaml, {
  Map<String, String> files = const {},
}) {
  final diagnostics = KeysDiagnostics();
  final set = ThemeSet.read(
    SpringKeyFiles.readProperties({'application.yml': yaml}, diagnostics),
    diagnostics,
  )!;
  final block = WebPageLoader.generate(
    set,
    diagnostics,
    readFile: (path) => files[path],
  );
  return (block: block, diagnostics: diagnostics);
}

const _doors = r'''
spring.flutter.theme:
  seed-color: '#6750A4'
  tokens:
    neon: { cyan: '#00E5FF', pink: '#FF2E97' }
  loaders:
    neon-doors:
      kind: doors
      phases:
        close: { duration: 500ms, curve: ease-in }
        fill: { progress: true }
      door: { color: '#0B0D14', edge: { color: $neon.cyan, width: 2, glow: 12 } }
      seam:
        width: 6
        fill: $neon.pink
        glow: { color: { color: $neon.pink, alpha: 60% }, blur: 24 }
      web: web/loaders/neon-doors.html
  splash:
    background: { color: '#0B0D14' }
    logo: { source: assets/images/logo.png, size: 96 }
    title: NEON
    loader: neon-doors
''';

const _doorsHtml = '<div class="doors"><i></i></div>';

void main() {
  group('the markers in the page', () {
    test('a new block goes right after <body>, the rest is untouched', () {
      final result = WebPageLoader.apply(_page, 'BLOCK')!;
      expect(
        result,
        _page.replaceFirst('<body class="x">', '<body class="x">\nBLOCK'),
      );
    });

    test('an old block is replaced between its markers', () {
      final once = WebPageLoader.apply(
        _page,
        '${WebPageLoader.startMarker}\nOLD\n${WebPageLoader.endMarker}',
      )!;
      final twice = WebPageLoader.apply(
        once,
        '${WebPageLoader.startMarker}\nNEW\n${WebPageLoader.endMarker}',
      )!;
      expect(twice, contains('NEW'));
      expect(twice, isNot(contains('OLD')));
      expect(
        twice.replaceAll(
          RegExp(
            '<!-- spring:loader:start -->.*?'
            '<!-- spring:loader:end -->',
            dotAll: true,
          ),
          '',
        ),
        _page.replaceFirst('<body class="x">', '<body class="x">\n'),
      );
    });

    test('the same block again changes nothing', () {
      const block =
          '${WebPageLoader.startMarker}\nX\n${WebPageLoader.endMarker}';
      final once = WebPageLoader.apply(_page, block)!;
      expect(WebPageLoader.apply(once, block), once);
    });

    test('no block removes the markers and what is between them', () {
      final once = WebPageLoader.apply(
        _page,
        '${WebPageLoader.startMarker}\nX\n${WebPageLoader.endMarker}',
      )!;
      expect(WebPageLoader.apply(once, null), _page);
    });

    test('no block and no markers leave the page alone', () {
      expect(WebPageLoader.apply(_page, null), _page);
    });

    test('a page without <body> gets the block before </html>', () {
      final result = WebPageLoader.apply('<html></html>', 'B')!;
      expect(result, '<html>B\n</html>');
    });

    test('markers that are not a pair leave the page and say so', () {
      final problems = <String>[];
      const broken = '$_page${WebPageLoader.startMarker}';
      expect(
        WebPageLoader.apply(broken, 'B', problem: problems.add),
        isNull,
      );
      expect(problems.single, contains('not one pair'));
      const reversed = '${WebPageLoader.endMarker}${WebPageLoader.startMarker}';
      expect(WebPageLoader.apply(reversed, 'B', problem: problems.add), isNull);
    });
  });

  group('the block of a theme', () {
    test('no splash, no block', () {
      final diagnostics = KeysDiagnostics();
      final set = ThemeSet.read(
        SpringKeyFiles.readProperties({
          'a.yml': 'spring.flutter.theme: { seed-color: red, splash: ripple }',
        }, diagnostics),
        diagnostics,
      )!;
      expect(
        WebPageLoader.generate(set, diagnostics, readFile: (_) => null),
        isNull,
      );
      expect(WebPageLoader.hasSplash(set), isFalse);
    });

    test("a kind of the app's own: its web file and the CSS variables", () {
      final (:block, :diagnostics) = _block(
        _doors,
        files: {'web/loaders/neon-doors.html': _doorsHtml},
      );
      expect(diagnostics.warnings, isEmpty);
      final text = block!;
      expect(text, startsWith(WebPageLoader.startMarker));
      expect(text, endsWith(WebPageLoader.endMarker));
      expect(text, contains(_doorsHtml));
      for (final fragment in [
        'background:#0b0d14',
        '--door-color:#0b0d14',
        '--door-edge-color:#00e5ff',
        '--door-edge-width:2',
        '--door-edge-glow:12',
        '--seam-width:6',
        '--seam-fill:#ff2e97',
        '--seam-glow-color:rgba(255, 46, 151, 0.6)',
        '--seam-glow-blur:24',
        '--phases-close-duration:500ms',
        '--phases-close-curve:ease-in',
        '--phases-fill-progress:1',
        '--spring-logo-size:96px',
        'src="assets/assets/images/logo.png"',
        '<div class="sl-title">NEON</div>',
        'data-kind="doors"',
      ]) {
        expect(text, contains(fragment), reason: fragment);
      }
      expect(text, isNot(contains('--web')));
      expect(text, isNot(contains('--kind')));
      expect(text, contains('prefers-reduced-motion'));
    });

    test("the script follows Flutter's loader and hands over", () {
      final text = _block(
        _doors,
        files: {'web/loaders/neon-doors.html': ''},
      ).block!;
      expect(text, contains('_flutter'));
      expect(text, contains('onEntrypointLoaded'));
      expect(text, contains('window.springLoaderHandOff = remove'));
      expect(text, contains('flutter-first-frame'));
      // The page loader's clock, for the splash to go on from.
      expect(text, contains('get elapsed()'));
      expect(text, contains('setTimeout(remove, 60000)'));
      expect(text, contains(WebPageLoader.script));
      expect(WebPageLoader.scriptHash, startsWith("'sha256-"));
    });

    test('a fill with a min-duration: when it starts and its minimum', () {
      final text = _block(
        _doors.replaceFirst(
          'fill: { progress: true }',
          'fill: { progress: true, min-duration: 2.5s }',
        ),
        files: {'web/loaders/neon-doors.html': ''},
      ).block!;
      // After close (500 ms), 2.5 s at least; the script reads them.
      expect(text, contains('data-fill-at="500" data-fill-min="2500"'));
      expect(text, contains('--phases-fill-min-duration:2500ms'));
      expect(WebPageLoader.script, contains("getAttribute('data-fill-min')"));
      expect(
        WebPageLoader.script,
        contains('get progress() { return shown; }'),
      );
      // Without one, or after a looping phase, no attributes.
      final plain = _block(
        _doors,
        files: {'web/loaders/neon-doors.html': ''},
      ).block!;
      expect(plain, isNot(contains('data-fill-at="')));
      final looping = _block(
        _doors
            .replaceFirst(
              'close: { duration: 500ms, curve: ease-in }',
              'close: { duration: 500ms, repeat: loop }',
            )
            .replaceFirst(
              'fill: { progress: true }',
              'fill: { progress: true, min-duration: 2.5s }',
            ),
        files: {'web/loaders/neon-doors.html': ''},
      ).block!;
      expect(looping, isNot(contains('data-fill-at="')));
    });

    test("built-in kinds have a CSS form, from the theme's keys", () {
      for (final (kind, keys, marker) in [
        ('spinner', 'size: 48', 'sl-spinner'),
        ('dots', 'count: 4, size: 12', 'sl-dots'),
        ('pulse', 'size: 30', 'sl-pulse'),
        ('bar', 'height: 4', 'sl-bar'),
        ('skeleton', 'radius: 8', 'sl-skeleton'),
      ]) {
        final (:block, :diagnostics) = _block('''
spring.flutter.theme:
  seed-color: '#336699'
  loaders:
    l: { kind: $kind, color: '#ff0000', $keys }
  splash: { loader: l }
''');
        expect(diagnostics.warnings, isEmpty, reason: kind);
        expect(block, contains(marker), reason: kind);
        expect(block, contains('--color:#ff0000'), reason: kind);
      }
      final dots = _block('''
spring.flutter.theme:
  loaders: { l: { kind: dots, count: 4 } }
  splash: { loader: l }
''').block!;
      expect('<span></span>'.allMatches(dots).length, 4);
    });

    test('colors come from the seed when the theme does not declare them', () {
      final text = _block('''
spring.flutter.theme:
  seed-color: '#6750A4'
  loaders: { l: { kind: spinner } }
  splash: { loader: l }
''').block!;
      // The background is the surface role, the loader the primary one.
      expect(text, contains('background:#'));
      expect(text, contains('var(--color,#'));
    });

    test('a custom kind without a web file shows a bar and warns', () {
      final (:block, :diagnostics) = _block('''
spring.flutter.theme:
  loaders: { l: { kind: doors } }
  splash: { loader: l }
''');
      expect(block, contains('sl-bar'));
      expect(diagnostics.warnings.single, contains('no `web:` file'));
    });

    test('a missing or unsafe web file is a warning', () {
      for (final path in ['web/x.html', '../x.html', '/etc/x', r'C:\x.html']) {
        final (:block, :diagnostics) = _block('''
spring.flutter.theme:
  loaders: { l: { kind: doors, web: '${path.replaceAll(r'\', r'\\')}' } }
  splash: { loader: l }
''');
        expect(block, isNotNull);
        expect(diagnostics.warnings, isNotEmpty, reason: path);
      }
    });

    test('a loader the splash does not find is a warning', () {
      final (:block, :diagnostics) = _block('''
spring.flutter.theme:
  splash: { title: Hi, loader: nope }
''');
      expect(block, contains('Hi'));
      expect(diagnostics.warnings.single, contains('"nope"'));
    });

    test(
      'a system theme gets a dark override when the dark splash differs',
      () {
        final text = _block('''
spring.flutter.theme:
  splash: { background: { color: '#ffffff' }, title: Hi }
  themes:
    dark:
      splash: { background: { color: '#000000' } }
''').block!;
        expect(text, contains('background:#ffffff'));
        expect(
          text,
          contains(
            '@media (prefers-color-scheme:dark)'
            '{#spring-loader{background:#000000',
          ),
        );
      },
    );

    test('a named active theme is the only one', () {
      final text = _block('''
spring.flutter.theme:
  active: ocean
  splash: { background: { color: '#ffffff' } }
  themes:
    ocean:
      splash: { background: { color: '#003366' } }
''').block!;
      expect(text, contains('background:#003366'));
      expect(text, isNot(contains('prefers-color-scheme')));
    });

    test('a gradient background', () {
      final text = _block('''
spring.flutter.theme:
  splash:
    background:
      gradient: { type: linear, begin: top, end: bottom, colors: ['#000000', '#ffffff'], stops: [0, 1] }
''').block!;
      expect(text, contains('linear-gradient(180deg,#000000 0%,#ffffff 100%)'));
    });

    test('references and color objects are resolved', () {
      final text = _block(r'''
spring.flutter.theme:
  colors: { primary: '#102030' }
  loaders:
    l:
      kind: bar
      color: $colors.primary
      track: { color: $colors.primary, alpha: 20% }
  splash: { loader: l }
''').block!;
      expect(text, contains('--color:#102030'));
      expect(text, contains('--track:rgba(16, 32, 48, 0.2)'));
    });
  });

  group('no injection from the theme', () {
    const evil = '</style><script>alert(1)</script>';

    test('the title is HTML text', () {
      final text = _block('''
spring.flutter.theme:
  splash: { title: '$evil &amp; "quoted"' }
''').block!;
      expect(text, isNot(contains('<script>alert(1)')));
      expect(text, contains('&lt;/style&gt;&lt;script&gt;alert(1)'));
      expect(text, contains('&amp;amp;'));
    });

    test('a list of colors gives its first as well, to close a circle', () {
      final text = _block(
        '''
spring.flutter.theme:
  loaders:
    l: { kind: doors, edge: { colors: ['#ff0000', '#00ff00', '#0000ff'] }, web: web/x.html }
  splash: { loader: l }
''',
        files: {'web/x.html': ''},
      ).block!;
      expect(text, contains('--edge-colors:#ff0000,#00ff00,#0000ff'));
      expect(text, contains('--edge-colors-first:#ff0000'));
    });

    test('a text key of a loader is a CSS string', () {
      final text = _block(
        '''
spring.flutter.theme:
  loaders:
    l: { kind: doors, label: '$evil', quote: 'a"b\\c', web: web/x.html }
  splash: { loader: l }
''',
        files: {'web/x.html': ''},
      ).block!;
      expect(text, isNot(contains('<script>alert(1)')));
      expect(text, isNot(contains('</style><script>')));
      expect(text, contains(r'--label:"\3C /style\3E \3C script\3E alert(1)'));
      expect(text, contains(r'--quote:"a\22 b\5C c"'));
    });

    test('a key name cannot leave the property', () {
      final text = _block(
        '''
spring.flutter.theme:
  loaders:
    l: { kind: doors, 'a;b}c': 1, web: web/x.html }
  splash: { loader: l }
''',
        files: {'web/x.html': ''},
      ).block!;
      expect(text, isNot(contains('a;b')));
      expect(text, contains('--a-b-c:1'));
    });

    test('the logo is an asset, http(s) or an image data URL', () {
      for (final source in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        '//evil.example/x.png',
        '../secret.png',
      ]) {
        final (:block, :diagnostics) = _block('''
spring.flutter.theme:
  splash: { logo: { source: '$source' }, title: T }
''');
        expect(block, isNot(contains('<img')), reason: source);
        expect(diagnostics.warnings.single, contains('no logo'));
      }
      final text = _block('''
spring.flutter.theme:
  splash: { logo: { source: 'https://cdn.example.com/a.png?x="1"&y=2' } }
''').block!;
      expect(
        text,
        contains(
          'src="https://cdn.example.com/a.png?x=&quot;1&quot;&amp;y=2"',
        ),
      );
    });

    test('the kind name is an attribute value', () {
      final text = _block(
        '''
spring.flutter.theme:
  loaders: { l: { kind: 'x" onload="alert(1)', web: web/x.html } }
  splash: { loader: l }
''',
        files: {'web/x.html': ''},
      ).block!;
      expect(text, isNot(contains('" onload="')));
    });
  });

  group('the builder', () {
    Future<(String?, List<String>)> run({
      required String? page,
      required String yaml,
      Map<String, String> web = const {},
      String pubspec =
          'name: app\ndependencies:\n  spring_boot_starter_flutter: any\n',
    }) async {
      final files = _Files({
        'web/index.html': ?page,
        ...web,
      });
      final logs = <String>[];
      await testBuilder(
        WebPageLoaderBuilder(files: files),
        {
          'app|pubspec.yaml': pubspec,
          'app|lib/app.dart': 'void main() {}',
          'app|lib/resources/application.yaml': yaml,
        },
        rootPackage: 'app',
        onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
      );
      return (files.files['web/index.html'], logs);
    }

    const yaml = '''
spring.flutter.theme:
  splash: { title: Hello }
''';

    test('writes the block, rewrites it, and removes it', () async {
      final (written, _) = await run(page: _page, yaml: yaml);
      expect(written, contains(WebPageLoader.startMarker));
      expect(written, contains('Hello'));
      expect(written, startsWith('<!DOCTYPE html>'));
      final (again, _) = await run(page: written, yaml: yaml);
      expect(again, written);
      final (removed, _) = await run(
        page: written,
        yaml: 'spring.flutter.theme: { seed-color: red }',
      );
      // The loader is gone; the theme's color stays the page's.
      expect(
        removed!.replaceFirst(
          RegExp(r'\s*<meta name="theme-color" content="#[0-9a-f]{6}">'),
          '',
        ),
        _page,
      );
    });

    test('the head and the manifest from spring.flutter.app.* and the '
        'theme', () async {
      const template = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="description" content="A new Flutter project.">
  <meta name="apple-mobile-web-app-title" content="app">
  <title>app</title>
</head>
<body></body>
</html>
''';
      final files = _Files({
        'web/index.html': template,
        'web/manifest.json':
            '{"name": "app", "short_name": "app", "start_url": ".", '
            '"description": "A new Flutter project.", '
            '"theme_color": "#0175C2", "background_color": "#0175C2"}',
      });
      await testBuilder(
        WebPageLoaderBuilder(files: files),
        {
          'app|pubspec.yaml':
              'name: app\ndependencies:\n  spring_boot_starter_flutter: any\n',
          'app|lib/app.dart': 'void main() {}',
          'app|lib/resources/application.yaml': '''
spring.flutter.app:
  title: Books & more
  description: A shop of "books".
spring.flutter.theme:
  colors: { primary: '#336699', surface: '#fafafa' }
''',
        },
        rootPackage: 'app',
      );
      final page = files.files['web/index.html']!;
      expect(page, contains('<title>Books &amp; more</title>'));
      expect(
        page,
        contains(
          '<meta name="description" content="A shop of &quot;books&quot;.">',
        ),
      );
      expect(
        page,
        contains(
          '<meta name="apple-mobile-web-app-title" content="Books &amp; more">',
        ),
      );
      expect(page, contains('<meta name="theme-color" content="#336699">'));
      final manifest =
          jsonDecode(files.files['web/manifest.json']!) as Map<String, Object?>;
      expect(manifest, {
        'name': 'Books & more',
        'short_name': 'Books & more',
        'start_url': '.',
        'description': 'A shop of "books".',
        'theme_color': '#336699',
        'background_color': '#fafafa',
      });
    });

    test('a package that does not use the starter is left alone', () async {
      final (written, _) = await run(
        page: _page,
        yaml: yaml,
        pubspec: 'name: app\n',
      );
      expect(written, _page);
    });

    test('no page, nothing is created', () async {
      final (written, _) = await run(page: null, yaml: yaml);
      expect(written, isNull);
    });

    test('the web file is read from the app directory', () async {
      final (written, logs) = await run(
        page: _page,
        yaml: '''
spring.flutter.theme:
  loaders: { l: { kind: doors, web: web/l.html } }
  splash: { loader: l }
''',
        web: {'web/l.html': '<p class="mine"></p>'},
      );
      expect(written, contains('<p class="mine"></p>'));
      expect(logs.where((l) => l.startsWith('WARNING')), isEmpty);
    });

    test('a broken pair of markers is a warning, the page is kept', () async {
      const broken = '$_page${WebPageLoader.endMarker}';
      final (written, logs) = await run(page: broken, yaml: yaml);
      expect(written, broken);
      expect(logs.join('\n'), contains('not one pair'));
    });
  });
}

// web/ files held in memory.
final class _Files implements WebPageFiles {
  _Files(this.files);

  final Map<String, String> files;

  @override
  Future<String?> read(
    BuildStep buildStep,
    String package,
    String path,
  ) async => files[path];

  @override
  Future<void> write(
    BuildStep buildStep,
    String package,
    String path,
    String content,
  ) async => files[path] = content;
}
