// lib/spring_gen/spring_metadata.json of a package with a data layer: its
// entities and repositories (the data starter's part).
@Timeout(Duration(minutes: 2))
library;

import 'package:test/test.dart';

import '../support/spring_metadata.dart';

void main() {
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
      json = (await runMetadataBuilder({'lib/shop.dart': source})).json!;
    });

    test('an entity lists its table, id and properties', () {
      final book = entriesOf(json, 'entities').firstWhere(
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
      final book = entriesOf(json, 'entities').firstWhere(
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
      final entities = entriesOf(json, 'entities');
      expect([for (final e in entities) e['class']], ['Author', 'Book']);
      expect(entities.first['table'], 'authors');
    });

    test('a repository lists its entity, id and methods', () {
      final repository = entriesOf(json, 'repositories').single;
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
      final result = await runMetadataBuilder({
        'lib/shop.dart': shopProperties,
      });
      expect(result.json!.containsKey('entities'), isFalse);
      expect(result.json!.containsKey('repositories'), isFalse);
    });
  });
}
