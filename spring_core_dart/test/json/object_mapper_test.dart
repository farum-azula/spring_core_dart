import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

enum Genre { fiction, science }

enum Stock {
  inStock('in_stock'),
  soldOut('sold_out');

  const Stock(this.json);
  final String json;
}

class Author {
  const Author(this.name, [this.born]);
  final String name;
  final int? born;
}

@JsonIgnoreProperties(value: ['secret'])
class Book {
  const Book({
    required this.isbn,
    required this.title,
    this.tags = const [],
    this.author,
    this.genre = Genre.fiction,
    this.stock = Stock.inStock,
    this.published,
    this.ratings = const {},
    this.note,
  });
  final String isbn;
  final String title;
  final List<String> tags;
  final Author? author;
  final Genre genre;
  final Stock stock;
  final DateTime? published;
  final Map<String, int> ratings;
  final String? note;
}

class Patch {
  @JsonProperty('the_title')
  String? title;
  @JsonIgnore()
  String? password;
  int count = 0;
  Set<String> labels = {};
  Duration? timeout;
  Uri? link;
  BigInt? big;
}

class Legacy {
  Legacy(this.value);
  factory Legacy.fromJson(Map<String, dynamic> json) =>
      Legacy(json['v'] as String);
  final String value;
  Map<String, Object?> toJson() => {'v': value};
}

class Plain {
  Plain(this.id);
  final int id;
  Map<String, Object?> toJson() => {'id': id};
}

class Money {
  const Money(this.cents, this.currency);
  final int cents;
  final String currency;
}

final class MoneySerializer extends JsonSerializer<Money> {
  const MoneySerializer();
  @override
  Object? serialize(Money value, ObjectMapper mapper) =>
      '${value.cents} ${value.currency}';
}

final class MoneyDeserializer extends JsonDeserializer<Money> {
  const MoneyDeserializer();
  @override
  Money deserialize(Object json, ObjectMapper mapper) {
    final [cents, currency] = (json as String).split(' ');
    return Money(int.parse(cents), currency);
  }
}

class Node {
  Node? next;
}

