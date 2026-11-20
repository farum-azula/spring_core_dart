// A value read in a file comes from the config of that file's package: a
// key that only another package of the workspace defines is no definition
// target there, and is reported as unresolved, in Dart and config files.
import 'dart:io';

import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

const _app = r'''
import 'package:spring_core_dart/spring_core_dart.dart';

@Service()
class App {
  App(@Value(r'${only.other}') this.foreign, @Value(r'${shared}') this.own);

  final String foreign;
  final String own;

  void run(Environment environment) {
    environment.getProperty('only.other');
  }
}
''';

const _other = r'''
import 'package:spring_core_dart/spring_core_dart.dart';

@Service()
class Other {
  Other(@Value(r'${only.other}') this.value);

  final String value;
}
''';

void main() {
  late Directory root;
  late SpringWorkspace workspace;
  late String appPath;
  late String otherPath;
  late String appConfig;
  late String otherConfig;

  void write(String path, String content) => File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  setUp(() {
    root = Directory.systemTemp.createTempSync('lsp_scoping_');
    appPath = '${root.path}/app/lib/app.dart';
    otherPath = '${root.path}/other/lib/other.dart';
    appConfig = '${root.path}/app/lib/resources/application.properties';
    otherConfig = '${root.path}/other/lib/resources/application.properties';
    write('${root.path}/app/pubspec.yaml', 'name: app\n');
    write('${root.path}/other/pubspec.yaml', 'name: other\n');
    write(appPath, _app);
    write(otherPath, _other);
    write(appConfig, 'shared=app\nderived=\${only.other}\n');
    write(otherConfig, 'only.other=1\nshared=other\n');
    workspace = SpringWorkspace([root.path])..refresh(force: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  int at(String text, String marker) => text.indexOf(marker) + 2;

  List<String> definitions(String path, int offset) => [
    for (final range in workspace.definition(path, offset))
      '${range.path.substring(root.path.length + 1)}:${range.startLine}',
  ];

  List<String> messages(String path) => [
    for (final problem in workspace.problems(path)) problem.message,
  ];

  const unresolved =
      "Cannot resolve property 'only.other' in any properties "
      'file';

  test("another package's key is no definition target in Dart", () {
    expect(definitions(appPath, at(_app, r"${only.other}')")), isEmpty);
    expect(definitions(appPath, at(_app, "('only.other')")), isEmpty);
    expect(definitions(appPath, at(_app, r"${shared}')")), [
      'app/lib/resources/application.properties:0',
    ]);
    expect(
      workspace.hover(appPath, at(_app, r"${only.other}')")),
      contains('not defined in any properties file'),
    );
  });

  test("another package's key is reported as unresolved in Dart", () {
    expect(messages(appPath), contains(unresolved));
    expect(messages(appPath), isNot(contains(contains("'shared'"))));
    expect(messages(otherPath), isNot(contains(unresolved)));
    expect(definitions(otherPath, at(_other, r"${only.other}')")), [
      'other/lib/resources/application.properties:0',
    ]);
  });

  test("another package's key is unresolved in a config file", () {
    final text = File(appConfig).readAsStringSync();
    expect(messages(appConfig), [unresolved]);
    expect(definitions(appConfig, at(text, r'${only.other}')), isEmpty);
    expect(
      workspace.hover(appConfig, at(text, r'${only.other}')),
      contains('not defined in any properties file'),
    );
  });
}
