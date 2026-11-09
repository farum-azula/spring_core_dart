import 'dart:convert';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

enum Status { open, closed }

enum Level {
  low('L'),
  high('H');

  Level(this.code);
  final String code;
}

class Item {
  const Item({required this.sku, required this.quantity, this.price});
  final String sku;
  final int quantity;
  final double? price;
}

class Order {
  Order({
    required this.id,
    required this.items,
    this.status = Status.open,
    this.level,
    this.note,
    this.tags = const {},
    this.labels = const {},
    this.createdAt,
    this.parent,
    this.password,
  });
  final String id;
  final List<Item> items;
  final Status status;
  final Level? level;
  final String? note;
  final Map<String, int> tags;
  final Set<String> labels;
  final DateTime? createdAt;
  final Order? parent;
  final String? password;
  String get total => '${items.length}';
  String get secret => 's';
  int count = 0;
}

const _schemaLocation = 'resources:schemas/order.json';

final _itemIntrospection = BeanIntrospection<Item>(
  annotations: const [JsonSchemaSource('resources:schemas/item.json')],
  properties: [
    BeanProperty<Item>(
      'sku',
      typeInfo: const ClassType<String>(),
      get: (b) => b.sku,
      annotations: const [NotBlank(), Matches('[A-Z]+-[0-9]+')],
    ),
    BeanProperty<Item>(
      'quantity',
      typeInfo: const ClassType<int>(),
      get: (b) => b.quantity,
      annotations: const [Min(1), Max(99)],
    ),
    BeanProperty<Item>(
      'price',
      typeInfo: const ClassType<double>(nullable: true),
      nullable: true,
      get: (b) => b.price,
      annotations: const [DecimalMin('0', inclusive: false)],
    ),
  ],
  constructor: BeanConstructor<Item>(
    parameters: const [
      BeanParameter(
        'sku',
        type: ClassType<String>(),
        symbol: #sku,
        isRequired: true,
      ),
      BeanParameter(
        'quantity',
        type: ClassType<int>(),
        symbol: #quantity,
        isRequired: true,
      ),
      BeanParameter(
        'price',
        type: ClassType<double>(nullable: true),
        symbol: #price,
      ),
    ],
    create: (positional, named) =>
        Function.apply(Item.new, positional, named) as Item,
  ),
);

