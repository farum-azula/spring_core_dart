// IntrospectedObject: ==, hashCode and toString() through the object
// methods of a class's description, written here by hand as the generator
// writes them for @EqualsAndHashCode and @ToString.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Book with IntrospectedObject {
  Book(this.title, this.tags, {this.password = ''});

  final String title;
  final List<String> tags;
  final String password;
}

class Novel extends Book {
  Novel(super.title, super.tags);
}

class Unregistered with IntrospectedObject {}

class Labelled with IntrospectedObject {
  Labelled(this.label);

  final String label;
}

class Holder<T> with IntrospectedObject {
  Holder(this.value);

  final T value;
}

class Base with IntrospectedObject {
  Base(this.id);

  final int id;
}

class Child extends Base {
  Child(super.id, this.name);

  final String name;
}

class Signed extends Base {
  Signed(super.id, this.signature);

  final String signature;
}

class Legacy {
  Legacy(this.code);

  final int code;

  @override
  bool operator ==(Object other) => other is Legacy && other.code == code;

  @override
  int get hashCode => code;

  @override
  String toString() => 'Legacy#$code';
}

class Modern extends Legacy with IntrospectedObject {
  Modern(super.code, this.name);

  final String name;
}

bool _bookEquals(Book a, Book b) =>
    a.title == b.title && deepEquals(a.tags, b.tags);

int _bookHash(Book object) => Object.hash(object.title, deepHash(object.tags));

String _bookText(Book o) =>
    'Book(title: ${o.title}, tags: ${o.tags}, password: ******)';

final _descriptions = <Introspection<Object>>[
  const Introspection<Book>(
    className: 'Book',
    parts: {},
    objectMethods: ObjectMethods<Book>(
      equals: _bookEquals,
      hashCode: _bookHash,
      toString: _bookText,
    ),
  ),
  Introspection<Labelled>(
    className: 'Labelled',
    parts: const {},
    objectMethods: ObjectMethods<Labelled>(
      toString: (o) => 'Labelled(label: ${o.label})',
    ),
  ),
  Introspection<Holder<dynamic>>(
    className: 'Holder',
    parts: const {},
    objectMethods: ObjectMethods<Holder<dynamic>>(
      equals: (a, b) => deepEquals(a.value, b.value),
      hashCode: (o) => deepHash(o.value),
      toString: (o) => 'Holder(value: ${o.value})',
    ),
  ),
  Introspection<Base>(
    className: 'Base',
    parts: const {},
    objectMethods: ObjectMethods<Base>(
      equals: (a, b) => a.id == b.id,
      hashCode: (o) => o.id.hashCode,
      toString: (o) => 'Base(id: ${o.id})',
    ),
  ),
  Introspection<Child>(
    className: 'Child',
    parts: const {},
    objectMethods: ObjectMethods<Child>(
      equals: (a, b) => a.name == b.name,
      hashCode: (o) => o.name.hashCode,
      toStringWithSuper: (o, superText) =>
          'Child(super: $superText, name: ${o.name})',
      superclass: Base,
      superEquals: SuperMethod.described,
      superToString: SuperMethod.described,
    ),
  ),
  Introspection<Signed>(
    className: 'Signed',
    parts: const {},
    objectMethods: ObjectMethods<Signed>(
      toString: (o) => 'Signed(signature: ${o.signature})',
      superclass: Base,
      superEquals: SuperMethod.described,
    ),
  ),
  Introspection<Modern>(
    className: 'Modern',
    parts: const {},
    objectMethods: ObjectMethods<Modern>(
      equals: (a, b) => a.name == b.name,
      hashCode: (o) => o.name.hashCode,
      toStringWithSuper: (o, superText) =>
          'Modern(super: $superText, name: ${o.name})',
      superEquals: SuperMethod.inherited,
      superToString: SuperMethod.inherited,
    ),
  ),
];

