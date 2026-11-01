// A class described for what the build saw used: getters only (written
// out), constructor and setters only (read in), methods only where an
// expression may call them. Asking for a part that was left out throws an
// error that names the class, the part and the fix.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Book {
  Book({this.title = '', this.pages = 0});
  String title;
  int pages;

  String shout() => title.toUpperCase();
}

@JsonInclude(JsonInclusion.nonDefault)
class Counter {
  Counter();
  int count = 0;
  bool live = true;
}

class Tag {
  Tag(this.label);
  final String label;

  @JsonValue()
  String asText() => 'tag:$label';
}

class Desk {
  Desk();
  Book? book;
}

class Frame {
  Frame();
  Book? get book => null;
}

enum Mood { calm, loud }

class Box<T> {
  Box();
  T? content;
}

class Form {
  Form();
  @NotBlank()
  String name = '';
  String note = '';
}

// What the generator writes for each use of Book.
BeanIntrospection<Book> _book({
  Set<IntrospectionPart> parts = const {
    IntrospectionPart.read,
    IntrospectionPart.write,
    IntrospectionPart.methods,
  },
}) {
  final read = parts.contains(IntrospectionPart.read);
  final write = parts.contains(IntrospectionPart.write);
  return BeanIntrospection<Book>(
    className: 'Book',
    parts: parts,
    properties: [
      BeanProperty<Book>(
        'title',
        type: String,
        typeInfo: const ClassType<String>(),
        get: read ? (b) => b.title : null,
        set: write ? (b, v) => b.title = v! as String : null,
      ),
      BeanProperty<Book>(
        'pages',
        type: int,
        typeInfo: const ClassType<int>(),
        get: read ? (b) => b.pages : null,
        set: write ? (b, v) => b.pages = v! as int : null,
      ),
    ],
    instantiate: write ? Book.new : null,
    methods: [
      if (parts.contains(IntrospectionPart.methods))
        BeanMethod<Book>(
          'shout',
          returnType: String,
          invoke: (b, _) => b.shout(),
        ),
    ],
  );
}

BeanIntrospector _introspector(
  BeanIntrospection<Object> Function() describe,
) => BeanIntrospector(introspections: [describe()]);

