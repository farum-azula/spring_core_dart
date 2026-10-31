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
    converter = EntityConverter(introspector: context.introspector);
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
    });

    test('a required positional parameter without column', () {
      expect(
        () => converter.read(reading, {'text': 'hi'}),
        failsWith('Reading: the constructor requires id'),
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
