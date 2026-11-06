// Typed keys of loaders and the splash: props classes of the app's own loader
// kinds, the checks across themes, and the typed accessors.
// ignore_for_file: lines_longer_than_80_chars
@Timeout(Duration(minutes: 2))
library;

import 'package:spring_core_dart_generator/src/spring_key_files.dart';
import 'package:spring_core_dart_generator/src/typed_theme_keys.dart';
import 'package:test/test.dart';

const _kinds = LoaderKinds(
  own: {'doors': (name: 'doors', className: 'DoorsLoader')},
  foreign: {'rings': 'rings'},
);

({String? code, KeysDiagnostics diagnostics}) _theme(
  String yaml, {
  LoaderKinds kinds = _kinds,
}) {
  final diagnostics = KeysDiagnostics();
  final parts = SpringKeyFiles.generate(
    {'application.yml': yaml},
    diagnostics,
    loaderKinds: kinds,
  );
  return (code: parts.theme, diagnostics: diagnostics);
}

String _flat(String? code) => (code ?? '').replaceAll(RegExp(r'\s+'), ' ');

const _doors = r'''
spring.flutter.theme:
  tokens:
    neon: { cyan: '#00E5FF', pink: '#FF2E97' }
  loaders:
    dots: { kind: dots, color: red }
    neon-doors:
      kind: doors
      phases:
        close: { duration: 500ms, curve: ease-in }
        fill: { progress: true }
      tracks:
        spin: { duration: 2s, repeat: loop }
      door: { color: '#0B0D14', edge: { color: $neon.cyan, width: 2, glow: 12 } }
      seam:
        width: 6
        fill: $neon.pink
        stops: [0.1, 0.9]
        tints: [red, blue]
        label: hello
        pulse: true
        curve: ease-out
        delay: 120ms
        flicker: { duration: 120ms, repeat: reverse }
      web: web/loaders/neon-doors.html
      web-sha256: 0000000000000000000000000000000000000000000000000000000000000000
  splash:
    title: NEON
    loader: neon-doors
''';