void main() {
  group('BeanProperty', () {
    test('a property without a getter is not readable', () {
      final property = BeanProperty<Book>(
        'title',
        type: String,
        set: (b, v) => b.title = v! as String,
      );
      expect(property.isReadable, isFalse);
      expect(property.isWritable, isTrue);
      expect(
        () => property.getValue(Book()),
        throwsA(
          isA<IntrospectionPartError>()
              .having((e) => e.beanType, 'beanType', Book)
              .having((e) => e.part, 'part', IntrospectionPart.read)
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('Book is described without its getters'),
                  contains("property 'title'"),
                  contains('@Introspected()'),
                ),
              ),
        ),
      );
    });

    test('a property with a getter is readable', () {
      final property = BeanProperty<Book>(
        'title',
        type: String,
        get: (b) => b.title,
      );
      expect(property.isReadable, isTrue);
      expect(property.getValue(Book(title: 'Dune')), 'Dune');
    });
  });

  group('BeanIntrospection', () {
    test('describes every part unless told otherwise', () {
      final all = BeanIntrospection<Book>();
      for (final part in IntrospectionPart.values) {
        expect(all.describesPart(part), isTrue);
      }
    });

    test('requirePart names the class, the part and the fix', () {
      final introspection = _book(parts: {IntrospectionPart.write});
      expect(
        () => introspection.requirePart(
          IntrospectionPart.methods,
          'an expression calls it',
        ),
        throwsA(
          isA<IntrospectionPartError>().having(
            (e) => e.message,
            'message',
            'Book is described without its methods, but an expression calls '
                'it. The build described only what it saw used, and did not '
                'see that: add @Introspected() to Book.',
          ),
        ),
      );
    });

    test('instantiate without the write part is an IntrospectionPartError', () {
      final introspection = _book(parts: {IntrospectionPart.read});
      expect(
        introspection.instantiate,
        throwsA(
          isA<IntrospectionPartError>().having(
            (e) => e.part,
            'part',
            IntrospectionPart.write,
          ),
        ),
      );
    });

    test('a class with the write part and no constructor keeps its error', () {
      final introspection = BeanIntrospection<Book>();
      expect(
        introspection.instantiate,
        throwsA(
          isA<StateError>().having(
            (e) => e is IntrospectionPartError,
            'is part error',
            isFalse,
          ),
        ),
      );
    });
  });

  group('BeanWrapper', () {
    test('reads a property of a class described for writing only', () {
      final introspector = _introspector(
        () => _book(parts: {IntrospectionPart.write}),
      );
      final wrapper = BeanWrapper(
        Book(title: 'Dune'),
        introspector: introspector,
      );
      expect(
        () => wrapper.getPropertyValue('title'),
        throwsA(
          isA<NotReadablePropertyException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Book is described without its getters'),
              contains('@Introspected()'),
            ),
          ),
        ),
      );
      expect(wrapper.isReadableProperty('title'), isFalse);
    });

    test('sets a property of a class described for writing only', () {
      final introspector = _introspector(
        () => _book(parts: {IntrospectionPart.write}),
      );
      final book = Book();
      BeanWrapper(
        book,
        introspector: introspector,
      ).setPropertyValue('title', 'Dune');
      expect(book.title, 'Dune');
    });

    test('sets a property of a class described for reading only', () {
      final introspector = _introspector(
        () => _book(parts: {IntrospectionPart.read}),
      );
      final wrapper = BeanWrapper(Book(), introspector: introspector);
      expect(
        () => wrapper.setPropertyValue('title', 'Dune'),
        throwsA(
          isA<NotWritablePropertyException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Book is described without its constructor and setters'),
              contains("property 'title' is set"),
            ),
          ),
        ),
      );
      expect(wrapper.getPropertyValue('title'), '');
    });

    test('grows a nested object only when its class can be created', () {
      final introspector = BeanIntrospector(
        introspections: [
          BeanIntrospection<Desk>(
            properties: [
              BeanProperty<Desk>(
                'book',
                type: Book,
                nullable: true,
                typeInfo: const ClassType<Book>(nullable: true),
                get: (d) => d.book,
                set: (d, v) => d.book = v as Book?,
              ),
            ],
            instantiate: Desk.new,
          ),
          _book(parts: {IntrospectionPart.read}),
        ],
      );
      final wrapper = BeanWrapper(
        Desk(),
        introspector: introspector,
        autoGrowNestedPaths: true,
      );
      expect(
        () => wrapper.setPropertyValue('book.title', 'Dune'),
        throwsA(isA<IntrospectionPartError>()),
      );
    });

    test('a null final nested property stays a null path', () {
      // The class of the value is described for reading only, yet the
      // property cannot be set: the path is null, not a missing part.
      final introspector = BeanIntrospector(
        introspections: [
          BeanIntrospection<Frame>(
            properties: [
              BeanProperty<Frame>(
                'book',
                type: Book,
                nullable: true,
                typeInfo: const ClassType<Book>(nullable: true),
                get: (f) => f.book,
              ),
            ],
            instantiate: Frame.new,
          ),
          _book(parts: {IntrospectionPart.read}),
        ],
      );
      final wrapper = BeanWrapper(Frame(), introspector: introspector);
      expect(
        () => wrapper.setPropertyValue('book.title', 'Dune'),
        throwsA(isA<NullValueInNestedPathException>()),
      );
    });
  });

  group('ObjectMapper', () {
    test('writes a class described for reading', () {
      final mapper = ObjectMapper(
        introspector: _introspector(
          () => _book(parts: {IntrospectionPart.read}),
        ),
      );
      expect(
        mapper.writeValueAsString(Book(title: 'Dune', pages: 3)),
        '{"pages":3,"title":"Dune"}',
      );
    });

    test('a class described for writing only is not written', () {
      final mapper = ObjectMapper(
        introspector: _introspector(
          () => _book(parts: {IntrospectionPart.write}),
        ),
      );
      expect(
        () => mapper.writeValueAsString(Book(title: 'Dune')),
        throwsA(
          isA<IntrospectionPartError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Book is described without its getters'),
              contains('it is written out as JSON'),
              contains('@Introspected()'),
            ),
          ),
        ),
      );
    });

    test('reads a class described for writing', () {
      final mapper = ObjectMapper(
        introspector: _introspector(
          () => _book(parts: {IntrospectionPart.write}),
        ),
      );
      final book = mapper.readValue<Book>('{"title":"Dune","pages":3}');
      expect(book.title, 'Dune');
      expect(book.pages, 3);
    });

    test('a class described for reading only is not read', () {
      final mapper = ObjectMapper(
        introspector: _introspector(
          () => _book(parts: {IntrospectionPart.read}),
        ),
      );
      expect(
        () => mapper.readValue<Book>('{"title":"Dune"}'),
        throwsA(
          isA<IntrospectionPartError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Book is described without its constructor and setters'),
              contains('it is read in from JSON'),
              contains('@Introspected()'),
            ),
          ),
        ),
      );
    });

    test('a nested value is written through its own description', () {
      final mapper = ObjectMapper(
        introspector: BeanIntrospector(
          introspections: [
            BeanIntrospection<Desk>(
              parts: {IntrospectionPart.read},
              properties: [
                BeanProperty<Desk>(
                  'book',
                  type: Book,
                  nullable: true,
                  typeInfo: const ClassType<Book>(nullable: true),
                  get: (d) => d.book,
                ),
              ],
            ),
            _book(parts: {IntrospectionPart.write}),
          ],
        ),
      );
      expect(
        () => mapper.writeValueAsString(Desk()..book = Book(title: 'Dune')),
        throwsA(isA<IntrospectionPartError>()),
      );
    });

    test('nonDefault inclusion needs the constructor of the class', () {
      Counter counter() => Counter();
      BeanIntrospection<Counter> describe(Set<IntrospectionPart> parts) =>
          BeanIntrospection<Counter>(
            parts: parts,
            annotations: const [JsonInclude(JsonInclusion.nonDefault)],
            properties: [
              BeanProperty<Counter>(
                'count',
                type: int,
                typeInfo: const ClassType<int>(),
                get: (c) => c.count,
              ),
              BeanProperty<Counter>(
                'live',
                type: bool,
                typeInfo: const ClassType<bool>(),
                get: (c) => c.live,
              ),
            ],
            instantiate: parts.contains(IntrospectionPart.write)
                ? counter
                : null,
          );
      final full = ObjectMapper(
        introspector: BeanIntrospector(
          introspections: [
            describe({IntrospectionPart.read, IntrospectionPart.write}),
          ],
        ),
      );
      // `live` equals the default of a new Counter, `count` differs.
      expect(
        full.writeValueAsString(Counter()..count = 2),
        '{"count":2}',
      );
      final readOnly = ObjectMapper(
        introspector: BeanIntrospector(
          introspections: [
            describe({IntrospectionPart.read}),
          ],
        ),
      );
      expect(
        () => readOnly.writeValueAsString(Counter()..count = 2),
        throwsA(
          isA<IntrospectionPartError>().having(
            (e) => e.message,
            'message',
            contains('JsonInclusion.nonDefault'),
          ),
        ),
      );
    });

    test('the mapper-wide nonDefault falls back to the defaults of types', () {
      // No class-level annotation: nothing asks for a new instance.
      final mapper = ObjectMapper(
        inclusion: JsonInclusion.nonDefault,
        introspector: _introspector(
          () => _book(parts: {IntrospectionPart.read}),
        ),
      );
      expect(
        mapper.writeValueAsString(Book(pages: 3)),
        '{"pages":3}',
      );
    });

    test('a @JsonValue method is described with the read part only', () {
      final mapper = ObjectMapper(
        introspector: BeanIntrospector(
          introspections: [
            BeanIntrospection<Tag>(
              parts: {IntrospectionPart.read},
              methods: [
                BeanMethod<Tag>(
                  'asText',
                  returnType: String,
                  annotations: const [JsonValue()],
                  invoke: (t, _) => t.asText(),
                ),
              ],
            ),
          ],
        ),
      );
      expect(mapper.writeValueAsString(Tag('a')), '"tag:a"');
    });
  });

  group('BeanValidator', () {
    BeanIntrospection<Form> describe({
      required bool name,
      required bool note,
    }) => BeanIntrospection<Form>(
      parts: const {},
      properties: [
        BeanProperty<Form>(
          'name',
          type: String,
          typeInfo: const ClassType<String>(),
          get: name ? (f) => f.name : null,
          annotations: const [NotBlank()],
        ),
        BeanProperty<Form>(
          'note',
          type: String,
          typeInfo: const ClassType<String>(),
          get: note ? (f) => f.note : null,
        ),
      ],
    );

    test('reads only the properties that carry constraints', () {
      final validator = BeanValidator(
        introspector: BeanIntrospector(
          introspections: [describe(name: true, note: false)],
        ),
      );
      final violations = validator.validateObject(Form());
      expect(violations.map((v) => v.propertyPath), ['name']);
    });

    test('a constrained property without a getter is an error', () {
      final validator = BeanValidator(
        introspector: BeanIntrospector(
          introspections: [describe(name: false, note: true)],
        ),
      );
      expect(
        () => validator.validateObject(Form()),
        throwsA(
          isA<IntrospectionPartError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Form is described without its getters'),
              contains("the validator reads property 'name'"),
            ),
          ),
        ),
      );
    });

    test('validateProperty of a property without a getter is an error', () {
      final validator = BeanValidator(
        introspector: BeanIntrospector(
          introspections: [describe(name: false, note: false)],
        ),
      );
      expect(
        () => validator.validateProperty(Form(), 'note'),
        throwsA(isA<IntrospectionPartError>()),
      );
    });
  });

  group('DataBinder', () {
    test('binding to a class described for reading is an error', () {
      final binder = DataBinder(
        Book(),
        objectName: 'book',
        introspector: _introspector(
          () => _book(parts: {IntrospectionPart.read}),
        ),
      );
      expect(
        () => binder.bind({'title': 'Dune'}),
        throwsA(
          isA<IntrospectionPartError>()
              .having((e) => e.part, 'part', IntrospectionPart.write)
              .having(
                (e) => e.message,
                'message',
                contains('Book is described without its constructor'),
              ),
        ),
      );
    });

    test('binds to a class described for writing', () {
      final book = Book();
      DataBinder(
        book,
        objectName: 'book',
        introspector: _introspector(
          () => _book(parts: {IntrospectionPart.write}),
        ),
      ).bind({'title': 'Dune'});
      expect(book.title, 'Dune');
    });

    test('constructs only a class described for writing', () {
      final binder = DataBinder(
        null,
        objectName: 'book',
        introspector: _introspector(
          () => _book(parts: {IntrospectionPart.read}),
        ),
      )..targetType = Book;
      expect(
        () => binder.construct(const MapValueResolver({})),
        throwsA(
          isA<IntrospectionPartError>().having(
            (e) => e.message,
            'message',
            contains('Book is described without its constructor and setters'),
          ),
        ),
      );
    });
  });

  group('expressions', () {
    BeanIntrospector introspector(Set<IntrospectionPart> parts) =>
        _introspector(() => _book(parts: parts));

    StandardEvaluationContext context(Object root, BeanIntrospector i) =>
        StandardEvaluationContext(root)
          ..addPropertyAccessor(IntrospectionPropertyAccessor(i))
          ..addMethodResolver(IntrospectionMethodResolver(i));

    final parser = SpelExpressionParser();

    test('read a property of a class described for reading', () {
      final i = introspector({IntrospectionPart.read});
      expect(
        parser
            .parseExpression('title')
            .getValue(context(Book(title: 'Dune'), i)),
        'Dune',
      );
    });

    test('a property without a getter says why it cannot be read', () {
      final i = introspector({IntrospectionPart.write});
      expect(
        () => parser
            .parseExpression('title')
            .getValue(context(Book(title: 'Dune'), i)),
        throwsA(
          isA<SpelEvaluationException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Book is described without its getters'),
              contains("property 'title'"),
              contains('@Introspected()'),
            ),
          ),
        ),
      );
    });

    test('a method of a class described with methods is called', () {
      final i = introspector({
        IntrospectionPart.read,
        IntrospectionPart.methods,
      });
      expect(
        parser
            .parseExpression('shout()')
            .getValue(context(Book(title: 'Dune'), i)),
        'DUNE',
      );
    });

    test('a method of a class described without methods says why', () {
      final i = introspector({IntrospectionPart.read});
      expect(
        () => parser
            .parseExpression('shout()')
            .getValue(context(Book(title: 'Dune'), i)),
        throwsA(
          isA<SpelEvaluationException>()
              .having((e) => e.messageCode, 'code', SpelMessage.methodNotFound)
              .having((e) => e.expressionString, 'expression', 'shout()')
              .having((e) => e.position, 'position', 0)
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('Method shout() cannot be found on type Book'),
                  contains('described without its methods'),
                  contains('@Introspected()'),
                ),
              ),
        ),
      );
    });

    test('a misspelled method is caught as a SpelEvaluationException', () {
      final i = introspector({IntrospectionPart.read});
      expect(
        () => parser
            .parseExpression('title + shoot(1)')
            .getValue(context(Book(title: 'Dune'), i)),
        throwsA(
          isA<SpelEvaluationException>()
              .having((e) => e.messageCode, 'code', SpelMessage.methodNotFound)
              .having((e) => e.position, 'position', 8)
              .having((e) => e.message, 'message', contains('shoot(int)')),
        ),
      );
    });

    test('toString() still works on a class described without methods', () {
      final i = introspector({IntrospectionPart.read});
      final book = Book(title: 'Dune');
      expect(
        parser.parseExpression('toString()').getValue(context(book, i)),
        book.toString(),
      );
    });
  });

  group('registering two descriptions of one class', () {
    BeanIntrospector register(List<BeanIntrospection<Object>> descriptions) =>
        BeanIntrospector()..registerAll(descriptions);

    test('two modules that use a class differently both get their parts', () {
      // One module writes Book out, the other reads it in: the order they
      // load in makes no difference.
      for (final order in [
        [IntrospectionPart.read, IntrospectionPart.write],
        [IntrospectionPart.write, IntrospectionPart.read],
      ]) {
        final introspector = register([
          for (final part in order) _book(parts: {part}),
        ]);
        final book = introspector.forType(Book)!;
        expect(book.parts, {IntrospectionPart.read, IntrospectionPart.write});
        final title = book.getProperty('title')!;
        expect(title.isReadable, isTrue, reason: '$order');
        expect(title.isWritable, isTrue, reason: '$order');
        expect(book.isInstantiable, isTrue, reason: '$order');
        final instance = book.instantiate() as Book;
        title.setValue(instance, 'Dune');
        expect(title.getValue(instance), 'Dune');
        expect(book.getProperty('pages')!.isWritable, isTrue);
        expect(book.getProperty('pages')!.isReadable, isTrue);
        expect(book.properties.map((p) => p.name), ['title', 'pages']);
      }
    });

    test('what one module wrote out the other can read back', () {
      final introspector = register([
        _book(parts: {IntrospectionPart.read}),
        _book(parts: {IntrospectionPart.write}),
      ]);
      final mapper = ObjectMapper(introspector: introspector);
      final json = mapper.writeValueAsString(Book(title: 'Dune', pages: 3));
      expect(json, '{"pages":3,"title":"Dune"}');
      final book = mapper.readValue<Book>(json);
      expect(book.title, 'Dune');
      expect(book.pages, 3);
    });

    test('a description that holds everything is not replaced by less', () {
      // An explicit @Introspected() in one module, a read-only description
      // in another that loads later.
      final introspector = register([
        _book(),
        _book(parts: {IntrospectionPart.read}),
      ]);
      final book = introspector.forType(Book)!;
      expect(book.parts, {
        IntrospectionPart.read,
        IntrospectionPart.write,
        IntrospectionPart.methods,
      });
      expect(book.isInstantiable, isTrue);
      expect(book.getMethod('shout'), isNotNull);
      expect(book.getProperty('title')!.isWritable, isTrue);
    });

    test('a description that holds more replaces the one before it', () {
      final more = _book();
      final introspector = register([
        _book(parts: {IntrospectionPart.read}),
        more,
      ]);
      expect(introspector.forType(Book), same(more));
    });

    test('the same description twice changes nothing', () {
      final once = _book(parts: {IntrospectionPart.read});
      final introspector = register([once, once]);
      expect(introspector.forType(Book), same(once));
    });

    test('where both have a part, the later description is kept', () {
      final first = BeanIntrospection<Book>(
        parts: const {IntrospectionPart.read, IntrospectionPart.write},
        properties: [
          BeanProperty<Book>(
            'title',
            type: String,
            get: (b) => 'first',
            set: (b, v) => b.title = 'first',
          ),
        ],
        instantiate: () => Book(title: 'first'),
      );
      final second = BeanIntrospection<Book>(
        parts: const {IntrospectionPart.read, IntrospectionPart.methods},
        properties: [
          BeanProperty<Book>('title', type: String, get: (b) => 'second'),
        ],
        methods: [
          BeanMethod<Book>('shout', invoke: (b, _) => 'second'),
        ],
      );
      final merged = register([first, second]).forType(Book)!;
      final title = merged.getProperty('title')!;
      expect(title.getValue(Book()), 'second');
      // The setter and the way to create one are the first's.
      title.setValue(Book(), 'x');
      expect(merged.instantiate() is Book, isTrue);
      expect((merged.instantiate() as Book).title, 'first');
      expect(merged.getMethod('shout'), isNotNull);
      expect(merged.parts, {
        IntrospectionPart.read,
        IntrospectionPart.write,
        IntrospectionPart.methods,
      });
    });

    test('the constructor, fromJson, toJson and annotations are kept', () {
      final withConstructor = BeanIntrospection<Tag>(
        parts: const {IntrospectionPart.write},
        properties: [
          BeanProperty<Tag>('label', type: String),
        ],
        annotations: const [JsonInclude(JsonInclusion.nonNull)],
        constructor: BeanConstructor<Tag>(
          parameters: const [
            BeanParameter(
              'label',
              type: ClassType<String>(),
              isRequired: true,
            ),
          ],
          create: (positional, named) => Tag(positional.first! as String),
        ),
        fromJson: (json) => Tag('$json'),
        toJson: (b) => b.label,
        className: 'Tag',
      );
      final readOnly = BeanIntrospection<Tag>(
        parts: const {IntrospectionPart.read},
        properties: [
          BeanProperty<Tag>('label', type: String, get: (b) => b.label),
        ],
        annotations: const [JsonInclude(JsonInclusion.nonNull)],
      );
      for (final order in [
        [withConstructor, readOnly],
        [readOnly, withConstructor],
      ]) {
        final tag = register(order).forType(Tag)!;
        expect(tag.constructor, isNotNull);
        expect(tag.hasFromJson, isTrue);
        expect(tag.hasToJson, isTrue);
        expect(tag.className, 'Tag');
        expect(tag.annotations, hasLength(1));
        expect(tag.parts, {IntrospectionPart.read, IntrospectionPart.write});
        expect(tag.getProperty('label')!.isReadable, isTrue);
      }
    });

    test('the enums of both descriptions are known', () {
      final introspector = register([
        BeanIntrospection<Book>(
          parts: const {IntrospectionPart.read},
          properties: [
            BeanProperty<Book>(
              'title',
              type: String,
              typeInfo: const EnumType<Mood>(Mood.values),
              get: (b) => b.title,
            ),
          ],
        ),
        BeanIntrospection<Book>(
          parts: const {IntrospectionPart.write},
          properties: [
            BeanProperty<Book>(
              'title',
              type: String,
              set: (b, v) => b.title = '$v',
            ),
          ],
          instantiate: Book.new,
        ),
      ]);
      expect(introspector.enumTypeFor(Mood), isNotNull);
      expect(
        introspector.forType(Book)!.getProperty('title')!.typeInfo,
        isA<EnumType<Mood>>(),
      );
    });

    test('a generic class is specialized from both', () {
      BeanIntrospection<Box<Object?>> box(
        IntrospectionPart part,
      ) => BeanIntrospection<Box<Object?>>(
        parts: {part},
        properties: [
          BeanProperty<Box<Object?>>(
            'content',
            type: Object,
            get: part == IntrospectionPart.read ? (b) => b.content : null,
            set: part == IntrospectionPart.write
                ? (b, v) => b.content = v
                : null,
          ),
        ],
        instantiate: part == IntrospectionPart.write ? Box<Object?>.new : null,
        specialize: (arguments) => BeanIntrospection<Box<String>>(
          parts: {part},
          properties: [
            BeanProperty<Box<String>>(
              'content',
              type: String,
              get: part == IntrospectionPart.read ? (b) => b.content : null,
              set: part == IntrospectionPart.write
                  ? (b, v) => b.content = v as String?
                  : null,
            ),
          ],
          instantiate: part == IntrospectionPart.write ? Box<String>.new : null,
        ),
      );
      final introspector = register([
        box(IntrospectionPart.read),
        box(IntrospectionPart.write),
      ]);
      final specialized = introspector.forGenericType<Box<String>>(const [
        ClassType<String>(),
      ])!;
      expect(specialized.parts, {
        IntrospectionPart.read,
        IntrospectionPart.write,
      });
      final content = specialized.getProperty('content')!;
      expect(content.isReadable, isTrue);
      expect(content.isWritable, isTrue);
      expect(specialized.isInstantiable, isTrue);
    });

    test('two modules of one context share what they describe', () {
      final context = ApplicationContext.run([
        BeanModule(
          'out',
          const [],
          introspections: [
            _book(parts: {IntrospectionPart.read}),
          ],
        ),
        BeanModule(
          'in',
          const [],
          introspections: [
            _book(parts: {IntrospectionPart.write}),
          ],
        ),
      ]);
      addTearDown(context.close);
      final book = context.getBean<BeanIntrospector>().forType(Book)!;
      expect(book.parts, {IntrospectionPart.read, IntrospectionPart.write});
      final wrapper = BeanWrapper(
        Book(),
        introspector: context.getBean<BeanIntrospector>(),
      )..setPropertyValue('title', 'Dune');
      expect(wrapper.getPropertyValue('title'), 'Dune');
    });
  });
}
