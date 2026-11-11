// Typed keys of the theme (references, nested tokens, styles, motion) and
// the files the keys builder writes next to the main builder's output.
// ignore_for_file: lines_longer_than_80_chars, no_adjacent_strings_in_list
// ignore_for_file: missing_whitespace_between_adjacent_strings
@Timeout(Duration(minutes: 2))
library;

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/flutter_keys_builder.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/spring_key_files.dart';
import 'package:spring_core_dart_generator/src/typed_theme_keys.dart';
import 'package:test/test.dart';

({String? code, KeysDiagnostics diagnostics}) _theme(String yaml) {
  final diagnostics = KeysDiagnostics();
  final parts = SpringKeyFiles.generate({'application.yml': yaml}, diagnostics);
  return (code: parts.theme, diagnostics: diagnostics);
}

// The code without whitespace, as the formatter may wrap lines.
String _flat(String? code) => (code ?? '').replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('nested tokens', () {
    const yaml = r'''
spring.flutter.theme:
  colors: { primary: '#112233' }
  tokens:
    neon:
      yellow: $colors.primary
      cyan: '#00FFFF'
      modal:
        width: 460
        barrier: transparent
        delay: 250ms
        title: Hello
        border:
          width: 1
          glow-alpha: 0.6
          colors: [$neon.yellow, $neon.cyan, white]
          widths: [1, 2]
          names: [a, b]
      background:
        source: https://cdn.example.com/bg.jpg
        refresh: 1d
''';

    test('groups of any depth, lists, durations and images', () {
      final (:code, :diagnostics) = _theme(yaml);
      expect(diagnostics.errors, isEmpty);
      final flat = _flat(code);
      for (final fragment in [
        'AppThemeTokensNeon get neon',
        'AppThemeTokensNeonModal get modal',
        'AppThemeTokensNeonModalBorder get border',
        "Color get yellow => _values.tokenColor('neon.yellow');",
        "double get width => _values.tokenNumber('neon.modal.width');",
        "Color get barrier => _values.tokenColor('neon.modal.barrier');",
        "Duration get delay => _values.tokenDuration('neon.modal.delay');",
        "String get title => _values.token('neon.modal.title');",
        "List<Color> get colors => _values.tokenColors('neon.modal.border.colors');",
        "List<double> get widths => _values.tokenNumbers('neon.modal.border.widths');",
        "List<String> get names => _values.tokenTexts('neon.modal.border.names');",
        "double get glowAlpha => _values.tokenNumber('neon.modal.border.glow-alpha');",
        "ThemeImage get background => _values.tokenImage('neon.background');",
      ]) {
        expect(flat, contains(fragment));
      }
      // The image map is a leaf: its keys are no tokens.
      expect(flat, isNot(contains('get refresh')));
      expect(flat, isNot(contains('get source')));
    });

    test('a token that is a group in one theme and a value in another', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  tokens: { a: { b: { c: 1 } } }
  themes:
    x: { tokens: { a: { b: 5 } } }
''');
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('tokens.a.b'));
    });

    test('a list of mixed types is an error', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  tokens: { a: { list: ['#112233', 3] } }
''');
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('one type'));
    });
  });

  group('references', () {
    test('type follows the referenced value and color objects', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  spacing: { m: 16 }
  shape: { medium: 12 }
  motion: { durations: { fast: 120ms } }
  tokens:
    neon: { yellow: '#FFEE00' }
    ref:
      from-role: $colors.primary
      from-spacing: $spacing.m
      from-shape: $shape.extra-small
      from-motion: $motion.durations.fast
      short: $neon.yellow
      long: $tokens.neon.yellow
      alpha: { color: $neon.yellow, alpha: 12% }
      alpha-unit: { color: $colors.primary, alpha: 0.5 }
      mix: { color: $neon.yellow, mix: { with: white, amount: 14% } }
      chained: { color: $tokens.ref.mix, alpha: 50% }
      old-form: $neon.yellow alpha 12%
      named: white
      escaped: $$colors.primary
      spring: ${cdn.token}
      price: $5
      plain: hello world
''');
      expect(diagnostics.errors, isEmpty);
      final flat = _flat(code);
      for (final (type, name) in [
        ('Color', 'fromRole'),
        ('double', 'fromSpacing'),
        ('double', 'fromShape'),
        ('Duration', 'fromMotion'),
        ('Color', 'short'),
        ('Color', 'long'),
        ('Color', 'alpha'),
        ('Color', 'alphaUnit'),
        ('Color', 'mix'),
        ('Color', 'chained'),
        ('String', 'oldForm'),
        ('Color', 'named'),
        ('String', 'escaped'),
        ('String', 'spring'),
        ('String', 'price'),
        ('String', 'plain'),
      ]) {
        expect(flat, contains('$type get $name =>'), reason: name);
      }
    });

    test('an extending theme changes what a reference resolves to', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  spacing: { m: 16 }
  tokens: { a: { gap: $spacing.m } }
  themes:
    base-x:
      colors: { gap: '#ff0000' }
    child:
      extends: base-x
      spacing: { m: 32 }
''');
      expect(diagnostics.errors, isEmpty);
      expect(_flat(code), contains('double get gap'));
    });

    test('a reference whose type differs between themes is an error', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  colors: { primary: '#112233' }
  spacing: { m: 16 }
  tokens: { a: { v: $spacing.m } }
  themes:
    x: { tokens: { a: { v: $colors.primary } } }
''');
      expect(code, isNull);
      expect(
        diagnostics.errors.single,
        allOf(
          contains('tokens.a.v has values of different types'),
          contains('number in'),
          contains('Color in'),
        ),
      );
    });

    test('an unknown reference names the chain and suggests a path', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  colors: { brand-accent: '#112233' }
  tokens:
    a: { x: $colors.brand-acent }
''');
      expect(code, isNull);
      expect(
        diagnostics.errors.single,
        allOf(
          contains('spring.flutter.theme.tokens.a.x'),
          contains(r'unknown reference $colors.brand-acent'),
          contains(r'Did you mean $colors.brand-accent?'),
        ),
      );
    });

    test(r'a $path inside longer text is a reference, as at run time', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  colors: { brand-accent: '#112233' }
  tokens:
    a: { ok: 'Accent is $colors.brand-accent today', bad: 'Is $colors.nope here' }
''');
      expect(code, isNull);
      expect(
        diagnostics.errors.single,
        contains(r'unknown reference $colors.nope'),
      );
    });

    test('an unknown reference in any section is reported once', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  seed-color: $colors.nothing-here
  themes:
    a: { colors: { x: '#fff' } }
    b: { colors: { y: '#fff' } }
''');
      expect(code, isNull);
      expect(diagnostics.errors, hasLength(1));
    });

    test('a cycle names the chain', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  tokens:
    a: { x: $a.y, y: $a.z, z: $a.x }
''');
      expect(code, isNull);
      expect(
        diagnostics.errors.single,
        allOf(
          contains('cycle'),
          contains('tokens.a.x'),
          contains('tokens.a.y'),
        ),
      );
    });

    test('a color object needs a color, valid keys and percents', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  spacing: { m: 16 }
  tokens:
    a: { x: { color: $spacing.m, alpha: 12% }, y: { color: white, alpha: 150% } }
''');
      expect(code, isNull);
      expect(diagnostics.errors, hasLength(2));
      expect(diagnostics.errors.first, contains('a color is expected'));
      expect(diagnostics.errors.last, contains('a percent'));
    });

    test('a reference to a group is an error', () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  tokens: { a: { g: { x: 1 }, y: $a.g } }
''');
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('group'));
    });

    test('an unknown parent theme is an error', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  themes:
    neon: { colors: { a: '#fff' } }
    x: { extends: neonn }
''');
      expect(code, isNull);
      expect(diagnostics.errors.single, contains("did you mean 'neon'"));
    });
  });

  group('styles', () {
    const yaml = r'''
spring.flutter.theme:
  colors: { outline: '#888888' }
  styles:
    neon-chip:
      padding: [12, 6]
      gap: 4
      radius: $shape.small
      border: { default: $colors.outline, hovered: $colors.primary, selected: white }
      fill: { default: transparent, selected: { color: $colors.primary, alpha: 12% } }
      label: { default: Hello }
      fade: 150ms
      transition: 120ms ease-out
    plain: { }
  themes:
    x:
      styles:
        neon-chip:
          padding: [1, 2, 3, 4]
''';

    test('a class per style with typed values', () {
      final (:code, :diagnostics) = _theme(yaml);
      expect(diagnostics.errors, isEmpty);
      expect(diagnostics.warnings, isEmpty);
      final flat = _flat(code);
      for (final fragment in [
        'AppThemeStyles get styles => AppThemeStyles._(_values);',
        'AppStyleNeonChip get neonChip => '
            "AppStyleNeonChip._(_values.style('neon-chip'));",
        'final class AppStyleNeonChip implements ThemeStyle<AppStyleNeonChipValues>',
        '@override final StateStyle style;',
        'AppStyleNeonChipValues view(StyleValues values) => '
            'AppStyleNeonChipValues._(values);',
        "EdgeInsets get padding => _values.insets('padding');",
        "double get gap => _values.number('gap');",
        "double get radius => _values.number('radius');",
        "Color get border => _values.color('border');",
        "Color get fill => _values.color('fill');",
        "String get label => _values.text('label');",
        "Duration get fade => _values.duration('fade');",
        'final class AppStylePlain implements ThemeStyle<AppStylePlainValues>',
      ]) {
        expect(flat, contains(fragment));
      }
      // transition belongs to the style, not to its values
      expect(flat, isNot(contains('get transition')));
    });

    test('a list in the base, states in an extending theme', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  styles: { chip: { padding: [8, 4] } }
  themes:
    x: { styles: { chip: { padding: { default: [2, 4], pressed: [1, 2] } } } }
''');
      expect(diagnostics.errors, isEmpty);
      expect(
        _flat(code),
        contains("EdgeInsets get padding => _values.insets('padding');"),
      );
    });

    test('a property of two types is an error', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  styles:
    chip: { fill: { default: '#fff', hovered: 3 } }
''');
      expect(code, isNull);
      expect(
        diagnostics.errors.single,
        allOf(
          contains('styles.chip.fill has values of different types'),
          contains('Color in'),
          contains('number in'),
        ),
      );
    });

    test('a property of two types in two themes is an error', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  styles: { chip: { size: 3 } }
  themes:
    x: { styles: { chip: { size: big } } }
''');
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('styles.chip.size'));
    });

    test('three numbers are no insets, an unknown state is an error', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  styles: { chip: { padding: [1, 2, 3], fill: { hoverd: '#fff' } } }
''');
      expect(code, isNull);
      expect(diagnostics.errors, hasLength(2));
      expect(diagnostics.errors.first, contains('insets'));
      expect(diagnostics.errors.last, contains('did you mean "hovered"'));
    });
  });

  group('motion, animations and background', () {
    const yaml = '''
spring.flutter.theme:
  motion:
    durations: { fast: 120ms, medium: 250ms, slow: 500ms }
    curves: { emphasized: [0.2, 0, 0, 1], out: ease-out, standard: ease }
    page-transition: fade-upwards
  animations:
    border-spin: { duration: 4s, curve: linear, repeat: loop }
    glow-pulse: { duration: 1.6s, repeat: reverse }
  background:
    color: white
    image: { source: https://cdn.example.com/b.jpg }
''';

    test('durations, curves, animations and the background', () {
      final (:code, :diagnostics) = _theme(yaml);
      expect(diagnostics.errors, isEmpty);
      final flat = _flat(code);
      for (final fragment in [
        "Duration get fast => _values.motionDuration('fast');",
        "Duration get medium => _values.motionDuration('medium');",
        "Duration get slow => _values.motionDuration('slow');",
        'AppThemeMotionCurves get curves => AppThemeMotionCurves._(_values);',
        "Curve get emphasized => _values.motionCurve('emphasized');",
        "Curve get out => _values.motionCurve('out');",
        "Curve get standard => _values.motionCurve('standard');",
        'AppThemeAnimations get animations',
        "AnimationSpec get borderSpin => _values.animation('border-spin');",
        "AnimationSpec get glowPulse => _values.animation('glow-pulse');",
        'ThemeBackgroundData? get background => _values.theme.background;',
      ]) {
        expect(flat, contains(fragment));
      }
      expect(flat, isNot(contains('get pageTransition')));
    });

    test('nothing for what the theme does not declare', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  spacing: { m: 16 }
  motion: { page-transition: fade-upwards }
''');
      expect(diagnostics.errors, isEmpty);
      final flat = _flat(code);
      expect(flat, isNot(contains('AppThemeMotion')));
      expect(flat, isNot(contains('background')));
      expect(flat, isNot(contains('AppThemeStyles')));
      expect(flat, isNot(contains('AppThemeAnimations')));
      // `spacing` reads the field of AppTheme.
      expect(flat, isNot(contains('unused_field')));
    });

    test('a theme with nothing to name leaves no analyzer warning', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  seed-color: '#3ECF8E'
''');
      expect(diagnostics.errors, isEmpty);
      // No getter reads the reader AppTheme keeps: `unused_field` is a
      // warning, not a lint, so `ignore_for_file: type=lint` leaves it.
      expect(
        _flat(code),
        contains(
          'const AppTheme._(this._values); // ignore: unused_field '
          'final ThemeKeyReader _values; }',
        ),
      );
    });

    test('a duration named curves clashes with the curves', () {
      final (:code, :diagnostics) = _theme('''
spring.flutter.theme:
  motion: { durations: { curves: 1s }, curves: { out: ease } }
''');
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('curves'));
    });
  });

  group('files', () {
    const pubspec =
        'name: app\ndependencies:\n  spring_boot_starter_flutter: any\n';
    const resources = {
      'app|lib/resources/application.properties':
          'spring.flutter.theme.spacing.m=16\n',
      'app|lib/resources/messages.properties': 'a=A\n',
    };
    const scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:app/spring_gen/main.spring.dart';

@ComponentScan()
final BeanModule appBeans = $appBeans;
''';

    Future<List<String>> run(
      Map<String, Object> files, {
      Map<String, Matcher> outputs = const {},
      String pubspecText = pubspec,
    }) async {
      final logs = <String>[];
      await testBuilder(
        FlutterKeysBuilder(),
        {...files, 'app|pubspec.yaml': pubspecText},
        rootPackage: 'app',
        outputs: outputs,
        onLog: (r) => logs.add('${r.level.name}: ${r.message}'),
      );
      return logs;
    }

    test('parts of the .spring.dart of the app, and a deprecated library', () {
      return run(
        {...resources, 'app|lib/main.dart': scan},
        outputs: {
          'app|lib/spring_gen/theme.spring.dart': decodedMatches(
            allOf(
              startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND'),
              contains("part of 'main.spring.dart';"),
              contains('extension SpringThemeKeys on BuildContext'),
              contains('AppTheme get theme'),
              isNot(contains('import ')),
            ),
          ),
          'app|lib/spring_gen/messages.spring.dart': decodedMatches(
            allOf(
              startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND'),
              contains("part of 'main.spring.dart';"),
              contains('extension SpringMessageKeys on BuildContext'),
              contains('AppMessages get messages'),
            ),
          ),
        },
      );
    });

    test('a library keeps its keys in spring_auto_configuration', () {
      return run(
        {
          'app|lib/resources/messages.properties': 'a=A\n',
          'app|lib/spring_auto_configuration.dart': scan,
        },
        outputs: {
          'app|lib/spring_gen/messages.spring.dart': decodedMatches(
            contains("part of 'spring_auto_configuration.spring.dart';"),
          ),
        },
      );
    });

    test('a theme a dependency ships and the app imports is read', () {
      const library = r'''
spring.flutter.theme:
  themes:
    neon:
      colors: { primary: '#F2E35B' }
      tokens: { neon: { cyan: '#4FD8E8', accent: $colors.primary } }
''';
      return run(
        {
          'app|lib/resources/application.yml': r'''
spring.config.import: optional:resources:themes/neon.yml, resources:other.yml
spring.flutter.theme.themes.ice:
  extends: neon
  colors: { primary: $neon.cyan }
''',
          'neon|lib/resources/themes/neon.yml': library,
          'other|lib/resources/other.yml':
              'spring.flutter.theme.spacing.m: 8\n',
          'app|lib/main.dart': scan,
        },
        pubspecText:
            'name: app\ndependencies:\n  spring_boot_starter_flutter: any\n'
            '  neon: any\n  other: any\n',
        outputs: {
          'app|lib/spring_gen/theme.spring.dart': decodedMatches(
            allOf(
              contains('AppThemeTokensNeon'),
              contains("tokenColor('neon.accent')"),
              contains("_values.spacing('m')"),
              contains("static const String ice = 'ice';"),
              contains("static const String neon = 'neon';"),
            ),
          ),
        },
      );
    });

    test("an import nobody has is the application's to report", () async {
      final logs = await run(
        {
          'app|lib/resources/application.yml':
              'spring.config.import: resources:themes/none.yml\n'
              'spring.flutter.theme.spacing.m: 8\n',
          'app|lib/main.dart': scan,
        },
        outputs: {
          'app|lib/spring_gen/theme.spring.dart': decodedMatches(
            contains('spacing'),
          ),
        },
      );
      expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
    });

    test('the parent may be in a subfolder', () {
      return run(
        {...resources, 'app|lib/src/app/root.dart': scan},
        outputs: {
          'app|lib/spring_gen/theme.spring.dart': decodedMatches(
            contains("part of 'src/app/root.spring.dart';"),
          ),
          'app|lib/spring_gen/messages.spring.dart': decodedMatches(
            contains("part of 'src/app/root.spring.dart';"),
          ),
        },
      );
    });

    test('only the part that has something to write', () {
      return run(
        {
          'app|lib/resources/messages.properties': 'a=A\n',
          'app|lib/main.dart': scan,
        },
        outputs: {
          'app|lib/spring_gen/messages.spring.dart': decodedMatches(
            contains('AppMessages'),
          ),
        },
      );
    });

    test('two @ComponentScan libraries stop the build and name both', () async {
      final logs = await run({
        ...resources,
        'app|lib/main.dart': scan,
        'app|lib/other.dart': scan,
      });
      final severe = logs.where((l) => l.startsWith('SEVERE')).single;
      expect(severe, contains('lib/main.dart'));
      expect(severe, contains('lib/other.dart'));
    });

    test('no @ComponentScan: no key files and a log line', () async {
      final logs = await run({
        ...resources,
        'app|lib/main.dart': 'void main() {}',
      });
      expect(
        logs.where((l) => l.startsWith('WARNING')).single,
        contains('@ComponentScan'),
      );
    });

    test('an app with @SpringBootApplication has its parts too', () {
      return run(
        {
          ...resources,
          'app|lib/main.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@SpringBootApplication()
void main(List<String> args) {}
''',
        },
        outputs: {
          'app|lib/spring_gen/theme.spring.dart': decodedMatches(
            contains("part of 'main.spring.dart';"),
          ),
          'app|lib/spring_gen/messages.spring.dart': decodedMatches(
            contains('part of'),
          ),
        },
      );
    });

    test('an @SpringBootApplication with a nested @ComponentScan', () {
      return run(
        {
          ...resources,
          'app|lib/main.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@SpringBootApplication()
void main(List<String> args) {}
''',
          'app|lib/src/feature/feature.dart': scan,
        },
        outputs: {
          'app|lib/spring_gen/theme.spring.dart': decodedMatches(
            contains("part of 'main.spring.dart';"),
          ),
          'app|lib/spring_gen/messages.spring.dart': decodedMatches(
            contains('part of'),
          ),
        },
      );
    });

    test('the outermost of nested @ComponentScan libraries is the parent', () {
      return run(
        {
          ...resources,
          'app|lib/src/feature/feature.dart': scan,
          'app|lib/main.dart': scan,
        },
        outputs: {
          'app|lib/spring_gen/theme.spring.dart': decodedMatches(
            contains("part of 'main.spring.dart';"),
          ),
          'app|lib/spring_gen/messages.spring.dart': decodedMatches(
            contains('part of'),
          ),
        },
      );
    });

    test('scans in sibling directories are unrelated', () async {
      final logs = await run({
        ...resources,
        'app|lib/a/one.dart': scan,
        'app|lib/b/two.dart': scan,
      });
      final severe = logs.where((l) => l.startsWith('SEVERE')).single;
      expect(severe, contains('lib/a/one.dart'));
      expect(severe, contains('lib/b/two.dart'));
    });

    test('a comment is no @ComponentScan', () {
      return run(
        {
          ...resources,
          'app|lib/main.dart': scan,
          'app|lib/notes.dart': '// @ComponentScan() is on main.dart\n',
        },
        outputs: {
          'app|lib/spring_gen/theme.spring.dart': decodedMatches(
            contains('part of'),
          ),
          'app|lib/spring_gen/messages.spring.dart': decodedMatches(
            contains('part of'),
          ),
        },
      );
    });

    test('nothing for a package without the Flutter starter', () {
      return run(
        {...resources, 'app|lib/main.dart': scan},
        pubspecText: 'name: app\ndependencies:\n  spring_boot_dart: any\n',
      );
    });

    test('an error writes nothing', () async {
      final logs = await run({
        'app|lib/resources/application.yml': r'''
spring.flutter.theme.tokens.a.x: $nope.y
''',
        'app|lib/main.dart': scan,
      });
      expect(logs.where((l) => l.startsWith('SEVERE')), hasLength(1));
    });

    test('also for a package that brings the starter', () {
      return run(
        {...resources, 'app|lib/main.dart': scan},
        pubspecText:
            'name: app\ndependencies:\n'
            '  spring_boot_starter_flutter_security: any\n',
        outputs: {
          'app|lib/spring_gen/theme.spring.dart': decodedMatches(
            contains('AppTheme'),
          ),
          'app|lib/spring_gen/messages.spring.dart': decodedMatches(
            contains('AppMessages'),
          ),
        },
      );
    });
  });

  group('main builder', () {
    Future<String> generate(
      Map<String, String> files, {
      String pubspec =
          'name: app\ndependencies:\n  spring_boot_starter_flutter: any\n',
      String output = 'lib/spring_gen/main.spring.dart',
    }) async {
      final readerWriter = TestReaderWriter(
        rootPackage: 'app',
        flattenOutput: true,
      );
      await readerWriter.testing.loadIsolateSources();
      final result = await testBuilder(
        SpringBuilder(),
        {
          'app|pubspec.yaml': pubspec,
          for (final MapEntry(:key, :value) in files.entries) 'app|$key': value,
        },
        rootPackage: 'app',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.errors, isEmpty);
      return result.readerWriter.testing.readString(
        AssetId('app', output),
      );
    }

    const main = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:app/spring_gen/main.spring.dart';

@ComponentScan()
final BeanModule appBeans = $appBeans;
''';

    test('declares the parts that exist and the imports they need', () async {
      final source = await generate({
        'lib/main.dart': main,
        'lib/resources/application.properties':
            'spring.flutter.theme.spacing.m=16\n',
        'lib/resources/messages.properties': 'a=A\n',
      });
      expect(source, contains("part 'messages.spring.dart';"));
      expect(source, contains("part 'theme.spring.dart';"));
      expect(source, contains("import 'package:flutter/widgets.dart';"));
      expect(
        source,
        contains(
          "import 'package:spring_boot_starter_flutter/"
          "spring_boot_starter_flutter.dart';",
        ),
      );
      expect(source, contains('ignore_for_file: unused_import'));
    });

    test('only the parts the keys builder writes', () async {
      final source = await generate({
        'lib/main.dart': main,
        'lib/resources/application.properties':
            'spring.flutter.theme.spacing.m=16\n',
      });
      expect(source, contains("part 'theme.spring.dart';"));
      expect(source, isNot(contains('messages.spring.dart')));
    });

    test('no part for a theme with an error', () async {
      final source = await generate({
        'lib/main.dart': main,
        'lib/resources/application.yml':
            r'spring.flutter.theme.tokens.a.x: $nope',
      });
      expect(source, isNot(contains('part ')));
    });

    test('a part path is relative to a parent in a subfolder', () async {
      final source = await generate({
        'lib/src/root.dart': main,
        'lib/resources/application.properties':
            'spring.flutter.theme.spacing.m=16\n',
      }, output: 'lib/spring_gen/src/root.spring.dart');
      expect(source, contains("part '../theme.spring.dart';"));
    });

    test('an @SpringBootApplication app declares its parts', () async {
      final source = await generate({
        'lib/main.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@SpringBootApplication()
void main(List<String> args) {}
''',
        'lib/resources/application.properties':
            'spring.flutter.theme.spacing.m=16\n',
      });
      expect(source, contains("part 'theme.spring.dart';"));
    });

    test('a nested @ComponentScan does not stop the parts', () async {
      final source = await generate({
        'lib/main.dart': main,
        'lib/src/other.dart': main,
        'lib/resources/application.properties':
            'spring.flutter.theme.spacing.m=16\n',
      });
      expect(source, contains("part 'theme.spring.dart';"));
    });

    test('the nested scan itself has no parts', () async {
      final source = await generate({
        'lib/main.dart': main,
        'lib/src/feature/other.dart': main,
        'lib/resources/application.properties':
            'spring.flutter.theme.spacing.m=16\n',
      }, output: 'lib/spring_gen/src/feature/other.spring.dart');
      expect(source, isNot(contains('part ')));
    });

    test('no parts with unrelated @ComponentScan roots', () async {
      final source = await generate({
        'lib/a/one.dart': main,
        'lib/b/two.dart': main,
        'lib/resources/application.properties':
            'spring.flutter.theme.spacing.m=16\n',
      }, output: 'lib/spring_gen/a/one.spring.dart');
      expect(source, isNot(contains('part ')));
    });

    test('@SpringBootApplication with a nested @ComponentScan', () async {
      const app = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@SpringBootApplication()
void main(List<String> args) {}
''';
      final source = await generate({
        'lib/main.dart': app,
        'lib/src/feature/other.dart': main,
        'lib/resources/application.properties':
            'spring.flutter.theme.spacing.m=16\n',
      });
      expect(source, contains("part 'theme.spring.dart';"));
    });

    test('no parts without the Flutter starter', () async {
      final source = await generate(
        {
          'lib/main.dart': main,
          'lib/resources/application.properties':
              'spring.flutter.theme.spacing.m=16\n',
        },
        pubspec: 'name: app\ndependencies:\n  spring_boot_dart: any\n',
      );
      expect(source, isNot(contains('part ')));
      expect(source, isNot(contains('unused_import')));
    });
  });

  test(
    r'the languages of code blocks are taken as written: no $ reference',
    () {
      final (:code, :diagnostics) = _theme(r'''
spring.flutter.theme:
  syntax:
    shell:
      aliases: [sh]
      keywords: [echo]
      rules:
        - { match: '\$[A-Za-z_]\w*|\$\{[^}]*\}', kind: variable }
        - { match: '[a-z]+', kind: word }
''');
      expect(diagnostics.errors, isEmpty);
      expect(_flat(code), isNot(contains('Syntax')));
    },
  );

  test(r'the glyphs of a text change are taken as written: no $ reference', () {
    final (:diagnostics, code: _) = _theme(r'''
spring.flutter.theme:
  motion:
    text-change: { type: morph, glyphs: '$ab#%', glyph-duration: 30ms }
''');
    expect(diagnostics.errors, isEmpty);
  });
}
