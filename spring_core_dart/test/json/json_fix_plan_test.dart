// Runs on the VM and on node (`dart test -p node`).
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

// The introspections below are what the generator writes for these classes.

enum Color { red, green }

enum Stock {
  inStock('in_stock'),
  soldOut('sold_out');

  const Stock(this.json);
  final String json;
}

// Used by no introspected class.
enum Lonely { a, b }

final _stock = EnumType<Stock>(Stock.values, jsonValue: (s) => s.json);

BeanProperty<T> _p<T extends Object>(
  String name,
  Object? Function(T bean) get,
  TypeInfo<Object?> info, {
  void Function(T bean, Object? value)? set,
  List<Object> annotations = const [],
}) => BeanProperty<T>(
  name,
  type: info.type,
  nullable: info.nullable,
  typeInfo: info,
  get: get,
  set: set,
  annotations: annotations,
);

class Palette {
  Color color = Color.red;
  Map<String, Stock> stocks = {};
  Object? anything;
}

class Note {}

class TextNote extends Note {
  TextNote(this.text);
  final String text;
}

class Isbn {
  Isbn(this.value);
  final String value;
}

class Shelf {
  Shelf(this.isbn);
  final Isbn isbn;
}

class Label {
  String code() => 'L-1';
}

class Account {
  Account(this.id, {this.nickname});
  final String id;
  final String? nickname;
  String? password;
  int version = 1;
}

class Ticket {
  Ticket(this.code);
  final String code;
}

class Counter {
  Counter(this.count, this.enabled, {this.ratio = 1});
  final int count;
  final bool enabled;
  final double ratio;
  int? optional;
  int total = 5;
}

class Range<T extends num> {
  Range(this.low);
  final T low;
}

