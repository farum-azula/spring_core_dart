// Typed keys of the configuration: context.theme and context.messages
// (lib/spring_keys.dart).

import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/dart_names.dart';
import 'package:spring_core_dart_generator/src/flutter_keys_builder.dart';
import 'package:spring_core_dart_generator/src/typed_message_keys.dart';
import 'package:spring_core_dart_generator/src/typed_theme_keys.dart';
import 'package:test/test.dart';

({String? code, KeysDiagnostics diagnostics}) _generate(
  Map<String, String> resources,
) {
  final diagnostics = KeysDiagnostics();
  final code = FlutterKeysBuilder.generate(resources, diagnostics);
  return (code: code, diagnostics: diagnostics);
}

const _oceanToken =
    'spring.flutter.theme.themes.ocean.tokens.brand.hero-height';

void main() {
  group('Dart names', () {
    test('kebab and snake case become camel case', () {
      expect(DartNames.member('surface-container-low'), 'surfaceContainerLow');
      expect(DartNames.member('neon_night'), 'neonNight');
      expect(DartNames.member('loginToOrder'), 'loginToOrder');
      expect(DartNames.member('NotBlank'), 'notBlank');
    });

    test('a leading digit and a keyword are escaped', () {
      expect(DartNames.member('2xl'), r'$2xl');
      expect(DartNames.member('default'), r'default$');
      expect(DartNames.member('hashCode'), r'hashCode$');
    });

    test('a name with other characters has no Dart name', () {
      expect(DartNames.member('a b'), isNull);
      expect(DartNames.member('größe'), isNull);
      expect(DartNames.member('--'), isNull);
    });
  });

  group('theme', () {
    const yaml = '''
spring:
  flutter:
    theme:
      seed-color: deepPurple
      colors:
        error: '#B3261E'
        surface-container-low: grey.shade100
      spacing: { s: 8, m: 16, 2xl: 48 }
      typography:
        font-family: Roboto
        code: { font-family: JetBrains Mono, size: 13 }
        title-large: { weight: 600 }
        display: { weight: bold }
      tokens:
        brand: { accent: '#FF6B00', hero-height: 240, name: Neon }
      themes:
        ocean:
          colors:
            highlight: '#00BFA5'
          tokens:
            brand: { accent: '#00BFA5' }
        neon-night:
          spacing: { xl: 32 }
''';

    test('writes the classes of every declared key', () {
      final (:code, :diagnostics) = _generate({'application.yml': yaml});
      expect(diagnostics.errors, isEmpty);
      expect(diagnostics.warnings, isEmpty);
      expect(code, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND'));
      expect(
        code,
        contains(
          'AppTheme get theme => '
          'AppTheme._(ThemeKeyReader(SpringTheme.of(this)));',
        ),
      );
      expect(code, isNot(contains('AppMessages')));
      // colors, from the base and from a theme
      expect(
        code,
        contains(
          'Color get surfaceContainerLow => '
          "_values.color('surface-container-low');",
        ),
      );
      expect(code, contains("Color get error => _values.color('error');"));
      expect(
        code,
        contains("Color get highlight => _values.color('highlight');"),
      );
      // spacing, an escaped name
      expect(code, contains("double get m => _values.spacing('m');"));
      expect(code, contains(r"double get $2xl => _values.spacing('2xl');"));
      expect(code, contains("double get xl => _values.spacing('xl');"));
      // text styles: the declared ones only, not font-family or the group
      expect(
        code,
        contains("TextStyle get code => _values.textStyle('code');"),
      );
      expect(
        code,
        contains(
          "TextStyle get titleLarge => _values.textStyle('title-large');",
        ),
      );
      expect(code, isNot(contains('fontFamily')));
      expect(code, isNot(contains('get display')));
      // tokens by type, in nested classes
      expect(code, contains('AppThemeTokensBrand get brand'));
      expect(
        code,
        contains("Color get accent => _values.tokenColor('brand.accent');"),
      );
      expect(
        code,
        contains(
          "double get heroHeight => _values.tokenNumber('brand.hero-height');",
        ),
      );
      expect(code, contains("String get name => _values.token('brand.name');"));
      // theme names
      expect(code, contains("static const String ocean = 'ocean';"));
      expect(code, contains("static const String neonNight = 'neon-night';"));
      expect(code, contains("static const String light = 'light';"));
      expect(code, contains("static const String system = 'system';"));
    });

    test('profile files, imported files and properties files all count', () {
      final (:code, :diagnostics) = _generate({
        'application.properties': 'spring.flutter.theme.spacing.s=8\n',
        'application-android.properties':
            'spring.flutter.theme.colors.primary=#112233\n',
        'themes/sepia.yml':
            'spring.flutter.theme.themes.sepia:\n  spacing: { tall: 99 }\n',
        'application-prod.yaml': '''
spring:
  config:
    activate:
      on-profile: prod
  flutter:
    theme:
      tokens:
        brand: { accent: '#000000' }
''',
      });
      expect(diagnostics.errors, isEmpty);
      for (final fragment in [
        'double get s =>',
        'Color get primary =>',
        'double get tall =>',
        'Color get accent =>',
        "static const String sepia = 'sepia';",
      ]) {
        expect(code, contains(fragment));
      }
    });

    test('a key spelled two ways is one key', () {
      final (:code, :diagnostics) = _generate({
        'application.yml': 'spring.flutter.theme.spacing.big-gap: 8\n',
        'themes.properties': 'spring.flutter.theme.themes.x.spacing.bigGap=9\n',
      });
      expect(diagnostics.errors, isEmpty);
      expect(RegExp('double get bigGap').allMatches(code!), hasLength(1));
    });

    test('no theme property: nothing is written', () {
      final (:code, :diagnostics) = _generate({
        'application.yml': 'spring.flutter.app.title: Shop\n',
      });
      expect(code, isNull);
      expect(diagnostics.errors, isEmpty);
    });

    test('a token of different types in two themes is an error', () {
      final (:code, :diagnostics) = _generate({
        'application.yml': '''
spring.flutter.theme:
  tokens: { brand: { hero-height: 240 } }
  themes:
    ocean:
      tokens: { brand: { hero-height: tall } }
''',
      });
      expect(code, isNull);
      expect(
        diagnostics.errors.single,
        allOf(
          contains('tokens.brand.hero-height'),
          contains('number in spring.flutter.theme.tokens.brand.hero-height'),
          contains(
            'string in $_oceanToken',
          ),
        ),
      );
    });

    test('a token more than two levels deep is an error', () {
      final (:code, :diagnostics) = _generate({
        'application.yml': 'spring.flutter.theme.tokens.brand.deep.value: 1\n',
      });
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('tokens.brand.deep.value'));
    });

    test('names that are no Dart name or collide are errors', () {
      final (:code, :diagnostics) = _generate({
        'application.yml': '''
spring.flutter.theme:
  spacing:
    "a b": 1
    big-gap: 2
    big_gap: 3
    bigGap: 4
''',
      });
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('spacing.a b'));
    });
  });

  group('message arguments', () {
    test('counts the highest index', () {
      expect(TypedMessageKeys.argumentCount('Empty'), 0);
      expect(TypedMessageKeys.argumentCount('Total: {0}'), 1);
      expect(TypedMessageKeys.argumentCount('{1} of {0}'), 2);
      expect(TypedMessageKeys.argumentCount('at most {1} characters'), 2);
      expect(
        TypedMessageKeys.argumentCount('{1,date,short} by {0,number}'),
        2,
      );
    });

    test('quoted braces are text', () {
      expect(TypedMessageKeys.argumentCount("It''s '{0}' here"), 0);
      expect(TypedMessageKeys.argumentCount("don't {0}"), 0);
    });

    test('a choice counts the arguments of its choices', () {
      expect(
        TypedMessageKeys.argumentCount(
          '{0,choice,0#none|1#one|1<{0} items for {2}}',
        ),
        3,
      );
    });

    test('a pattern MessageFormat rejects throws', () {
      expect(() => TypedMessageKeys.argumentCount('{0'), throwsFormatException);
      expect(
        () => TypedMessageKeys.argumentCount('{x}'),
        throwsFormatException,
      );
      expect(
        () => TypedMessageKeys.argumentCount('{0,bogus}'),
        throwsFormatException,
      );
    });
  });

  group('messages', () {
    test('getters, methods and nested groups', () {
      final (:code, :diagnostics) = _generate({
        'messages.properties': '''
basket.total=Total: {0}
basket.empty=Your basket is empty
order.shipped=Order {0} shipped on {1,date,short}
admin.field.isbn=ISBN
theme.neon-night=Neon at night
title=Shop
''',
        'messages_ja.properties': '''
basket.total=合計：{0}
basket.empty=カートは空です
order.shipped=注文 {0} は {1,date,short} に発送されました
admin.field.isbn=ISBN
theme.neon-night=夜のネオン
title=店
''',
      });
      expect(diagnostics.errors, isEmpty);
      expect(diagnostics.warnings, isEmpty);
      expect(
        code,
        contains('AppMessages get messages => AppMessages._(this);'),
      );
      expect(code, isNot(contains('AppTheme')));
      expect(code, contains('AppMessagesBasket get basket'));
      expect(
        code,
        contains(
          'String total(Object? arg0) => '
          "_context.message('basket.total', args: [arg0]);",
        ),
      );
      expect(
        code,
        contains("String get empty => _context.message('basket.empty');"),
      );
      expect(
        code,
        contains(
          'String shipped(Object? arg0, Object? arg1) =>',
        ),
      );
      expect(code, contains('final class AppMessagesAdminField {'));
      expect(
        code,
        contains(
          "String get neonNight => _context.message('theme.neon-night');",
        ),
      );
      expect(code, contains("String get title => _context.message('title');"));
      // the default text is in the documentation
      expect(code, contains('/// `basket.total`: Total: {0}'));
    });

    test('a key missing in a locale or only in a locale is a warning', () {
      final (:code, :diagnostics) = _generate({
        'messages.properties': 'a=A\nb=B\n',
        'messages_ja.properties': 'a=ア\nc=シ\n',
        'messages_de.properties': 'a=A\nb=B\n',
      });
      expect(diagnostics.errors, isEmpty);
      expect(
        diagnostics.warnings,
        unorderedEquals([
          'lib/resources/messages_ja.properties: b is missing (it is in messages.properties).',
          'lib/resources/messages_ja.properties: c is not in messages.properties.',
        ]),
      );
      // the key only in a language is typed too
      expect(code, contains('String get c =>'));
    });

    test('a different number of arguments between languages is an error', () {
      final (:code, :diagnostics) = _generate({
        'messages.properties': 'basket.total=Total: {0}\n',
        'messages_ja.properties': 'basket.total=合計：{0} {1}\n',
      });
      expect(code, isNull);
      expect(
        diagnostics.errors.single,
        allOf(
          contains('messages_ja.properties'),
          contains('basket.total has 2 argument(s)'),
          contains('messages.properties has 1'),
        ),
      );
    });

    test('a bad placeholder fails with the file and key named', () {
      final (:code, :diagnostics) = _generate({
        'messages.properties': 'a=Total {0\n',
      });
      expect(code, isNull);
      expect(
        diagnostics.errors.single,
        allOf(contains('messages.properties'), contains('a:')),
      );
    });

    test('a key that is a message and a prefix is an error', () {
      final (:code, :diagnostics) = _generate({
        'messages.properties': 'basket=Basket\nbasket.total=Total\n',
      });
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('basket'));
    });

    test('a key with no Dart name is an error', () {
      final (:code, :diagnostics) = _generate({
        'messages.properties': 'a.b\\ c=x\n',
      });
      expect(code, isNull);
      expect(diagnostics.errors.single, contains('"b c"'));
    });

    test('spring.messages.basename picks the files, in folders too', () {
      final (:code, :diagnostics) = _generate({
        'application.properties':
            'spring.messages.basename=i18n/texts, resources:more\n',
        'messages.properties': 'ignored=1\n',
        'i18n/texts.properties': 'hello=Hello\n',
        'i18n/texts_ja.properties': 'hello=こんにちは\n',
        'more.properties': 'bye=Bye\n',
      });
      expect(diagnostics.errors, isEmpty);
      expect(code, contains('String get hello'));
      expect(code, contains('String get bye'));
      expect(code, isNot(contains('ignored')));
    });

    test('theme and messages share one file', () {
      final (:code, :diagnostics) = _generate({
        'application.properties': 'spring.flutter.theme.spacing.m=16\n',
        'messages.properties': 'a=A\n',
      });
      expect(diagnostics.errors, isEmpty);
      expect(code, contains('AppTheme get theme'));
      expect(code, contains('AppMessages get messages'));
    });
  });

  group('builder', () {
    const files = {
      'app|lib/resources/application.properties':
          'spring.flutter.theme.spacing.m=16\n',
      'app|lib/resources/messages.properties': 'a=A\n',
    };

    test('writes lib/spring_keys.dart for an app with the Flutter starter', () {
      return testBuilder(
        FlutterKeysBuilder(),
        {
          ...files,
          'app|pubspec.yaml':
              'name: app\ndependencies:\n  spring_boot_starter_flutter: any\n',
        },
        rootPackage: 'app',
        outputs: {
          'app|lib/spring_keys.dart': decodedMatches(
            allOf(contains('AppTheme get theme'), contains('AppMessages')),
          ),
        },
      );
    });

    test('also for a package that brings the starter', () {
      return testBuilder(
        FlutterKeysBuilder(),
        {
          ...files,
          'app|pubspec.yaml':
              'name: app\ndependencies:\n'
              '  spring_boot_starter_flutter_security: any\n',
        },
        rootPackage: 'app',
        outputs: {
          'app|lib/spring_keys.dart': decodedMatches(contains('AppTheme')),
        },
      );
    });

    test('nothing for a package without the Flutter starter', () {
      return testBuilder(
        FlutterKeysBuilder(),
        {
          ...files,
          'app|pubspec.yaml':
              'name: app\ndependencies:\n  spring_boot_dart: any\n',
        },
        rootPackage: 'app',
        outputs: {},
      );
    });
  });
}
