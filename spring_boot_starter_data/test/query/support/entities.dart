import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

/// A stub aggregate class for the parser tests.
class Book {}

/// A stub child class.
class Chapter {}

/// A stub entity class that is not the entity under test.
class Author {}

BeanProperty<Object> _bean(String name, TypeInfo<Object?> info) =>
    BeanProperty<Object>(
      name,
      type: info.type,
      nullable: info.nullable,
      typeInfo: info,
      get: (_) => null,
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
  accessor: _bean(name, type),
  isId: isId,
  mappedCollection: mapped,
  childEntity: child,
  referencedType: referencedType,
);

/// `Book` with the properties the tests query: a mix of names containing
/// `Or`, `And`, `In`, `Is` and other keywords.
PersistentEntity<Object> bookEntity() {
  final chapter = PersistentEntity<Object>(
    introspection: BeanIntrospection<Chapter>(),
    tableName: 'chapters',
    properties: [_property('number', const ClassType<int>())],
  );
  return PersistentEntity<Object>(
    introspection: BeanIntrospection<Book>(),
    tableName: 'books',
    properties: [
      _property('id', const ClassType<int>(nullable: true), isId: true),
      _property('title', const ClassType<String>()),
      _property('year', const ClassType<int>()),
      _property('price', const ClassType<double>()),
      _property('inStock', const ClassType<bool>()),
      _property('orderNumber', const ClassType<int>()),
      _property('origin', const ClassType<String>()),
      _property('android', const ClassType<String>()),
      _property('isbn', const ClassType<String>()),
      _property('notes', const ClassType<String>(nullable: true)),
      _property('between', const ClassType<int>(nullable: true)),
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
