import 'dart:convert';

import 'package:dart_spring_language_server/src/workspace.dart';

import 'editor_fixture.dart';

/// The entities and repositories of a small shop, as the sources and as the
/// Spring metadata the generator writes for them.
const dataShopSource = '''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

@Table('authors')
class Author {
  Author({required this.name, this.id});

  @Id()
  int? id;

  String name;
}

@Table('books')
class Book {
  Book({
    required this.title,
    required this.year,
    this.id,
    this.author,
    this.inStock = true,
  });

  @Id()
  int? id;

  String title;
  int year;
  bool inStock;
  AggregateReference<Author, int>? author;

  @Transient()
  String cache = '';

  @MappedCollection()
  List<Note> notes = [];
}

@Table('notes')
class Note {
  Note({required this.text});

  String text;
}

class BookCard {
  const BookCard({required this.title});

  final String title;
}

abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {
  @Query(
    'select b.title, a.name as author_name, b.year from {Book} b '
    'join {Author} a on a.{Author.id} = b.{Book.author} '
    'where b.year >= :year order by b.year, b.title',
  )
  Future<List<BookCard>> cardsSince(int year);

  @Query('select {Book.title} from {Book} where {Book.title} = :title')
  Future<List<String>> byTitle(String title, Pageable page);

  @Query('select * from {Book} where title = :#{#book.title} -- by title')
  Future<List<Book>> sameTitle(Book book);

  Future<List<Book>> findByTitleAndYearGreaterThan(String title, int year);
  Future<int> countByAuthor(AggregateReference<Author, int> author);
  Future<bool> existsByTitle(String title);
  Future<int> deleteByYearLessThan(int year);
  Future<List<Book>> findByInStockOrderByYearDescTitleAsc(bool inStock);
  Future<List<Book>> findByYear(int year, Pageable page);
}
''';

/// The metadata of [dataShopSource], as the generator writes it.
Map<String, Object?> dataShopMetadata() => {
  'entities': [
    {
      'class': 'Author',
      'table': 'authors',
      'source': 'package:app/shop.dart',
      'line': 4,
      'id': 'id',
      'properties': [
        _property('id', 'int?', 'id', 7),
        _property('name', 'String', 'name', 9),
      ],
    },
    {
      'class': 'Book',
      'table': 'books',
      'source': 'package:app/shop.dart',
      'line': 12,
      'id': 'id',
      'properties': [
        _property('id', 'int?', 'id', 26),
        _property('title', 'String', 'title', 28),
        _property('year', 'int', 'year', 29),
        _property('inStock', 'bool', 'in_stock', 30),
        {
          ..._property(
            'author',
            'AggregateReference<Author, int>?',
            'author',
            31,
          ),
          'relation': {'entity': 'Author', 'id': 'int'},
        },
        {..._property('cache', 'String', null, 34), 'kind': 'transient'},
        {..._property('notes', 'List<Note>', null, 37), 'kind': 'collection'},
      ],
    },
  ],
  'repositories': [
    {
      'name': 'BookRepository',
      'entity': 'Book',
      'id': 'int',
      'source': 'package:app/shop.dart',
      'line': 56,
      'methods': <Object?>[],
    },
  ],
};

Map<String, Object?> _property(
  String name,
  String type,
  String? column,
  int line,
) => {
  'name': name,
  'type': type,
  'kind': 'column',
  'column': column,
  'relation': null,
  'source': 'package:app/shop.dart',
  'line': line,
};

/// A fixture whose package `app` has [source] as `lib/shop.dart` and the
/// metadata [metadata] (the shop's by default); returns the path of the
/// file.
(EditorFixture, String) dataFixture({
  String source = dataShopSource,
  Map<String, Object?>? metadata,
}) {
  final fixture = EditorFixture.create(withAppMetadata: false)
    ..open(
      'lib/spring_gen/spring_metadata.json',
      jsonEncode({
        'version': 1,
        'package': 'app',
        ...(metadata ?? dataShopMetadata()),
      }),
    );
  return (fixture, fixture.open('lib/shop.dart', source));
}

/// The messages of the problems of [path] with their line (zero based).
List<String> problemsOf(SpringWorkspace workspace, String path) =>
    messages(workspace.problems(path));
