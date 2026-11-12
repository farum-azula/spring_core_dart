// The fixture fixtures/theme_value_kinds.yaml is the one truth of how a
// theme value is classified; the generator reads the same file. Here every
// value goes through the runtime: ThemeValues.kindOf, the typing of a
// style value and the token readers.
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

SpringThemeData theme(Map<String, String> properties) =>
    SpringThemeData.of(ThemeConfig(properties), 'light');

// The fixture is simple on purpose: `- item` lines under a key, and
// `- {value: "...", kind: ...}` lines.
({
  List<String> roots,
  List<String> imageKeys,
  List<(String, String)> values,
  List<({Map<String, String> props, String? error})> objects,
})
_fixture() {
  final lines = File('test/fixtures/theme_value_kinds.yaml').readAsLinesSync();
  final roots = <String>[];
  final imageKeys = <String>[];
  final values = <(String, String)>[];
  final objects = <({Map<String, String> props, String? error})>[];
  List<String>? list;
  final entry = RegExp(r'^\s*- \{value: "(.*)", kind: (\w+)\}$');
  final object = RegExp(
    r'^\s*- \{props: "(.*?)", (?:kind: color|error: "(.*)")\}$',
  );
  for (final line in lines) {
    if (line.startsWith('root-sections:')) {
      list = roots;
    } else if (line.startsWith('image-keys:')) {
      list = imageKeys;
    } else if (line.startsWith('values:') ||
        line.startsWith('color-objects:')) {
      list = null;
    } else if (entry.firstMatch(line) case final match?) {
      values.add((match[1]!, match[2]!));
    } else if (object.firstMatch(line) case final match?) {
      objects.add((
        props: {
          for (final part in match[1]!.split(' | '))
            part.substring(0, part.indexOf('=')): part.substring(
              part.indexOf('=') + 1,
            ),
        },
        error: match[2],
      ));
    } else if (list != null && line.startsWith('  - ')) {
      list.add(line.substring(4).trim());
    }
  }
  return (
    roots: roots,
    imageKeys: imageKeys,
    values: values,
    objects: objects,
  );
}

void main() {
  final fixture = _fixture();

  test('the fixture is read', () {
    expect(fixture.values.length, greaterThan(70));
    expect(fixture.objects.length, greaterThan(25));
  });

  test('root sections are the theme properties, the design starters\' '
      'among them', () {
    // A reference may start with a property of a design starter in an app
    // without that starter too, so both lists make the roots.
    expect(fixture.roots.toSet(), hasLength(fixture.roots.length));
    expect(
      {for (final root in fixture.roots) ThemeValues.canonical(root)},
      {
        for (final property in SpringThemeData.themeProperties)
          ThemeValues.canonical(property),
        ...ThemeDesigns.familyProperties,
      },
    );
  });

  test('image keys are those of ThemeImage', () {
    expect(fixture.imageKeys, ThemeImage.keys);
  });

  group('every value', () {
    for (final (value, kind) in fixture.values) {
      test('"$value" is $kind', () {
        expect(ThemeValues.kindOf(value), kind);

        // As the value of a style.
        final values = theme({'styles.s.v': value.trim()}).styles['s']!
            .resolve(const {});
        switch (kind) {
          case 'number':
            expect(values.number('v'), ThemeValues.number(value));
          case 'duration':
            expect(values.duration('v'), ThemeValues.duration(value));
          case 'insets':
            expect(values.insets('v'), isA<EdgeInsets>());
          case 'color':
            expect(values.color('v'), ThemeValues.color(value));
          default:
            expect(values.text('v'), value.trim());
        }

        // As a token.
        final t = theme({'tokens.a.v': value.trim()});
        expect(
          t.tokenNumber('a.v') != null,
          kind == 'number',
          reason: 'tokenNumber',
        );
        expect(t.tokenColor('a.v') != null, kind == 'color');
        if (kind == 'duration') {
          expect(t.tokenDuration('a.v'), isNotNull);
        }
        if (kind == 'color') {
          expect(t.tokenDuration('a.v'), isNull);
        }
      });
    }
  });

  group('color objects', () {
    for (final (:props, :error) in fixture.objects) {
      final title = props.entries.map((e) => '${e.key}=${e.value}').join(' ');
      test(error == null ? '$title is a color' : '$title: $error', () {
        Map<String, String> under(String prefix) => {
          for (final MapEntry(:key, :value) in props.entries)
            '$prefix.$key': value,
        };
        // Read directly.
        final direct = ThemeProperties(
          'light',
          {for (final e in props.entries) 'n.${e.key}': e.value},
        );
        if (error == null) {
          // As a token and as a style value, resolved with references.
          final t = theme(under('tokens.a.v'));
          final token = t.tokenColor('a.v');
          expect(token, isNotNull);
          final style = theme(under('styles.s.v')).styles['s']!.resolve(
            const {},
          );
          expect(style.color('v'), token);
          if (!props.values.any((v) => v.contains(r'$'))) {
            expect(direct.color('n'), token);
          }
          return;
        }
        Matcher fails() => throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.toString(),
            'message',
            contains(error),
          ),
        );
        if (!props.values.any((v) => v.contains(r'$'))) {
          expect(() => direct.color('n'), fails());
        }
        // A node with a `color` is a color, so a token and a style fail at
        // the start; without one it is a group of tokens (or states).
        if (props.containsKey('color')) {
          expect(() => theme(under('tokens.a.v')), fails());
          expect(() => theme(under('styles.s.v')), fails());
        }
      });
    }
  });

  group('image tokens', () {
    const base = {'source': 'assets/a.png'};

    Set<String> images(Map<String, String> tokens) => {
      for (final image in theme({
        for (final MapEntry(:key, :value) in tokens.entries)
          'tokens.$key': value,
      }).images)
        image.source,
    };

    test('tokens.<group>.<key> with source and only image keys', () {
      expect(images({'brand.logo.source': 'assets/a.png'}), {'assets/a.png'});
      expect(
        images({
          'brand.logo.source': 'assets/a.png',
          'brand.logo.fallback': 'assets/b.png',
          'brand.logo.headers.x-key': 'k',
          'brand.logo.refresh': '1h',
          'brand.logo.timeout': '5s',
          'brand.logo.source-sha256': 'a' * 64,
        }),
        {'assets/a.png'},
      );
    });

    test('another child makes it a group of tokens, not an image', () {
      expect(
        images({
          'brand.logo.source': 'assets/a.png',
          'brand.logo.width': '24',
        }),
        isEmpty,
      );
    });

    test('too shallow (tokens.<key>.source) is not an image', () {
      expect(images({'logo.source': base['source']!}), isEmpty);
    });

    test('a deeper node is an image too', () {
      expect(
        images({'brand.hero.light.source': 'assets/a.png'}),
        {'assets/a.png'},
      );
    });
  });
}
