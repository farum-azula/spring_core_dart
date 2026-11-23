// `this` in a security expression on a data repository: the generated
// repository, over a real store. The application is built, written out and
// run in its own process.
@TestOn('vm')
@Tags(['integration'])
library;

import 'package:test/test.dart';

import '../support/generated_app.dart';

const _pubspec = '''
name: pkg
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  spring_boot_starter_data: any
  spring_security_core: any
  sqlite3: any
''';

const _library = r'''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_security_core/spring_security_core.dart';

@Table('docs')
class Doc {
  Doc({this.id, required this.owner, required this.title});

  @Id()
  int? id;

  String owner;
  String title;
}

@Repository()
abstract interface class DocRepository implements ListCrudRepository<Doc, int> {
  @PreAuthorize('this.findByOwner(#title) != null')
  Future<List<Doc>> findByTitle(String title);

  @PreAuthorize('this.existsById(1) != false')
  Future<List<Doc>> findByOwner(String owner);

  @PreAuthorize('this.nothing == 1')
  Future<int> countByOwner(String owner);

  @PreAuthorize('this.count() != null')
  Future<int> countByTitle(String title);

  @PreAuthorize('#root.this != null and #owner == authentication.name')
  Future<List<Doc>> findByOwnerAndTitle(String owner, String title);

  @PostAuthorize('this != null and returnObject.owner == authentication.name')
  Future<Doc?> findFirstByTitle(String title);

  @PreAuthorize('#owner == authentication.name and this != null')
  Future<int> deleteByOwner(String owner);

  @PreAuthorize("this.ownedBy('ada') != null")
  @Query('select * from docs where id = :id')
  Future<List<Doc>> byId(int id);

  @PreAuthorize('#root.this != null and #owner == authentication.name')
  @Query('select * from docs where owner = :owner')
  Future<List<Doc>> ownedBy(String owner);

  @PostFilter('this != null and filterObject.owner == authentication.name')
  @Query('select * from docs')
  Future<List<Doc>> visible();
}
''';

const _main = r'''
import 'dart:convert';
import 'dart:io';

import 'package:pkg/app.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/spring_security_core.dart';

import 'spring_gen/main.spring.dart';

Future<String> call(Future<Object?> Function() body) async {
  try {
    final value = await body();
    return switch (value) {
      List() => 'rows:${value.length}',
      Doc() => 'doc',
      _ => 'value:$value',
    };
  } on AuthorizationDeniedException {
    return 'denied';
  } on ArgumentError catch (e) {
    return '$e'.contains('asynchronous') ? 'refused:async' : 'refused';
  } on Object catch (e) {
    return 'error:${e.runtimeType}:$e';
  }
}

Future<T> as<T>(String name, Future<T> Function() body) {
  final user = User.withUsername(name).password(null).roles(['USER']).build();
  return SecurityContextHolder.runWithContext(
    body,
    SecurityContextImpl(
      UsernamePasswordAuthenticationToken.authenticated(
        user,
        null,
        user.authorities,
      ),
    ),
  );
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final database = await Directory.systemTemp.createTemp('spring_this_db_');
  final context = await runApplicationAsync([
    '--spring.main.banner-mode=off',
    '--logging.level.root=off',
    '--spring.main.web-application-type=none',
    '--spring.datasource.url=sqlite:file:${database.path}/docs.db',
    '--spring.data.jdbc.schema=create',
    ...args,
  ]);
  final docs = context.getBean<DocRepository>();
  await docs.save(Doc(owner: 'ada', title: 'a'));
  Future<Map<String, String>> all() async => {
    'ownMethod': await call(() => docs.findByTitle('a')),
    'inheritedMethod': await call(() => docs.findByOwner('ada')),
    'unreadable': await call(() => docs.countByOwner('ada')),
    'inheritedNotNull': await call(() => docs.countByTitle('a')),
    'derived': await call(() => docs.findByOwnerAndTitle('ada', 'a')),
    'postAuthorize': await call(() => docs.findFirstByTitle('a')),
    'queryOwnMethod': await call(() => docs.byId(1)),
    'query': await call(() => docs.ownedBy('ada')),
    'postFilter': await call(docs.visible),
  };
  final bob = await as('bob', all);
  final bobDelete = await as('bob', () => call(() => docs.deleteByOwner('ada')));
  final afterBob = (await docs.findAll()).length;
  final ada = await as('ada', all);
  final adaDelete = await as('ada', () => call(() => docs.deleteByOwner('ada')));
  final afterAda = (await docs.findAll()).length;
  print('RESULT ${jsonEncode({
    'ada': {...ada, 'delete': adaDelete, 'rowsAfter': afterAda},
    'bob': {...bob, 'delete': bobDelete, 'rowsAfter': afterBob},
  })}');
  context.close();
  await database.delete(recursive: true);
  exit(0);
}
''';

void main() {
  test('this on a repository: allow, deny and refuse for two users', () async {
    const refused = {
      'ownMethod': 'refused:async',
      'inheritedMethod': 'refused',
      'unreadable': 'refused',
      'inheritedNotNull': 'refused',
      'queryOwnMethod': 'refused:async',
    };
    expect(
      await runGeneratedApp({
        'pubspec.yaml': _pubspec,
        'lib/app.dart': _library,
        'bin/main.dart': _main,
      }, sqlite: true),
      {
        'ada': {
          ...refused,
          'derived': 'rows:1',
          'postAuthorize': 'doc',
          'query': 'rows:1',
          'postFilter': 'rows:1',
          'delete': 'value:1',
          'rowsAfter': 0,
        },
        'bob': {
          ...refused,
          'derived': 'denied',
          'postAuthorize': 'denied',
          'query': 'denied',
          'postFilter': 'rows:0',
          'delete': 'denied',
          'rowsAfter': 1,
        },
      },
    );
  }, timeout: const Timeout(Duration(minutes: 25)));
}
