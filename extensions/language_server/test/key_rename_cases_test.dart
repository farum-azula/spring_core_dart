// The cases of find references, rename and the missing-key fixes that Spring
// binds and the editor must follow: nested placeholders in code, enum and
// nested-class fields of @ConfigurationProperties, a prefix with a trailing
// dot, comments, collisions, document versions, and where a fix inserts.
import 'dart:io';

import 'package:dart_spring_language_server/src/features/code_actions.dart';
import 'package:dart_spring_language_server/src/features/document_sync.dart';
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

void main() {
  late Directory root;
  late SpringSession session;

  String write(String name, String content) {
    final file = File('${root.path}/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    return file.path;
  }

  void start([Map<String, Object?> initialize = const {}]) {
    session = SpringSession(
      SpringWorkspace([root.path]),
      _Editor(),
      initialize,
    )..workspace.refresh(force: true);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('lsp_rename_cases_');
    write('pubspec.yaml', 'name: shop\n');
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

  List<String> references(Map<String, Object?> position) {
    final found =
        KeyReferences(session).requests['textDocument/references']!({
              ...position,
              'context': {'includeDeclaration': true},
            })!
            as List<Object?>;
    return [
      for (final place in found.cast<Map<Object?, Object?>>()) describe(place),
    ];
  }

  Map<String, Object?> renameEdit(
    Map<String, Object?> position,
    String newName,
  ) =>
      KeyRenames(session).requests['textDocument/rename']!({
            ...position,
            'newName': newName,
          })!
          as Map<String, Object?>;

  List<String> rename(Map<String, Object?> position, String newName) => [
    for (final MapEntry(key: uri, value: edits)
        in (renameEdit(position, newName)['changes']! as Map).entries)
      for (final change in (edits as List).cast<Map<Object?, Object?>>())
        describe({
          'uri': uri,
          'range': change['range'],
        }, change['newText']! as String),
  ]..sort();

  Matcher refusedWith(String message) => throwsA(
    isA<RequestFailure>().having(
      (f) => f.message,
      'message',
      contains(message),
    ),
  );

  group('references and rename', () {
    test('a placeholder nested in the default of another, in code', () {
      write('lib/resources/application.yaml', 'app:\n  name: A\n');
      write(
        'lib/a.dart',
        "@Component()\nclass A {\n  A(@Value(r'\${app.x:\${app.name}}') "
            'this.b);\n  final String b;\n}\n',
      );
      start();
      expect(references(at('lib/resources/application.yaml', 'name:')), [
        'lib/a.dart:2 "app.name"',
        'lib/resources/application.yaml:1 "name"',
      ]);
      expect(
        rename(at('lib/resources/application.yaml', 'name:'), 'app.title'),
        [
          'lib/a.dart:2 "app.name" -> "app.title"',
          'lib/resources/application.yaml:1 "name" -> "title"',
        ],
      );
    });

    test('enum and nested-class fields bind, and refuse a rename', () {
      write(
        'lib/resources/application.yaml',
        'shop:\n  mode: fast\n  address:\n    city: X\n  tags:\n    a: 1\n',
      );
      write(
        'lib/address.dart',
        'class Address {\n  final String city;\n'
            '  Address(this.city);\n}\n',
      );
      write('lib/p.dart', '''
enum Mode { fast, slow }
@ConfigurationProperties('shop')
class ShopProps {
  final Mode mode;
  final Address address;
  final Map<String, String> tags;
  ShopProps(this.mode, this.address, this.tags);
}
''');
      start();
      expect(references(at('lib/resources/application.yaml', 'mode:')), [
        'lib/p.dart:3 "mode"',
        'lib/resources/application.yaml:1 "mode"',
      ]);
      expect(references(at('lib/resources/application.yaml', 'city:')), [
        'lib/address.dart:1 "city"',
        'lib/resources/application.yaml:3 "city"',
      ]);
      expect(
        () => rename(at('lib/resources/application.yaml', 'mode:'), 'shop.zzz'),
        refusedWith("bound by the field 'mode'"),
      );
      expect(
        () => rename(
          at('lib/resources/application.yaml', 'city:'),
          'shop.address.town',
        ),
        refusedWith("bound by the field 'city'"),
      );
      expect(
        () => rename(at('lib/resources/application.yaml', 'a:'), 'shop.tags.b'),
        refusedWith("an entry of 'shop.tags'"),
      );
    });

    test('a prefix with a trailing dot', () {
      write('lib/resources/application.yaml', 'feat:\n  on: true\n');
      write(
        'lib/f.dart',
        "@Component()\n@ConditionalOnProperty('on', prefix: 'feat.')\n"
            'class F {}\n',
      );
      start();
      expect(references(at('lib/resources/application.yaml', 'on:')), [
        'lib/f.dart:1 "on"',
        'lib/resources/application.yaml:1 "on"',
      ]);
    });

    test('placeholders in comments are left alone', () {
      write(
        'lib/resources/application.yaml',
        'app:\n  name: A\n'
            '  x: y # see \${app.name}\n',
      );
      write(
        'lib/resources/application-prod.properties',
        'app.name=B\n'
            '# comment \${app.name}\n! also \${app.name}\napp.y=\${app.name}\n',
      );
      start();
      expect(references(at('lib/resources/application.yaml', 'name:')), [
        'lib/resources/application-prod.properties:0 "app.name"',
        'lib/resources/application-prod.properties:3 "app.name"',
        'lib/resources/application.yaml:1 "name"',
      ]);
    });

    test('a rename onto a key already defined is refused', () {
      write('lib/resources/application.yaml', 'app:\n  name: A\n  name-x: B\n');
      start();
      expect(
        () => rename(
          at('lib/resources/application.yaml', 'name:'),
          'app.name-x',
        ),
        refusedWith("'app.name-x' is already defined"),
      );
      expect(
        rename(at('lib/resources/application.yaml', 'name:'), 'app.nAme'),
        ['lib/resources/application.yaml:1 "name" -> "nAme"'],
        reason: 'the same key in another form is no collision',
      );
    });

    test('edits carry the version of open documents', () {
      final path = write('lib/resources/application.yaml', 'app:\n  name: A\n');
      write('lib/resources/application.properties', 'app.name=B\n');
      start({
        'capabilities': {
          'workspace': {
            'workspaceEdit': {'documentChanges': true},
          },
        },
      });
      DocumentSync(session).notifications['textDocument/didOpen']!({
        'textDocument': {
          'uri': uriOf(path),
          'version': 7,
          'text': 'app:\n  name: A\n',
        },
      });
      final edit = renameEdit(
        at('lib/resources/application.yaml', 'name:'),
        'app.title',
      );
      final versions = {
        for (final change
            in (edit['documentChanges']! as List).cast<Map<Object?, Object?>>())
          pathOf((change['textDocument']! as Map)['uri']! as String)
                  .split('/')
                  .last:
              (change['textDocument']! as Map)['version'],
      };
      expect(versions, {
        'application.yaml': 7,
        'application.properties': null,
      });
    });
  });

  group('missing key fixes', () {
    List<String> fixes(String path, int line) {
      session.workspace.setOverlay(path, File(path).readAsStringSync());
      final actions =
          CodeActions(session).requests['textDocument/codeAction']!({
                'textDocument': {'uri': uriOf(path)},
                'range': {
                  'start': {'line': line, 'character': 0},
                  'end': {'line': line, 'character': 200},
                },
                'context': {'diagnostics': <Object?>[]},
              })!
              as List<Object?>;
      return [
        for (final action in actions.cast<Map<String, Object?>>())
          for (final MapEntry(value: edits)
              in ((action['edit']! as Map)['changes']! as Map).entries)
            for (final edit in (edits as List).cast<Map<String, Object?>>())
              '${((edit['range']! as Map)['start']! as Map).values.join(':')} '
                  '${edit['newText']}',
      ];
    }

    test('the key goes before the first profile document, with the file '
        'line ending', () {
      write(
        'lib/resources/application.yaml',
        'shop:\r\n  name: A\r\n---\r\nspring.config.activate.on-profile: '
            'prod\r\nshop:\r\n  name: P\r\n',
      );
      final path = write(
        'lib/shop.dart',
        "@Component()\nclass Shop {\n  Shop(@Value(r'\${ shop.title }') "
            'this.t);\n  final String t;\n}\n',
      );
      start();
      expect(fixes(path, 2), [
        '2:0 shop.title: \r\n',
        '2:29 :',
      ]);
    });
  });
}
