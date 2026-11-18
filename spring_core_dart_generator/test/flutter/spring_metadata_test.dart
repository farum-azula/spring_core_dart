// lib/spring_gen/spring_metadata.json of the Flutter starter's part: the
// theme's metadata and the theme loader kinds.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../support/spring_metadata.dart';

void main() {
  group('theme', () {
    test('only the Flutter starter embeds tool/theme_metadata.json', () async {
      final theme = jsonEncode({
        'types': {
          'color': {'kind': 'color'},
        },
        'properties': [
          {'name': 'components.app-bar.background-color', 'type': 'color'},
        ],
        'ignored': 1,
      });
      final starter = await runMetadataBuilder({
        'lib/a.dart': shopProperties,
        'tool/theme_metadata.json': theme,
      }, package: 'spring_boot_starter_flutter');
      expect(starter.json!['theme'], {
        'types': {
          'color': {'kind': 'color'},
        },
        'properties': [
          {'name': 'components.app-bar.background-color', 'type': 'color'},
        ],
      });
      final other = await runMetadataBuilder({
        'lib/a.dart': shopProperties,
        'tool/theme_metadata.json': theme,
      });
      expect(other.json!.containsKey('theme'), isFalse);
    });
  });

  group('loader kinds', () {
    test('the @ThemeLoaderKind classes and the keys the themes give', () async {
      final result = await runMetadataBuilder({
        'lib/loaders/doors.dart':
            '''
$metadataHeader
class ThemeLoaderKind {
  const ThemeLoaderKind(this.name);
  final String name;
}

@ThemeLoaderKind('doors')
final class DoorsLoader {}
''',
        'lib/resources/application.yaml': '''
spring.flutter.theme:
  loaders:
    neon-doors: { kind: doors, door: { color: red }, seam: { width: 1 }, web: x }
''',
      });
      final kinds = entriesOf(result.json!, 'loaderKinds');
      expect(kinds, [
        {
          'name': 'doors',
          'class': 'DoorsLoader',
          'source': 'package:pkg/loaders/doors.dart',
          'line': 9,
          'props': ['door', 'seam'],
        },
      ]);
    });

    test('a kind of bin/ names its file as the beans of bin/ do', () async {
      final result = await runMetadataBuilder({
        'bin/main.dart':
            '''
$metadataHeader
class ThemeLoaderKind {
  const ThemeLoaderKind(this.name);
  final String name;
}

@ThemeLoaderKind('doors')
final class DoorsLoader {}

@Component()
class Shop {}
''',
      });
      final kind = entriesOf(result.json!, 'loaderKinds').single;
      expect(kind['source'], 'bin/main.dart');
      expect(
        namedEntry(result.json!, 'beans', 'shop')['source'],
        'bin/main.dart',
      );
    });

    test('a package without loader kinds has no entry', () async {
      final result = await runMetadataBuilder({
        'lib/shop.dart': shopProperties,
      });
      expect(result.json!.containsKey('loaderKinds'), isFalse);
    });
  });
}
