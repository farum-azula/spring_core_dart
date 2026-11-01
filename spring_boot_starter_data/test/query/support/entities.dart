import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

/// A stub aggregate class for the parser tests.
class Book {}

/// A stub child class.
class Chapter {}

/// A stub entity class that is not the entity under test.
class Author {}

// The parser tests never read or create instances: the description lists
// no properties.
EntityIntrospection<T> _stub<T extends Object>(
  String name,
  T Function() make,
) => EntityIntrospection<T>(
  name,
  const [],
  get: (_, i) => throw StateError('no properties'),
  create: (_) => make(),
);

final EntityIntrospection<Book> _bookIntrospection = _stub<Book>(
  'Book',
  Book.new,
);
final EntityIntrospection<Chapter> _chapterIntrospection = _stub<Chapter>(
  'Chapter',
  Chapter.new,
);

PersistentProperty _property(
  String name,
  TypeInfo<Object?> type, {
  bool isId = false,
  MappedCollection? mapped,
  PersistentEntity<Object>? child,
  TypeInfo<Object?>? referencedType,
}) => PersistentProperty(
  name: name,
  columnName: name,
  type: type,
  owner: _bookIntrospection,
  index: 0,
  isId: isId,
  mappedCollection: mapped,
  childEntity: child,
  referencedType: referencedType,
);

/// `Book` with the properties the tests query: a mix of names containing
/// `Or`, `And`, `In`, `Is` and other keywords.
PersistentEntity<Object> bookEntity() {
  final chapter = PersistentEntity<Object>(
    introspection: _chapterIntrospection,
    tableName: 'chapters',
    properties: [
      _property('number', const ClassType<int>()),
    ],
  );
  return PersistentEntity<Object>(
    introspection: _bookIntrospection,
    tableName: 'books',
    properties: [
      _property(
        'id',
        const ClassType<int>(nullable: true),
        isId: true,
      ),
      _property('title', const ClassType<String>()),
      _property('year', const ClassType<int>()),
      _property('price', const ClassType<double>()),
      _property('inStock', const ClassType<bool>()),
      _property('orderNumber', const ClassType<int>()),
      _property('origin', const ClassType<String>()),
      _property('android', const ClassType<String>()),
      _property('isbn', const ClassType<String>()),
      _property(
        'notes',
        const ClassType<String>(nullable: true),
      ),
      _property(
        'between',
        const ClassType<int>(nullable: true),
      ),
      _property('URL', const ClassType<String>()),
      _property('address', const ClassType<String>()),
      _property('published', const ClassType<DateTime>()),
      _property(
        'authorId',
        const ClassType<Object>(),
        referencedType: const ClassType<int>(),
      ),
      _property(
        'chapters',
        const ListType<Chapter>(ClassType<Chapter>()),
        mapped: const MappedCollection(),
        child: chapter,
      ),
    ],
  );
}

/// A positional parameter of [type].
BeanParameter param(String name, TypeInfo<Object?> type) =>
    BeanParameter(name, type: type);

/// `String`.
const string = ClassType<String>();

/// `int`.
const integer = ClassType<int>();
