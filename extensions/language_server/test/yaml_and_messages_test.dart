// application.yml keys are properties like .properties ones (with their
// position in the file); message bundles (messages*.properties) are not
// config: their keys answer context.message('...') and getMessage('...').
import 'dart:io';

import 'package:dart_spring_language_server/src/properties_index.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

const _yaml = '''
shop:
  name: NEON Books
  currencies: [EUR, USD]
  servers:
    - host: a.example
      port: 8080
---
spring:
  config:
    activate:
      on-profile: prod
shop:
  name: NEON Prod
''';

const _app = r'''
import 'package:spring_core_dart/spring_core_dart.dart';

class Shop {
  @Value(r'${shop.name}')
  late String name;

  @Value(r'${shop.currencies}')
  late List<String> currencies;

  @Value(r'${shop.servers[0].host}')
  late String host;

  @Value(r'${about.title}')
  late String notAProperty;
}

void page(BuildContext context, ApplicationContext app) {
  context.message('about.title');
  context.message('about.missing');
  context.message('about.other', defaultMessage: 'fine');
  app.getMessage('counter.pushed', args: [1]);
}
''';

void main() {
  test('parseYamlProperties flattens documents, lists and positions', () {
    final entries = parseYamlProperties('application.yml', _yaml);
    final keys = [
      for (final e in entries) '${e.key}=${e.value}@${e.line}:${e.keyStart}',
    ];
    expect(keys, [
      'shop.name=NEON Books@1:2',
      'shop.currencies=EUR,USD@2:2',
      'shop.currencies[0]=EUR@2:15',
      'shop.currencies[1]=USD@2:20',
      'shop.servers[0].host=a.example@4:6',
      'shop.servers[0].port=8080@5:6',
      'spring.config.activate.on-profile=prod@10:6',
      'shop.name=NEON Prod@12:2',
    ]);
    expect(entries.first.keyEnd, 6);
    expect(entries.first.fileName, 'application');
  });

  test('a broken YAML file gives no entries', () {
    expect(parseYamlProperties('a.yml', 'a: [b\n'), isEmpty);
  });

  group('workspace', () {
    late Directory root;
    late SpringWorkspace workspace;
    late String appPath;
    late String ymlPath;

    setUpAll(() {
      root = Directory.systemTemp.createTempSync('lsp_yaml_');
      appPath = '${root.path}/lib/src/shop.dart';
      ymlPath = '${root.path}/lib/resources/application.yml';
      File(appPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(_app);
      File(ymlPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(_yaml);
      File('${root.path}/lib/resources/messages.properties')
          .writeAsStringSync('about.title=About\ncounter.pushed=Pushed {0}\n');
      File('${root.path}/lib/resources/messages_ja.properties')
          .writeAsStringSync('about.title=概要\n');
      // Outside resources/: not config.
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: x\n');
      workspace = SpringWorkspace([root.path])..refresh(force: true);
    });

    tearDownAll(() => root.deleteSync(recursive: true));

    List<String> messages() => [
      for (final problem in workspace.problems(appPath)) problem.message,
    ];

    int offsetOf(String needle, {int shift = 1}) =>
        _app.indexOf(needle) + shift;

    test('YAML keys resolve; message keys are not properties', () {
      expect(messages().where((m) => m.startsWith('Cannot resolve')), [
        "Cannot resolve property 'about.title' in any properties file",
      ]);
      expect(workspace.property('name'), isEmpty); // pubspec.yaml
      expect(
        [for (final e in workspace.property('shop.name')) e.value],
        ['NEON Books', 'NEON Prod'],
      );
    });

    test('go to definition of a YAML key', () {
      final targets = workspace.definition(
        appPath,
        offsetOf(r'shop.servers[0].host', shift: 2),
      );
      expect(targets.single.path, ymlPath);
      expect(targets.single.startLine, 4);
    });

    test('a message code goes to every bundle', () {
      final targets = workspace.definition(appPath, offsetOf("'about.title')"));
      expect(
        [for (final t in targets) t.path.split('/').last],
        ['messages.properties', 'messages_ja.properties'],
      );
      final pushed = workspace.definition(
        appPath,
        offsetOf("'counter.pushed'"),
      );
      expect(pushed.single.path, endsWith('messages.properties'));
    });

    test('an unknown message code without defaultMessage is reported', () {
      expect(messages().where((m) => m.startsWith('No message')), [
        "No message 'about.missing' in the message bundles "
            '(messages*.properties)',
      ]);
    });

    test('hover lists the translations', () {
      expect(
        workspace.hover(appPath, offsetOf("'about.title')")),
        allOf(contains('(message)'), contains('messages_ja'), contains('概要')),
      );
    });
  });

  test('spring.messages.basename chooses the bundles', () {
    final root = Directory.systemTemp.createTempSync('lsp_basename_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/lib/resources/application.properties')
      ..createSync(recursive: true)
      ..writeAsStringSync('spring.messages.basename=i18n.texts\n');
    File('${root.path}/lib/resources/i18n/texts_de.properties')
      ..createSync(recursive: true)
      ..writeAsStringSync('hello=Hallo\n');
    File('${root.path}/lib/resources/messages.properties')
        .writeAsStringSync('hello.config=x\n');
    final workspace = SpringWorkspace([root.path])..refresh(force: true);
    expect(workspace.messages('hello').single.value, 'Hallo');
    expect(workspace.property('hello'), isEmpty);
    // Not a bundle with this basename: an ordinary properties file.
    expect(workspace.property('hello.config'), hasLength(1));
  });

  test('each package of a monorepo has its own spring.messages.basename', () {
    final root = Directory.systemTemp.createTempSync('lsp_mono_');
    addTearDown(() => root.deleteSync(recursive: true));
    void write(String path, String text) => File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    // A package that moves its bundles to messages/messages*.
    write('tour/pubspec.yaml', 'name: tour\n');
    write(
      'tour/lib/resources/application.properties',
      'spring.messages.basename=messages/messages\n',
    );
    write('tour/lib/resources/messages/messages.properties', 'greeting=Hi\n');
    // A Flutter app with the default basename.
    write('app/pubspec.yaml', 'name: app\n');
    write('app/lib/resources/messages.properties', 'about.title=About\n');
    write(
      'app/lib/about.dart',
      "void f(BuildContext context) => context.message('about.title');\n",
    );
    final workspace = SpringWorkspace([root.path])..refresh(force: true);
    final appFile = '${root.path}/app/lib/about.dart';
    expect(
      workspace.problems(appFile).map((p) => p.message),
      isNot(contains(startsWith('No message'))),
    );
    expect(workspace.messages('about.title', from: appFile), hasLength(1));
    // The other package's messages are not this file's.
    expect(workspace.messages('greeting', from: appFile), isEmpty);
    expect(workspace.property('about.title'), isEmpty);
  });
}