final _orderIntrospection = BeanIntrospection<Order>(
  annotations: const [JsonSchemaSource(_schemaLocation)],
  properties: [
    BeanProperty<Order>(
      'id',
      typeInfo: const ClassType<String>(),
      get: (b) => b.id,
      annotations: const [Size(min: 2, max: 10)],
    ),
    BeanProperty<Order>(
      'items',
      typeInfo: const ListType<Item>(ClassType<Item>()),
      get: (b) => b.items,
      annotations: const [
        NotEmpty(),
        JsonProperty('lines'),
      ],
    ),
    BeanProperty<Order>(
      'status',
      typeInfo: const EnumType<Status>(Status.values),
      get: (b) => b.status,
    ),
    BeanProperty<Order>(
      'level',
      typeInfo: EnumType<Level>(
        Level.values,
        jsonValue: (l) => l.code,
        nullable: true,
      ),
      nullable: true,
      get: (b) => b.level,
    ),
    BeanProperty<Order>(
      'note',
      typeInfo: const ClassType<String>(nullable: true),
      nullable: true,
      get: (b) => b.note,
      annotations: const [NotNull()],
    ),
    BeanProperty<Order>(
      'tags',
      typeInfo: const MapType<String, int>(
        ClassType<String>(),
        ClassType<int>(),
      ),
      get: (b) => b.tags,
      annotations: const [
        Each([PositiveOrZero()]),
      ],
    ),
    BeanProperty<Order>(
      'labels',
      typeInfo: const SetType<String>(ClassType<String>()),
      get: (b) => b.labels,
      annotations: const [
        Each([Email()]),
      ],
    ),
    BeanProperty<Order>(
      'createdAt',
      typeInfo: const ClassType<DateTime>(nullable: true),
      nullable: true,
      get: (b) => b.createdAt,
    ),
    BeanProperty<Order>(
      'parent',
      typeInfo: const ClassType<Order>(nullable: true),
      nullable: true,
      get: (b) => b.parent,
    ),
    BeanProperty<Order>(
      'password',
      typeInfo: const ClassType<String>(nullable: true),
      nullable: true,
      get: (b) => b.password,
      annotations: const [
        JsonProperty('password', access: JsonPropertyAccess.writeOnly),
      ],
    ),
    BeanProperty<Order>(
      'total',
      typeInfo: const ClassType<String>(),
      get: (b) => b.total,
    ),
    BeanProperty<Order>(
      'secret',
      typeInfo: const ClassType<String>(),
      get: (b) => b.secret,
      annotations: const [JsonIgnore()],
    ),
    BeanProperty<Order>(
      'count',
      typeInfo: const ClassType<int>(),
      get: (b) => b.count,
      set: (b, v) => b.count = v! as int,
      annotations: const [
        JsonProperty('', access: JsonPropertyAccess.readOnly),
      ],
    ),
  ],
  constructor: BeanConstructor<Order>(
    parameters: [
      const BeanParameter(
        'id',
        type: ClassType<String>(),
        symbol: #id,
        isRequired: true,
      ),
      const BeanParameter(
        'items',
        type: ListType<Item>(ClassType<Item>()),
        symbol: #items,
        isRequired: true,
      ),
      const BeanParameter(
        'status',
        type: EnumType<Status>(Status.values),
        symbol: #status,
        hasDefaultValue: true,
        defaultValue: Status.open,
      ),
      BeanParameter(
        'level',
        type: EnumType<Level>(
          Level.values,
          jsonValue: (l) => l.code,
          nullable: true,
        ),
        symbol: #level,
      ),
      const BeanParameter(
        'note',
        type: ClassType<String>(nullable: true),
        symbol: #note,
      ),
      const BeanParameter(
        'tags',
        type: MapType<String, int>(ClassType<String>(), ClassType<int>()),
        symbol: #tags,
        hasDefaultValue: true,
        defaultValue: <String, int>{},
      ),
      const BeanParameter(
        'labels',
        type: SetType<String>(ClassType<String>()),
        symbol: #labels,
        hasDefaultValue: true,
        defaultValue: <String>{},
      ),
      const BeanParameter(
        'createdAt',
        type: ClassType<DateTime>(nullable: true),
        symbol: #createdAt,
      ),
      const BeanParameter(
        'parent',
        type: ClassType<Order>(nullable: true),
        symbol: #parent,
      ),
      const BeanParameter(
        'password',
        type: ClassType<String>(nullable: true),
        symbol: #password,
      ),
    ],
    create: (positional, named) =>
        Function.apply(Order.new, positional, named) as Order,
  ),
);

BeanIntrospector _introspector() =>
    BeanIntrospector(introspections: [_itemIntrospection, _orderIntrospection]);

Map<String, Object?> _object(Object? value) => value! as Map<String, Object?>;