final _introspector = BeanIntrospector(
  introspections: [
    BeanIntrospection<Palette>(
      properties: [
        _p<Palette>(
          'color',
          (b) => b.color,
          const EnumType<Color>(Color.values),
          set: (b, v) => b.color = v! as Color,
        ),
        _p<Palette>(
          'stocks',
          (b) => b.stocks,
          MapType<String, Stock>(const ClassType<String>(), _stock),
          set: (b, v) => b.stocks = v! as Map<String, Stock>,
        ),
        _p<Palette>(
          'anything',
          (b) => b.anything,
          const DynamicType(),
          set: (b, v) => b.anything = v,
        ),
      ],
      instantiate: Palette.new,
    ),
    BeanIntrospection<Note>(
      annotations: const [
        JsonTypeInfo(property: 'kind', defaultImpl: TextNote),
        JsonSubTypes([JsonSubType(TextNote, name: 'text')]),
      ],
    ),
    BeanIntrospection<TextNote>(
      properties: [
        _p<TextNote>('text', (b) => b.text, const ClassType<String>()),
      ],
      constructor: BeanConstructor<TextNote>(
        parameters: const [
          BeanParameter('text', type: ClassType<String>(), isRequired: true),
        ],
        create: (positional, named) => TextNote(positional[0]! as String),
      ),
    ),
    BeanIntrospection<Isbn>(
      properties: [
        _p<Isbn>(
          'value',
          (b) => b.value,
          const ClassType<String>(),
          annotations: const [JsonValue()],
        ),
      ],
      constructor: BeanConstructor<Isbn>(
        parameters: const [
          BeanParameter('value', type: ClassType<String>(), isRequired: true),
        ],
        create: (positional, named) => Isbn(positional[0]! as String),
      ),
    ),
    BeanIntrospection<Shelf>(
      properties: [_p<Shelf>('isbn', (b) => b.isbn, const ClassType<Isbn>())],
      constructor: BeanConstructor<Shelf>(
        parameters: const [
          BeanParameter('isbn', type: ClassType<Isbn>(), isRequired: true),
        ],
        create: (positional, named) => Shelf(positional[0]! as Isbn),
      ),
    ),
    BeanIntrospection<Label>(
      methods: [
        BeanMethod<Label>(
          'code',
          invoke: (b, a) => b.code(),
          returnType: String,
          annotations: const [JsonValue()],
        ),
      ],
      instantiate: Label.new,
    ),
    BeanIntrospection<Account>(
      properties: [
        _p<Account>('id', (b) => b.id, const ClassType<String>()),
        _p<Account>(
          'nickname',
          (b) => b.nickname,
          const ClassType<String>(nullable: true),
        ),
        _p<Account>(
          'password',
          (b) => b.password,
          const ClassType<String>(nullable: true),
          set: (b, v) => b.password = v as String?,
          annotations: const [
            JsonProperty('', access: JsonPropertyAccess.writeOnly),
          ],
        ),
        _p<Account>(
          'version',
          (b) => b.version,
          const ClassType<int>(),
          set: (b, v) => b.version = v! as int,
          annotations: const [
            JsonProperty('v', access: JsonPropertyAccess.readOnly),
          ],
        ),
      ],
      constructor: BeanConstructor<Account>(
        parameters: const [
          BeanParameter('id', type: ClassType<String>(), isRequired: true),
          BeanParameter(
            'nickname',
            type: ClassType<String>(nullable: true),
            symbol: #nickname,
            annotations: [JsonProperty('', required: true)],
          ),
        ],
        create: (positional, named) => Account(
          positional[0]! as String,
          nickname: named[#nickname] as String?,
        ),
      ),
    ),
    BeanIntrospection<Ticket>(
      properties: [
        _p<Ticket>(
          'code',
          (b) => b.code,
          const ClassType<String>(),
          annotations: const [
            JsonProperty('', access: JsonPropertyAccess.readOnly),
          ],
        ),
      ],
      constructor: BeanConstructor<Ticket>(
        parameters: const [
          BeanParameter('code', type: ClassType<String>(), isRequired: true),
        ],
        create: (positional, named) => Ticket(positional[0]! as String),
      ),
    ),
    BeanIntrospection<Counter>(
      properties: [
        _p<Counter>('count', (b) => b.count, const ClassType<int>()),
        _p<Counter>('enabled', (b) => b.enabled, const ClassType<bool>()),
        _p<Counter>('ratio', (b) => b.ratio, const ClassType<double>()),
        _p<Counter>(
          'optional',
          (b) => b.optional,
          const ClassType<int>(nullable: true),
          set: (b, v) => b.optional = v as int?,
        ),
        _p<Counter>(
          'total',
          (b) => b.total,
          const ClassType<int>(),
          set: (b, v) => b.total = v! as int,
        ),
      ],
      constructor: BeanConstructor<Counter>(
        parameters: const [
          BeanParameter('count', type: ClassType<int>(), isRequired: true),
          BeanParameter('enabled', type: ClassType<bool>(), isRequired: true),
          BeanParameter('ratio', type: ClassType<double>(), symbol: #ratio),
        ],
        create: (positional, named) => Counter(
          positional[0]! as int,
          positional[1]! as bool,
          ratio: (named[#ratio] ?? 1.0) as double,
        ),
      ),
    ),
    // A bounded generic class: raw only (what the generator writes).
    BeanIntrospection<Range<num>>(
      className: 'Range',
      properties: [_p<Range<num>>('low', (b) => b.low, const ClassType<num>())],
    ),
  ],
);

Matcher _mappingError(String message) => throwsA(
  isA<JsonMappingException>().having(
    (e) => e.toString(),
    'message',
    contains(message),
  ),
);

void main() {
  final mapper = ObjectMapper(introspector: _introspector);

  group('enums without their own EnumType', () {
    test('top-level reads and writes use the registered EnumType', () {
      expect(mapper.readValue<Color>('"green"'), Color.green);
      expect(mapper.readValue<Color?>('null'), isNull);
      expect(mapper.readValue<Stock>('"sold_out"'), Stock.soldOut);
      expect(mapper.readList<Stock>('["in_stock","sold_out"]'), [
        Stock.inStock,
        Stock.soldOut,
      ]);
      expect(mapper.readMap<Stock>('{"a":"in_stock"}'), {'a': Stock.inStock});
      expect(mapper.writeValueAsString(Stock.soldOut), '"sold_out"');
      expect(mapper.writeValueAsString([Stock.inStock]), '["in_stock"]');
      expect(mapper.valueToTree({'s': Stock.soldOut}), {'s': 'sold_out'});
      expect(mapper.valueToTree({Stock.soldOut: 1}), {'sold_out': 1});
      expect(
        mapper.readValue(
          '{"in_stock":1}',
          MapType<Stock, int>(const ClassType<Stock>(), const ClassType<int>()),
        ),
        {Stock.inStock: 1},
      );
    });

    test('an Object? property holding an enum honours @JsonValue', () {
      final palette = Palette()..anything = Stock.inStock;
      expect(mapper.valueToTree(palette), {
        'anything': 'in_stock',
        'color': 'red',
        'stocks': <String, Object?>{},
      });
    });

    test('an enum no introspected class uses: a clear error', () {
      expect(
        () => mapper.readValue<Lonely>('"a"'),
        _mappingError('cannot read the enum Lonely'),
      );
      expect(
        mapper.readValue('"b"', const EnumType<Lonely>(Lonely.values)),
        Lonely.b,
      );
      final introspector = BeanIntrospector()
        ..registerEnum(const EnumType<Lonely>(Lonely.values));
      expect(
        ObjectMapper(introspector: introspector).readValue<Lonely>('"a"'),
        Lonely.a,
      );
    });
  });

  test('an unknown type id falls back to defaultImpl, like Jackson', () {
    final note = mapper.readValue<Note>('{"kind":"audio","text":"hi"}');
    expect(note, isA<TextNote>().having((n) => n.text, 'text', 'hi'));
    expect(mapper.readValue<Note>('{"text":"x"}'), isA<TextNote>());
  });

  group('@JsonValue on classes', () {
    test('a property: written as its value, read back via the constructor', () {
      expect(mapper.writeValueAsString(Isbn('978-0')), '"978-0"');
      expect(mapper.valueToTree(Shelf(Isbn('1'))), {'isbn': '1'});
      expect(mapper.readValue<Shelf>('{"isbn":"2"}').isbn.value, '2');
      expect(mapper.readValue<Isbn>('"3"').value, '3');
    });

    test('map keys are written as their @JsonValue', () {
      expect(mapper.writeValueAsString({Isbn('978-0'): 1}), '{"978-0":1}');
      expect(mapper.writeValueAsString({Label(): 2}), '{"L-1":2}');
    });

    test('a method', () {
      expect(mapper.writeValueAsString(Label()), '"L-1"');
      expect(
        () => mapper.readValue<Label>('"L-1"'),
        _mappingError('it is written through its @JsonValue'),
      );
    });
  });

  group('@JsonProperty(access:, required:)', () {
    test('writeOnly is read, not written; readOnly is written, not read', () {
      final account = mapper.readValue<Account>(
        '{"id":"a","nickname":null,"password":"secret","v":7}',
      );
      expect(account.password, 'secret');
      expect(account.version, 1);
      expect(mapper.valueToTree(account..version = 3), {
        'id': 'a',
        'nickname': null,
        'v': 3,
      });
    });

    test('a read-only constructor property is not read, and says so', () {
      expect(mapper.writeValueAsString(Ticket('t-1')), '{"code":"t-1"}');
      expect(
        () => mapper.readValue<Ticket>('{"code":"t-1"}'),
        _mappingError(
          'property "code" is read-only (JsonPropertyAccess.readOnly), so it '
          'is not read from JSON, but the constructor of Ticket requires it',
        ),
      );
    });

    test('required constructor parameters must be present', () {
      expect(
        () => mapper.readValue<Account>('{"id":"a"}'),
        _mappingError('missing required creator property "nickname"'),
      );
      expect(
        mapper.readValue<Account>('{"id":"a","nickname":"n"}').nickname,
        'n',
      );
    });
  });

  group('null for primitives (Jackson 3: FAIL_ON_NULL_FOR_PRIMITIVES on)', () {
    test('null or a missing creator value fails by default', () {
      expect(
        () => mapper.readValue<Counter>('{"count":null,"enabled":true}'),
        _mappingError('null is not allowed here'),
      );
      expect(
        () => mapper.readValue<Counter>('{"enabled":true}'),
        _mappingError('missing property "count"'),
      );
      expect(
        () => mapper.readValue<int>('null'),
        _mappingError('null is not allowed here'),
      );
      expect(
        mapper.isEnabled(DeserializationFeature.failOnNullForPrimitives),
        isTrue,
      );
    });

    test('off: 0 and false, like Java primitives', () {
      final lenient = mapper
          .rebuild()
          .disable(DeserializationFeature.failOnNullForPrimitives)
          .build();
      final counter = lenient.readValue<Counter>(
        '{"count":null,"ratio":null,"total":null,"optional":null}',
      );
      expect(counter.count, 0);
      expect(counter.enabled, isFalse);
      expect(counter.ratio, 0.0);
      expect(counter.total, 0);
      expect(counter.optional, isNull);
      expect(lenient.readValue<bool>('null'), isFalse);
      expect(lenient.readValue<int?>('null'), isNull);
      // Not a primitive: still an error.
      expect(
        () => lenient.readValue<Isbn>('null'),
        _mappingError('null is not allowed here'),
      );
    });
  });

  test('a bounded generic class read with type arguments: a clear error', () {
    expect(
      () => mapper.readValue(
        '{"low":1}',
        const GenericType<Range<int>>([ClassType<int>()]),
      ),
      _mappingError('Range has bounded type parameters'),
    );
  });

  test('JsonNode.hashCode does not depend on the key order', () {
    final a = mapper.readTree('{"a":1,"b":[1,{"c":2,"d":3}]}');
    final b = mapper.readTree('{"b":[1,{"d":3,"c":2}],"a":1}');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect({a}.contains(b), isTrue);
    expect(
      mapper.readTree('[1,2]').hashCode,
      isNot(mapper.readTree('[2,1]').hashCode),
    );
    expect(mapper.readTree('1.0'), mapper.readTree('1'));
    expect(mapper.readTree('1.0').hashCode, mapper.readTree('1').hashCode);
  });

  test('durations are written like Java Duration.toString()', () {
    String write(Duration d) => mapper.writeValueAsString(d);
    expect(write(const Duration(seconds: -90)), '"PT-1M-30S"');
    expect(write(const Duration(hours: -1)), '"PT-1H"');
    expect(write(const Duration(milliseconds: -1500)), '"PT-1.5S"');
    expect(write(const Duration(milliseconds: -500)), '"PT-0.5S"');
    expect(write(const Duration(minutes: 1, seconds: 30)), '"PT1M30S"');
    expect(write(const Duration(milliseconds: 1500)), '"PT1.5S"');
    expect(write(const Duration(hours: 2)), '"PT2H"');
    expect(write(Duration.zero), '"PT0S"');
    expect(
      mapper.readValue<Duration>('"PT-1M-30S"'),
      const Duration(seconds: -90),
    );
    expect(
      mapper.readValue<Duration>('"PT-1.5S"'),
      const Duration(milliseconds: -1500),
    );
  });
}