// What the generator writes for the classes above.
final _introspections = <BeanIntrospection<Object>>[
  BeanIntrospection<Author>(
    properties: [
      BeanProperty<Author>(
        'name',
        type: String,
        typeInfo: const ClassType<String>(),
        get: (b) => b.name,
      ),
      BeanProperty<Author>(
        'born',
        type: int,
        nullable: true,
        typeInfo: const ClassType<int>(nullable: true),
        get: (b) => b.born,
      ),
    ],
    constructor: BeanConstructor<Author>(
      parameters: const [
        BeanParameter('name', type: ClassType<String>(), isRequired: true),
        BeanParameter('born', type: ClassType<int>(nullable: true)),
      ],
      create: (positional, named) =>
          Function.apply(Author.new, positional, named) as Author,
    ),
  ),
  BeanIntrospection<Book>(
    annotations: const [
      JsonIgnoreProperties(value: ['secret']),
    ],
    properties: [
      BeanProperty<Book>(
        'isbn',
        type: String,
        typeInfo: const ClassType<String>(),
        get: (b) => b.isbn,
      ),
      BeanProperty<Book>(
        'title',
        type: String,
        typeInfo: const ClassType<String>(),
        get: (b) => b.title,
      ),
      BeanProperty<Book>(
        'tags',
        type: List<String>,
        typeInfo: const ListType<String>(ClassType<String>()),
        get: (b) => b.tags,
      ),
      BeanProperty<Book>(
        'author',
        type: Author,
        nullable: true,
        typeInfo: const ClassType<Author>(nullable: true),
        get: (b) => b.author,
      ),
      BeanProperty<Book>(
        'genre',
        type: Genre,
        typeInfo: const EnumType<Genre>(Genre.values),
        get: (b) => b.genre,
      ),
      BeanProperty<Book>(
        'stock',
        type: Stock,
        typeInfo: EnumType<Stock>(Stock.values, jsonValue: (e) => e.json),
        get: (b) => b.stock,
      ),
      BeanProperty<Book>(
        'published',
        type: DateTime,
        nullable: true,
        typeInfo: const ClassType<DateTime>(nullable: true),
        get: (b) => b.published,
      ),
      BeanProperty<Book>(
        'ratings',
        type: Map<String, int>,
        typeInfo: const MapType<String, int>(
          ClassType<String>(),
          ClassType<int>(),
        ),
        get: (b) => b.ratings,
      ),
      BeanProperty<Book>(
        'note',
        type: String,
        nullable: true,
        typeInfo: const ClassType<String>(nullable: true),
        get: (b) => b.note,
      ),
    ],
    constructor: BeanConstructor<Book>(
      parameters: [
        const BeanParameter(
          'isbn',
          type: ClassType<String>(),
          symbol: #isbn,
          isRequired: true,
        ),
        const BeanParameter(
          'title',
          type: ClassType<String>(),
          symbol: #title,
          isRequired: true,
        ),
        const BeanParameter(
          'tags',
          type: ListType<String>(ClassType<String>()),
          symbol: #tags,
        ),
        const BeanParameter(
          'author',
          type: ClassType<Author>(nullable: true),
          symbol: #author,
        ),
        const BeanParameter(
          'genre',
          type: EnumType<Genre>(Genre.values),
          symbol: #genre,
        ),
        BeanParameter(
          'stock',
          type: EnumType<Stock>(Stock.values, jsonValue: (e) => e.json),
          symbol: #stock,
        ),
        const BeanParameter(
          'published',
          type: ClassType<DateTime>(nullable: true),
          symbol: #published,
        ),
        const BeanParameter(
          'ratings',
          type: MapType<String, int>(ClassType<String>(), ClassType<int>()),
          symbol: #ratings,
        ),
        const BeanParameter(
          'note',
          type: ClassType<String>(nullable: true),
          symbol: #note,
        ),
      ],
      create: (positional, named) =>
          Function.apply(Book.new, positional, named) as Book,
    ),
  ),
  BeanIntrospection<Patch>(
    properties: [
      BeanProperty<Patch>(
        'title',
        type: String,
        nullable: true,
        typeInfo: const ClassType<String>(nullable: true),
        get: (b) => b.title,
        set: (b, v) => b.title = v as String?,
        annotations: const [JsonProperty('the_title')],
      ),
      BeanProperty<Patch>(
        'password',
        type: String,
        nullable: true,
        typeInfo: const ClassType<String>(nullable: true),
        get: (b) => b.password,
        set: (b, v) => b.password = v as String?,
        annotations: const [JsonIgnore()],
      ),
      BeanProperty<Patch>(
        'count',
        type: int,
        typeInfo: const ClassType<int>(),
        get: (b) => b.count,
        set: (b, v) => b.count = v! as int,
      ),
      BeanProperty<Patch>(
        'labels',
        type: Set<String>,
        typeInfo: const SetType<String>(ClassType<String>()),
        get: (b) => b.labels,
        set: (b, v) => b.labels = v! as Set<String>,
      ),
      BeanProperty<Patch>(
        'timeout',
        type: Duration,
        nullable: true,
        typeInfo: const ClassType<Duration>(nullable: true),
        get: (b) => b.timeout,
        set: (b, v) => b.timeout = v as Duration?,
      ),
      BeanProperty<Patch>(
        'link',
        type: Uri,
        nullable: true,
        typeInfo: const ClassType<Uri>(nullable: true),
        get: (b) => b.link,
        set: (b, v) => b.link = v as Uri?,
      ),
      BeanProperty<Patch>(
        'big',
        type: BigInt,
        nullable: true,
        typeInfo: const ClassType<BigInt>(nullable: true),
        get: (b) => b.big,
        set: (b, v) => b.big = v as BigInt?,
      ),
    ],
    instantiate: Patch.new,
  ),
  BeanIntrospection<Legacy>(
    fromJson: (json) => Legacy.fromJson(json! as Map<String, dynamic>),
    toJson: (bean) => bean.toJson(),
  ),
  BeanIntrospection<Node>(
    properties: [
      BeanProperty<Node>(
        'next',
        type: Node,
        nullable: true,
        typeInfo: const ClassType<Node>(nullable: true),
        get: (b) => b.next,
        set: (b, v) => b.next = v as Node?,
      ),
    ],
    instantiate: Node.new,
  ),
];

