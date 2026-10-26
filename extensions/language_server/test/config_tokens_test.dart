// Placeholders and SpEL in config files: the server highlights `${key}`,
// `${key:default}` and `#{...}` in the values of application.yml and
// .properties files (comments left out), and reads unsaved config documents.
import 'dart:io';

import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late SpringWorkspace workspace;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lsp_config_tokens_');
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: shop\n');
    Directory('${root.path}/lib/resources').createSync(recursive: true);
    workspace = SpringWorkspace([root.path])..refresh(force: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// `text: type` of each token of [path], whose text is [text].
  List<String> tokens(String path, String text) {
    final lines = text.split('\n');
    return [
      for (final token in workspace.semanticTokens(path))
        '${lines[token.line].substring(token.column, token.column + token.length)}'
            ': ${semanticTokenTypes[token.type]}',
    ];
  }

  test('placeholders and SpEL in application.yml values, not comments', () {
    const text = '''
server:
  port: \${PORT:8080} # \${not.this}
app:
  title: "\${app.name} #{1 + 2}"
  motto: Don't panic # \${nor.this}
# \${commented.out}
''';
    final path = '${root.path}/lib/resources/application.yml';
    workspace.setOverlay(path, text);
    expect(tokens(path, text), [
      r'${: operator',
      'PORT: property',
      '}: operator',
      r'${: operator',
      'app.name: property',
      '}: operator',
      '#{: keyword',
      '1: number',
      '+: operator',
      '2: number',
      '}: keyword',
    ]);
  });

  test('placeholders in .properties values, not comment lines', () {
    const text = '''
# \${commented.out}
! \${also.out}
greeting=Hello, \${user.name:you}
''';
    final path = '${root.path}/lib/resources/application.properties';
    File(path).writeAsStringSync(text);
    expect(tokens(path, text), [
      r'${: operator',
      'user.name: property',
      '}: operator',
    ]);
  });

  test('other YAML and other files get no tokens', () {
    const workflow = r'run: echo ${{ github.sha }}';
    final path = '${root.path}/.github/workflows/ci.yml';
    workspace.setOverlay(path, workflow);
    expect(workspace.semanticTokens(path), isEmpty);
    expect(workspace.file(path), isNull);
    expect(SpringWorkspace.isConfigFile(path), isFalse);
    expect(
      SpringWorkspace.isConfigFile('${root.path}/config/application-dev.yaml'),
      isTrue,
    );
  });

  test('an open config document counts before it is saved', () {
    const dart = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@Component()
class Shop {
  Shop(@Value(r'\${shop.name}') String name);
}
''';
    final dartPath = '${root.path}/lib/shop.dart';
    File(dartPath).writeAsStringSync(dart);
    final properties = '${root.path}/lib/resources/application.properties';
    File(properties).writeAsStringSync('other=1\n');
    workspace.refresh(force: true);
    List<String> problems() => [
      for (final problem in workspace.problems(dartPath)) problem.message,
    ];
    expect(problems(), [
      "Cannot resolve property 'shop.name' in any properties file",
    ]);

    workspace.setOverlay(properties, 'other=1\nshop.name=NEON\n');
    workspace.refresh(force: true);
    expect(problems(), isEmpty);

    // Closed without saving: the file on disk counts again.
    workspace.setOverlay(properties, null);
    workspace.refresh(force: true);
    expect(problems(), hasLength(1));
  });
}
