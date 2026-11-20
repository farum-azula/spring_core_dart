// The semantic tokens of placeholders in Dart annotation strings: a key
// nothing defines is marked `unresolved`, a default `defaultValue`.
import 'dart:io';

import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late SpringWorkspace workspace;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lsp_placeholder_tokens_');
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: shop\n');
    File('${root.path}/lib/resources/application.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('shop:\n  name: Farum\n');
    workspace = SpringWorkspace([root.path])..refresh(force: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('an unresolved key, a resolved one, a default', () {
    const text = r'''
class Shop {
  @Value(r'${shop.name}')
  late String name;
  @Value(r'${shop.nmae}')
  late String typo;
  @Value(r'${server.port:8080}')
  late int port;
}
''';
    final path = '${root.path}/lib/shop.dart';
    File(path).writeAsStringSync(text);
    workspace.setOverlay(path, text);
    final lines = text.split('\n');
    expect(
      [
        for (final token in workspace.semanticTokens(path))
          if (token.type.legendName != 'operator')
            [
              lines[token.line].substring(
                token.column,
                token.column + token.length,
              ),
              token.type.legendName,
              for (final modifier in TokenModifier.values)
                if (token.has(modifier)) modifier.name,
            ].join(' '),
      ],
      [
        'shop.name property',
        'shop.nmae property unresolved',
        'server.port property',
        '8080 string defaultValue',
      ],
    );
  });
}
