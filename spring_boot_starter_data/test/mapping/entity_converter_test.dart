import 'dart:typed_data';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late RelationalMappingContext context;
  late EntityConverter converter;
  late PersistentEntity<Book> book;
  setUp(() {
    context = testContext();
    converter = EntityConverter();
    book = context.getRequiredPersistentEntity<Book>();
  });

  Matcher failsWith(String text) => throwsA(
    isA<MappingException>().having((e) => e.message, 'message', contains(text)),
  );

  group('write', () {
    test('every column, converted', () {
      final row = converter.write(
        book,
        Book(
          id: 3,
          title: 'Dune',
          genre: Genre.science,
          author: const AggregateReference<Author, int>(7),
          createdAt: DateTime.utc(2024),
          note: 'not stored',
        ),
      );
      expect(row, {
        'id': 3,
        'title': 'Dune',
        'year': null,
        'genre': 'science',
        'price': 0.0,
        'available': false,
        'writer_id': 7,
        'version': 0,
        'created_at': DateTime.utc(2024),
        'modified_at': null,
        'created_by': null,
        'modified_by': null,
      });
    });

    test('leaves the children out', () {
      final line = context.getRequiredPersistentEntity<OrderLine>();
      final row = converter.write(
        line,
        OrderLine(
          id: 1,
          items: [Item(sku: 'a')],
          tags: {},
          notes: {},
        ),
      );
      expect(row, {'id': 1});
    });

    test('toColumnValue', () {
      expect(converter.toColumnValue(Genre.fiction), 'fiction');
      expect(
        converter.toColumnValue(const AggregateReference<Author, String>('x')),
        'x',
      );
      expect(converter.toColumnValue(BigInt.two), BigInt.two);
      expect(converter.toColumnValue(null), isNull);
    });
  });

  group('read', () {
    test('constructor with named parameters, then the other properties', () {
      final b = converter.read(book, {
        'id': 4,
        'title': 'Emma',
        'year': 1815,
        'version': 2,
      });
      expect(b.id, 4);
      expect(b.title, 'Emma');
      expect(b.year, 1815);
      expect(b.version, 2);
      expect(b.price, 0);
      expect(b.genre, isNull);
    });

    test('a missing optional parameter keeps its default', () {
      final b = converter.read(book, {'title': 'Emma'});
      expect(b.version, 0);
      expect(b.price, 0.0);
      expect(b.available, isFalse);
    });

    test(
      'a default the description gives as an int is widened to a double',
      () {
        expect(converter.read(book, {'title': 'Emma'}).price, isA<double>());
      },
    );

    test('a missing nullable parameter is null', () {
      final b = converter.read(book, {'title': 'Emma'});
      expect(b.id, isNull);
      expect(b.author, isNull);
      expect(b.createdAt, isNull);
    });

    test('a required parameter without a column', () {
      expect(
        () => converter.read(book, {'year': 1}),
        failsWith('Book: the constructor requires title'),
      );
    });

    test('null for a required non-nullable parameter', () {
      expect(
        () => converter.read(book, {'title': null}),
        failsWith('Book.title is null'),
      );
    });

    test('null for an optional non-nullable parameter uses the default', () {
      expect(converter.read(book, {'title': 'x', 'version': null}).version, 0);
    });

    test('a row key that is no column is ignored', () {
      expect(converter.read(book, {'title': 'x', 'zzz': 1}).title, 'x');
    });

    test('enum name to constant', () {
      expect(
        converter.read(book, {'title': 'x', 'genre': 'science'}).genre,
        Genre.science,
      );
      expect(
        () => converter.read(book, {'title': 'x', 'genre': 'poetry'}),
        failsWith('"poetry" is not a constant of Genre'),
      );
    });

    test('int to double', () {
      expect(converter.read(book, {'title': 'x', 'price': 12}).price, 12.0);
    });

    test('0 and 1 to bool', () {
      expect(
        converter.read(book, {'title': 'x', 'available': 1}).available,
        true,
      );
      expect(
        converter.read(book, {'title': 'x', 'available': 0}).available,
        false,
      );
      expect(
        converter.read(book, {'title': 'x', 'available': true}).available,
        true,
      );
    });

    test('ISO-8601 text and epoch milliseconds to DateTime', () {
      final b = converter.read(book, {
        'title': 'x',
        'created_at': '2024-05-06T07:08:09.000Z',
        'modified_at': 1000,
      });
      expect(b.createdAt, DateTime.utc(2024, 5, 6, 7, 8, 9));
      expect(
        b.modifiedAt,
        DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );
      expect(
        () => converter.read(book, {'title': 'x', 'created_at': 'soon'}),
        failsWith('"soon" is not a date'),
      );
    });

    test('id to AggregateReference with the right type arguments', () {
      final b = converter.read(book, {'title': 'x', 'writer_id': 9});
      expect(b.author, const AggregateReference<Author, int>(9));
      expect(b.author, isA<AggregateReference<Author, int>>());
      expect(b.author!.id, 9);
    });

    test('a null reference stays null', () {
      expect(
        converter.read(book, {'title': 'x', 'writer_id': null}).author,
        isNull,
      );
    });

    test('a value of the wrong type', () {
      expect(
        () => converter.read(book, {'title': 'x', 'year': 'old'}),
        failsWith('Book.year: cannot use a String as int?'),
      );
    });

    test('a double that is whole is an int', () {
      expect(converter.read(book, {'title': 'x', 'year': 1815.0}).year, 1815);
    });

    test('write then read round-trips', () {
      final original = Book(
        id: 1,
        title: 'Dune',
        year: 1965,
        genre: Genre.fiction,
        price: 9.5,
        available: true,
        author: const AggregateReference<Author, int>(2),
        version: 3,
        createdAt: DateTime.utc(2020, 1, 2),
        createdBy: 'ann',
      );
      final copy = converter.read(book, converter.write(book, original));
      expect(converter.write(book, copy), converter.write(book, original));
    });
  });

  group('fromColumnValue', () {
    test('BigInt and Uint8List', () {
      expect(
        converter.fromColumnValue(5, const ClassType<BigInt>()),
        BigInt.from(5),
      );
      expect(
        converter.fromColumnValue(
          '12345678901234567890',
          const ClassType<BigInt>(),
        ),
        BigInt.parse('12345678901234567890'),
      );
      final bytes = converter.fromColumnValue(
        <int>[1, 2],
        const ClassType<Uint8List>(),
      );
      expect(bytes, isA<Uint8List>());
      expect(bytes, [1, 2]);
    });

    test('num and String are unchanged', () {
      expect(converter.fromColumnValue(3, const ClassType<num>()), 3);
      expect(converter.fromColumnValue('a', const ClassType<String>()), 'a');
    });

    test(
      'an enum the property does not describe is found in the introspector',
      () {
        final withEnum = EntityConverter(
          introspector: BeanIntrospector()
            ..registerEnum(const EnumType<Genre>(Genre.values)),
        );
        expect(
          withEnum.fromColumnValue('fiction', const ClassType<Genre>()),
          Genre.fiction,
        );
      },
    );

    test('null for a non-nullable type', () {
      expect(
        () => converter.fromColumnValue(null, const ClassType<int>()),
        failsWith('is null'),
      );
    });
  });

  group('mapped collections', () {
    late PersistentEntity<OrderLine> line;
    setUp(() => line = context.getRequiredPersistentEntity<OrderLine>());

    test('are passed ready-made, converted to the right collection types', () {
      final o = converter.read(
        line,
        {'id': 1},
        children: {
          'items': <Object?>[Item(sku: 'a'), Item(sku: 'b')],
          'tags': <Object?>[Tag('x'), Tag('y')],
          'notes': <Object?, Object?>{'k': Note(text: 't')},
          'extras': <Object?>[Item(sku: 'c')],
        },
      );
      expect(o.items.map((i) => i.sku), ['a', 'b']);
      expect(o.tags.map((t) => t.label), unorderedEquals(['x', 'y']));
      expect(o.notes['k']!.text, 't');
      expect(o.extras!.single.sku, 'c');
    });

    test('absent collections are empty, a nullable one is left null', () {
      final o = converter.read(line, {'id': 1});
      expect(o.items, isEmpty);
      expect(o.tags, isEmpty);
      expect(o.notes, isEmpty);
      expect(o.extras, isNull);
    });

    test('of the wrong kind', () {
      expect(
        () => converter.read(line, {'id': 1}, children: {'items': 5}),
        failsWith('OrderLine.items: cannot use a int'),
      );
    });

    test('children rows are read with their own entity', () {
      final items = line.property('items')!.childEntity!;
      final item = converter.read(items, {'sku': 'z', 'qty': 4});
      expect((item as Item).qty, 4);
    });
  });

  group('constructor-only entity', () {
    late PersistentEntity<Reading> reading;
    setUp(() => reading = context.getRequiredPersistentEntity<Reading>());

    test('positional parameters, required and optional', () {
      final r = converter.read(reading, {'id': 1, 'text': 'hi', 'score': 2});
      expect(r.id, 1);
      expect(r.text, 'hi');
      expect(r.score, 2.0);
      expect(r.version, 0);
    });

    test('a required positional parameter may be null when nullable', () {
      final r = converter.read(reading, {'id': null, 'text': 'hi'});
      expect(r.id, isNull);
      // A nullable parameter without a column is null too.
      expect(converter.read(reading, {'text': 'hi'}).id, isNull);
    });

    test('a parameter that cannot be null, without column', () {
      expect(
        () => converter.read(reading, {'id': 1}),
        failsWith(
          'Reading: the constructor requires text but there is no '
          'column for it',
        ),
      );
    });

    test('null for a parameter that cannot be null', () {
      expect(
        () => converter.read(reading, {'id': 1, 'text': null}),
        failsWith('Reading.text is null but the constructor requires a '),
      );
    });

    test('a @Transient parameter that cannot be null is refused', () {
      final locked = context.getRequiredPersistentEntity<Locked>();
      expect(
        () => converter.read(locked, {'id': 1}),
        failsWith(
          'Locked: the constructor requires pin but there is no column for '
          'it (a @Transient property, or a missing column)',
        ),
      );
    });

    test('a missing column with a default gives the default', () {
      final r = converter.read(reading, {'id': 1, 'text': 'hi'});
      expect(r.version, 0);
      // The null of a column falls back to the default as well.
      expect(
        converter.read(reading, {
          'id': 1,
          'text': 'a',
          'version': null,
        }).version,
        0,
      );
    });

    test('a missing optional positional before a present one is null', () {
      final r = converter.read(reading, {
        'id': 1,
        'text': 'a',
        'version': 3,
      });
      expect(r.score, isNull);
      expect(r.version, 3);
    });
  });

  group('properties the constructor does not take', () {
    late PersistentEntity<Gauge> gauge;
    setUp(() => gauge = context.getRequiredPersistentEntity<Gauge>());

    test('are set after the constructor', () {
      final g = converter.read(gauge, {
        'id': 1,
        'name': 'n',
        'level': 9,
        'label': 'x',
      });
      expect((g.id, g.name, g.level, g.label), (1, 'n', 9, 'x'));
      expect(g.scratch, isNull);
    });

    test('keep their initializer when the column is missing or null', () {
      final g = converter.read(gauge, {'id': 1, 'name': 'n', 'level': null});
      expect(g.level, 5);
      expect(g.label, isNull);
      expect(converter.read(gauge, {'id': 1, 'name': 'n'}).level, 5);
    });

    test('a nullable one takes a null column', () {
      final g = converter.read(gauge, {'id': 1, 'name': 'n', 'label': null});
      expect(g.label, isNull);
    });

    test('the converted value is set', () {
      final g = converter.read(gauge, {'id': 1, 'name': 'n', 'level': 7.0});
      expect(g.level, 7);
    });

    test('write gives their columns, never a @Transient one', () {
      final g = Gauge(1, 'n')
        ..level = 3
        ..label = 'x'
        ..scratch = 'tmp';
      expect(converter.write(gauge, g), {
        'id': 1,
        'name': 'n',
        'level': 3,
        'label': 'x',
      });
    });
  });

  group('a @Transient late field nobody set', () {
    late PersistentEntity<Draft> draft;
    setUp(() => draft = context.getRequiredPersistentEntity<Draft>());

    test('is not read by write', () {
      expect(converter.write(draft, Draft(id: 1, title: 't')), {
        'id': 1,
        'title': 't',
      });
    });

    test('is not read by idOf or the properties', () {
      final d = Draft(id: 4, title: 't');
      expect(converter.idOf(draft, d), 4);
      expect(draft.property('title')!.getValue(d), 't');
      expect(() => d.display, throwsA(isA<Error>()));
    });

    test('is not read when the id is set in place', () {
      final d = Draft(title: 't');
      expect(converter.withId(draft, d, 9), same(d));
      expect(d.id, 9);
    });
  });

  group('id and version', () {
    test('idOf and versionOf', () {
      final b = Book(id: 8, title: 'x', version: 2);
      expect(converter.idOf(book, b), 8);
      expect(converter.versionOf(book, b), 2);
    });

    test('setId and setVersion on writable properties', () {
      final b = Book(title: 'x');
      converter
        ..setId(book, b, 5)
        ..setVersion(book, b, 1);
      expect(b.id, 5);
      expect(b.version, 1);
    });

    test('withId on a writable property returns the same instance', () {
      final b = Book(title: 'x');
      expect(converter.withId(book, b, 5), same(b));
      expect(b.id, 5);
    });

    test('withId on a final property copies through the constructor', () {
      final reading = context.getRequiredPersistentEntity<Reading>();
      final original = makeReading(
        null,
        'hi',
        score: 1.5,
        created: DateTime.utc(2000),
      );
      final saved = converter.withId(reading, original, 11);
      expect(saved, isNot(same(original)));
      expect(saved.id, 11);
      expect(saved.text, 'hi');
      expect(saved.score, 1.5);
      expect(saved.created, DateTime.utc(2000));
      expect(original.id, isNull);
    });

    test(
      'a copy sets the settable properties the constructor does not take',
      () {
        final gauge = context.getRequiredPersistentEntity<Gauge>();
        final original = Gauge(null, 'n')
          ..level = 8
          ..label = 'x'
          ..scratch = 'carried over';
        final saved = converter.withId(gauge, original, 4);
        expect(saved, isNot(same(original)));
        expect(saved.id, 4);
        expect(saved.name, 'n');
        expect(saved.level, 8);
        expect(saved.label, 'x');
        expect(saved.scratch, 'carried over');
        expect(original.id, isNull);
      },
    );

    test('a copy takes the changes of settable properties too', () {
      final gauge = context.getRequiredPersistentEntity<Gauge>();
      final saved = converter.withValues(gauge, Gauge(null, 'n'), {
        'id': 2,
        'level': 6,
      });
      expect((saved.id, saved.level), (2, 6));
    });

    test('withValues in place when every change is writable', () {
      final gauge = context.getRequiredPersistentEntity<Gauge>();
      final g = Gauge(1, 'n');
      expect(converter.withValues(gauge, g, {'level': 2}), same(g));
      expect(g.level, 2);
    });

    test('a mutable entity is changed in place, @Transient included', () {
      final b = Book(id: 1, title: 'x', note: 'memo', price: 2);
      // Nothing is final: the same instance, @Transient note included.
      final same_ = converter.withValues(book, b, {'year': 1999});
      expect(same_, same(b));
      expect(b.year, 1999);
      expect(b.note, 'memo');
    });

    test('setId on a settable property of a mixed entity says to copy', () {
      final gauge = context.getRequiredPersistentEntity<Gauge>();
      expect(
        () => converter.setId(gauge, Gauge(null, 'n'), 1),
        failsWith('Gauge.id is final'),
      );
    });

    test('withVersion on a final property copies', () {
      final reading = context.getRequiredPersistentEntity<Reading>();
      final saved = converter.withVersion(reading, makeReading(1, 'a'), 1);
      expect(saved.version, 1);
      expect(saved.id, 1);
    });

    test('setId on a final property says to copy', () {
      final reading = context.getRequiredPersistentEntity<Reading>();
      expect(
        () => converter.setId(reading, makeReading(null, 'a'), 1),
        failsWith('Reading.id is final'),
      );
    });

    test('withValues changes several, mixed final and writable', () {
      final reading = context.getRequiredPersistentEntity<Reading>();
      final r = converter.withValues(reading, makeReading(null, 'a'), {
        'id': 2,
        'version': 5,
      });
      expect((r.id, r.version), (2, 5));
    });

    test('withValues with an unknown property', () {
      expect(
        () => converter.withValues(book, Book(title: 'x'), {'nope': 1}),
        failsWith('Book has no stored property nope'),
      );
    });

    test('a value of the wrong type is refused', () {
      expect(
        () => converter.withId(book, Book(title: 'x'), 'abc'),
        failsWith('Book.id: cannot use a String as int?'),
      );
    });

    test('no @Id or @Version', () {
      final tags = context
          .getRequiredPersistentEntity<OrderLine>()
          .property('tags')!
          .childEntity!;
      expect(() => converter.idOf(tags, Tag('x')), failsWith('Tag has no @Id'));
      expect(
        () => converter.versionOf(tags, Tag('x')),
        failsWith('Tag has no @Version'),
      );
    });
  });
}
