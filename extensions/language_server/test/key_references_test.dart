// Find references and rename of a property key: every place of the package
// that names it (config entries, `${key}` in values and in code,
// `getProperty`, `@ConditionalOnProperty` under its prefix), and a rename
// that edits them all or says why it cannot.
import 'dart:io';

import 'package:dart_spring_language_server/src/features/key_references.dart';
import 'package:dart_spring_language_server/src/features/key_renames.dart';
import 'package:dart_spring_language_server/src/features/session.dart';
import 'package:dart_spring_language_server/src/protocol/language_server.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

final class _Editor implements Editor {
  @override
  void notify(String method, Map<String, Object?> params) {}

  @override
  void request(String method, [Map<String, Object?>? params]) {}
}

const _yaml = 'shop:\n  name: Farum\n  url: http://\${shop.name}/\n';

const _dart = r'''
@Component()
@ConditionalOnProperty('name', prefix: 'shop')
class Shop {
  Shop(@Value(r'${shop.name}') this.name, this.environment);

  final String name;
  final Environment environment;

  String get title => environment.getProperty('shop.name')!;
}
''';

void main() {
  late Directory root;
  late SpringSession session;

  String write(String name, String content) {
    final file = File('${root.path}/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    return file.path;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('lsp_key_references_');
    write('pubspec.yaml', 'name: shop\n');
    write('lib/resources/application.yaml', _yaml);
    write('lib/resources/application-dev.properties', 'shop.name=Dev\n');
    write('lib/shop.dart', _dart);
    write('other/pubspec.yaml', 'name: other\n');
    write('other/lib/resources/application.yaml', 'shop.name: Other\n');
    write(
      'other/lib/other.dart',
      "@Component()\nclass Other {\n  Other(@Value(r'\${shop.name}') this.n);\n"
          '  final String n;\n}\n',
    );
    session = SpringSession(
      SpringWorkspace([root.path]),
      _Editor(),
      const {},
    )..workspace.refresh(force: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Map<String, Object?> at(String file, String text, {int into = 1}) {
    final lines = File('${root.path}/$file').readAsLinesSync();
    final line = lines.indexWhere((l) => l.contains(text));
    return {
      'textDocument': {'uri': uriOf('${root.path}/$file')},
      'position': {
        'line': line,
        'character': lines[line].indexOf(text) + into,
      },
    };
  }

  /// `file:line "text"` of a protocol location or edit.
  String describe(Map<Object?, Object?> place, [String? newText]) {
    final path = pathOf(place['uri']! as String);
    final range = place['range']! as Map;
    final start = range['start']! as Map;
    final end = range['end']! as Map;
    final line = File(path).readAsLinesSync()[start['line']! as int];
    final text = line.substring(
      start['character']! as int,
      end['character']! as int,
    );
    return '${path.substring(root.path.length + 1)}:${start['line']} "$text"'
        '${newText == null ? '' : ' -> "$newText"'}';
  }

  List<String> references(
    Map<String, Object?> position, {
    bool declarations = true,
  }) {
    final found =
        KeyReferences(session).requests['textDocument/references']!({
              ...position,
              'context': {'includeDeclaration': declarations},
            })!
            as List<Object?>;
    return [
      for (final place in found.cast<Map<Object?, Object?>>()) describe(place),
    ];
  }

  List<String> rename(Map<String, Object?> position, String newName) {
    final edit =
        KeyRenames(session).requests['textDocument/rename']!({
              ...position,
              'newName': newName,
            })!
            as Map<String, Object?>;
    return [
      for (final MapEntry(key: uri, value: edits)
          in (edit['changes']! as Map).entries)
        for (final change in (edits as List).cast<Map<Object?, Object?>>())
          describe({
            'uri': uri,
            'range': change['range'],
          }, change['newText']! as String),
    ]..sort();
  }

  const everyPlace = [
    'lib/resources/application-dev.properties:0 "shop.name"',
    'lib/resources/application.yaml:1 "name"',
    'lib/resources/application.yaml:2 "shop.name"',
    'lib/shop.dart:1 "name"',
    'lib/shop.dart:3 "shop.name"',
    'lib/shop.dart:8 "shop.name"',
  ];

  test('from a placeholder in code: every place of its package', () {
    expect(
      references(at('lib/shop.dart', r'${shop.name}', into: 3)),
      everyPlace,
    );
    expect(
      references(
        at('lib/shop.dart', r'${shop.name}', into: 3),
        declarations: false,
      ),
      [
        'lib/resources/application.yaml:2 "shop.name"',
        'lib/shop.dart:1 "name"',
        'lib/shop.dart:3 "shop.name"',
        'lib/shop.dart:8 "shop.name"',
      ],
      reason: 'the definitions left out',
    );
  });

  test('from a key of nested YAML and from a prefixed name', () {
    expect(
      references(at('lib/resources/application.yaml', 'name:')),
      everyPlace,
    );
    expect(references(at('lib/shop.dart', "'name'")), everyPlace);
  });

  test('a rename edits every place, the nested and prefixed ones by their '
      'last part', () {
    final prepared =
        KeyRenames(session).requests['textDocument/prepareRename']!(
              at('lib/resources/application-dev.properties', 'shop.name'),
            )!
            as Map;
    expect(prepared['placeholder'], 'shop.name');
    expect(
      rename(
        at('lib/shop.dart', "getProperty('shop.name", into: 14),
        'shop.title',
      ),
      [
        'lib/resources/application-dev.properties:0 "shop.name" -> "shop.title"',
        'lib/resources/application.yaml:1 "name" -> "title"',
        'lib/resources/application.yaml:2 "shop.name" -> "shop.title"',
        'lib/shop.dart:1 "name" -> "title"',
        'lib/shop.dart:3 "shop.name" -> "shop.title"',
        'lib/shop.dart:8 "shop.name" -> "shop.title"',
      ],
    );
  });

  test('a rename that would leave a place reading the old key is refused', () {
    expect(
      () => rename(at('lib/shop.dart', r'${shop.name}', into: 3), 'store.name'),
      throwsA(
        isA<RequestFailure>().having(
          (failure) => failure.message,
          'message',
          contains("written as 'name' under the prefix 'shop'"),
        ),
      ),
    );
    write(
      'lib/shop_properties.dart',
      "@ConfigurationProperties('shop')\nclass ShopProperties {\n"
          '  ShopProperties(this.name);\n  final String name;\n}\n',
    );
    session.workspace.refresh(force: true);
    expect(
      () => rename(at('lib/shop.dart', r'${shop.name}', into: 3), 'shop.title'),
      throwsA(
        isA<RequestFailure>().having(
          (failure) => failure.message,
          'message',
          contains("bound by the field 'name'"),
        ),
      ),
    );
    expect(
      () => rename(at('lib/shop.dart', r'${shop.name}', into: 3), 'not a key'),
      throwsA(isA<RequestFailure>()),
    );
  });
}
