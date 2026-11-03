// tool/spring_schema.dart: the JSON Schema of application*.yml made from
// the spring_metadata.json files of an app and its dependencies.
import 'package:test/test.dart';

import '../spring_schema.dart';

void main() {
  final app = <String, Object?>{
    'properties': [
      {'name': 'shop.name', 'type': 'String', 'description': 'The shop.'},
      {'name': 'shop.retries', 'type': 'int', 'default': 3},
      {'name': 'shop.tags', 'type': 'List<String>'},
      {'name': 'shop.mode', 'type': 'Mode'},
      {'name': 'shop.limits', 'type': 'Map<String, int>'},
      {'name': 'shop.users', 'type': 'Map<String, User>'},
      {'name': 'shop.users.*.roles', 'type': 'List<String>'},
      {'name': 'shop.items[*].sku', 'type': 'String'},
      {'name': 'shop.items', 'type': 'List<Item>'},
    ],
    'hints': [
      {
        'name': 'shop.mode',
        'values': [
          {'value': 'fast', 'description': 'Quick.'},
          {'value': 'safe', 'description': null},
        ],
      },
      {
        'name': 'shop.retries',
        'range': [0, 10],
      },
    ],
  };
  final flutter = <String, Object?>{
    'properties': <Object?>[],
    'hints': <Object?>[],
    'theme': {
      'types': {
        'hex-color': {'kind': 'string', 'pattern': r'^#[0-9a-f]{6}$'},
        'percent': {'kind': 'number', 'min': 0, 'max': 1},
        'color-object': {
          'kind': 'object',
          'keys': {
            'color': {'type': 'color', 'required': true},
            'alpha': {'type': 'percent', 'required': false},
          },
        },
        'color': {
          'kind': 'oneOf',
          'of': ['hex-color', 'color-object'],
        },
        'true / false': {'kind': 'boolean'},
      },
      'properties': [
        {
          'name': 'components.app-bar.background-color',
          'type': 'color',
          'states': true,
          'description': 'The bar.',
        },
        {
          'name': 'components.app-bar.center-title',
          'type': 'true / false',
          'states': false,
        },
        {
          'name': 'components.app-bar.system-overlay-style',
          'type': 'choice',
          'values': ['light', 'dark'],
          'states': false,
        },
      ],
    },
  };
  final schema = buildSchema([app, flutter]);
  Map<String, Object?> at(Object? node, List<String> path) {
    var current = node! as Map<String, Object?>;
    for (final key in path) {
      current = (current['properties']! as Map)[key] as Map<String, Object?>;
    }
    return current;
  }

  test('draft 2020-12, keys nested by dots', () {
    expect(
      schema[r'$schema'],
      'https://json-schema.org/draft/2020-12/schema',
    );
    final name = at(schema, ['shop', 'name']);
    expect(name['type'], 'string');
    expect(name['description'], 'The shop.');
  });

  test('types: numbers accept a placeholder, lists a comma text', () {
    final retries = at(schema, ['shop', 'retries']);
    expect(retries['default'], 3);
    final anyOf = retries['anyOf']! as List;
    expect(anyOf.first, {'type': 'integer', 'minimum': 0, 'maximum': 10});
    expect(anyOf.last, {r'$ref': r'#/$defs/placeholder'});
    final tags = at(schema, ['shop', 'tags'])['anyOf']! as List;
    expect(tags.first, {
      'type': 'array',
      'items': {'type': 'string'},
    });
    expect(tags.last, {'type': 'string'});
  });

  test('hint values become constants with descriptions', () {
    final mode = (at(schema, ['shop', 'mode'])['anyOf']! as List)
        .cast<Map<String, Object?>>();
    expect(mode.first, {'const': 'fast', 'description': 'Quick.'});
    expect(mode[1], {'const': 'safe'});
  });

  test('maps, wildcards and [*] lists', () {
    final limits = at(schema, ['shop', 'limits']);
    expect(limits['type'], 'object');
    expect((limits['additionalProperties']! as Map)['anyOf'], isNotNull);
    final users = at(schema, ['shop', 'users']);
    final user = users['additionalProperties']! as Map<String, Object?>;
    expect(user['properties'], contains('roles'));
    final items = at(schema, ['shop', 'items'])['anyOf']! as List;
    final element = (items.first as Map)['items'] as Map;
    expect((element['properties']! as Map).keys, ['sku']);
  });

  test('the theme: type definitions and keys under every theme root', () {
    final defs = schema[r'$defs']! as Map<String, Object?>;
    expect(defs, containsPair('true-false', {'type': 'boolean'}));
    expect((defs['color']! as Map)['anyOf'], [
      {r'$ref': r'#/$defs/hex-color'},
      {r'$ref': r'#/$defs/color-object'},
    ]);
    final colorObject = defs['color-object']! as Map;
    expect(colorObject['required'], ['color']);
    expect(colorObject['additionalProperties'], isFalse);
    final theme = at(schema, ['spring', 'flutter', 'theme']);
    for (final root in [
      theme,
      at(theme, ['light']),
      at(theme, ['dark']),
    ]) {
      final bar = at(root, ['components', 'app-bar']);
      final colors = (bar['properties']! as Map).cast<String, Object?>();
      expect(colors.keys, containsAll(['background-color', 'center-title']));
    }
    final themes = at(theme, ['themes'])['additionalProperties']! as Map;
    expect(themes['properties'], contains('components'));
    final background = at(theme, [
      'components',
      'app-bar',
      'background-color',
    ]);
    expect((background['anyOf']! as List)[1], containsPair('type', 'object'));
    expect(
      (at(theme, ['components', 'app-bar', 'system-overlay-style'])['anyOf']!
              as List)
          .first,
      {
        'enum': ['light', 'dark'],
      },
    );
  });
}
