// The screens of spring_boot_starter_flutter_navigation in the editor: the
// paths of the metadata's routes completed in `go('/...')`, `push`,
// `redirect`, and an address no screen has underlined; a path (an address,
// a shell's branch, a config value) goes to its screen; `#{key}` in a title
// or description is a message key.
import 'dart:convert';
import 'dart:io';

import 'package:dart_spring_language_server/src/config_editor.dart';
import 'package:dart_spring_language_server/src/metadata.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

import 'support/editor_fixture.dart';

void main() {
  late EditorFixture fixture;

  setUp(() {
    fixture = EditorFixture.create();
    File(fixture.app('lib/spring_gen/spring_metadata.json')).writeAsStringSync(
      jsonEncode({
        'package': 'app',
        'routes': [
          {'path': '/catalog', 'name': 'catalog', 'class': 'CatalogPage'},
          {
            'path': '/catalog/books/{isbn}',
            'name': 'book',
            'class': 'BookPage',
            'title': 'Book',
          },
          {'path': '/docs/{*path}', 'name': 'doc', 'class': 'DocPage'},
        ],
      }),
    );
    fixture.workspace.refresh(force: true);
  });
  tearDown(() => fixture.dispose());

  const code = '''
void open(dynamic route) {
  route.go('/catalog/books/1');
  route.push('/docs/core/beans?x=1');
  route.go('/nowhere');
  route.go('/catalog/books/{isbn}', pathVariables: {'isbn': '1'});
  route.go('/c');
  other('/nowhere');
}
''';

  test('the paths of the screens are completed', () {
    final path = fixture.open('lib/open.dart', code);
    final result = fixture.workspace.completion(path, at(code, "'/c|'"));
    expect(
      [for (final item in result?.items ?? const <Completion>[]) item.label],
      ['/catalog', '/catalog/books/{isbn}', '/docs/{*path}'],
    );
  });

  test('an address no screen has is underlined', () {
    final path = fixture.open('lib/open.dart', code);
    expect(
      [
        for (final problem in fixture.workspace.problems(path))
          if (problem.message.contains('No screen')) problem.message,
      ],
      [
        "No screen has the address '/nowhere' (@ScreenRoute or ScreenRoutes)",
        "No screen has the address '/c' (@ScreenRoute or ScreenRoutes)",
      ],
    );
  });

  test('a route matches its addresses', () {
    const book = MetaRoute(path: '/catalog/books/{isbn}');
    expect(book.matches('/catalog/books/978-0'), isTrue);
    expect(book.matches('/catalog/books/978-0/x'), isFalse);
    expect(const MetaRoute(path: '/docs/{*path}').matches('/docs/a/b'), isTrue);
  });

  group('paths go to their screens', () {
    const screens = '''
@ScreenRoute('/catalog', title: '#{nav.catalog}')
class CatalogPage {}

@ScreenRoute('/catalog/books/{isbn}')
@RouteInfo(paths: ['/catalog/books/1'], description: '#{nav.missing}')
class BookPage {}

@RouteShell(branches: <String>['/catalog', '/settings'])
class Shell {}

@ScreenRoute('/motion', branch: '/catalog')
class MotionPage {}

@ScreenRoute('/lost', branch: '/nowhere')
class LostPage {}

void open(dynamic route) {
  route.go('/catalog/books/978-0?page=2');
  route.go('/catalog/books/{isbn}', pathVariables: {'isbn': '1'});
}
''';

    String classAt(SourceRange range) {
      final lines = File(range.path).readAsLinesSync();
      return lines[range.startLine].substring(
        range.startColumn,
        range.endColumn,
      );
    }

    late String path;
    setUp(() {
      File(fixture.app('lib/resources/messages.properties'))
        ..createSync(recursive: true)
        ..writeAsStringSync('nav.catalog=Catalog\nnav.settings=Settings\n');
      path = fixture.open('lib/screens.dart', screens);
    });

    test('the branch of @ScreenRoute(branch:) goes to its screen', () {
      final found = fixture.workspace.definition(
        path,
        at(screens, "branch: '/cat|alog'"),
      );
      expect(found.map(classAt), ['CatalogPage']);
    });

    test('a branch no @RouteShell has is underlined', () {
      File(
        fixture.app('lib/spring_gen/spring_metadata.json'),
      ).writeAsStringSync(
        jsonEncode({
          'package': 'app',
          'routes': [
            {'path': '/catalog', 'class': 'CatalogPage'},
            {'path': '/motion', 'class': 'MotionPage', 'branch': '/catalog'},
          ],
          'shells': [
            {
              'class': 'Shell',
              'branches': ['/catalog', '/settings'],
            },
          ],
        }),
      );
      fixture.workspace.refresh(force: true);
      expect(
        [
          for (final problem in fixture.workspace.problems(path))
            if (problem.message.contains('@RouteShell has')) problem.message,
        ],
        [
          "No @RouteShell has the branch '/nowhere' (branches: /catalog, /settings)",
        ],
      );
    });

    test('a branch of @RouteShell', () {
      final found = fixture.workspace.definition(
        path,
        at(screens, "['/cat|alog'"),
      );
      expect(found.map(classAt), ['CatalogPage']);
    });

    test('an address with a variable and a query, and a pattern', () {
      expect(
        fixture.workspace
            .definition(path, at(screens, "go('/catalog/books/97|8"))
            .map(classAt),
        ['BookPage'],
      );
      expect(
        fixture.workspace
            .definition(path, at(screens, "go('/catalog/books/{is|bn}'"))
            .map(classAt),
        ['BookPage'],
      );
    });

    test('a path of @RouteInfo(paths:)', () {
      expect(
        fixture.workspace
            .definition(path, at(screens, "paths: ['/catalog/bo|oks/1'"))
            .map(classAt),
        ['BookPage'],
      );
    });

    test('a branch no screen has is underlined', () {
      expect(
        [
          for (final problem in fixture.workspace.problems(path))
            if (problem.message.contains('No screen')) problem.message,
        ],
        ["No screen has the address '/settings' (@ScreenRoute or ScreenRoutes)"],
      );
    });

    test('spring.flutter.navigation.initial goes to its screen', () {
      const properties = 'spring.flutter.navigation.initial=/catalog\n';
      final config = fixture.open(
        'lib/resources/application.properties',
        properties,
      );
      final found = fixture.workspace.definition(
        config,
        at(properties, '=/cat|alog'),
      );
      expect(found.map(classAt), ['CatalogPage']);
    });

    test('a redirect target in YAML goes to its screen', () {
      const yaml = '''
spring:
  flutter:
    navigation:
      redirects:
        '[/home]': /catalog
''';
      final config = fixture.open('lib/resources/application.yml', yaml);
      expect(
        fixture.workspace
            .definition(config, at(yaml, ': /cata|log'))
            .map(classAt),
        ['CatalogPage'],
      );
    });

    test('#{key} of a title goes to the message and is hovered', () {
      final found = fixture.workspace.definition(
        path,
        at(screens, "'#{nav.cat|alog}'"),
      );
      expect(found.single.path, endsWith('messages.properties'));
      expect(
        fixture.workspace.hover(path, at(screens, "'#{nav.cat|alog}'")),
        allOf(contains('(message)'), contains('Catalog')),
      );
    });

    test('an unknown key is reported, and no SpEL error', () {
      final messages = [
        for (final problem in fixture.workspace.problems(path)) problem.message,
      ];
      expect(
        messages.where((m) => m.startsWith('No message')),
        [startsWith("No message 'nav.missing' in the message bundles")],
      );
      expect(messages.where((m) => m.contains('nav.catalog')), isEmpty);
    });

    test('#{key} of a @RouteInfo description goes to the message', () {
      File(fixture.app('lib/resources/messages.properties'))
          .writeAsStringSync('nav.catalog=Catalog\nnav.missing=Book\n');
      final reopened = fixture.open('lib/screens.dart', screens);
      final found = fixture.workspace.definition(
        reopened,
        at(screens, "'#{nav.mis|sing}'"),
      );
      expect(found.single.path, endsWith('messages.properties'));
    });

    test('the keys are completed after #{', () {
      const typing = '''
@ScreenRoute('/x', title: '#{nav.')
class X {}
''';
      final typed = fixture.open('lib/typing.dart', typing);
      final result = fixture.workspace.completion(
        typed,
        at(typing, "'#{nav.|'"),
      );
      expect(
        [for (final item in result?.items ?? const <Completion>[]) item.label],
        ['nav.catalog', 'nav.settings'],
      );
    });
  });
}
