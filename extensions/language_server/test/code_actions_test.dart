// Quick fixes: a key nothing defines is added to the package's config file
// or given a default, a misspelt profile or bean is changed to the one it
// was probably meant to be.
import 'dart:io';

import 'package:dart_spring_language_server/src/features/code_actions.dart';
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

  setUp(() {
    root = Directory.systemTemp.createTempSync('lsp_code_actions_');
    write('pubspec.yaml', 'name: shop\n');
    write('lib/resources/application.yaml', 'shop:\n  name: Farum');
    write('lib/resources/application-prod.yaml', 'shop:\n  name: Prod\n');
    session = SpringSession(
      SpringWorkspace([root.path]),
      _Editor(),
      const {},
    )..workspace.refresh(force: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// The quick fixes on [line] of [path]: `title -> file:line:column "text"`
  /// for each edit.
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
        for (final MapEntry(key: uri, value: edits)
            in ((action['edit']! as Map)['changes']! as Map).entries)
          for (final edit in (edits as List).cast<Map<String, Object?>>())
            _describe(action['title']! as String, uri as String, edit),
    ];
  }

  test('a placeholder of a key nothing defines: add it, or give a default', () {
    final path = write(
      'lib/shop.dart',
      '@Component()\nclass Shop {\n'
          "  Shop(@Value(r'\${shop.title}') this.title);\n"
          '  final String title;\n}\n',
    );
    const addition = '"\nshop.title: \n"';
    const withDefault = r'Give the placeholder a default (${shop.title:...})';
    expect(fixes(path, 2), [
      "Add 'shop.title' to application.yaml -> application.yaml:1:13 $addition",
      '$withDefault -> shop.dart:2:28 ":"',
    ]);
  });

  test('a placeholder in a config value: the same fixes', () {
    final path = write(
      'lib/resources/application-prod.yaml',
      'shop:\n  name: Prod\n  url: http://\${shop.host}/\n',
    );
    session.workspace.refresh(force: true);
    const addition = '"\nshop.host: \n"';
    const withDefault = r'Give the placeholder a default (${shop.host:...})';
    expect(fixes(path, 2), [
      "Add 'shop.host' to application.yaml -> application.yaml:1:13 $addition",
      '$withDefault -> application-prod.yaml:2:25 ":"',
    ]);
  });

  test('a misspelt profile and bean are changed to the known ones', () {
    // The metadata says which profiles the package declares in code.
    write('lib/spring_gen/spring_metadata.json', '{"package": "shop"}');
    session.workspace.refresh(force: true);
    final path = write(
      'lib/clock.dart',
      '@Service()\nclass Clock {}\n\n'
          "@Profile('prd')\n@Component()\nclass Report {\n"
          "  Report(@Value('#{@clok.toString()}') this.at);\n"
          '  final String at;\n}\n',
    );
    expect(fixes(path, 3), ["Change to 'prod' -> clock.dart:3:10 \"prod\""]);
    expect(fixes(path, 6), [
      "Change to '@clock' -> clock.dart:6:19 \"@clock\"",
    ]);
  });
}

/// `title -> file:line:column "text"` of an [edit] of the file [uri].
String _describe(String title, String uri, Map<String, Object?> edit) {
  final start = (edit['range']! as Map)['start']! as Map;
  return '$title -> ${uri.split('/').last}:'
      '${start['line']}:${start['character']} "${edit['newText']}"';
}
