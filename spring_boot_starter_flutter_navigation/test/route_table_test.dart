// Locations, and the route table: the checks at the start (a path twice,
// a screen under two shells, an unknown shell, two not-found screens), the
// most specific pattern first, the place of each screen.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

Widget _screen(RouteState route) => const SizedBox();
Widget _shell(ShellState shell) => shell.child;

void main() {
  group('RouteLocation', () {
    test('a pattern with its variables, percent-encoded', () {
      final location = RouteLocation.expand(
        '/catalog/books/{isbn:\\d+}',
        pathVariables: {'isbn': 'a b'},
        params: {
          'page': 2,
          'tag': ['x', 'y'],
          'skip': null,
        },
      );
      expect(
        location.uri.toString(),
        '/catalog/books/a%20b?page=2&tag=x&tag=y',
      );
    });

    test('the rest of the path keeps its slashes', () {
      expect(
        RouteLocation.expand(
          '/docs/{*path}',
          pathVariables: {'path': '/core/beans'},
        ).path,
        '/docs/core/beans',
      );
    });

    test('a missing variable is named', () {
      expect(
        () => RouteLocation.expand('/books/{isbn}'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('"isbn"'),
          ),
        ),
      );
    });

    test('a link of the app scheme reads its host as the first segment', () {
      expect(
        RouteLocation.fromUri(Uri.parse('neonbooks://catalog/books/1?a=1')).uri
            .toString(),
        '/catalog/books/1?a=1',
      );
      expect(
        RouteLocation.fromUri(Uri.parse('https://books.test/catalog')).path,
        '/catalog',
      );
    });

    test('equal by address; the extra does not count', () {
      expect(
        RouteLocation('/a', extra: 1),
        RouteLocation.parse('/a', extra: 2),
      );
      expect(RouteLocation('/a', params: {'b': 1}), isNot(RouteLocation('/a')));
    });
  });

  group('RouteTable', () {
    test('the most specific pattern wins', () {
      final table = RouteTable([
        ScreenRoutes.route()
            .screen('/books/{id}', _screen)
            .screen('/books/new', _screen)
            .screen('/books/{*rest}', _screen)
            .build(),
      ]);
      expect(table.match('/books/new')!.$1.pattern.pattern, '/books/new');
      expect(table.match('/books/7')!.$1.pattern.pattern, '/books/{id}');
      expect(table.match('/books/7/x')!.$1.pattern.pattern, '/books/{*rest}');
      expect(table.match('/other'), isNull);
    });

    test('a path declared twice names both places', () {
      expect(
        () => RouteTable([
          ScreenRoutes.route(source: 'AppRoutes').screen('/a', _screen).build(),
          ScreenRoutes.route(source: 'AdminRoutes')
              .screen('/a', _screen)
              .build(),
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('AppRoutes'), contains('AdminRoutes')),
          ),
        ),
      );
    });

    test('a screen opens in the shell whose branch covers its path', () {
      final table = RouteTable([
        ScreenRoutes.route()
            .shell(
              _shell,
              (tabs) => tabs
                  .branch('/catalog', (b) => b.screen('/catalog', _screen))
                  .branch('/basket', (b) => b),
              key: 'tabs',
            )
            .screen('/catalog/books/{isbn}', _screen)
            .screen('/checkout', _screen)
            .build(),
      ]);
      final book = table.match('/catalog/books/1')!.$1;
      expect(table.placeOf(book)?.$1.key, 'tabs');
      expect(table.placeOf(book)?.$2, 0);
      expect(table.placeOf(table.match('/checkout')!.$1), isNull);
    });

    test('a screen under the branches of two shells stops the start', () {
      expect(
        () => RouteTable([
          ScreenRoutes.route()
              .shell(_shell, (t) => t.branch('/a', (b) => b), key: 1)
              .shell(_shell, (t) => t.branch('/a/b', (b) => b), key: 2)
              .screen('/a/b/c', _screen)
              .build(),
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('a screen naming an unknown shell stops the start', () {
      expect(
        () => RouteTable([
          ScreenRoutes.route().screen('/x', _screen, shell: 'nope').build(),
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not declared'),
          ),
        ),
      );
    });

    test('two not-found screens stop the start', () {
      expect(
        () => RouteTable([
          ScreenRoutes.route(source: 'one').notFound(_screen).build(),
          ScreenRoutes.route(source: 'two').notFound(_screen).build(),
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('a screen in a branch outside its path opens in that branch', () {
      final table = RouteTable([
        ScreenRoutes.route()
            .shell(
              _shell,
              (t) => t
                  .branch('/home', (b) => b.screen('/home', _screen))
                  .branch(
                    '/more',
                    (b) =>
                        b.screen('/more', _screen).screen('/motion', _screen),
                  ),
              key: 'tabs',
            )
            .screen('/zoom', _screen, branch: '/more')
            .build(),
      ]);
      for (final path in ['/motion', '/zoom']) {
        final screen = table.match(path)!.$1;
        expect(screen.branch, '/more', reason: path);
        expect(table.placeOf(screen)?.$1.key, 'tabs', reason: path);
        expect(table.placeOf(screen)?.$2, 1, reason: path);
      }
    });

    test('a branch no shell has stops the start, naming it', () {
      expect(
        () => RouteTable([
          ScreenRoutes.route()
              .screen('/motion', _screen, branch: '/more')
              .build(),
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('/motion'), contains('/more')),
          ),
        ),
      );
    });
  });
}