void main() {
  final introspector = BeanIntrospector(introspections: _introspections);
  final mapper = ObjectMapper(introspector: introspector);

  final book = Book(
    isbn: '978-0',
    title: 'Dune',
    tags: ['sf'],
    author: const Author('Herbert', 1920),
    genre: Genre.science,
    stock: Stock.soldOut,
    published: DateTime.utc(1965, 8),
    ratings: {'ann': 5},
  );

  group('immutable classes through the constructor', () {
    test('round trip with nested objects, enums, lists, maps, dates', () {
      final json = mapper.writeValueAsString(book);
      expect(
        json,
        '{"author":{"born":1920,"name":"Herbert"},"genre":"science",'
        '"isbn":"978-0","note":null,"published":"1965-08-01T00:00:00.000Z",'
        '"ratings":{"ann":5},"stock":"sold_out","tags":["sf"],'
        '"title":"Dune"}',
      );
      final again = mapper.readValue<Book>(json);
      expect(again.tags, isA<List<String>>());
      expect(again.ratings, isA<Map<String, int>>());
      expect(again.author!.born, 1920);
      expect(again.stock, Stock.soldOut);
      expect(again.genre, Genre.science);
      expect(again.published, DateTime.utc(1965, 8));
    });

    test('missing optional values keep their defaults', () {
      final read = mapper.readValue<Book>('{"isbn":"1","title":"T"}');
      expect(read.tags, isEmpty);
      expect(read.genre, Genre.fiction);
      expect(read.stock, Stock.inStock);
      expect(read.author, isNull);
      // A trailing optional positional parameter too.
      expect(
        mapper
            .readValue<Book>('{"isbn":"1","title":"T","author":{"name":"A"}}')
            .author!
            .born,
        isNull,
      );
    });

    test('enum values by @JsonValue and by name', () {
      expect(
        mapper
            .readValue<Book>('{"isbn":"1","title":"T","stock":"soldOut"}')
            .stock,
        Stock.soldOut,
      );
    });
  });

  group('mutable classes through setters', () {
    test('@JsonProperty, @JsonIgnore, sets, durations, URIs, big integers', () {
      final patch = Patch()
        ..title = 'x'
        ..password = 'secret'
        ..count = 2
        ..labels = {'a'}
        ..timeout = const Duration(minutes: 1, seconds: 30)
        ..link = Uri.parse('https://neon.books')
        ..big = BigInt.parse('123456789012345678901234567890');
      final tree = mapper.valueToTree(patch);
      expect(tree, {
        'the_title': 'x',
        'count': 2,
        'labels': ['a'],
        'timeout': 'PT1M30S',
        'link': 'https://neon.books',
        'big': '123456789012345678901234567890',
      });
      final read = mapper.convertValue<Patch>({
        ...tree! as Map<String, Object?>,
        'password': 'ignored',
        'timeout': '10s',
      });
      expect(read.title, 'x');
      expect(read.password, isNull);
      expect(read.labels, isA<Set<String>>());
      expect(read.timeout, const Duration(seconds: 10));
      expect(read.big, patch.big);
    });

    test('numbers and booleans in strings are accepted', () {
      expect(mapper.convertValue<Patch>({'count': '7'}).count, 7);
      expect(mapper.convertValue<Patch>({'count': 7.0}).count, 7);
    });
  });

  group('settings', () {
    test('naming strategy, inclusion, timestamps, indentation', () {
      final snake = ObjectMapper(
        introspector: introspector,
        namingStrategy: PropertyNamingStrategy.snakeCase,
        inclusion: JsonInclusion.nonNull,
        writeDatesAsTimestamps: true,
      );
      final tree = snake.valueToTree(book)! as Map<String, Object?>;
      // Jackson 3: seconds with the fraction (WRITE_DATE_TIMESTAMPS_AS_NANOSECONDS).
      expect(tree['published'], -139449600.0);
      expect(tree.containsKey('note'), isFalse);
      final read = snake.treeToValue<Book>(tree);
      expect(read.published, DateTime.utc(1965, 8));
      expect(
        ObjectMapper(
          introspector: introspector,
          indentOutput: true,
        ).writeValueAsString(const Author('A')),
        '{\n  "born": null,\n  "name": "A"\n}',
      );
    });

    test('unknown properties: ignored by default, an error when asked', () {
      const json = '{"isbn":"1","title":"T","extra":1,"secret":2}';
      expect(mapper.readValue<Book>(json).isbn, '1');
      final strict = ObjectMapper(
        introspector: introspector,
        failOnUnknownProperties: true,
      );
      expect(
        () => strict.readValue<Book>(json),
        throwsA(
          isA<JsonMappingException>().having(
            (e) => e.message,
            'message',
            contains('unknown property "extra"'),
          ),
        ),
      );
      // "secret" is in @JsonIgnoreProperties: fine even when strict.
      expect(
        strict.readValue<Book>('{"isbn":"1","title":"T","secret":2}').isbn,
        '1',
      );
    });

    test('naming strategies', () {
      expect(
        PropertyNamingStrategy.snakeCase.translate('publishedAt'),
        'published_at',
      );
      expect(
        PropertyNamingStrategy.snakeCase.translate('URLValue'),
        'urlvalue',
      );
      expect(PropertyNamingStrategy.snakeCase.translate('isbn13'), 'isbn13');
      expect(
        PropertyNamingStrategy.upperSnakeCase.translate('publishedAt'),
        'PUBLISHED_AT',
      );
      expect(
        PropertyNamingStrategy.kebabCase.translate('publishedAt'),
        'published-at',
      );
      expect(
        PropertyNamingStrategy.upperCamelCase.translate('publishedAt'),
        'PublishedAt',
      );
      expect(
        PropertyNamingStrategy.lowerDotCase.translate('publishedAt'),
        'published.at',
      );
      expect(
        PropertyNamingStrategy.lowerCase.translate('publishedAt'),
        'publishedat',
      );
      expect(
        PropertyNamingStrategy.parse('SNAKE_CASE'),
        PropertyNamingStrategy.snakeCase,
      );
      expect(
        PropertyNamingStrategy.parse('kebab-case'),
        PropertyNamingStrategy.kebabCase,
      );
      expect(() => PropertyNamingStrategy.parse('weird'), throwsArgumentError);
    });
  });

  group('generic and top-level values', () {
    test('readList, readMap, nullable roots, scalars', () {
      final books = mapper.readList<Book>('[{"isbn":"1","title":"A"}]');
      expect(books, isA<List<Book>>());
      expect(books.single.title, 'A');
      final byId = mapper.readMap<Author>('{"x":{"name":"X"}}');
      expect(byId['x']!.name, 'X');
      expect(mapper.readValue<Book?>('null'), isNull);
      expect(mapper.readValue<int>('42'), 42);
      expect(
        mapper.readValue<List<int>>(
          '[1,2]',
          const ListType<int>(ClassType<int>()),
        ),
        [1, 2],
      );
      expect(
        () => mapper.readValue<List<Book>>('[]'),
        throwsA(
          isA<JsonMappingException>().having(
            (e) => e.message,
            'message',
            contains('readList'),
          ),
        ),
      );
    });
  });

  group('own fromJson / toJson, plain toJson, custom serializers', () {
    test('a class with fromJson/toJson uses them', () {
      expect(mapper.writeValueAsString(Legacy('a')), '{"v":"a"}');
      expect(mapper.readValue<Legacy>('{"v":"b"}').value, 'b');
    });

    test('a class that is not introspected but has toJson can be written', () {
      expect(mapper.valueToTree([Plain(1)]), [
        {'id': 1},
      ]);
      expect(
        () => mapper.valueToTree(Object()),
        throwsA(isA<JsonMappingException>()),
      );
    });

    test('JsonSerializer and JsonDeserializer', () {
      final money = ObjectMapper(
        introspector: introspector,
        serializers: const [MoneySerializer()],
        deserializers: const [MoneyDeserializer()],
      );
      expect(
        money.writeValueAsString({'price': const Money(1250, 'EUR')}),
        '{"price":"1250 EUR"}',
      );
      final read = money.readMap<Money>('{"price":"990 USD"}');
      expect(read['price']!.cents, 990);
    });
  });

  group('errors say where', () {
    void expectError(void Function() body, String text) => expect(
      body,
      throwsA(
        isA<JsonMappingException>().having(
          (e) => '$e',
          'toString',
          contains(text),
        ),
      ),
    );

    test('wrong types, nulls, missing values, cycles', () {
      expectError(
        () => mapper.readList<Book>(
          '[{"isbn":"1","title":"A"},{"isbn":"2","title":"B","ratings":{"x":"five"}}]',
        ),
        '[1].ratings.x: expected an integer, got "five"',
      );
      expectError(
        () => mapper.readValue<Book>('{"isbn":"1","title":null}'),
        'title: null is not allowed here',
      );
      expectError(
        () => mapper.readValue<Book>('{"title":"T"}'),
        'missing property "isbn" (required by Book)',
      );
      expectError(
        () =>
            mapper.readValue<Book>('{"isbn":"1","title":"T","genre":"poetry"}'),
        'genre: expected one of "fiction", "science", got "poetry"',
      );
      expectError(() => mapper.readValue<Book>('{oops'), 'invalid JSON');
      final node = Node();
      node.next = node;
      expectError(() => mapper.writeValueAsString(node), 'cycle');
    });
  });

  group('Jackson parity', () {
    test('DateTime is written like an OffsetDateTime; UTC with Z', () {
      final local = DateTime(2026, 1, 1, 12);
      final written = mapper.valueToTree(local)! as String;
      expect(
        written,
        matches(RegExp(r'^2026-01-01T12:00:00\.000([+-]\d\d:\d\d|Z)$')),
      );
      expect(DateTime.parse(written).isAtSameMomentAs(local), isTrue);
      expect(
        mapper.writeValueAsString(DateTime.utc(2026, 1, 1, 12)),
        '"2026-01-01T12:00:00.000Z"',
      );
      expect(mapper.valueToTree({DateTime.utc(2026): 1}), {
        '2026-01-01T00:00:00.000Z': 1,
      });
    });

    test('timeZone converts to UTC or a fixed offset', () {
      final instant = DateTime.utc(2026, 1, 1, 10);
      expect(
        ObjectMapper(timeZone: '+02:00').valueToTree(instant),
        '2026-01-01T12:00:00.000+02:00',
      );
      expect(
        ObjectMapper(timeZone: 'GMT-05:30').valueToTree(instant),
        '2026-01-01T04:30:00.000-05:30',
      );
      expect(
        ObjectMapper(timeZone: 'UTC').valueToTree(instant.toLocal()),
        '2026-01-01T10:00:00.000Z',
      );
      expect(ObjectMapper(timeZone: 'Z').timeZone, 'Z');
      expect(
        () => ObjectMapper(timeZone: 'Europe/Berlin'),
        throwsArgumentError,
      );
    });

    test('reads what it writes, and Jackson Instant forms', () {
      final instant = DateTime.utc(2026, 1, 1, 10);
      for (final text in [
        '2026-01-01T12:00:00.000+02:00',
        '2026-01-01T12:00:00+02:00',
        '2026-01-01T10:00:00Z',
        '2026-01-01T10:00:00.000Z',
      ]) {
        expect(
          mapper.readValue<DateTime>('"$text"').isAtSameMomentAs(instant),
          isTrue,
          reason: text,
        );
      }
      final local = DateTime(2026, 3, 1, 8, 30);
      expect(
        mapper
            .readValue<DateTime>(mapper.writeValueAsString(local))
            .isAtSameMomentAs(local),
        isTrue,
      );
    });

    test('naming strategies keep acronyms like Jackson', () {
      String t(PropertyNamingStrategy s, String name) => s.translate(name);
      expect(t(PropertyNamingStrategy.snakeCase, 'myURLValue'), 'my_urlvalue');
      expect(t(PropertyNamingStrategy.snakeCase, 'URLValue'), 'urlvalue');
      expect(t(PropertyNamingStrategy.snakeCase, '_private'), 'private');
      expect(
        t(PropertyNamingStrategy.snakeCase, 'address1Line'),
        'address1_line',
      );
      expect(
        t(PropertyNamingStrategy.upperSnakeCase, 'myURLValue'),
        'MY_URLVALUE',
      );
      expect(
        t(PropertyNamingStrategy.upperCamelCase, 'myURLValue'),
        'MyURLValue',
      );
      expect(t(PropertyNamingStrategy.kebabCase, 'myURLValue'), 'my-url-value');
      expect(
        t(PropertyNamingStrategy.lowerDotCase, 'myURLValue'),
        'my.url.value',
      );
      expect(t(PropertyNamingStrategy.lowerCase, 'my_URLValue'), 'my_urlvalue');
    });

    test('Map, List and Object? without a TypeInfo are plain JSON', () {
      final map = mapper.readValue<Map<String, dynamic>>(
        '{"a":1,"b":[true,{"c":null}]}',
      );
      expect(map, {
        'a': 1,
        'b': [
          true,
          {'c': null},
        ],
      });
      expect(mapper.readValue<Map<String, Object?>>('{"a":1}'), {'a': 1});
      expect(mapper.readValue<List<dynamic>>('[1,"x"]'), [1, 'x']);
      expect(mapper.readValue<List<Object?>>('[null]'), [null]);
      expect(mapper.readValue<Object?>('{"a":[1]}'), {
        'a': [1],
      });
      expect(mapper.readValue<Object?>('null'), isNull);
    });

    test('NaN and infinities are written as strings and read back', () {
      expect(mapper.writeValueAsString(double.nan), '"NaN"');
      expect(
        mapper.writeValueAsString([double.infinity, double.negativeInfinity]),
        '["Infinity","-Infinity"]',
      );
      expect(mapper.readValue<double>('"NaN"').isNaN, isTrue);
      expect(mapper.readValue<double>('"Infinity"'), double.infinity);
      expect(mapper.readValue<num>('"-Infinity"'), double.negativeInfinity);
    });
  });
}
