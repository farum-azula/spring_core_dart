// A closure's parameters are highlighted where they are declared and where
// the closure's body uses them (a semantic token of their own), unlike the
// parameters of functions and methods.
import 'dart:io';

import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late SpringWorkspace workspace;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lsp_closure_parameters_');
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: shop\n');
    Directory('${root.path}/lib').createSync(recursive: true);
  });

  tearDown(() => root.deleteSync(recursive: true));

  /// `line:column text` of each closure-parameter token of [source].
  List<String> closureTokens(String source) {
    final path = '${root.path}/lib/shop.dart';
    File(path).writeAsStringSync(source);
    workspace = SpringWorkspace([root.path])..refresh(force: true);
    final lines = source.split('\n');
    String text(SemanticToken t) =>
        lines[t.line].substring(t.column, t.column + t.length);
    return [
      for (final token in workspace.semanticTokens(path))
        if (semanticTokenTypes[token.type] == 'closureParameter')
          '${token.line}:${token.column} ${text(token)}',
    ];
  }

  test('declared and used in the body, also in string interpolation', () {
    expect(
      closureTokens(r'''
void listen(List<String> heard, void Function(void Function(Alert)) add) {
  add((alert) => heard.add('parent: ${alert.isbn} $alert'));
}
'''),
      ['1:7 alert', '1:38 alert', '1:51 alert'],
    );
  });

  test('typed, named and positional parameters, a block body', () {
    expect(
      closureTokens('''
final f = (int a, [int b = 0]) {
  return a + b;
};
final g = ({required int size}) => size * 2;
'''),
      ['0:15 a', '0:23 b', '1:9 a', '1:13 b', '3:25 size', '3:35 size'],
    );
  });

  test('not a function or method parameter, nor a member of the same name', () {
    expect(
      closureTokens('''
class Shop {
  int count = 0;
  void sell(int count) => count;
  void each(List<int> all) => all.forEach((count) {
    this.count = count;
    other.count;
    order(count: 1);
  });
}
int top(int count) => count;
'''),
      ['3:43 count', '4:17 count'],
    );
  });

  test('a name declared again inside hides the parameter', () {
    expect(
      closureTokens('''
final f = (item) {
  print(item);
  for (final item in const [1]) {
    print(item);
  }
  print(item);
  void local(int item) => print(item);
  final g = (item) => item;
};
'''),
      [
        '0:11 item',
        '1:8 item',
        '5:8 item',
        '7:13 item',
        '7:22 item',
      ],
    );
  });
}
