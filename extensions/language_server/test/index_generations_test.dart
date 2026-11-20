// Typing inside a method body must not build the indexes again: the
// classes, the beans and the keys the code reads. A change of what they
// read (a declaration, an annotation, a key) builds what depends on it.
import 'dart:io';

import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

const _shop = r'''
import 'package:spring_core_dart/spring_core_dart.dart';

class Clock {}

@Service()
class Checkout {
  Checkout(this.clock, @Value(r'${shop.name}') this.name);

  final Clock clock;
  final String name;

  String total(Environment environment) {
    environment.getProperty('shop.currency');
    return 'total';
  }
}

@Configuration()
class TimeConfig {
  @Bean()
  Clock clock() => Clock();
}
''';

void main() {
  late Directory root;
  late SpringWorkspace workspace;
  late String path;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lsp_generations_');
    path = '${root.path}/lib/shop.dart';
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(_shop);
    File('${root.path}/lib/resources/application.properties')
      ..createSync(recursive: true)
      ..writeAsStringSync('shop.name=NEON\n');
    workspace = SpringWorkspace([root.path])..refresh(force: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  // What an editor asks after each key: the checks (which read the beans
  // and the known keys), the tokens, a definition.
  void ask(String text) {
    workspace
      ..setOverlay(path, text)
      ..problems(path)
      ..semanticTokens(path)
      ..definition(path, text.indexOf('this.clock') + 'this.'.length);
  }

  // The text with [typed] put inside the body of `total`.
  String typedInBody(String typed) {
    final body = _shop.indexOf("return 'total';");
    return _shop.replaceRange(body, body, typed);
  }

  test('typing inside a method body builds no index again', () {
    ask(_shop);
    final before = workspace.indexGenerations;
    final beans = workspace.beans;
    const statement = 'final unused = 1;\n    ';
    for (var i = 1; i <= statement.length; i++) {
      ask(typedInBody(statement.substring(0, i)));
    }
    expect(workspace.indexGenerations, before);
    expect(identical(workspace.beans, beans), isTrue);
  });

  test('a bean is found where it is now after typing above it', () {
    ask(_shop);
    final before = workspace.indexGenerations;
    final text = typedInBody('// one\n    // two\n    // three\n    ');
    workspace.setOverlay(path, text);
    final ranges = workspace.definition(
      path,
      text.indexOf('this.clock') + 'this.'.length,
    );
    final clockLine =
        text.substring(0, text.indexOf('Clock clock()')).split('\n').length - 1;
    expect([for (final range in ranges) range.startLine], [clockLine]);
    expect(workspace.indexGenerations, before);
  });

  test('a new annotation builds the classes and beans again', () {
    ask(_shop);
    final before = workspace.indexGenerations;
    ask(_shop.replaceFirst('@Service()\n', '@Service()\n@Primary()\n'));
    final after = workspace.indexGenerations;
    expect(after.declarations, greaterThan(before.declarations));
    expect(after.beans, greaterThan(before.beans));
    expect(
      workspace.beans.where((bean) => bean.name == 'checkout').single.primary,
      isTrue,
    );
  });

  test('a key read in a method body changes only the keys of the code', () {
    ask(_shop);
    final before = workspace.indexGenerations;
    ask(_shop.replaceFirst("'shop.currency'", "'shop.locale'"));
    final after = workspace.indexGenerations;
    expect(after.codeKeys, greaterThan(before.codeKeys));
    expect(after.declarations, before.declarations);
    expect(after.beans, before.beans);
  });
}
