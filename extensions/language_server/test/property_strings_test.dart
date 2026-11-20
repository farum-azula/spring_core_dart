// The strings of a Dart file that name a property outside a template: the
// key of `getProperty('...')` and of `@ConditionalOnProperty('...')`. Only
// the key is one (not a `defaultValue:`, a `havingValue:` or the prefix),
// it goes to its definitions, shows its value inline, and a hover on a key
// set nowhere names only its own default.
import 'dart:io';

import 'package:dart_spring_language_server/src/features/inlay_hints.dart';
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

const _source = r'''
@Service()
class Clock {}

@Component()
@ConditionalOnProperty('cache', prefix: 'shop', havingValue: 'redis')
@ConditionalOnMissingBean('clock')
class Shop {
  Shop(this.environment);

  final Environment environment;

  /// The name, `${a:not this}` in a comment.
  String get name => environment.getProperty('shop.name')!;

  String get motto =>
      environment.getProperty('shop.motto', defaultValue: 'Read on')!;
}
''';

void main() {
  late Directory root;
  late String path;
  late SpringWorkspace workspace;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lsp_property_strings_');
    void write(String name, String content) => File('${root.path}/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    write('pubspec.yaml', 'name: shop\n');
    write(
      'lib/resources/application.yaml',
      'shop:\n  name: Farum\n  cache: redis\n',
    );
    path = '${root.path}/lib/shop.dart';
    write('lib/shop.dart', _source);
    workspace = SpringWorkspace([root.path])
      ..refresh(force: true)
      ..setOverlay(path, _source);
  });

  tearDown(() => root.deleteSync(recursive: true));

  int at(String text, [int into = 1]) => _source.indexOf(text) + into;

  List<String> definitions(int offset) => [
    for (final range in workspace.definition(path, offset))
      '${range.path.split('/').last}:${range.startLine}',
  ];

  test('the key of @ConditionalOnProperty is under its prefix; '
      'havingValue and the prefix are no keys', () {
    expect(definitions(at("'cache'")), ['application.yaml:2']);
    expect(workspace.hover(path, at("'cache'")), contains('`shop.cache`'));
    expect(definitions(at("'redis'")), isEmpty);
    expect(workspace.hover(path, at("'redis'")), isNull);
    expect(definitions(at("'shop',")), isEmpty);
  });

  test('the key of getProperty is its first argument, not defaultValue', () {
    expect(definitions(at("'shop.name'")), ['application.yaml:1']);
    expect(definitions(at("'Read on'")), isEmpty);
    expect(workspace.hover(path, at("'Read on'")), isNull);
  });

  test('a key set nowhere: the hover names its own default, '
      'not a placeholder elsewhere in the file', () {
    expect(
      workspace.hover(path, at("'shop.motto'")),
      contains('the default after the colon is used: `Read on`'),
    );
    final undefined = _source.replaceFirst("'shop.name'", "'shop.title'");
    workspace.setOverlay(path, undefined);
    expect(
      workspace.hover(path, undefined.indexOf("'shop.title'") + 1),
      allOf(contains('not defined'), isNot(contains('default'))),
    );
  });

  test('the value of the key is shown after the string', () {
    final session = SpringSession(workspace, _Editor(), const {});
    final hints =
        InlayHints(session).requests['textDocument/inlayHint']!({
              'textDocument': {'uri': uriOf(path)},
              'range': {
                'start': {'line': 0, 'character': 0},
                'end': {'line': 100, 'character': 0},
              },
            })!
            as List<Object?>;
    expect(
      [
        for (final hint in hints.cast<Map<String, Object?>>())
          ((hint['label']! as List).single as Map)['value'],
      ],
      ['= redis', '= Farum', '= Read on (default)'],
    );
  });

  test('a bean name of @ConditionalOnMissingBean completes', () {
    final offset = at("'clock'", 3);
    final names = [
      for (final item in workspace.completion(path, offset)!.items) item.label,
    ];
    expect(names, contains('clock'));
  });
}
