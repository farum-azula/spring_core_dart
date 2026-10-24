import 'dart:convert';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

// The introspections below are what the generator writes for these classes.

enum Genre { fiction, science }

enum Stock {
  inStock('in_stock'),
  soldOut('sold_out');

  const Stock(this.json);
  final String json;
}

enum Level {
  low(10),
  high(20);

  const Level(this.code);
  final int code;
}

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

BeanConstructor<T> _ctor<T extends Object>(
  Function constructor,
  List<BeanParameter> parameters,
) => BeanConstructor<T>(
  parameters: parameters,
  create: (positional, named) =>
      Function.apply(constructor, positional, named) as T,
);

class Holder {
  int? n;
  DateTime? at;
  bool? flag;
  Map<Stock, int> counts = {};
}

class Author {
  const Author(this.name);
  final String name;
}

class Page<T> {
  Page(this.content, {this.total = 0});
  final List<T> content;
  final int total;
}

BeanIntrospection<Page<T>> _pageOf<T>(
  TypeInfo<T> element, {
  BeanIntrospection<Object> Function(List<TypeInfo<Object?>>)? specialize,
}) => BeanIntrospection<Page<T>>(
  className: 'Page',
  specialize: specialize,
  properties: [
    _p<Page<T>>('content', (b) => b.content, ListType<T>(element)),
    _p<Page<T>>('total', (b) => b.total, const ClassType<int>()),
  ],
  // A direct call, like the generator writes for generic classes (dart2js
  // cannot Function.apply named arguments to `Page<T>.new`).
  constructor: BeanConstructor<Page<T>>(
    parameters: [
      BeanParameter('content', type: ListType<T>(element), isRequired: true),
      const BeanParameter('total', type: ClassType<int>(), symbol: #total),
    ],
    create: (positional, named) => Page<T>(
      positional[0]! as List<T>,
      total: named.containsKey(#total) ? named[#total]! as int : 0,
    ),
  ),
);

class Shelf {
  Shelf(this.page);
  final Page<Author> page;
}

// Polymorphism: a type id property.
abstract class Animal {
  Animal(this.name);
  final String name;
}

class Dog extends Animal {
  Dog(super.name, {this.bark = true});
  final bool bark;
}

class Cat extends Animal {
  Cat(super.name, {this.lives = 9});
  final int lives;
}

// A wrapper object, a wrapper array, deduction, an existing visible
// property with a default implementation.
abstract class Shape {}

class Circle extends Shape {
  Circle(this.r);
  final int r;
}

abstract class Item {}

class Thing extends Item {
  Thing(this.id);
  final int id;
}

abstract class Vehicle {}

class Car extends Vehicle {
  Car(this.wheels, this.doors);
  final int wheels;
  final int doors;
}

class Bike extends Vehicle {
  Bike(this.wheels, this.gears);
  final int wheels;
  final int gears;
}

abstract class Message {
  Message(this.type);
  final String? type;
}

class TextMessage extends Message {
  TextMessage(super.type, this.body);
  final String body;
}

class ImageMessage extends Message {
  ImageMessage(super.type, this.url);
  final String url;
}

class Contact {
  Contact({required this.name});
  final String name;
}

class Event {
  DateTime at = DateTime.utc(2026);
  Genre genre = Genre.fiction;
  int count = 0;
  DateTime stamp = DateTime.utc(2026);
  Duration wait = Duration.zero;
}

class Point {
  Point(this.x, this.y);
  final int x;
  final int y;
}

class Bag {
  String id = '';
  Map<String, Object?> extra = {};
}

class Props {
  Props({required this.id, this.rest = const {}});
  final String id;
  final Map<String, int> rest;
}

class MethodBag {
  final data = <String, Object?>{};
  void put(String key, Object? value) => data[key] = value;
  Map<String, Object?> all() => data;
}

class Address {
  Address({required this.city, this.zip});
  final String city;
  final String? zip;
}

class Person {
  Person(this.name, this.address);
  final String name;
  final Address? address;
}

class Row {
  String bookTitle = '';
  String isbnCode = '';
}

class Public {}

class Internal extends Public {}

class User {
  String id = '';
  String name = '';
  String email = '';
}

class Counter {
  int count = 0;
  String label = 'x';
  List<String> tags = [];
  String? note;
}

class Score {
  int points = 5;
  bool flag = false;
  String? memo;
}

final _introspections = <BeanIntrospection<Object>>[
  BeanIntrospection<Holder>(
    instantiate: Holder.new,
    properties: [
      _p<Holder>(
        'n',
        (b) => b.n,
        const ClassType<int>(nullable: true),
        set: (b, v) => b.n = v as int?,
      ),
      _p<Holder>(
        'at',
        (b) => b.at,
        const ClassType<DateTime>(nullable: true),
        set: (b, v) => b.at = v as DateTime?,
      ),
      _p<Holder>(
        'flag',
        (b) => b.flag,
        const ClassType<bool>(nullable: true),
        set: (b, v) => b.flag = v as bool?,
      ),
      _p<Holder>(
        'counts',
        (b) => b.counts,
        MapType<Stock, int>(_stock, const ClassType<int>()),
        set: (b, v) => b.counts = v! as Map<Stock, int>,
      ),
    ],
  ),
  BeanIntrospection<Author>(
    properties: [_p<Author>('name', (b) => b.name, const ClassType<String>())],
    constructor: _ctor<Author>(Author.new, [
      const BeanParameter('name', type: ClassType<String>(), isRequired: true),
    ]),
  ),
  _pageOf<Object?>(
    const DynamicType(),
    specialize: (arguments) =>
        arguments[0].capture(<T>() => _pageOf<T>(arguments[0] as TypeInfo<T>)),
  ),
  BeanIntrospection<Shelf>(
    properties: [
      _p<Shelf>(
        'page',
        (b) => b.page,
        const GenericType<Page<Author>>([ClassType<Author>()]),
      ),
    ],
    constructor: _ctor<Shelf>(Shelf.new, [
      const BeanParameter(
        'page',
        type: GenericType<Page<Author>>([ClassType<Author>()]),
        isRequired: true,
      ),
    ]),
  ),
  BeanIntrospection<Animal>(
    className: 'Animal',
    annotations: const [
      JsonTypeInfo(property: 'kind'),
      JsonSubTypes([
        JsonSubType(Dog, name: 'dog', names: ['hound']),
        JsonSubType(Cat),
      ]),
    ],
    properties: [_p<Animal>('name', (b) => b.name, const ClassType<String>())],
  ),
  BeanIntrospection<Dog>(
    className: 'Dog',
    properties: [
      _p<Dog>('bark', (b) => b.bark, const ClassType<bool>()),
      _p<Dog>('name', (b) => b.name, const ClassType<String>()),
    ],
    constructor: _ctor<Dog>(Dog.new, [
      const BeanParameter('name', type: ClassType<String>(), isRequired: true),
      const BeanParameter('bark', type: ClassType<bool>(), symbol: #bark),
    ]),
  ),
  BeanIntrospection<Cat>(
    className: 'Cat',
    annotations: const [JsonTypeName('kitty')],
    properties: [
      _p<Cat>('lives', (b) => b.lives, const ClassType<int>()),
      _p<Cat>('name', (b) => b.name, const ClassType<String>()),
    ],
    constructor: _ctor<Cat>(Cat.new, [
      const BeanParameter('name', type: ClassType<String>(), isRequired: true),
      const BeanParameter('lives', type: ClassType<int>(), symbol: #lives),
    ]),
  ),
  BeanIntrospection<Shape>(
    annotations: const [
      JsonTypeInfo(include: JsonTypeInclusion.wrapperObject),
      JsonSubTypes([JsonSubType(Circle, name: 'circle')]),
    ],
  ),
  BeanIntrospection<Circle>(
    properties: [_p<Circle>('r', (b) => b.r, const ClassType<int>())],
    constructor: _ctor<Circle>(Circle.new, [
      const BeanParameter('r', type: ClassType<int>(), isRequired: true),
    ]),
  ),
  BeanIntrospection<Item>(
    annotations: const [
      JsonTypeInfo(include: JsonTypeInclusion.wrapperArray),
      JsonSubTypes([JsonSubType(Thing, name: 'thing')]),
    ],
  ),
  BeanIntrospection<Thing>(
    properties: [_p<Thing>('id', (b) => b.id, const ClassType<int>())],
    constructor: _ctor<Thing>(Thing.new, [
      const BeanParameter('id', type: ClassType<int>(), isRequired: true),
    ]),
  ),
  BeanIntrospection<Vehicle>(
    annotations: const [
      JsonTypeInfo(use: JsonTypeId.deduction),
      JsonSubTypes([JsonSubType(Car), JsonSubType(Bike)]),
    ],
  ),
  BeanIntrospection<Car>(
    properties: [
      _p<Car>('wheels', (b) => b.wheels, const ClassType<int>()),
      _p<Car>('doors', (b) => b.doors, const ClassType<int>()),
    ],
    constructor: _ctor<Car>(Car.new, [
      const BeanParameter('wheels', type: ClassType<int>(), isRequired: true),
      const BeanParameter('doors', type: ClassType<int>(), isRequired: true),
    ]),
  ),
  BeanIntrospection<Bike>(
    properties: [
      _p<Bike>('wheels', (b) => b.wheels, const ClassType<int>()),
      _p<Bike>('gears', (b) => b.gears, const ClassType<int>()),
    ],
    constructor: _ctor<Bike>(Bike.new, [
      const BeanParameter('wheels', type: ClassType<int>(), isRequired: true),
      const BeanParameter('gears', type: ClassType<int>(), isRequired: true),
    ]),
  ),
  BeanIntrospection<Message>(
    annotations: const [
      JsonTypeInfo(
        include: JsonTypeInclusion.existingProperty,
        property: 'type',
        visible: true,
        defaultImpl: TextMessage,
      ),
      JsonSubTypes([
        JsonSubType(TextMessage, name: 'text'),
        JsonSubType(ImageMessage, name: 'image'),
      ]),
    ],
    properties: [
      _p<Message>(
        'type',
        (b) => b.type,
        const ClassType<String>(nullable: true),
      ),
    ],
  ),
  BeanIntrospection<TextMessage>(
    properties: [
      _p<TextMessage>(
        'type',
        (b) => b.type,
        const ClassType<String>(nullable: true),
      ),
      _p<TextMessage>('body', (b) => b.body, const ClassType<String>()),
    ],
    constructor: _ctor<TextMessage>(TextMessage.new, [
      const BeanParameter(
        'type',
        type: ClassType<String>(nullable: true),
        isRequired: true,
      ),
      const BeanParameter('body', type: ClassType<String>(), isRequired: true),
    ]),
  ),
  BeanIntrospection<ImageMessage>(
    properties: [
      _p<ImageMessage>(
        'type',
        (b) => b.type,
        const ClassType<String>(nullable: true),
      ),
      _p<ImageMessage>('url', (b) => b.url, const ClassType<String>()),
    ],
    constructor: _ctor<ImageMessage>(ImageMessage.new, [
      const BeanParameter(
        'type',
        type: ClassType<String>(nullable: true),
        isRequired: true,
      ),
      const BeanParameter('url', type: ClassType<String>(), isRequired: true),
    ]),
  ),
  BeanIntrospection<Contact>(
    properties: [_p<Contact>('name', (b) => b.name, const ClassType<String>())],
    constructor: _ctor<Contact>(Contact.new, [
      const BeanParameter(
        'name',
        type: ClassType<String>(),
        symbol: #name,
        isRequired: true,
        annotations: [
          JsonAlias(['fullName', 'n']),
        ],
      ),
    ]),
  ),
  BeanIntrospection<Event>(
    instantiate: Event.new,
    properties: [
      _p<Event>(
        'at',
        (b) => b.at,
        const ClassType<DateTime>(),
        set: (b, v) => b.at = v! as DateTime,
        annotations: const [
          JsonFormat(pattern: 'dd.MM.yyyy HH:mm', timezone: '+01:00'),
        ],
      ),
      _p<Event>(
        'genre',
        (b) => b.genre,
        const EnumType<Genre>(Genre.values),
        set: (b, v) => b.genre = v! as Genre,
        annotations: const [JsonFormat(shape: JsonFormatShape.number)],
      ),
      _p<Event>(
        'count',
        (b) => b.count,
        const ClassType<int>(),
        set: (b, v) => b.count = v! as int,
        annotations: const [JsonFormat(shape: JsonFormatShape.string)],
      ),
      _p<Event>(
        'stamp',
        (b) => b.stamp,
        const ClassType<DateTime>(),
        set: (b, v) => b.stamp = v! as DateTime,
        annotations: const [JsonFormat(shape: JsonFormatShape.number)],
      ),
      _p<Event>(
        'wait',
        (b) => b.wait,
        const ClassType<Duration>(),
        set: (b, v) => b.wait = v! as Duration,
        annotations: const [JsonFormat(shape: JsonFormatShape.number)],
      ),
    ],
  ),
  BeanIntrospection<Point>(
    annotations: const [JsonFormat(shape: JsonFormatShape.array)],
    properties: [
      _p<Point>('x', (b) => b.x, const ClassType<int>()),
      _p<Point>('y', (b) => b.y, const ClassType<int>()),
    ],
    constructor: _ctor<Point>(Point.new, [
      const BeanParameter('x', type: ClassType<int>(), isRequired: true),
      const BeanParameter('y', type: ClassType<int>(), isRequired: true),
    ]),
  ),
  BeanIntrospection<Bag>(
    instantiate: Bag.new,
    properties: [
      _p<Bag>(
        'id',
        (b) => b.id,
        const ClassType<String>(),
        set: (b, v) => b.id = v! as String,
      ),
      _p<Bag>(
        'extra',
        (b) => b.extra,
        const MapType<String, Object?>(ClassType<String>(), DynamicType()),
        set: (b, v) => b.extra = v! as Map<String, Object?>,
        annotations: const [JsonAnyGetter(), JsonAnySetter()],
      ),
    ],
  ),
  BeanIntrospection<Props>(
    properties: [
      _p<Props>('id', (b) => b.id, const ClassType<String>()),
      _p<Props>(
        'rest',
        (b) => b.rest,
        const MapType<String, int>(ClassType<String>(), ClassType<int>()),
        annotations: const [JsonAnyGetter(), JsonAnySetter()],
      ),
    ],
    constructor: _ctor<Props>(Props.new, [
      const BeanParameter(
        'id',
        type: ClassType<String>(),
        symbol: #id,
        isRequired: true,
      ),
      const BeanParameter(
        'rest',
        type: MapType<String, int>(ClassType<String>(), ClassType<int>()),
        symbol: #rest,
      ),
    ]),
  ),
  BeanIntrospection<MethodBag>(
    instantiate: MethodBag.new,
    methods: [
      BeanMethod<MethodBag>(
        'put',
        invoke: (b, a) => b.put(a[0]! as String, a[1]),
        annotations: const [JsonAnySetter()],
      ),
      BeanMethod<MethodBag>(
        'all',
        invoke: (b, a) => b.all(),
        annotations: const [JsonAnyGetter()],
      ),
    ],
  ),
  BeanIntrospection<Address>(
    properties: [
      _p<Address>('city', (b) => b.city, const ClassType<String>()),
      _p<Address>('zip', (b) => b.zip, const ClassType<String>(nullable: true)),
    ],
    constructor: _ctor<Address>(Address.new, [
      const BeanParameter(
        'city',
        type: ClassType<String>(),
        symbol: #city,
        isRequired: true,
      ),
      const BeanParameter(
        'zip',
        type: ClassType<String>(nullable: true),
        symbol: #zip,
      ),
    ]),
  ),
  BeanIntrospection<Person>(
    properties: [
      _p<Person>('name', (b) => b.name, const ClassType<String>()),
      _p<Person>(
        'address',
        (b) => b.address,
        const ClassType<Address>(nullable: true),
        annotations: const [JsonUnwrapped(prefix: 'home_')],
      ),
    ],
    constructor: _ctor<Person>(Person.new, [
      const BeanParameter('name', type: ClassType<String>(), isRequired: true),
      const BeanParameter(
        'address',
        type: ClassType<Address>(nullable: true),
        isRequired: true,
      ),
    ]),
  ),
  BeanIntrospection<Row>(
    instantiate: Row.new,
    annotations: const [JsonNaming(PropertyNamingStrategy.snakeCase)],
    properties: [
      _p<Row>(
        'bookTitle',
        (b) => b.bookTitle,
        const ClassType<String>(),
        set: (b, v) => b.bookTitle = v! as String,
      ),
      _p<Row>(
        'isbnCode',
        (b) => b.isbnCode,
        const ClassType<String>(),
        set: (b, v) => b.isbnCode = v! as String,
        annotations: const [JsonProperty('ISBN')],
      ),
    ],
  ),
  BeanIntrospection<Public>(instantiate: Public.new),
  BeanIntrospection<Internal>(instantiate: Internal.new),
  BeanIntrospection<User>(
    instantiate: User.new,
    properties: [
      _p<User>(
        'id',
        (b) => b.id,
        const ClassType<String>(),
        set: (b, v) => b.id = v! as String,
      ),
      _p<User>(
        'name',
        (b) => b.name,
        const ClassType<String>(),
        set: (b, v) => b.name = v! as String,
        annotations: const [
          JsonView([Public]),
        ],
      ),
      _p<User>(
        'email',
        (b) => b.email,
        const ClassType<String>(),
        set: (b, v) => b.email = v! as String,
        annotations: const [
          JsonView([Internal]),
        ],
      ),
    ],
  ),
  BeanIntrospection<Counter>(
    instantiate: Counter.new,
    annotations: const [JsonInclude(JsonInclusion.nonDefault)],
    properties: [
      _p<Counter>('count', (b) => b.count, const ClassType<int>()),
      _p<Counter>('label', (b) => b.label, const ClassType<String>()),
      _p<Counter>(
        'tags',
        (b) => b.tags,
        const ListType<String>(ClassType<String>()),
      ),
      _p<Counter>(
        'note',
        (b) => b.note,
        const ClassType<String>(nullable: true),
      ),
    ],
  ),
  BeanIntrospection<Score>(
    instantiate: Score.new,
    properties: [
      _p<Score>(
        'points',
        (b) => b.points,
        const ClassType<int>(),
        annotations: const [JsonInclude(JsonInclusion.nonDefault)],
      ),
      _p<Score>(
        'flag',
        (b) => b.flag,
        const ClassType<bool>(),
        annotations: const [JsonInclude(JsonInclusion.nonDefault)],
      ),
      _p<Score>(
        'memo',
        (b) => b.memo,
        const ClassType<String>(nullable: true),
        annotations: const [JsonInclude(JsonInclusion.nonAbsent)],
      ),
    ],
  ),
];

Matcher _mappingError(String text) => throwsA(
  isA<JsonMappingException>().having((e) => '$e', 'toString', contains(text)),
);

void main() {
  final introspector = BeanIntrospector(introspections: _introspections);
  final mapper = ObjectMapper(introspector: introspector);

  group('timestamps like Jackson 3', () {
    final instant = DateTime.utc(2023, 11, 14, 22, 13, 20, 123, 456);

    test('dates are written as seconds with the fraction', () {
      final stamps = ObjectMapper(writeDatesAsTimestamps: true);
      expect(stamps.valueToTree(instant), 1700000000.123456);
      // `1700000000.0` (on the web, where every number is a double:
      // `1700000000`).
      expect(
        jsonDecode(
          stamps.writeValueAsString(DateTime.utc(2023, 11, 14, 22, 13, 20)),
        ),
        1700000000,
      );
      // Without WRITE_DATE_TIMESTAMPS_AS_NANOSECONDS: epoch milliseconds.
      expect(
        ObjectMapper(
          writeDatesAsTimestamps: true,
          writeDateTimestampsAsNanoseconds: false,
        ).valueToTree(instant),
        1700000000123,
      );
    });

    test('durations are a separate feature, also in seconds', () {
      const wait = Duration(seconds: 90, milliseconds: 500);
      // WRITE_DATES_AS_TIMESTAMPS does not turn durations into numbers.
      expect(
        ObjectMapper(writeDatesAsTimestamps: true).valueToTree(wait),
        'PT1M30.5S',
      );
      expect(
        ObjectMapper(writeDurationsAsTimestamps: true).valueToTree(wait),
        90.5,
      );
      expect(
        ObjectMapper(
          writeDurationsAsTimestamps: true,
          writeDateTimestampsAsNanoseconds: false,
        ).valueToTree(wait),
        90500,
      );
    });

    test('numbers are read as seconds; decimals always', () {
      expect(
        mapper.readValue<DateTime>('1700000000'),
        DateTime.utc(2023, 11, 14, 22, 13, 20),
      );
      expect(
        mapper.readValue<DateTime>('1700000000.5'),
        DateTime.utc(2023, 11, 14, 22, 13, 20, 500),
      );
      // A numeric string too, with up to nanoseconds (cut to microseconds).
      expect(mapper.readValue<DateTime>('"1700000000.123456789"'), instant);
      expect(mapper.readValue<Duration>('90'), const Duration(seconds: 90));
      expect(
        mapper.readValue<Duration>('1.5'),
        const Duration(milliseconds: 1500),
      );
      final millis = ObjectMapper(readDateTimestampsAsNanoseconds: false);
      expect(
        millis.readValue<DateTime>('1700000000123'),
        DateTime.utc(2023, 11, 14, 22, 13, 20, 123),
      );
      expect(
        millis.readValue<Duration>('90'),
        const Duration(milliseconds: 90),
      );
      // A decimal is seconds whatever the setting.
      expect(
        millis.readValue<Duration>('1.5'),
        const Duration(milliseconds: 1500),
      );
    });

    test('what is written is read back', () {
      final stamps = ObjectMapper(
        writeDatesAsTimestamps: true,
        writeDurationsAsTimestamps: true,
      );
      expect(
        stamps.readValue<DateTime>(stamps.writeValueAsString(instant)),
        instant,
      );
      const wait = Duration(minutes: 2, microseconds: 7);
      expect(stamps.readValue<Duration>(stamps.writeValueAsString(wait)), wait);
    });
  });

  group('number and string leniency', () {
    test('a number out of range of int fails instead of saturating', () {
      expect(
        () => mapper.readValue<int>('1e20'),
        _mappingError('out of range of int'),
      );
      expect(
        () => mapper.readValue<int>('-1e19'),
        _mappingError('out of range of int'),
      );
      expect(
        () => mapper.readValue<int>('99999999999999999999'),
        _mappingError('out of range of int'),
      );
      expect(mapper.readValue<int>('1e3'), 1000);
    });

    test('a number with a fraction into an int is truncated', () {
      expect(mapper.readValue<int>('1.5'), 1);
      expect(mapper.readValue<int>('-2.7'), -2);
      expect(
        () => ObjectMapper(acceptFloatAsInt: false).readValue<int>('1.5'),
        _mappingError('cannot coerce floating-point value (1.5) to int'),
      );
      // A string with a fraction is not an integer.
      expect(() => mapper.readValue<int>('"1.5"'), _mappingError('integer'));
    });

    test('"" is null for nullable numbers, booleans and dates', () {
      final holder = mapper.readValue<Holder>('{"n":"","at":"","flag":""}');
      expect(holder.n, isNull);
      expect(holder.at, isNull);
      expect(holder.flag, isNull);
      expect(mapper.readValue<int?>('""'), isNull);
      expect(mapper.readValue<Duration?>('""'), isNull);
      expect(mapper.readValue<String?>('""'), '');
      expect(() => mapper.readValue<int>('""'), _mappingError('integer'));
    });

    test('dates without an offset are in the mapper time zone (UTC)', () {
      expect(
        mapper.readValue<DateTime>('"2026-01-01T10:00:00"'),
        DateTime.utc(2026, 1, 1, 10),
      );
      expect(mapper.readValue<DateTime>('"2026-01-01"'), DateTime.utc(2026));
      expect(
        ObjectMapper(timeZone: '+02:00')
            .readValue<DateTime>('"2026-01-01T10:00"'),
        DateTime.utc(2026, 1, 1, 8),
      );
      expect(
        mapper.readValue<DateTime>('"2026-01-01T10:00:00.5+0130"'),
        DateTime.utc(2026, 1, 1, 8, 30, 0, 500),
      );
    });

    test('dates are parsed strictly', () {
      for (final text in [
        '2026-02-30',
        '2026-13-01',
        '2026-01-01T24:00:00Z',
        '2026-1-1',
        '2026-01-01 10:00',
        '2026-01-01T10:00:00+25:00',
        'yesterday',
      ]) {
        expect(
          () => mapper.readValue<DateTime>('"$text"'),
          _mappingError('ISO-8601'),
          reason: text,
        );
      }
    });

    test('enum map keys use @JsonValue', () {
      final holder = Holder()..counts = {Stock.inStock: 1, Stock.soldOut: 2};
      final json = mapper.writeValueAsString(holder);
      expect(json, contains('"counts":{"in_stock":1,"sold_out":2}'));
      expect(mapper.readValue<Holder>(json).counts, {
        Stock.inStock: 1,
        Stock.soldOut: 2,
      });
      // The name is still accepted.
      expect(mapper.readValue<Holder>('{"counts":{"soldOut":3}}').counts, {
        Stock.soldOut: 3,
      });
    });

    test('enums are read by index too', () {
      expect(
        mapper.readValue('1', const EnumType<Genre>(Genre.values)),
        Genre.science,
      );
      // A stringified index too, without a leading zero (Jackson).
      expect(
        mapper.readValue('"1"', const EnumType<Genre>(Genre.values)),
        Genre.science,
      );
      expect(
        () => mapper.readValue('"01"', const EnumType<Genre>(Genre.values)),
        _mappingError('expected one of'),
      );
    });

    test('an int @JsonValue is matched by value, never as an index', () {
      final level = EnumType<Level>(Level.values, jsonValue: (l) => l.code);
      expect(mapper.readValue('20', level), Level.high);
      expect(mapper.readValue('"20"', level), Level.high);
      expect(mapper.readValue('10', level), Level.low);
      expect(() => mapper.readValue('1', level), _mappingError('10, 20'));
      expect(() => mapper.readValue('"1"', level), _mappingError('10, 20'));
    });
  });

  group('generic classes', () {
    test('read with their type arguments', () {
      final page = mapper.readValue(
        '{"content":[{"name":"Ann"}],"total":1}',
        const GenericType<Page<Author>>([ClassType<Author>()]),
      );
      expect(page, isA<Page<Author>>());
      expect(page.content.single.name, 'Ann');
      expect(page.total, 1);
      expect(
        mapper.writeValueAsString(page),
        '{"content":[{"name":"Ann"}],"total":1}',
      );
    });

    test('as a property type, nested and nullable arguments', () {
      final shelf = mapper.readValue<Shelf>(
        '{"page":{"content":[{"name":"Bo"}]}}',
      );
      expect(shelf.page, isA<Page<Author>>());
      expect(shelf.page.content.single.name, 'Bo');
      final nested = mapper.readValue(
        '{"content":[[1,null]]}',
        const GenericType<Page<List<int?>>>([
          ListType<int?>(ClassType<int>(nullable: true)),
        ]),
      );
      expect(nested.content.single, [1, null]);
    });

    test('without type arguments: a clear error', () {
      expect(
        () => mapper.readValue<Page<Author>>('{"content":[]}'),
        _mappingError('without its type arguments: pass a GenericType'),
      );
    });
  });

  group('polymorphism', () {
    test('a type id property, written first', () {
      expect(
        mapper.writeValueAsString(Dog('Rex')),
        '{"kind":"dog","bark":true,"name":"Rex"}',
      );
      // @JsonTypeName when @JsonSubTypes gives no name.
      expect(
        mapper.writeValueAsString(Cat('Tom')),
        '{"kind":"kitty","lives":9,"name":"Tom"}',
      );
    });

    test('a value of the base type is read as the right subclass', () {
      final animals = mapper.readList<Animal>(
        '[{"kind":"dog","name":"Rex","bark":false},'
        '{"name":"Tom","kind":"kitty"},{"kind":"hound","name":"Fang"}]',
      );
      expect(animals[0], isA<Dog>().having((d) => d.bark, 'bark', isFalse));
      expect(animals[1], isA<Cat>().having((c) => c.lives, 'lives', 9));
      expect(animals[2], isA<Dog>().having((d) => d.name, 'name', 'Fang'));
      // Reading the subtype itself checks the id too.
      expect(mapper.readValue<Dog>('{"kind":"dog","name":"Rex"}').name, 'Rex');
    });

    test('missing, unknown and incompatible type ids fail', () {
      expect(
        () => mapper.readValue<Animal>('{"name":"Rex"}'),
        _mappingError('missing type id property "kind" (for Animal)'),
      );
      expect(
        () => mapper.readValue<Animal>('{"kind":"cow","name":"Bess"}'),
        _mappingError(
          'could not resolve type id "cow" as a subtype of Animal: known '
          'type ids = [Animal, dog, hound, kitty]',
        ),
      );
      expect(
        () => mapper.readValue<Dog>('{"kind":"kitty","name":"Tom"}'),
        _mappingError('is not a subtype of Dog'),
      );
    });

    test('wrapper object and wrapper array', () {
      expect(mapper.valueToTree(Circle(2)), {
        'circle': {'r': 2},
      });
      expect(mapper.readValue<Shape>('{"circle":{"r":3}}'), isA<Circle>());
      expect(mapper.valueToTree(Thing(7)), [
        'thing',
        {'id': 7},
      ]);
      expect((mapper.readValue<Item>('["thing",{"id":8}]') as Thing).id, 8);
    });

    test('deduction picks the subtype by its properties', () {
      expect(mapper.valueToTree(Car(4, 5)), {'doors': 5, 'wheels': 4});
      expect(mapper.readValue<Vehicle>('{"wheels":4,"doors":3}'), isA<Car>());
      expect(mapper.readValue<Vehicle>('{"gears":21,"wheels":2}'), isA<Bike>());
      expect(
        () => mapper.readValue<Vehicle>('{"wheels":2}'),
        _mappingError('cannot deduce unique subtype of Vehicle (2 candidates'),
      );
    });

    test('an existing visible property and a default implementation', () {
      expect(mapper.valueToTree(TextMessage('text', 'hi')), {
        'body': 'hi',
        'type': 'text',
      });
      final image = mapper.readValue<Message>('{"type":"image","url":"u"}');
      expect(image, isA<ImageMessage>());
      expect(image.type, 'image');
      // No type id: defaultImpl.
      final text = mapper.readValue<Message>('{"body":"hello"}');
      expect(text, isA<TextMessage>());
      expect((text as TextMessage).body, 'hello');
    });
  });

  group('annotations', () {
    test('@JsonAlias', () {
      expect(mapper.readValue<Contact>('{"fullName":"Ann"}').name, 'Ann');
      expect(mapper.readValue<Contact>('{"n":"Bo"}').name, 'Bo');
      expect(mapper.writeValueAsString(Contact(name: 'C')), '{"name":"C"}');
      final strict = ObjectMapper(
        introspector: introspector,
        failOnUnknownProperties: true,
      );
      expect(strict.readValue<Contact>('{"n":"D"}').name, 'D');
    });

    test('@JsonFormat on dates, enums, numbers and durations', () {
      final event = Event()
        ..at = DateTime.utc(2026, 12, 24, 17, 30)
        ..genre = Genre.science
        ..count = 42
        ..stamp = DateTime.utc(2023, 11, 14, 22, 13, 20)
        ..wait = const Duration(seconds: 3);
      final tree = mapper.valueToTree(event)! as Map<String, Object?>;
      expect(tree, {
        'at': '24.12.2026 18:30',
        'count': '42',
        'genre': 1,
        'stamp': 1700000000.0,
        'wait': 3.0,
      });
      final again = mapper.convertValue<Event>(tree);
      expect(again.at, DateTime.utc(2026, 12, 24, 17, 30));
      expect(again.genre, Genre.science);
      expect(again.count, 42);
      expect(again.stamp, event.stamp);
      expect(again.wait, const Duration(seconds: 3));
      expect(
        () => mapper.convertValue<Event>({'at': '2026-12-24'}),
        _mappingError('expected a date-time like "dd.MM.yyyy HH:mm"'),
      );
    });

    test('date patterns', () {
      final at = DateTime.utc(2026, 3, 5, 14, 7, 9, 45);
      // Written, then read back to the pattern's precision.
      DateTime? read;
      String format(String pattern, [String zone = 'Z']) {
        final patterned = _patternMapper(pattern, zone);
        final text =
            (patterned.valueToTree(_At(at))! as Map<String, Object?>)['at']!
                as String;
        read = patterned.convertValue<_At>({'at': text}).at;
        return text;
      }

      expect(
        format("yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
        '2026-03-05T14:07:09.045Z',
      );
      expect(read, at);
      expect(format('EEE, d MMM yy h:mm a'), 'Thu, 5 Mar 26 2:07 PM');
      expect(read, DateTime.utc(2026, 3, 5, 14, 7));
      expect(format('EEEE d MMMM yyyy', '-05:30'), 'Thursday 5 March 2026');
      expect(read, DateTime.utc(2026, 3, 5, 5, 30));
      expect(format('yyyyMMddHHmmZ', '-05:30'), '202603050837-0530');
      expect(read, DateTime.utc(2026, 3, 5, 14, 7));
      expect(
        () => _patternMapper(
          'dd.MM.yyyy',
          'Z',
        ).convertValue<_At>({'at': '31.02.2026'}),
        _mappingError('expected a date-time like "dd.MM.yyyy"'),
      );
      expect(
        () => _patternMapper('yyyy Q', 'Z').valueToTree(_At(at)),
        throwsArgumentError,
      );
    });

    test('@JsonFormat(shape: array) on a class', () {
      expect(mapper.writeValueAsString(Point(1, 2)), '[1,2]');
      final point = mapper.readValue<Point>('[3,4]');
      expect((point.x, point.y), (3, 4));
      expect(mapper.readValue<Point>('{"x":5,"y":6}').y, 6);
    });

    test('@JsonAnyGetter / @JsonAnySetter on a map property', () {
      final bag = mapper.readValue<Bag>('{"id":"b","color":"red","n":[1]}');
      expect(bag.id, 'b');
      expect(bag.extra, {
        'color': 'red',
        'n': [1],
      });
      expect(
        mapper.writeValueAsString(bag),
        '{"id":"b","color":"red","n":[1]}',
      );
      // Unknown properties go to the any-setter, never fail.
      final strict = ObjectMapper(
        introspector: introspector,
        failOnUnknownProperties: true,
      );
      expect(strict.readValue<Bag>('{"x":1}').extra, {'x': 1});
    });

    test('an any-setter constructor parameter gets the map, typed', () {
      final props = mapper.readValue<Props>('{"id":"p","a":1,"b":"2"}');
      expect(props.rest, {'a': 1, 'b': 2});
      expect(props.rest, isA<Map<String, int>>());
      expect(mapper.valueToTree(props), {'id': 'p', 'a': 1, 'b': 2});
    });

    test('@JsonAnyGetter / @JsonAnySetter on methods', () {
      final bag = mapper.readValue<MethodBag>('{"k":true}');
      expect(bag.data, {'k': true});
      expect(mapper.valueToTree(bag), {'k': true});
    });

    test('@JsonUnwrapped with a prefix', () {
      final person = Person('Ann', Address(city: 'Lyon', zip: '69001'));
      expect(mapper.valueToTree(person), {
        'name': 'Ann',
        'home_city': 'Lyon',
        'home_zip': '69001',
      });
      final again = mapper.readValue<Person>(
        '{"name":"Ann","home_city":"Nice"}',
      );
      expect(again.address!.city, 'Nice');
      expect(again.address!.zip, isNull);
      // None of its properties: null (the property is nullable).
      expect(mapper.readValue<Person>('{"name":"Bo"}').address, isNull);
      expect(mapper.valueToTree(Person('Bo', null)), {'name': 'Bo'});
      final strict = ObjectMapper(
        introspector: introspector,
        failOnUnknownProperties: true,
      );
      expect(
        strict.readValue<Person>('{"name":"C","home_city":"X"}').address!.city,
        'X',
      );
      expect(
        () => strict.readValue<Person>('{"name":"C","home_town":"X"}'),
        _mappingError('unknown property "home_town"'),
      );
    });

    test('@JsonNaming on a class wins over the mapper', () {
      final row = Row()
        ..bookTitle = 'Dune'
        ..isbnCode = '1';
      expect(mapper.valueToTree(row), {'ISBN': '1', 'book_title': 'Dune'});
      expect(
        mapper.readValue<Row>('{"book_title":"X","ISBN":"2"}').bookTitle,
        'X',
      );
    });

    test('@JsonView with view inheritance; no view: excluded', () {
      final user = User()
        ..id = '1'
        ..name = 'Ann'
        ..email = 'a@b.c';
      expect(mapper.writerWithView(Public).valueToTree(user), {'name': 'Ann'});
      expect(mapper.writerWithView(Internal).valueToTree(user), {
        'email': 'a@b.c',
        'name': 'Ann',
      });
      expect(
        ObjectMapper(
          introspector: introspector,
          defaultViewInclusion: true,
        ).writerWithView(Public).valueToTree(user),
        {'id': '1', 'name': 'Ann'},
      );
      // Without a view everything is written.
      expect(mapper.valueToTree(user), hasLength(3));
      final read = mapper
          .readerWithView(Public)
          .readValue<User>('{"id":"9","name":"Bo","email":"x"}');
      expect((read.id, read.name, read.email), ('', 'Bo', ''));
    });

    test('NON_DEFAULT on a class compares with a default instance', () {
      expect(mapper.valueToTree(Counter()), isEmpty);
      expect(
        mapper.valueToTree(
          Counter()
            ..label = ''
            ..count = 3,
        ),
        {'count': 3, 'label': ''},
      );
    });

    test('NON_DEFAULT on a property and NON_ABSENT', () {
      expect(mapper.valueToTree(Score()), {'points': 5});
      expect(
        mapper.valueToTree(
          Score()
            ..points = 0
            ..flag = true
            ..memo = '',
        ),
        {'flag': true, 'memo': ''},
      );
      expect(
        ObjectMapper(
          introspector: introspector,
          inclusion: JsonInclusion.nonAbsent,
        ).valueToTree(Holder()),
        {'counts': <String, Object?>{}},
      );
    });
  });

  group('tree model', () {
    test('readTree navigation, paths and pointers', () {
      final root = mapper.readTree(
        '{"book":{"title":"Dune","tags":["sf","classic"],"price":9.5,'
        '"stock":3,"used":false,"note":null}}',
      );
      expect(root.isObject, isTrue);
      final book = root.get('book')!;
      expect(book.get('title')!.asString(), 'Dune');
      expect(book.get('title')!.stringValue(), 'Dune');
      expect(book.get('price')!.doubleValue(), 9.5);
      expect(book.get('price')!.asInt(), 9);
      expect(book.get('stock')!.isIntegralNumber, isTrue);
      expect(book.get('used')!.booleanValue(), isFalse);
      expect(book.get('note')!.isNull, isTrue);
      expect(book.get('missing'), isNull);
      expect(root.path('book').path('missing').isMissingNode, isTrue);
      expect(root.path('book').path('missing').asInt(10), 10);
      expect(root.at('/book/tags/1').stringValue(), 'classic');
      expect(root.at('/book/tags/7').isMissingNode, isTrue);
      expect(book.get('tags')!.size, 2);
      expect(
        [for (final t in book.get('tags')!.values()) t.asString()],
        ['sf', 'classic'],
      );
      expect(book.propertyNames(), contains('price'));
      expect(
        () => book.get('stock')!.stringValue(),
        throwsA(isA<JsonNodeException>()),
      );
    });

    test('building, writing and converting trees', () {
      final node = mapper.createObjectNode()
        ..put('name', 'Ann')
        ..putArray('tags').add('x').add(1);
      node.putObject('nested').put('ok', true);
      expect(
        mapper.writeValueAsString(node),
        '{"name":"Ann","tags":["x",1],"nested":{"ok":true}}',
      );
      expect(node.toString(), mapper.writeValueAsString(node));
      expect(mapper.treeToValue<Author>(node).name, 'Ann');
      final tree = mapper.convertValue<JsonNode>(const Author('Bo'));
      expect(tree, isA<ObjectNode>());
      expect(tree.get('name')!.asString(), 'Bo');
      expect(mapper.readValue<ObjectNode>('{"a":1}').get('a')!.intValue(), 1);
      expect(
        () => mapper.readValue<ObjectNode>('[1]'),
        throwsA(isA<JsonMappingException>()),
      );
      expect(mapper.readTree('{"a":[1]}'), mapper.readTree('{"a": [1]}'));
      expect(
        JsonNode.from(jsonDecode('{"a":1}')),
        isNot(mapper.readTree('{"a":2}')),
      );
    });

    test('equality and coercion follow Jackson 3', () {
      final nodeException = throwsA(isA<JsonNodeException>());
      expect(NullNode.instance, isNot(MissingNode.instance));
      expect(MissingNode.instance, isNot(NullNode.instance));
      expect(NullNode.instance, JsonNode.from(null));
      // intValue: exactly an int only.
      expect(const NumericNode(2.0).intValue(), 2);
      expect(() => const NumericNode(1.5).intValue(), nodeException);
      expect(() => const NumericNode(double.nan).intValue(), nodeException);
      // asInt: numbers truncate, strings must be integers, else the default
      // or an exception.
      expect(const NumericNode(1.5).asInt(), 1);
      expect(() => const NumericNode(double.infinity).asInt(), nodeException);
      expect(const StringNode('42').asInt(), 42);
      expect(() => const StringNode('abc').asInt(), nodeException);
      expect(() => const StringNode('1.5').asInt(), nodeException);
      expect(() => const StringNode(' 1').asInt(), nodeException);
      expect(const StringNode('abc').asInt(7), 7);
      expect(const StringNode('1.5').asDouble(), 1.5);
      expect(() => const StringNode('NaN').asDouble(), nodeException);
      expect(() => const StringNode('yes').asBoolean(), nodeException);
      expect(const StringNode('yes').asBoolean(true), isTrue);
      expect(NullNode.instance.asInt(), 0);
      expect(NullNode.instance.asInt(5), 5);
      // asString: '' for null and missing; containers have no string.
      expect(NullNode.instance.asString(), '');
      expect(NullNode.instance.asString('n/a'), 'n/a');
      expect(MissingNode.instance.asString(), '');
      expect(const NumericNode(3).asString(), '3');
      expect(() => ObjectNode().asString(), nodeException);
      expect(ArrayNode().asString('[]'), '[]');
      expect(() => ArrayNode().asInt(), nodeException);
    });
  });

  group('JsonMapper.builder() and rebuild()', () {
    test('builds with features and modules', () {
      final built = JsonMapper.builder()
          .introspector(introspector)
          .propertyNamingStrategy(PropertyNamingStrategy.snakeCase)
          .defaultPropertyInclusion(JsonInclusion.nonNull)
          .enable(DeserializationFeature.failOnUnknownProperties)
          .enable(DateTimeFeature.writeDatesAsTimestamps)
          .disable(MapperFeature.sortPropertiesAlphabetically)
          .defaultTimeZone('+01:00')
          .build();
      expect(built, isA<ObjectMapper>());
      expect(built.namingStrategy, PropertyNamingStrategy.snakeCase);
      expect(built.inclusion, JsonInclusion.nonNull);
      expect(
        built.isEnabled(DeserializationFeature.failOnUnknownProperties),
        isTrue,
      );
      expect(built.isEnabled(DeserializationFeature.acceptFloatAsInt), isTrue);
      expect(
        built.isEnabled(MapperFeature.sortPropertiesAlphabetically),
        isFalse,
      );
      expect(built.isEnabled(MapperFeature.defaultViewInclusion), isFalse);
      expect(built.timeZone, '+01:00');
      expect(built.valueToTree(DateTime.utc(1970, 1, 1, 0, 0, 2)), 2.0);
      expect(
        () => built.readValue<Contact>('{"name":"A","x":1}'),
        _mappingError('unknown property "x"'),
      );
    });

    test('rebuild keeps the configuration and changes a copy', () {
      final base = JsonMapper.builder()
          .introspector(introspector)
          .enable(SerializationFeature.indentOutput)
          .addModule(const JsonModule(serializers: [_UpperSerializer()]))
          .build();
      final changed = base
          .rebuild()
          .disable(SerializationFeature.indentOutput)
          .build();
      expect(base.indentOutput, isTrue);
      expect(changed.indentOutput, isFalse);
      expect(changed.introspector, same(introspector));
      expect(changed.writeValueAsString(const Shout('hey')), '"HEY"');
      expect(base.writeValueAsString(['a']), '[\n  "a"\n]');
    });
  });
}

ObjectMapper _patternMapper(String pattern, String zone) => ObjectMapper(
  introspector: BeanIntrospector(
    introspections: [
      BeanIntrospection<_At>(
        properties: [
          _p<_At>(
            'at',
            (b) => b.at,
            const ClassType<DateTime>(),
            annotations: [JsonFormat(pattern: pattern, timezone: zone)],
          ),
        ],
        constructor: _ctor<_At>(_At.new, [
          const BeanParameter(
            'at',
            type: ClassType<DateTime>(),
            isRequired: true,
          ),
        ]),
      ),
    ],
  ),
);

class _At {
  _At(this.at);
  final DateTime at;
}

class Shout {
  const Shout(this.text);
  final String text;
}

final class _UpperSerializer extends JsonSerializer<Shout> {
  const _UpperSerializer();
  @override
  Object? serialize(Shout value, ObjectMapper mapper) =>
      value.text.toUpperCase();
}
