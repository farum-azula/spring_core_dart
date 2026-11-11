// lib/spring_gen/spring_metadata.json: properties, beans, profiles, hints.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_metadata_builder.dart';
import 'package:test/test.dart';

const _header = '''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
''';

/// Runs the builder over `sources` (paths below `pkg|`); returns the JSON
/// and the log lines. `null` JSON: nothing was written.
typedef _Run = ({Map<String, Object?>? json, String? text, List<String> logs});

Future<_Run> _run(
  Map<String, Object> sources, {
  String package = 'pkg',
}) async {
  final logs = <String>[];
  final readerWriter = TestReaderWriter(
    rootPackage: package,
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringMetadataBuilder(
      packageDirectories: PackageDirectories(),
    ),
    {for (final e in sources.entries) '$package|${e.key}': e.value},
    rootPackage: package,
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (r) => logs.add('${r.level.name}: ${r.message}'),
  );
  expect(result.errors, isEmpty);
  final id = AssetId(package, 'lib/spring_gen/spring_metadata.json');
  if (!await readerWriter.canRead(id)) {
    return (json: null, text: null, logs: logs);
  }
  final text = readerWriter.testing.readString(id);
  return (
    json: jsonDecode(text) as Map<String, Object?>,
    text: text,
    logs: logs,
  );
}

List<Map<String, Object?>> _list(Map<String, Object?> json, String key) => [
  for (final e in json[key]! as List) e as Map<String, Object?>,
];

Map<String, Object?> _named(
  Map<String, Object?> json,
  String key,
  String name,
) => _list(json, key).firstWhere((e) => e['name'] == name);

const _properties =
    '''
$_header
enum Mode {
  /// Fast and loose.
  fastMode,
  slow,
}

class Pool {
  /// How many connections.
  int size = 4;
  Mode mode = Mode.slow;
}

class Route {
  String path = '/';
}

/// Settings of the shop.
@ConfigurationProperties('app.shop')
class ShopProperties {
  /// The name shown in the title bar.
  String displayName = 'Shop';

  /// Maximum of items.
  int maxItems = 10;

  double rate = 1.5;
  bool open = true;
  Duration timeout = const Duration(seconds: 3);
  Mode mode = Mode.fastMode;

  @Deprecated('Use displayName.')
  String title = '';

  List<String> tags = [];
  Map<String, String> labels = {};
  Pool pool = Pool();
  List<Route> routes = [];
  Map<String, Route> byHost = {};

  final String fixed = 'x';
}

@ConfigurationProperties('db')
class DbProperties {
  const DbProperties(this.url, {this.maxSize = 10});

  /// The URL of the database.
  final String url;
  final int maxSize;
}
''';