void main() {
  test('without a registered description, each method says how to register '
      'it, never compares by identity', () {
    final object = Unregistered();

    for (final call in <Object? Function()>[
      () => object == Unregistered(),
      () => object.hashCode,
      () => object.toString(),
    ]) {
      expect(
        call,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('No description of Unregistered is registered'),
              contains('Start the application'),
              contains(
                r'Introspector.shared.registerAll($<module>Introspections)',
              ),
            ),
          ),
        ),
      );
    }
    // identical objects are equal without a description.
    expect(object == object, isTrue);
  });

  group('registered', () {
    // A context's introspector, a child of the shared one: what it
    // registers is known to IntrospectedObject too.
    setUpAll(
      () =>
          Introspector(parent: Introspector.shared).registerAll(_descriptions),
    );

    test('== and hashCode by the fields, collections by content', () {
      final dune = Book('Dune', ['sf']);
      final same = Book('Dune', ['sf']);

      expect(dune, same);
      expect(dune.hashCode, same.hashCode);
      expect({dune}.contains(same), isTrue);
      expect(dune, isNot(Book('Dune', ['fantasy'])));
      expect(dune, isNot(Book('Emma', ['sf'])));
    });

    test('toString() as generated', () {
      expect(
        '${Book('Dune', ['sf'], password: 'spice')}',
        'Book(title: Dune, tags: [sf], password: ******)',
      );
    });

    test("a subclass without a description uses its superclass's, and is "
        'never equal to it', () {
      expect(Novel('Dune', ['sf']), Novel('Dune', ['sf']));
      expect(Novel('Dune', ['sf']), isNot(Book('Dune', ['sf'])));
      expect(Book('Dune', ['sf']), isNot(Novel('Dune', ['sf'])));
      expect('${Novel('Dune', [])}', startsWith('Book(title: Dune'));
    });

    test('@ToString alone: identity for == and hashCode', () {
      final label = Labelled('a');

      expect(label, isNot(Labelled('a')));
      expect(label.hashCode, identityHashCode(label));
      expect('$label', 'Labelled(label: a)');
    });

    test("a generic class's parameterizations use its description", () {
      expect(Holder(<int>[1, 2]), Holder(<int>[1, 2]));
      expect(Holder(<int>[1, 2]).hashCode, Holder(<int>[1, 2]).hashCode);
      expect(Holder('a'), isNot(Holder('b')));
      expect('${Holder(3)}', 'Holder(value: 3)');
    });

    test('callSuper with a described superclass: its functions first', () {
      expect(Child(1, 'a'), Child(1, 'a'));
      expect(Child(1, 'a'), isNot(Child(2, 'a')));
      expect(Child(1, 'a'), isNot(Child(1, 'b')));
      expect(Child(1, 'a').hashCode, Child(1, 'a').hashCode);
      expect('${Child(1, 'a')}', 'Child(super: Base(id: 1), name: a)');
    });

    test('@ToString alone below a described superclass: its == stays', () {
      expect(Signed(1, 'a'), Signed(1, 'b'));
      expect(Signed(1, 'a'), isNot(Signed(2, 'a')));
      expect(Signed(1, 'a').hashCode, Signed(1, 'b').hashCode);
      expect('${Signed(1, 'a')}', 'Signed(signature: a)');
    });

    test("callSuper with a superclass's own methods: called as super", () {
      expect(Modern(1, 'a'), Modern(1, 'a'));
      expect(Modern(1, 'a'), isNot(Modern(2, 'a')));
      expect(Modern(1, 'a'), isNot(Modern(1, 'b')));
      expect(Modern(1, 'a').hashCode, Modern(1, 'a').hashCode);
      expect(Modern(1, 'a').hashCode, isNot(Modern(2, 'a').hashCode));
      expect('${Modern(7, 'a')}', 'Modern(super: Legacy#7, name: a)');
    });

    test('the descriptions are found by the type, the object methods too', () {
      expect(Introspector.objectMethodsForType(Book)?.definesEquals, isTrue);
      expect(
        Introspector.objectMethodsForType(Labelled)?.definesEquals,
        isFalse,
      );
      expect(Introspector.objectMethodsForType(Novel), isNull);
      expect(
        Introspector.objectMethodsOf(Novel('a', [])).isInstance(Book('a', [])),
        isTrue,
      );
    });
  });
}