void main() {
  group('loaders', () {
    test('the typed key of every loader, and the splash', () {
      final (:code, :diagnostics) = _theme(_doors);
      expect(diagnostics.errors, isEmpty);
      final flat = _flat(code);
      expect(flat, contains('AppThemeLoaders get loaders'));
      expect(
        flat,
        contains(
          "ThemeLoaderSpec get neonDoors => _values.loader('neon-doors');",
        ),
      );
      expect(
        flat,
        contains("ThemeLoaderSpec get dots => _values.loader('dots');"),
      );
      expect(flat, contains('ThemeSplashData get splash => _values.splash();'));
    });

    test("a kind of the app's own gets its props class", () {
      final flat = _flat(_theme(_doors).code);
      for (final fragment in [
        'final class DoorsLoaderProps {',
        'const DoorsLoaderProps._(this.values);',
        'final LoaderValues values;',
        "static const List<String>? keys = ['door', 'seam'];",
        "DoorsLoaderPropsDoor get door => DoorsLoaderPropsDoor._(values.at('door'));",
        "Color get color => _v.color('color');",
        "DoorsLoaderPropsDoorEdge get edge => DoorsLoaderPropsDoorEdge._(_v.at('edge'));",
        "double get glow => _v.number('glow');",
        "Color get fill => _v.color('fill');",
        "bool get pulse => _v.boolean('pulse');",
        "Curve get curve => _v.curve('curve');",
        "Duration get delay => _v.duration('delay');",
        "String get label => _v.text('label');",
        "AnimationSpec get flicker => _v.animation('flicker');",
        'List<double> get stops =>',
        r"_v.number('stops.$i')",
        'List<Color> get tints =>',
        r"_v.color('tints.$i')",
      ]) {
        expect(flat, contains(fragment), reason: fragment);
      }
      expect(flat, isNot(contains("at('phases')")));
      expect(flat, isNot(contains("at('web')")));
      // The keys every loader has are the starter's, not the kind's.
      expect(flat, isNot(contains("at('tracks')")));
      expect(flat, isNot(contains('websha256')));
    });

    test('built-in and foreign kinds get no props class', () {
      final flat = _flat(
        _theme('''
spring.flutter.theme:
  loaders:
    a: { kind: spinner }
    b: { kind: rings, ring: { width: 3 } }
''', kinds: const LoaderKinds(foreign: {'rings': 'rings'})).code,
      );
      expect(flat, contains('ThemeLoaderSpec get a'));
      expect(flat, contains('ThemeLoaderSpec get b'));
      expect(flat, isNot(contains('LoaderProps')));
    });

    test('a kind without a loader in any theme takes any key', () {
      final flat = _flat(
        _theme('spring.flutter.theme: { seed-color: red }').code,
      );
      expect(flat, contains('static const List<String>? keys = null;'));
      expect(flat, contains('final class DoorsLoaderProps'));
    });

    test('a library with kinds and no theme has only the props classes', () {
      final diagnostics = KeysDiagnostics();
      final parts = SpringKeyFiles.generate(
        {'application.yml': 'a: b'},
        diagnostics,
        loaderKinds: _kinds,
      );
      expect(diagnostics.errors, isEmpty);
      expect(parts.theme, contains('final class DoorsLoaderProps'));
      expect(parts.theme, isNot(contains('extension SpringThemeKeys')));
      expect(parts.theme, isNot(contains('AppTheme ')));
    });

    test('an unknown kind stops the build, with a hint', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  loaders:
    a: { kind: dotz }
    b: { kind: door }
''');
      expect(code, isNull);
      expect(
        diagnostics.errors.join('\n'),
        allOf(
          contains('unknown loader kind "dotz"'),
          contains('did you mean "dots"?'),
          contains('unknown loader kind "door"'),
          contains('did you mean "doors"?'),
          contains("@ThemeLoaderKind('dotz')"),
        ),
      );
    });

    test('a loader without a kind stops the build', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  loaders:
    a: { color: red }
''');
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('loaders.a has no kind'));
    });

    test('keys that differ between themes stop the build, with a hint', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  loaders:
    neon-doors: { kind: doors, seam: { width: 6 }, door: { color: red } }
  themes:
    dark:
      loaders:
        neon-doors: { seem: { width: 6 } }
''');
      expect(code, isNull);
      final errors = diagnostics.errors.join('\n');
      expect(errors, contains('(theme dark) has seem.width'));
      expect(errors, contains('(theme light) lacks'));
      expect(errors, contains('did you mean "seam.width"?'));
    });

    test('a key of two types in two themes stops the build', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  loaders:
    neon-doors: { kind: doors, seam: { width: 6 } }
  themes:
    dark:
      loaders:
        neon-doors: { seam: { width: wide } }
''');
      expect(code, isNull);
      expect(
        diagnostics.errors.join('\n'),
        contains('seam.width has values of different types'),
      );
    });

    test('two loaders of one kind give the same keys', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  loaders:
    a: { kind: doors, seam: { width: 6 } }
    b: { kind: doors, seam: { width: 6, fill: red } }
''');
      expect(code, isNull);
      expect(
        diagnostics.errors.join('\n'),
        contains('loaders.b (theme light) has seam.fill'),
      );
    });

    test('splash.loader must name a loader', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  loaders:
    neon-doors: { kind: spinner }
  splash: { loader: neon-door }
''');
      expect(code, isNull);
      expect(
        diagnostics.errors.single,
        allOf(
          contains('splash.loader "neon-door" is no loader'),
          contains('did you mean "neon-doors"?'),
        ),
      );
    });

    test('a splash without a loader is fine; the ink splash is not one', () {
      final plain = _flat(
        _theme('spring.flutter.theme: { splash: { title: Hi } }').code,
      );
      expect(plain, contains('ThemeSplashData get splash'));
      final ink = _flat(
        _theme('spring.flutter.theme: { splash: ripple }').code,
      );
      expect(ink, isNot(contains('ThemeSplashData')));
    });
  });
}
