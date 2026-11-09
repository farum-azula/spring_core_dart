import 'dart:convert';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

JsonSchemaResult _check(Object schema, String json, {JsonSchemaRegistry? r}) =>
    JsonSchema.parse(
      jsonEncode(schema),
      registry: r,
    ).validate(jsonDecode(json));

List<String> _problems(Object schema, String json, {JsonSchemaRegistry? r}) => [
  for (final v in _check(schema, json, r: r).violations) '$v',
];

void _valid(Object schema, String json) =>
    expect(_problems(schema, json), isEmpty, reason: json);

void main() {
  group('types', () {
    test('type, a list of types and integer', () {
      _valid({'type': 'integer'}, '3');
      _valid({'type': 'integer'}, '3.0');
      expect(_problems({'type': 'integer'}, '3.5'), [
        '(root): must be an integer, got a number',
      ]);
      _valid({
        'type': ['string', 'null'],
      }, 'null');
      expect(
        _problems({
          'type': ['string', 'null'],
        }, '1'),
        ['(root): must be a string or null, got an integer'],
      );
      expect(_problems({'type': 'boolean'}, '0'), hasLength(1));
      _valid({'type': 'object'}, '{}');
      _valid({'type': 'array'}, '[]');
    });

    test('enum and const compare JSON values', () {
      expect(
        _problems({
          'enum': ['a', 'b', 1],
        }, '"c"'),
        ['(root): must be one of: a, b, 1'],
      );
      _valid({
        'enum': [
          {'x': 1},
        ],
      }, '{"x": 1.0}');
      _valid({'const': 2}, '2.0');
      expect(_problems({'const': true}, '1'), ['(root): must be true']);
    });

    test('boolean schemas', () {
      _valid(true, '{"anything": 1}');
      expect(_problems(false, '1'), ['(root): is not allowed']);
      expect(
        _problems({
          'properties': {'x': false},
        }, '{"x": 1}'),
        ['/x: is not allowed'],
      );
    });
  });

  group('numbers', () {
    test('limits and multipleOf', () {
      final schema = {
        'minimum': 1,
        'maximum': 10,
        'exclusiveMaximum': 10,
        'multipleOf': 0.5,
      };
      _valid(schema, '9.5');
      expect(_problems(schema, '0'), ['(root): must be at least 1']);
      expect(_problems(schema, '10'), ['(root): must be less than 10']);
      expect(_problems(schema, '11'), [
        '(root): must be at most 10',
        '(root): must be less than 10',
      ]);
      expect(_problems(schema, '1.2'), ['(root): must be a multiple of 0.5']);
      _valid({'multipleOf': 0.01}, '19.99');
      expect(_problems({'exclusiveMinimum': 0}, '0'), [
        '(root): must be greater than 0',
      ]);
    });
  });

  group('strings', () {
    test('lengths count code points', () {
      _valid({'maxLength': 2}, '"😀😀"');
      expect(_problems({'minLength': 3}, '"😀😀"'), [
        '(root): must be at least 3 characters long',
      ]);
      expect(_problems({'maxLength': 1}, '"ab"'), [
        '(root): must be at most 1 character long',
      ]);
    });

    test('pattern is not anchored', () {
      _valid({'pattern': 'b'}, '"abc"');
      expect(_problems({'pattern': r'^\d+$'}, '"12a"'), [
        r'(root): must match the pattern ^\d+$',
      ]);
      _valid({'pattern': r'^\p{L}+$'}, '"été"');
    });

    test('formats', () {
      final good = {
        'date-time': ['2026-01-31T12:00:00Z', '2026-01-31T12:00:00.5+02:00'],
        'date': ['2024-02-29'],
        'time': ['23:59:60Z', '08:30:00-05:00'],
        'email': ['a.b@example.com', 'me@localhost'],
        'uri': ['https://example.com/a?b#c', 'urn:isbn:1'],
        'uri-reference': ['../a/b', 'https://x'],
        'uuid': ['123e4567-e89b-12d3-a456-426614174000'],
        'ipv4': ['192.168.0.1'],
        'ipv6': ['::1', '2001:db8::8a2e:370:7334'],
        'unknown-format': ['anything'],
      };
      final bad = {
        'date-time': ['2026-01-31 12:00:00Z', '2026-01-31T12:00:00'],
        'date': ['2023-02-29', '2026-13-01', '2026-1-1'],
        'time': ['24:00:00Z', '12:00:00'],
        'email': ['no-at', 'a b@c.d', 'a@'],
        'uri': ['/relative', 'has space:x'],
        'uuid': ['123e4567e89b12d3a456426614174000'],
        'ipv4': ['256.1.1.1', '01.2.3.4', '1.2.3'],
        'ipv6': ['1.2.3.4', '::g'],
      };
      for (final MapEntry(key: format, value: values) in good.entries) {
        for (final value in values) {
          _valid({'format': format}, jsonEncode(value));
        }
      }
      for (final MapEntry(key: format, value: values) in bad.entries) {
        for (final value in values) {
          expect(
            _problems({'format': format}, jsonEncode(value)),
            ['(root): must be a valid $format'],
            reason: value,
          );
        }
      }
      _valid({'format': 'email'}, '1');
    });
  });

  group('arrays', () {
    test('items, prefixItems and their paths', () {
      final schema = {
        'prefixItems': [
          {'type': 'string'},
        ],
        'items': {'type': 'integer', 'minimum': 0},
      };
      _valid(schema, '["a", 1, 2]');
      expect(_problems(schema, '[1, 1, -1]'), [
        '/0: must be a string, got an integer',
        '/2: must be at least 0',
      ]);
      expect(
        _problems({
          'prefixItems': [true],
          'items': false,
        }, '[1, 2]'),
        ['/1: is not allowed'],
      );
    });

    test('minItems, maxItems, uniqueItems', () {
      final schema = {'minItems': 1, 'maxItems': 2, 'uniqueItems': true};
      expect(_problems(schema, '[]'), ['(root): must have at least 1 item']);
      expect(_problems(schema, '[1, 2, 3]'), [
        '(root): must have at most 2 items',
      ]);
      expect(_problems(schema, '[{"a": 1}, {"a": 1.0}]'), [
        '(root): must not have duplicate items (items 0 and 1 are equal)',
      ]);
      _valid(schema, '[1, true]');
    });

    test('contains, minContains, maxContains', () {
      final schema = {
        'contains': {'type': 'string'},
        'minContains': 2,
        'maxContains': 3,
      };
      _valid(schema, '[1, "a", "b"]');
      expect(
        _check(schema, '["a"]').violations.single.keyword,
        'minContains',
      );
      expect(
        _check(schema, '["a", "b", "c", "d"]').violations.single.keyword,
        'maxContains',
      );
      expect(
        _check({
          'contains': {'const': 1},
        }, '[2]').violations.single.keyword,
        'contains',
      );
      _valid({
        'contains': {'const': 1},
        'minContains': 0,
      }, '[]');
    });
  });

  group('objects', () {
    final schema = {
      'type': 'object',
      'required': ['id', 'a/b'],
      'properties': {
        'id': {'type': 'integer'},
        'a/b': {'type': 'string'},
      },
      'patternProperties': {
        '^x-': {'type': 'string'},
      },
      'additionalProperties': false,
    };

    test('required and additionalProperties name the property', () {
      _valid(schema, '{"id": 1, "a/b": "", "x-trace": "t"}');
      expect(_problems(schema, '{"x-trace": 1, "other": 2}'), [
        '/id: is required',
        '/a~1b: is required',
        '/x-trace: must be a string, got an integer',
        '/other: is not allowed',
      ]);
    });

    test('additionalProperties as a schema', () {
      expect(
        _problems({
          'additionalProperties': {'type': 'integer'},
        }, '{"a": 1, "b": "x"}'),
        ['/b: must be an integer, got a string'],
      );
    });

    test('propertyNames, minProperties, maxProperties', () {
      expect(
        _problems({
          'propertyNames': {'pattern': r'^[a-z]+$'},
          'maxProperties': 1,
        }, '{"ok": 1, "No": 2}'),
        [
          r'/No: is not a valid property name: must match the pattern ^[a-z]+$',
          '(root): must have at most 1 property',
        ],
      );
      expect(_problems({'minProperties': 2}, '{"a": 1}'), [
        '(root): must have at least 2 properties',
      ]);
    });

    test('dependentRequired and dependentSchemas', () {
      final dependent = {
        'dependentRequired': {
          'card': ['cvc'],
        },
        'dependentSchemas': {
          'card': {
            'properties': {
              'card': {'minLength': 4},
            },
          },
        },
      };
      _valid(dependent, '{"cvc": 1}');
      expect(_problems(dependent, '{"card": "12"}'), [
        '/cvc: is required when "card" is present',
        '/card: must be at least 4 characters long',
      ]);
    });

    test('nested paths', () {
      final order = {
        'properties': {
          'items': {
            'type': 'array',
            'items': {
              'properties': {
                'price': {'minimum': 1},
              },
            },
          },
        },
      };
      final violation = _check(
        order,
        '{"items": [{"price": 1}, {"price": 2}, {"price": 0}]}',
      ).violations.single;
      expect(violation.path, '/items/2/price');
      expect(violation.keyword, 'minimum');
      expect(violation.message, 'must be at least 1');
      expect('$violation', '/items/2/price: must be at least 1');
    });
  });

  group('combinators', () {
    test('allOf collects every violation', () {
      expect(
        _problems({
          'allOf': [
            {'minimum': 5},
            {'multipleOf': 2},
          ],
        }, '3'),
        ['(root): must be at least 5', '(root): must be a multiple of 2'],
      );
    });

    test('anyOf', () {
      final schema = {
        'anyOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
      };
      _valid(schema, '1');
      expect(_problems(schema, 'true'), [
        '(root): must match at least one of the schemas',
      ]);
    });

    test('anyOf with null reports the one branch that fits the type', () {
      final schema = {
        'anyOf': [
          {
            'type': 'object',
            'required': ['id'],
          },
          {'type': 'null'},
        ],
      };
      _valid(schema, 'null');
      expect(_problems(schema, '{}'), ['/id: is required']);
    });

    test('oneOf', () {
      final schema = {
        'oneOf': [
          {'type': 'integer'},
          {'minimum': 2},
        ],
      };
      _valid(schema, '1');
      _valid(schema, '2.5');
      expect(_problems(schema, '3'), [
        '(root): must match exactly one of the schemas, but matches 2 (0, 1)',
      ]);
      expect(_check(schema, '"x"').isValid, isTrue);
      expect(
        _problems({
          'oneOf': [
            {'type': 'string'},
            {'type': 'boolean'},
          ],
        }, '1'),
        ['(root): must match exactly one of the schemas'],
      );
    });

    test('not', () {
      expect(
        _problems({
          'not': {'type': 'string'},
        }, '"a"'),
        ['(root): must not match the schema'],
      );
      _valid({
        'not': {'type': 'string'},
      }, '1');
    });

    test('if / then / else', () {
      final schema = {
        'if': {
          'properties': {
            'country': {'const': 'US'},
          },
        },
        'then': {
          'properties': {
            'zip': {'pattern': r'^\d{5}$'},
          },
        },
        'else': {
          'properties': {
            'zip': {'pattern': r'^[A-Z0-9 ]+$'},
          },
        },
      };
      _valid(schema, '{"country": "US", "zip": "12345"}');
      _valid(schema, '{"country": "UK", "zip": "SW1A 1AA"}');
      expect(_problems(schema, '{"country": "US", "zip": "SW1A"}'), [
        r'/zip: must match the pattern ^\d{5}$',
      ]);
      expect(_problems(schema, '{"country": "FR", "zip": "a"}'), [
        r'/zip: must match the pattern ^[A-Z0-9 ]+$',
      ]);
    });
  });

  group(r'$ref', () {
    test(r'local pointers, $defs, definitions and anchors', () {
      final schema = {
        r'$defs': {
          'positive': {'exclusiveMinimum': 0},
          'a~b': {'type': 'string'},
          'named': {r'$anchor': 'name', 'minLength': 2},
        },
        'definitions': {
          'flag': {'type': 'boolean'},
        },
        'properties': {
          'n': {r'$ref': r'#/$defs/positive'},
          's': {r'$ref': r'#/$defs/a~0b'},
          'f': {r'$ref': '#/definitions/flag'},
          'm': {r'$ref': '#name'},
          'list': {
            'type': 'array',
            'items': {r'$ref': '#/properties/n'},
          },
        },
      };
      _valid(schema, '{"n": 1, "s": "x", "f": true, "m": "ab", "list": [2]}');
      expect(
        _problems(
          schema,
          '{"n": 0, "s": 1, "f": 1, "m": "a", "list": [1, -1]}',
        ),
        [
          '/n: must be greater than 0',
          '/s: must be a string, got an integer',
          '/f: must be a boolean, got an integer',
          '/m: must be at least 2 characters long',
          '/list/1: must be greater than 0',
        ],
      );
    });

    test('a recursive schema follows the instance', () {
      final tree = {
        'type': 'object',
        'properties': {
          'value': {'type': 'integer'},
          'children': {
            'type': 'array',
            'items': {r'$ref': '#'},
          },
        },
      };
      expect(
        _problems(
          tree,
          '{"value": 1, "children": [{"value": 2, "children": '
          '[{"value": "x"}]}]}',
        ),
        ['/children/0/children/0/value: must be an integer, got a string'],
      );
    });

    test(r'a $ref loop is reported, not followed forever', () {
      final loop = {
        r'$defs': {
          'a': {r'$ref': r'#/$defs/b'},
          'b': {r'$ref': r'#/$defs/a'},
        },
        r'$ref': r'#/$defs/a',
      };
      final result = _check(loop, '1');
      expect(result.isValid, isFalse);
      expect(result.violations.single.keyword, r'$ref');
      expect(_check({r'$ref': '#'}, '1').violations.single.keyword, r'$ref');
    });

    test(r'an unknown $ref is a violation', () {
      expect(_problems({r'$ref': '#/nothing'}, '1'), [
        r'(root): cannot resolve the $ref "#/nothing"',
      ]);
    });

    test('other documents through the registry', () {
      final registry = JsonSchemaRegistry()
        ..add(
          JsonSchema({
            r'$id': 'https://example.com/schemas/address.json',
            'type': 'object',
            'required': ['city'],
            r'$defs': {
              'zip': {'pattern': r'^\d+$'},
            },
            'properties': {
              'zip': {r'$ref': r'#/$defs/zip'},
            },
          }),
        )
        ..add(
          JsonSchema({'type': 'string', 'minLength': 1}),
          uri: Uri.parse('urn:example:name'),
        );
      final order = {
        r'$id': 'https://example.com/schemas/order.json',
        'properties': {
          'to': {r'$ref': 'address.json'},
          'from': {
            r'$ref': 'https://example.com/schemas/address.json',
          },
          'zip': {
            r'$ref': r'address.json#/$defs/zip',
          },
          'name': {r'$ref': 'urn:example:name'},
        },
      };
      expect(
        _problems(
          order,
          '{"to": {"city": "Lyon", "zip": "69001"}, "from": {"zip": "x"}, '
          '"zip": "y", "name": ""}',
          r: registry,
        ),
        [
          '/from/city: is required',
          r'/from/zip: must match the pattern ^\d+$',
          r'/zip: must match the pattern ^\d+$',
          '/name: must be at least 1 character long',
        ],
      );
      expect(
        registry.resolve(
          Uri.parse('https://example.com/schemas/address.json#x'),
        ),
        isNotNull,
      );
      expect(registry.resolve(Uri.parse('https://nowhere/x.json')), isNull);
    });

    test(r'embedded $id resources resolve relative refs', () {
      final schema = {
        r'$id': 'https://example.com/root.json',
        r'$defs': {
          'item': {
            r'$id': 'item.json',
            'type': 'object',
            'properties': {
              'n': {r'$ref': r'#/$defs/n'},
            },
            r'$defs': {
              'n': {'type': 'integer'},
            },
          },
        },
        'items': {r'$ref': 'item.json'},
      };
      expect(_problems(schema, '[{"n": 1}, {"n": "x"}]'), [
        '/1/n: must be an integer, got a string',
      ]);
    });
  });

  test('parse, id and unknown keywords', () {
    final schema = JsonSchema.parse(
      r'{"$id": "order.json", "title": "Order", "x-custom": 1, '
      '"default": 3, "examples": [1]}',
      id: Uri.parse('https://example.com/schemas/'),
    );
    expect(schema.id, Uri.parse('https://example.com/schemas/order.json'));
    expect(schema.validate('anything').isValid, isTrue);
    expect(JsonSchema.parse('false').validate(1).isValid, isFalse);
    expect(JsonSchema.parse('true').validate(1).isValid, isTrue);
    expect(() => JsonSchema.parse('1'), throwsFormatException);
    expect(() => JsonSchema.parse('{'), throwsFormatException);
    expect(
      () => JsonSchemaRegistry().add(JsonSchema(const {})),
      throwsArgumentError,
    );
  });

  group('JsonSchemaLocations.resourceOf', () {
    const resourceOf = JsonSchemaLocations.resourceOf;

    test('a resources: location is its own path', () {
      expect(resourceOf('resources:schemas/order.json'), 'schemas/order.json');
      expect(resourceOf(' resources:/a.json '), 'a.json');
    });

    test('URLs below json-schemas/<host>', () {
      expect(
        resourceOf('https://example.com/schemas/order.json'),
        'json-schemas/example.com/schemas/order.json',
      );
      expect(
        resourceOf('http://Example.COM/schemas/order.json'),
        'json-schemas/example.com/schemas/order.json',
      );
      expect(
        resourceOf('https://example.com:8443/v1/order?v=2&x=a b#frag'),
        'json-schemas/example.com_8443/v1/order_v_2_x_a_b.json',
      );
      expect(
        resourceOf('https://example.com/s/order.json?v=2'),
        'json-schemas/example.com/s/order_v_2.json',
      );
      expect(
        resourceOf('https://example.com/a//b%20c/%7Eschema'),
        'json-schemas/example.com/a/b_c/_schema.json',
      );
    });

    test('github: locations below json-schemas/github, with the ref', () {
      expect(
        resourceOf('github:acme/shop/schemas/order.json@v1.2'),
        'json-schemas/github/acme/shop/schemas/order@v1.2.json',
      );
      expect(
        resourceOf('github:acme/shop/schemas/order.json'),
        'json-schemas/github/acme/shop/schemas/order.json',
      );
      expect(
        resourceOf('github:acme/shop/order.schema@feature/x'),
        'json-schemas/github/acme/shop/order.schema@feature_x.json',
      );
    });

    test('results are file-system safe and deterministic', () {
      const locations = [
        'https://h.example/ä/ö ü/<x>:y*?.json',
        'github:o/r/p/q r.json@a:b',
        'https://h/x/../a b',
        'github:o/r/../x.json@..',
      ];
      final safe = RegExp(r'^[A-Za-z0-9._@/-]+$');
      for (final location in locations) {
        final path = resourceOf(location);
        expect(path, matches(safe), reason: location);
        expect(path.split('/'), isNot(contains('..')), reason: location);
        expect(resourceOf(location), path);
        expect(path, endsWith('.json'));
      }
    });

    test('other forms throw', () {
      for (final location in [
        'schemas/order.json',
        'ftp://h/x.json',
        'github:acme/shop',
        'github:acme/shop/x.json@',
        'https://example.com',
        'resources:',
      ]) {
        expect(
          () => resourceOf(location),
          throwsArgumentError,
          reason: location,
        );
      }
    });

    test('isRemote', () {
      expect(JsonSchemaLocations.isRemote('github:a/b/c'), isTrue);
      expect(JsonSchemaLocations.isRemote('https://x/y.json'), isTrue);
      expect(JsonSchemaLocations.isRemote('resources:x.json'), isFalse);
    });
  });
}