void main() {
  group('properties', () {
    late Map<String, Object?> json;

    setUpAll(() async {
      json = (await _run({'lib/shop.dart': _properties})).json!;
    });

    test('names are kebab case under the prefix, with type and docs', () {
      final property = _named(json, 'properties', 'app.shop.display-name');
      expect(property['type'], 'String');
      expect(property['description'], 'The name shown in the title bar.');
      expect(property['default'], 'Shop');
      expect(property['deprecated'], isNull);
      expect(property['source'], 'package:pkg/shop.dart');
      expect(property['class'], 'ShopProperties');
      expect(property['line'], isA<int>());
    });

    test('literal defaults', () {
      Object? default_(String name) =>
          _named(json, 'properties', 'app.shop.$name')['default'];
      expect(default_('max-items'), 10);
      expect(default_('rate'), 1.5);
      expect(default_('open'), true);
      expect(default_('timeout'), '3s');
      expect(default_('mode'), 'fast-mode');
      expect(default_('tags'), <Object?>[]);
    });

    test('@Deprecated gives the message', () {
      expect(
        _named(json, 'properties', 'app.shop.title')['deprecated'],
        'Use displayName.',
      );
    });

    test('nested classes, lists and maps', () {
      final names = [for (final p in _list(json, 'properties')) p['name']];
      expect(
        names,
        containsAll([
          'app.shop.pool.size',
          'app.shop.pool.mode',
          'app.shop.routes[*].path',
          'app.shop.by-host.*.path',
          'app.shop.tags',
          'app.shop.labels.*',
        ]),
      );
      // A map of plain values is described by its entries; a list of plain
      // values stays one property (a comma list binds there).
      expect(_named(json, 'properties', 'app.shop.labels.*')['type'], 'String');
      expect(names, isNot(contains('app.shop.labels')));
      expect(
        _named(json, 'properties', 'app.shop.tags')['type'],
        'List<String>',
      );
      // Final fields are not bound.
      expect(names, isNot(contains('app.shop.fixed')));
    });

    test('constructor binding reads the parameters', () {
      final url = _named(json, 'properties', 'db.url');
      expect(url['description'], 'The URL of the database.');
      expect(_named(json, 'properties', 'db.max-size')['default'], 10);
    });

    test('enum properties get hints with the constants', () {
      final hint = _named(json, 'hints', 'app.shop.mode');
      expect(hint['values'], [
        {'value': 'fast-mode', 'description': 'Fast and loose.'},
        {'value': 'slow', 'description': null},
      ]);
      expect(
        _list(json, 'hints').map((h) => h['name']),
        contains('app.shop.pool.mode'),
      );
    });

    test('properties are sorted by name', () {
      final names = [for (final p in _list(json, 'properties')) '${p['name']}'];
      expect(names, [...names]..sort());
    });
  });

  group('beans', () {
    const beans =
        '''
$_header
abstract class Catalog {}

@Service()
class DbCatalog implements Catalog {
  final List<String> titles = [];
  double get total => 0;
  void add(String title, {int count = 1}) {}
  void drop([int? index]) {}
  String _hidden() => '';
}

@Component()
@Primary()
@Profile(['!test', 'dev'])
@Scope('prototype')
@Qualifier('main')
@ConditionalOnProperty('app.basket.enabled')
class Basket {
  Basket(this.catalog, @Qualifier('special') this.other);
  final Catalog catalog;
  final Catalog other;
}

@Configuration()
class Config {
  @Bean()
  @Profile(['prod'])
  Clock clock() => Clock();
}

class Clock {}
''';

    late Map<String, Object?> json;

    setUpAll(() async {
      json = (await _run({'lib/beans.dart': beans})).json!;
    });

    test('a component lists its types, scope, profiles and conditions', () {
      final bean = _named(json, 'beans', 'basket');
      expect(bean['type'], 'Basket');
      expect(bean['types'], ['Basket']);
      expect(bean['scope'], 'prototype');
      expect(bean['primary'], true);
      expect(bean['qualifiers'], ['main']);
      expect(bean['profiles'], ['!test', 'dev']);
      expect(bean['conditions'], [
        "@ConditionalOnProperty('app.basket.enabled')",
      ]);
      expect(bean['source'], 'package:pkg/beans.dart');
      expect(bean['line'], isA<int>());
    });

    test('all assignable types', () {
      expect(_named(json, 'beans', 'dbCatalog')['types'], [
        'DbCatalog',
        'Catalog',
      ]);
    });

    test('injection points', () {
      expect(_named(json, 'beans', 'basket')['injects'], [
        {'parameter': 'catalog', 'type': 'Catalog', 'qualifier': null},
        {'parameter': 'other', 'type': 'Catalog', 'qualifier': 'special'},
      ]);
    });

    test('a @Bean method is a bean', () {
      final bean = _named(json, 'beans', 'clock');
      expect(bean['type'], 'Clock');
      expect(bean['profiles'], ['prod']);
    });

    test('members: getters, fields and methods with parameters', () {
      final members = {
        for (final m in _list(_named(json, 'beans', 'dbCatalog'), 'members'))
          m['name']: m,
      };
      expect(members['total'], {
        'name': 'total',
        'kind': 'getter',
        'type': 'double',
      });
      expect(members['titles']!['kind'], 'field');
      expect(members['add'], {
        'name': 'add',
        'kind': 'method',
        'type': 'void',
        'parameters': ['String title', '{int count}'],
      });
      expect(members['drop']!['parameters'], ['[int? index]']);
      expect(members, isNot(contains('_hidden')));
      expect(members, isNot(contains('hashCode')));
    });

    test('profiles are collected from the beans', () {
      expect(json['profiles'], ['dev', 'prod', 'test']);
    });
  });

  group('profiles from files', () {
    test('application-<profile> files name profiles', () async {
      final result = await _run({
        'lib/a.dart': '$_header\n@Component()\nclass A {}\n',
        'lib/resources/application.yml': 'a: 1',
        'lib/resources/application-cloud.yml': 'a: 2',
        'lib/resources/application-local.properties': 'a=3',
      });
      expect(result.json!['profiles'], ['cloud', 'local']);
    });
  });

  group('hand-written BeanDefinitions', () {
    test('an auto-configuration is read with types and conditions', () async {
      final result = await _run({
        'lib/auto.dart': '''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

abstract class Engine {}
class Diesel implements Engine {}

const _on = [
  ConditionGroup('pkg#Auto', [
    ConditionalOnProperty('engine.enabled', matchIfMissing: true),
  ]),
];

final auto = <BeanDefinition<Object>>[
  BeanDefinition<Diesel>(
    name: 'diesel',
    source: 'pkg#Auto',
    primary: true,
    qualifiers: {'main'},
    conditions: _on,
    create: (_) => Diesel(),
  ),
];
''',
      });
      final bean = _named(result.json!, 'beans', 'diesel');
      expect(bean['types'], ['Diesel', 'Engine']);
      expect(bean['primary'], true);
      expect(bean['qualifiers'], ['main']);
      expect(bean['scope'], 'singleton');
      expect(bean['conditions'], [
        "@ConditionalOnProperty('engine.enabled', matchIfMissing: true)",
      ]);
      expect(bean['source'], 'package:pkg/auto.dart');
    });
  });

  group('annotations', () {
    test('@Range, @WarnValues and @PropertyValues make hint parts', () async {
      final result = await _run({
        'lib/tls.dart':
            '''
$_header
enum Tls {
  /// Checks certificates.
  verify,

  /// Skips the checks.
  insecureMode,
}

@ConfigurationProperties('net')
class NetProperties {
  /// The port.
  @Range(0, 65535)
  @WarnValues([22, 25], 'Blocked by browsers.')
  int port = 80;

  Tls tls = Tls.verify;

  /// A pattern flavour.
  @PropertyValues(['plain', 'json'])
  String format = 'plain';

  @WarnValues([Tls.insecureMode], 'No certificate checks.')
  Tls fallback = Tls.verify;

  Map<String, Tls> perHost = {};

  @Range(1, 9)
  List<int> levels = [];
}
''',
      });
      final json = result.json!;
      expect(_named(json, 'hints', 'net.port'), {
        'name': 'net.port',
        'range': [0, 65535],
        'warn': [
          {
            'values': [22, 25],
            'message': 'Blocked by browsers.',
          },
        ],
      });
      expect(_named(json, 'hints', 'net.tls')['values'], [
        {'value': 'verify', 'description': 'Checks certificates.'},
        {'value': 'insecure-mode', 'description': 'Skips the checks.'},
      ]);
      expect(_named(json, 'hints', 'net.format')['values'], [
        {'value': 'plain', 'description': null},
        {'value': 'json', 'description': null},
      ]);
      expect(_named(json, 'hints', 'net.fallback')['warn'], [
        {
          'values': ['insecure-mode'],
          'message': 'No certificate checks.',
        },
      ]);
      expect(_named(json, 'hints', 'net.per-host.*')['values'], hasLength(2));
      expect(_named(json, 'hints', 'net.levels[*]')['range'], [1, 9]);
    });

    test('a hand-written additional file is not read', () async {
      final result = await _run({
        'lib/shop.dart': _properties,
        'spring_metadata_additional.json': jsonEncode({
          'properties': [
            {'name': 'by.hand', 'type': 'String'},
          ],
        }),
      });
      final names = [
        for (final p in _list(result.json!, 'properties')) p['name'],
      ];
      expect(names, isNot(contains('by.hand')));
    });
  });

  group('format', () {
    test('nothing is written for a package without Spring code', () async {
      final result = await _run({'lib/a.dart': 'class A {}'});
      expect(result.json, isNull);
    });

    test(
      'top-level keys in order, version 1, pretty and deterministic',
      () async {
        final sources = {'lib/shop.dart': _properties};
        final first = await _run(sources);
        final second = await _run(sources);
        expect(first.text, second.text);
        expect(first.json!.keys, [
          'version',
          'package',
          'properties',
          'hints',
          'beans',
          'profiles',
        ]);
        expect(first.json!['version'], 1);
        expect(first.json!['package'], 'pkg');
        expect(
          first.text,
          startsWith('{\n  "version": 1,\n  "package": "pkg",'),
        );
        expect(first.text, endsWith('}\n'));
      },
    );

    test('a property has the keys of the contract in order', () async {
      final result = await _run({'lib/shop.dart': _properties});
      expect(_list(result.json!, 'properties').first.keys, [
        'name',
        'type',
        'description',
        'default',
        'deprecated',
        'source',
        'line',
        'class',
      ]);
    });
  });

  group('data layer', () {
    const source = '''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

@Service()
class Marker {}

@Table('authors')
class Author {
  Author({required this.name, this.id});

  @Id()
  int? id;
  String name;
}

/// A book.
@Table('books')
class Book {
  Book({
    required this.title,
    required this.year,
    this.id,
    this.author,
    this.authorId,
    this.note = '',
  });

  @Id()
  int? id;
  String title;
  int year;
  AggregateReference<Author, int>? author;

  @Reference(Author)
  int? authorId;

  @Column('remark')
  String note;
}

class BookCard {
  const BookCard({required this.title});
  final String title;
}

abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {
  Future<List<Book>> findByTitleAndYearGreaterThan(String title, int year);

  @Query('select {Book.title} as title from {Book} where {Book.year} >= :year')
  Future<List<BookCard>> cards(int year);
}
''';

    late Map<String, Object?> json;

    setUpAll(() async {
      json = (await _run({'lib/shop.dart': source})).json!;
    });

    test('an entity lists its table, id and properties', () {
      final book = _list(json, 'entities').firstWhere(
        (e) => e['class'] == 'Book',
      );
      expect(book.keys, [
        'class',
        'table',
        'source',
        'line',
        'id',
        'properties',
      ]);
      expect(book['table'], 'books');
      expect(book['id'], 'id');
      expect(book['source'], 'package:pkg/shop.dart');
      expect(book['line'], isA<int>());
      final properties = [
        for (final p in book['properties']! as List) p as Map<String, Object?>,
      ];
      expect(
        [for (final p in properties) p['name']],
        [
          'id',
          'title',
          'year',
          'author',
          'authorId',
          'note',
        ],
      );
      Map<String, Object?> property(String name) =>
          properties.firstWhere((p) => p['name'] == name);
      expect(property('authorId')['column'], 'author_id');
      expect(property('note')['column'], 'remark');
      expect(property('title')['type'], 'String');
      expect(property('year')['line'], isA<int>());
    });

    test('references name the entity and the id type', () {
      final book = _list(json, 'entities').firstWhere(
        (e) => e['class'] == 'Book',
      );
      final properties = [
        for (final p in book['properties']! as List) p as Map<String, Object?>,
      ];
      Object? relation(String name) =>
          properties.firstWhere((p) => p['name'] == name)['relation'];
      expect(relation('author'), {'entity': 'Author', 'id': 'int'});
      expect(relation('authorId'), {'entity': 'Author', 'id': 'int'});
      expect(relation('title'), isNull);
    });

    test('an entity uses its @Table name, a DTO is no entity', () {
      final entities = _list(json, 'entities');
      expect([for (final e in entities) e['class']], ['Author', 'Book']);
      expect(entities.first['table'], 'authors');
    });

    test('a repository lists its entity, id and methods', () {
      final repository = _list(json, 'repositories').single;
      expect(repository['name'], 'BookRepository');
      expect(repository['entity'], 'Book');
      expect(repository['id'], 'int');
      final methods = [
        for (final m in repository['methods']! as List)
          m as Map<String, Object?>,
      ];
      expect(
        [for (final m in methods) '${m['name']}:${m['kind']}'],
        [
          'findByTitleAndYearGreaterThan:derived',
          'cards:query',
        ],
      );
      final cards = methods.last;
      expect(cards['query'], contains('{Book.year}'));
      expect(cards['parameters'], [
        {'name': 'year', 'type': 'int'},
      ]);
      expect(cards['line'], isA<int>());
    });

    test('a package without a data layer has neither key', () async {
      final result = await _run({'lib/shop.dart': _properties});
      expect(result.json!.containsKey('entities'), isFalse);
      expect(result.json!.containsKey('repositories'), isFalse);
    });
  });

  group('keys read without @ConfigurationProperties', () {
    const source =
        '''
$_header
/// The shop's mailer.
@Component()
class Mailer {
  Mailer(@Value(r'\${mail.host:localhost}') String host);

  /// The sender shown on mails.
  @Value(r'\${mail.sender}')
  late String sender;
}

/// Sends the newsletter.
@Component()
@ConditionalOnProperty('shop.newsletter.enabled')
class Newsletter {}

@Component()
@ConditionalOnBooleanProperty.names(['a', 'b'], prefix: 'shop.flags')
class Flags {}

@ConfigurationProperties('mail')
class MailProperties {
  /// Bound by the class, so this description wins.
  String host = 'smtp';
}
''';

    late Map<String, Object?> json;

    setUpAll(() async {
      json = (await _run({'lib/mail.dart': source})).json!;
    });

    test('@Value placeholders become String properties', () {
      final sender = _named(json, 'properties', 'mail.sender');
      expect(sender['type'], 'String');
      expect(sender['description'], isNull);
      expect(sender['class'], 'Mailer');
    });

    test('a key bound by a class keeps the class description', () {
      final names = [for (final p in _list(json, 'properties')) p['name']];
      expect(names, contains('mail.host'));
      // `mail.host` is bound by MailProperties, which wins.
      expect(
        _named(json, 'properties', 'mail.host')['description'],
        'Bound by the class, so this description wins.',
      );
    });

    test('@ConditionalOnProperty names, without a description', () {
      final property = _named(json, 'properties', 'shop.newsletter.enabled');
      expect(property['type'], 'String');
      expect(property['description'], isNull);
    });

    test('the boolean condition gives bool and applies the prefix', () {
      expect(_named(json, 'properties', 'shop.flags.a')['type'], 'bool');
      expect(_named(json, 'properties', 'shop.flags.b')['type'], 'bool');
    });
  });

  group('theme', () {
    test('only the Flutter starter embeds tool/theme_metadata.json', () async {
      final theme = jsonEncode({
        'types': {
          'color': {'kind': 'color'},
        },
        'properties': [
          {'name': 'components.app-bar.background-color', 'type': 'color'},
        ],
        'ignored': 1,
      });
      final starter = await _run({
        'lib/a.dart': _properties,
        'tool/theme_metadata.json': theme,
      }, package: 'spring_boot_starter_flutter');
      expect(starter.json!['theme'], {
        'types': {
          'color': {'kind': 'color'},
        },
        'properties': [
          {'name': 'components.app-bar.background-color', 'type': 'color'},
        ],
      });
      final other = await _run({
        'lib/a.dart': _properties,
        'tool/theme_metadata.json': theme,
      });
      expect(other.json!.containsKey('theme'), isFalse);
    });
  });

  group('loader kinds', () {
    test('the @ThemeLoaderKind classes and the keys the themes give', () async {
      final result = await _run({
        'lib/loaders/doors.dart':
            '''
$_header
class ThemeLoaderKind {
  const ThemeLoaderKind(this.name);
  final String name;
}

@ThemeLoaderKind('doors')
final class DoorsLoader {}
''',
        'lib/resources/application.yaml': '''
spring.flutter.theme:
  loaders:
    neon-doors: { kind: doors, door: { color: red }, seam: { width: 1 }, web: x }
''',
      });
      final kinds = _list(result.json!, 'loaderKinds');
      expect(kinds, [
        {
          'name': 'doors',
          'class': 'DoorsLoader',
          'source': 'package:pkg/loaders/doors.dart',
          'line': 9,
          'props': ['door', 'seam'],
        },
      ]);
    });

    test('a kind of bin/ names its file as the beans of bin/ do', () async {
      final result = await _run({
        'bin/main.dart':
            '''
$_header
class ThemeLoaderKind {
  const ThemeLoaderKind(this.name);
  final String name;
}

@ThemeLoaderKind('doors')
final class DoorsLoader {}

@Component()
class Shop {}
''',
      });
      final kind = _list(result.json!, 'loaderKinds').single;
      expect(kind['source'], 'bin/main.dart');
      expect(_named(result.json!, 'beans', 'shop')['source'], 'bin/main.dart');
    });

    test('a package without loader kinds has no entry', () async {
      final result = await _run({'lib/shop.dart': _properties});
      expect(result.json!.containsKey('loaderKinds'), isFalse);
    });
  });
}