void main() {
  final introspector = _introspector();
  final generator = JsonSchemaGenerator(introspector: introspector);
  final schema = generator.schemaOf(Order);
  final properties = _object(schema['properties']);

  group('JsonSchemaGenerator', () {
    test('the root: draft, title, object, required', () {
      expect(schema[r'$schema'], JsonSchemaGenerator.draft);
      expect(schema['title'], 'Order');
      expect(schema['type'], 'object');
      expect(schema.containsKey('additionalProperties'), isFalse);
      expect(schema['required'], ['id', 'lines', 'note']);
    });

    test('JSON names follow the mapper; ignored properties are left out', () {
      expect(properties.keys, [
        'id',
        'lines',
        'status',
        'level',
        'note',
        'tags',
        'labels',
        'createdAt',
        'parent',
        'password',
        'total',
        'count',
      ]);
      final snake = JsonSchemaGenerator(
        introspector: introspector,
        namingStrategy: PropertyNamingStrategy.snakeCase,
      ).schemaOf(Order);
      expect(_object(snake['properties']).keys, contains('created_at'));
      expect(_object(snake['properties']).keys, contains('lines'));
    });

    test('types', () {
      expect(properties['id'], {
        'type': 'string',
        'minLength': 2,
        'maxLength': 10,
      });
      expect(properties['status'], {
        'type': 'string',
        'enum': ['open', 'closed'],
      });
      expect(properties['level'], {
        'type': ['string', 'null'],
        'enum': ['L', 'H', null],
      });
      expect(properties['createdAt'], {
        'type': ['string', 'null'],
        'format': 'date-time',
      });
      expect(properties['tags'], {
        'type': 'object',
        'additionalProperties': {'type': 'integer', 'minimum': 0},
      });
      expect(properties['labels'], {
        'type': 'array',
        'items': {'type': 'string', 'format': 'email'},
        'uniqueItems': true,
      });
    });

    test('NotNull makes a nullable property required and not null', () {
      expect(properties['note'], {'type': 'string'});
    });

    test(r'nested classes in $defs, the root as # for a cycle', () {
      expect(properties['lines'], {
        'type': 'array',
        'items': {r'$ref': r'#/$defs/Item'},
        'minItems': 1,
      });
      expect(properties['parent'], {
        'anyOf': [
          {r'$ref': '#'},
          {'type': 'null'},
        ],
      });
      expect(_object(schema[r'$defs']).keys, ['Item']);
      final item = _object(_object(schema[r'$defs'])['Item']);
      expect(item['title'], 'Item');
      expect(item['required'], ['sku', 'quantity']);
      expect(_object(item['properties'])['sku'], {
        'type': 'string',
        'minLength': 1,
        'pattern': r'\S',
        'allOf': [
          {'pattern': r'^(?:[A-Z]+-[0-9]+)$'},
        ],
      });
      expect(_object(item['properties'])['quantity'], {
        'type': 'integer',
        'minimum': 1,
        'maximum': 99,
      });
      expect(_object(item['properties'])['price'], {
        'type': ['number', 'null'],
        'exclusiveMinimum': 0,
      });
    });

    test('read-only and write-only properties', () {
      expect(_object(properties['password'])['writeOnly'], isTrue);
      expect(_object(properties['count'])['readOnly'], isTrue);
      // A getter only: written, never read.
      expect(_object(properties['total'])['readOnly'], isTrue);
      expect(_object(properties['id']).containsKey('readOnly'), isFalse);
    });

    test('schemasOf and all', () {
      expect(generator.schemasOf([Item]).keys, ['Item']);
      expect(generator.all().keys, unorderedEquals(['Item', 'Order']));
      expect(() => generator.schemaOf(String), throwsArgumentError);
    });

    test('the generated schema is a valid JSON Schema for the JSON '
        'the mapper writes', () {
      final mapper = ObjectMapper(introspector: introspector);
      final order = Order(
        id: 'A1',
        items: const [Item(sku: 'AB-1', quantity: 2, price: 9.5)],
        level: Level.high,
        note: 'gift',
        tags: const {'a': 1},
        labels: const {'me@example.com'},
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        parent: Order(
          id: 'P0',
          items: const [Item(sku: 'X-1', quantity: 1)],
        ),
      );
      final json = mapper.valueToTree(order);
      final validator = JsonSchema(
        jsonDecode(jsonEncode(schema)) as Map<String, Object?>,
      );
      // The parent has no note: the generated schema requires one.
      expect(
        validator.validate(json).violations.map((v) => '$v'),
        ['/parent/note: must be a string, got null'],
      );
      final withoutParent = Order(
        id: 'A1',
        items: const [Item(sku: 'AB-1', quantity: 2, price: 9.5)],
        note: 'n',
        createdAt: DateTime(2026, 1, 2, 3, 4, 5, 6, 7),
      );
      expect(
        validator.validate(mapper.valueToTree(withoutParent)).violations,
        isEmpty,
      );
      final empty = _object(mapper.valueToTree(withoutParent))
        ..['lines'] = <Object?>[];
      expect(validator.validate(empty).violations.map((v) => '$v'), [
        '/lines: must have at least 1 item',
      ]);
    });
  });

  group('ObjectMapper with a schemaResolver', () {
    final schemas = <String, JsonSchema>{
      _schemaLocation: JsonSchema(schema),
      'resources:schemas/item.json': JsonSchema({
        'type': 'object',
        'properties': {
          'sku': {'pattern': '^[A-Z]'},
        },
      }),
    };
    final asked = <String>[];
    JsonSchema? resolve(String location) {
      asked.add(location);
      return schemas[location];
    }

    final mapper = ObjectMapper(
      introspector: introspector,
      schemaResolver: resolve,
    );

    test('valid JSON is read', () {
      final order = mapper.readValue<Order>(
        '{"id": "A1", "lines": [{"sku": "AB-1", "quantity": 2}], '
        '"note": "n", "level": "H"}',
      );
      expect(order.level, Level.high);
      expect(order.items.single.quantity, 2);
    });

    test('invalid JSON throws with every violation and its path', () {
      expect(
        () => mapper.readValue<Order>(
          '{"id": "A", "lines": [{"sku": "AB-1", "quantity": 0}, '
          '{"sku": "", "quantity": 100}], "status": "lost"}',
        ),
        throwsA(
          isA<JsonSchemaValidationException>()
              .having((e) => e.path, 'path', '')
              .having((e) => e.location, 'location', _schemaLocation)
              .having(
                (e) => e.violations.map((v) => '$v'),
                'violations',
                [
                  '/note: is required',
                  '/id: must be at least 2 characters long',
                  '/lines/0/quantity: must be at least 1',
                  '/lines/1/sku: must be at least 1 character long',
                  r'/lines/1/sku: must match the pattern \S',
                  r'/lines/1/sku: must match the pattern ^(?:[A-Z]+-[0-9]+)$',
                  '/lines/1/quantity: must be at most 99',
                  '/status: must be one of: open, closed',
                ],
              )
              .having(
                (e) => e.toString(),
                'toString',
                contains('/lines/0/quantity: must be at least 1'),
              ),
        ),
      );
    });

    test('a nested class is checked against its own schema', () {
      expect(
        () => mapper.readList<Item>(
          '[{"sku": "A-1", "quantity": 1}, '
          '{"sku": "a-1", "quantity": 1}]',
        ),
        throwsA(
          isA<JsonSchemaValidationException>()
              .having((e) => e.path, 'path', '[1]')
              .having(
                (e) => e.violations.map((v) => '$v'),
                'violations',
                ['/sku: must match the pattern ^[A-Z]'],
              ),
        ),
      );
    });

    test('each location is resolved once', () {
      asked.clear();
      final again = ObjectMapper(
        introspector: introspector,
        schemaResolver: resolve,
      );
      for (var i = 0; i < 3; i++) {
        again.readValue<Item>('{"sku": "A-1", "quantity": 1}');
      }
      expect(asked, ['resources:schemas/item.json']);
    });

    test('the resolver is kept by rebuild and the builder', () {
      expect(
        mapper.rebuild().build().schemaResolver,
        same(mapper.schemaResolver),
      );
      final built = JsonMapper.builder()
          .introspector(introspector)
          .schemaResolver(resolve)
          .build();
      expect(
        () => built.readValue<Item>('{"sku": "a", "quantity": 1}'),
        throwsA(isA<JsonSchemaValidationException>()),
      );
      expect(
        () => built
            .readerWithView(Object)
            .readValue<Item>('{"sku": "a", "quantity": 1}'),
        throwsA(isA<JsonSchemaValidationException>()),
      );
    });

    test('without a resolver, or without a schema, nothing is checked', () {
      final plain = ObjectMapper(introspector: introspector);
      expect(
        plain.readValue<Item>('{"sku": "a", "quantity": 1}').sku,
        'a',
      );
      final none = ObjectMapper(
        introspector: introspector,
        schemaResolver: (_) => null,
      );
      expect(none.readValue<Item>('{"sku": "a", "quantity": 1}').sku, 'a');
    });
  });
}
