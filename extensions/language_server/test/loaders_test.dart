// Loaders and the splash of a theme in the editor: kinds (built in and of the
// app's own, from the metadata), the keys each takes, `splash.loader` and
// `splash.animation` as references, and the `web:` file.
import 'dart:io';

import 'package:dart_spring_language_server/src/config_editor.dart';
import 'package:test/test.dart';

import 'support/editor_fixture.dart';

const _theme = '''
spring:
  flutter:
    theme:
      loaders:
        dots:
          kind: dots
          count: 3
        neon-doors:
          kind: doors
          door: { color: red }
          web: web/loaders/mine.html
      animations:
        splash-in: { duration: 300ms }
      splash:
        title: NEON
        loader: neon-doors
        animation: splash-in
''';

void main() {
  late EditorFixture fixture;

  setUp(() => fixture = EditorFixture.create());
  tearDown(() => fixture.dispose());

  List<String> problemsOf(String text, {Map<String, String> files = const {}}) {
    for (final MapEntry(:key, :value) in files.entries) {
      File(fixture.app(key))
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    return messages(
      fixture.workspace.problems(
        fixture.open('lib/resources/application.yml', text),
      ),
    );
  }

  List<String> labels(String text, String marker) {
    final path = fixture.open('lib/resources/application.yml', text);
    final result = fixture.workspace.completion(path, at(text, marker));
    return [
      for (final item in result?.items ?? const <Completion>[]) item.label,
    ];
  }

  group('diagnostics', () {
    test('a valid theme has none', () {
      expect(
        problemsOf(
          _theme,
          files: {'web/loaders/mine.html': '<div></div>'},
        ),
        isEmpty,
      );
    });

    test('the scalar splash stays the ink splash', () {
      expect(
        problemsOf(
          'spring:\n  flutter:\n    theme:\n      splash: ripple\n',
        ),
        isEmpty,
      );
      expect(
        problemsOf(
          'spring:\n  flutter:\n    theme:\n      splash: ripples\n',
        ),
        [contains("'ripples' is not allowed here")],
      );
    });

    test('an unknown kind names the kinds, with a hint', () {
      final problems = problemsOf('''
spring:
  flutter:
    theme:
      loaders:
        a: { kind: dotz }
        b: { kind: door }
''');
      expect(problems, hasLength(2));
      expect(problems[0], contains("Did you mean 'dots'?"));
      expect(problems[1], contains("Did you mean 'doors'?"));
      expect(problems[1], contains('doors'));
    });

    test('a key a built-in kind does not take', () {
      final problems = problemsOf('''
spring:
  flutter:
    theme:
      loaders:
        a:
          kind: dots
          colour: red
          height: 3
''');
      expect(problems, hasLength(2));
      expect(problems[0], contains("'colour' is not a key of a 'dots' loader"));
      expect(problems[0], contains("Did you mean 'color'?"));
      expect(problems[1], contains("'height'"));
    });

    test("keys of a kind of the app's own come from its metadata", () {
      final problems = problemsOf(
        '''
spring:
  flutter:
    theme:
      loaders:
        a:
          kind: doors
          door: { color: red }
          seem: { width: 1 }
          web: web/loaders/neon-doors.html
''',
        files: {'web/loaders/neon-doors.html': ''},
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains("'seem' is not a key of a 'doors'"));
      expect(problems.single, contains("Did you mean 'seam'?"));
    });

    test('a loader the splash names must exist', () {
      final problems = problemsOf('''
spring:
  flutter:
    theme:
      loaders:
        neon-doors: { kind: spinner }
      animations:
        splash-in: { duration: 1s }
      splash:
        loader: neon-door
        animation: splash-on
''');
      expect(problems, hasLength(2));
      expect(problems[0], contains("Did you mean 'neon-doors'?"));
      expect(problems[1], contains("Did you mean 'splash-in'?"));
    });

    test('the web file must exist below the app, or in a dependency', () {
      final problems = problemsOf('''
spring:
  flutter:
    theme:
      loaders:
        a: { kind: doors, web: web/loaders/missing.html }
        b: { kind: doors, web: '../secret.html' }
        c: { kind: doors, web: web/loaders/neon-doors.html }
''');
      expect(problems, hasLength(2));
      expect(
        problems[0],
        contains("'web/loaders/missing.html' does not exist"),
      );
      expect(problems[1], contains('no .. and not absolute'));
    });
  });

  group('completion', () {
    test('kind offers the built-in kinds and those of the metadata', () {
      const text = '''
spring:
  flutter:
    theme:
      loaders:
        a:
          kind: 
''';
      expect(
        labels(text, 'kind: |'),
        containsAll(['spinner', 'dots', 'pulse', 'bar', 'skeleton', 'doors']),
      );
    });

    test('keys of a loader follow its kind', () {
      const text = '''
spring:
  flutter:
    theme:
      loaders:
        a:
          kind: dots
          
''';
      expect(
        labels(text, '          |\n'),
        unorderedEquals(
          [
            'kind',
            'phases',
            'tracks',
            'web',
            'web-sha256',
            'color',
            'size',
            'count',
            'gap',
            'animation',
          ],
        ),
      );
      const custom = '''
spring:
  flutter:
    theme:
      loaders:
        a:
          kind: doors
          
''';
      expect(
        labels(custom, '          |\n'),
        unorderedEquals([
          'kind',
          'phases',
          'tracks',
          'web',
          'web-sha256',
          'door',
          'seam',
        ]),
      );
    });

    test('splash.loader and splash.animation offer declared names', () {
      const text = '''
spring:
  flutter:
    theme:
      loaders:
        neon-doors: { kind: spinner }
        dots: { kind: dots }
      animations:
        splash-in: { duration: 1s }
      splash:
        loader: 
        animation: 
''';
      expect(
        labels(text, 'loader: |'),
        unorderedEquals(['dots', 'neon-doors']),
      );
      expect(labels(text, 'animation: |'), ['splash-in']);
    });

    test('web offers the html files of the app and of dependencies', () {
      File(fixture.app('web/loaders/mine.html'))
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      const text = '''
spring:
  flutter:
    theme:
      loaders:
        a:
          kind: doors
          web: 
''';
      expect(
        labels(text, 'web: |'),
        unorderedEquals([
          'web/loaders/mine.html',
          'web/loaders/neon-doors.html',
        ]),
      );
    });
  });

  group('go to definition', () {
    test('splash.loader goes to loaders.<name>, animation to animations', () {
      final path = fixture.open('lib/resources/application.yml', _theme);
      final loader = fixture.workspace.definition(
        path,
        at(_theme, 'loader: neon-d|oors'),
      );
      expect(loader, isNotEmpty);
      expect(loader.first.startLine, 8);
      final animation = fixture.workspace.definition(
        path,
        at(_theme, 'animation: spl|ash-in'),
      );
      expect(animation.first.startLine, 12);
    });

    test('web goes to the file', () {
      final text = _theme.replaceFirst('mine.html', 'neon-doors.html');
      final path = fixture.open('lib/resources/application.yml', text);
      final targets = fixture.workspace.definition(
        path,
        at(text, 'web: web/loa|ders'),
      );
      expect(targets.single.path, endsWith('web/loaders/neon-doors.html'));
    });
  });

  test('a reference may name a loader value', () {
    final problems = problemsOf(r'''
spring:
  flutter:
    theme:
      tokens: { neon: { cyan: '#00E5FF' } }
      loaders:
        a: { kind: bar, color: $neon.cyan, track: { color: $neon.cyan, alpha: 20% } }
        b: { kind: bar, color: $loaders.a.color }
''');
    expect(problems, isEmpty);
  });
}
