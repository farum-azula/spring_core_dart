// The descriptions a module's generated `<library>.spring.introspection.dart`
// lists, registered without a context: what a unit test of the
// application's classes does (`Introspector.registerAll`).
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Book {
  Book({this.title = '', this.pages = 0});
  String title;
  int pages;
}

class Shelf {
  Shelf();
  List<Book> books = [];
}

// What the generator writes for each class (the getter of the module's
// `.spring.introspection.dart`).
List<Introspection<Object>> get _descriptions => [
  Introspection<Book>(
    className: 'Book',
    properties: [
      IntrospectedProperty<Book>(
        'title',
        typeInfo: const ClassType<String>(),
        get: (bean) => bean.title,
        set: (bean, value) => bean.title = value! as String,
      ),
      IntrospectedProperty<Book>(
        'pages',
        typeInfo: const ClassType<int>(),
        get: (bean) => bean.pages,
        set: (bean, value) => bean.pages = value! as int,
      ),
    ],
    instantiate: Book.new,
  ),
  Introspection<Shelf>(
    className: 'Shelf',
    properties: [
      IntrospectedProperty<Shelf>(
        'books',
        typeInfo: const ListType<Book>(ClassType<Book>()),
        get: (bean) => bean.books,
        set: (bean, value) => bean.books = value! as List<Book>,
      ),
    ],
    instantiate: Shelf.new,
  ),
];

void main() {
  test('registers every description of the list', () {
    final introspector = Introspector()..registerAll(_descriptions);

    expect(introspector.forType(Book)?.className, 'Book');
    expect(introspector.forType(Shelf)?.className, 'Shelf');
  });

  test('a mapper over the registry reads and writes the classes', () {
    final introspector = Introspector()..registerAll(_descriptions);
    final mapper = ObjectMapper(introspector: introspector);

    final shelf = mapper.readValue<Shelf>(
      '{"books":[{"title":"Dune","pages":412}]}',
    );

    expect(shelf.books.single.title, 'Dune');
    expect(mapper.writeValueAsString(shelf.books.single), contains('"Dune"'));
  });

  test('the same as the constructor', () {
    final registered = Introspector()..registerAll(_descriptions);
    final constructed = Introspector(introspections: _descriptions);

    expect(
      registered.introspections.map((i) => i.className),
      constructed.introspections.map((i) => i.className),
    );
  });
}
