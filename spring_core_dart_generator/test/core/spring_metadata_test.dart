// lib/spring_gen/spring_metadata.json: properties, beans, profiles, hints.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../support/spring_metadata.dart';

void main() {
  group('properties', () {
    late Map<String, Object?> json;

    setUpAll(() async {
      json = (await runMetadataBuilder({'lib/shop.dart': shopProperties}))
          .json!;
    });

    test('names are kebab case under the prefix, with type and docs', () {
      final property = namedEntry(json, 'properties', 'app.shop.display-name');
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
          namedEntry(json, 'properties', 'app.shop.$name')['default'];
      expect(default_('max-items'), 10);
      expect(default_('rate'), 1.5);
      expect(default_('open'), true);
      expect(default_('timeout'), '3s');
      expect(default_('mode'), 'fast-mode');
      expect(default_('tags'), <Object?>[]);
    });

    test('@Deprecated gives the message', () {
      expect(
        namedEntry(json, 'properties', 'app.shop.title')['deprecated'],
        'Use displayName.',
      );
    });

    test('nested classes, lists and maps', () {
      final names = [for (final p in entriesOf(json, 'properties')) p['name']];
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
      expect(
        namedEntry(json, 'properties', 'app.shop.labels.*')['type'],
        'String',
      );
      expect(names, isNot(contains('app.shop.labels')));
      expect(
        namedEntry(json, 'properties', 'app.shop.tags')['type'],
        'List<String>',
      );
      // Final fields are not bound.
      expect(names, isNot(contains('app.shop.fixed')));
    });

    test('constructor binding reads the parameters', () {
      final url = namedEntry(json, 'properties', 'db.url');
      expect(url['description'], 'The URL of the database.');
      expect(namedEntry(json, 'properties', 'db.max-size')['default'], 10);
    });

    test('enum properties get hints with the constants', () {
      final hint = namedEntry(json, 'hints', 'app.shop.mode');
      expect(hint['values'], [
        {'value': 'fast-mode', 'description': 'Fast and loose.'},
        {'value': 'slow', 'description': null},
      ]);
      expect(
        entriesOf(json, 'hints').map((h) => h['name']),
        contains('app.shop.pool.mode'),
      );
    });

    test('properties are sorted by name', () {
      final names = [
        for (final p in entriesOf(json, 'properties')) '${p['name']}',
      ];
      expect(names, [...names]..sort());
    });
  });

  group('beans', () {
    const beans =
        '''
$metadataHeader
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
      json = (await runMetadataBuilder({'lib/beans.dart': beans})).json!;
    });

    test('a component lists its types, scope, profiles and conditions', () {
      final bean = namedEntry(json, 'beans', 'basket');
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
      expect(namedEntry(json, 'beans', 'dbCatalog')['types'], [
        'DbCatalog',
        'Catalog',
      ]);
    });

    test('injection points', () {
      expect(namedEntry(json, 'beans', 'basket')['injects'], [
        {'parameter': 'catalog', 'type': 'Catalog', 'qualifier': null},
        {'parameter': 'other', 'type': 'Catalog', 'qualifier': 'special'},
      ]);
    });

    test('a @Bean method is a bean', () {
      final bean = namedEntry(json, 'beans', 'clock');
      expect(bean['type'], 'Clock');
      expect(bean['profiles'], ['prod']);
    });

    test('members: getters, fields and methods with parameters', () {
      final members = {
        for (final m in entriesOf(
          namedEntry(json, 'beans', 'dbCatalog'),
          'members',
        ))
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
      final result = await runMetadataBuilder({
        'lib/a.dart': '$metadataHeader\n@Component()\nclass A {}\n',
        'lib/resources/application.yml': 'a: 1',
        'lib/resources/application-cloud.yml': 'a: 2',
        'lib/resources/application-local.properties': 'a=3',
      });
      expect(result.json!['profiles'], ['cloud', 'local']);
    });
  });

  group('hand-written BeanDefinitions', () {
    test('an auto-configuration is read with types and conditions', () async {
      final result = await runMetadataBuilder({
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
      final bean = namedEntry(result.json!, 'beans', 'diesel');
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
      final result = await runMetadataBuilder({
        'lib/tls.dart':
            '''
$metadataHeader
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
      expect(namedEntry(json, 'hints', 'net.port'), {
        'name': 'net.port',
        'range': [0, 65535],
        'warn': [
          {
            'values': [22, 25],
            'message': 'Blocked by browsers.',
          },
        ],
      });
      expect(namedEntry(json, 'hints', 'net.tls')['values'], [
        {'value': 'verify', 'description': 'Checks certificates.'},
        {'value': 'insecure-mode', 'description': 'Skips the checks.'},
      ]);
      expect(namedEntry(json, 'hints', 'net.format')['values'], [
        {'value': 'plain', 'description': null},
        {'value': 'json', 'description': null},
      ]);
      expect(namedEntry(json, 'hints', 'net.fallback')['warn'], [
        {
          'values': ['insecure-mode'],
          'message': 'No certificate checks.',
        },
      ]);
      expect(
        namedEntry(json, 'hints', 'net.per-host.*')['values'],
        hasLength(2),
      );
      expect(namedEntry(json, 'hints', 'net.levels[*]')['range'], [1, 9]);
    });

    test('a hand-written additional file is not read', () async {
      final result = await runMetadataBuilder({
        'lib/shop.dart': shopProperties,
        'spring_metadata_additional.json': jsonEncode({
          'properties': [
            {'name': 'by.hand', 'type': 'String'},
          ],
        }),
      });
      final names = [
        for (final p in entriesOf(result.json!, 'properties')) p['name'],
      ];
      expect(names, isNot(contains('by.hand')));
    });
  });

  group('format', () {
    test('nothing is written for a package without Spring code', () async {
      final result = await runMetadataBuilder({'lib/a.dart': 'class A {}'});
      expect(result.json, isNull);
    });

    test(
      'top-level keys in order, version 1, pretty and deterministic',
      () async {
        final sources = {'lib/shop.dart': shopProperties};
        final first = await runMetadataBuilder(sources);
        final second = await runMetadataBuilder(sources);
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
      final result = await runMetadataBuilder({
        'lib/shop.dart': shopProperties,
      });
      expect(entriesOf(result.json!, 'properties').first.keys, [
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

  group('keys read without @ConfigurationProperties', () {
    const source =
        '''
$metadataHeader
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
      json = (await runMetadataBuilder({'lib/mail.dart': source})).json!;
    });

    test('@Value placeholders become String properties', () {
      final sender = namedEntry(json, 'properties', 'mail.sender');
      expect(sender['type'], 'String');
      expect(sender['description'], isNull);
      expect(sender['class'], 'Mailer');
    });

    test('a key bound by a class keeps the class description', () {
      final names = [for (final p in entriesOf(json, 'properties')) p['name']];
      expect(names, contains('mail.host'));
      // `mail.host` is bound by MailProperties, which wins.
      expect(
        namedEntry(json, 'properties', 'mail.host')['description'],
        'Bound by the class, so this description wins.',
      );
    });

    test('@ConditionalOnProperty names, without a description', () {
      final property = namedEntry(
        json,
        'properties',
        'shop.newsletter.enabled',
      );
      expect(property['type'], 'String');
      expect(property['description'], isNull);
    });

    test('the boolean condition gives bool and applies the prefix', () {
      expect(namedEntry(json, 'properties', 'shop.flags.a')['type'], 'bool');
      expect(namedEntry(json, 'properties', 'shop.flags.b')['type'], 'bool');
    });
  });
}
