import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late RelationalMappingContext context;
  setUp(() => context = testContext());

  group('Book', () {
    late PersistentEntity<Book> book;
    setUp(() => book = context.getRequiredPersistentEntity<Book>());

    test('table, schema and type', () {
      expect(book.tableName, 'books');
      expect(book.schema, isNull);
      expect(book.type, Book);
    });

    test('is cached', () {
      expect(context.getRequiredPersistentEntity<Book>(), same(book));
    });

    test('transient properties are left out, the others kept in order', () {
      expect(book.property('note'), isNull);
      expect(book.properties.map((p) => p.name), [
        'id',
        'title',
        'year',
        'genre',
        'price',
        'available',
        'author',
        'version',
        'createdAt',
        'modifiedAt',
        'createdBy',
        'modifiedBy',
      ]);
    });

    test('id and version', () {
      expect(book.idProperty!.name, 'id');
      expect(book.versionProperty!.name, 'version');
      expect(book.hasVersion, isTrue);
      expect(book.property('title')!.isId, isFalse);
    });

    test('columns: snake case, overridden by @Column', () {
      expect(book.property('createdAt')!.columnName, 'created_at');
      expect(book.property('modifiedBy')!.columnName, 'modified_by');
      expect(book.property('author')!.columnName, 'writer_id');
    });

    test('audit kinds', () {
      expect(book.property('createdAt')!.audit, AuditKind.createdDate);
      expect(book.property('modifiedAt')!.audit, AuditKind.lastModifiedDate);
      expect(book.property('createdBy')!.audit, AuditKind.createdBy);
      expect(book.property('modifiedBy')!.audit, AuditKind.lastModifiedBy);
      expect(book.property('title')!.audit, isNull);
    });

    test('aggregate reference: the id type', () {
      final author = book.property('author')!;
      expect(author.isAggregateReference, isTrue);
      expect(author.referencedType!.type, int);
      expect(book.property('year')!.isAggregateReference, isFalse);
    });

    test('nullability follows the declaration', () {
      expect(book.property('year')!.isNullable, isTrue);
      expect(book.property('title')!.isNullable, isFalse);
    });

    test('by type and by instance', () {
      expect(context.getPersistentEntity(Book)!.type, Book);
      expect(context.getPersistentEntity(String), isNull);
      expect(context.entityOf(Book(title: 'x')).tableName, 'books');
    });

    test('values are read and written through the property', () {
      final b = Book(title: 'Dune');
      book.property('title')!.setValue(b, 'Emma');
      expect(book.property('title')!.getValue(b), 'Emma');
    });
  });

  group('final fields', () {
    test('a read-only property the constructor does not take is skipped', () {
      final reading = context.getRequiredPersistentEntity<Reading>();
      expect(reading.property('kind'), isNull);
      expect(reading.property('text'), isNotNull);
      expect(reading.tableName, 'reading');
    });
  });

  group('mapped collections', () {
    late PersistentEntity<OrderLine> line;
    setUp(() => line = context.getRequiredPersistentEntity<OrderLine>());

    test('table named after the class', () {
      expect(line.tableName, 'order_line');
    });

    test('List, Set and Map have a child entity', () {
      final items = line.property('items')!;
      expect(items.isMappedCollection, isTrue);
      expect(items.childEntity!.type, Item);
      expect(items.childEntity!.tableName, 'item');
      expect(line.property('tags')!.childEntity!.tableName, 'tags');
      expect(line.property('notes')!.childEntity!.type, Note);
      expect(line.property('extras')!.childEntity!.type, Item);
    });

    test('columns leaves the collections out', () {
      expect(line.columns.map((p) => p.name), ['id']);
    });

    test('reverse and key column names', () {
      final items = line.property('items')!.mappedCollection;
      expect(context.reverseColumnName(line, items), 'line_ref');
      expect(context.keyColumnName(line, items), 'position');
      final tags = line.property('tags')!.mappedCollection;
      expect(context.reverseColumnName(line, tags), 'order_line_id');
      expect(context.keyColumnName(line, tags), 'order_line_key');
    });

    test('the child has its own @Id', () {
      expect(line.property('items')!.childEntity!.idProperty!.name, 'id');
    });
  });

  group('naming strategy', () {
    test('is used for tables and columns', () {
      final c = testContext(naming: _Prefixed());
      final book = c.getRequiredPersistentEntity<Book>();
      expect(book.tableName, 'books');
      expect(book.property('title')!.columnName, 'c_title');
      expect(book.property('author')!.columnName, 'writer_id');
      expect(
        c.getRequiredPersistentEntity<OrderLine>().tableName,
        'order_line',
      );
    });
  });

  group('MappingException', () {
    RelationalMappingContext with_(BeanIntrospection<Object> i) =>
        RelationalMappingContext(
          introspector: BeanIntrospector(
            introspections: [
              i,
              versionedChildIntrospection(),
              plainChildIntrospection(),
              loopIntrospection(),
            ],
          ),
        );

    Matcher failsWith(String text) => throwsA(
      isA<MappingException>().having(
        (e) => e.message,
        'message',
        contains(text),
      ),
    );

    test('is a data access API usage error', () {
      expect(
        MappingException('x'),
        isA<InvalidDataAccessApiUsageException>(),
      );
    });

    test('class not described', () {
      expect(
        () => context.getRequiredPersistentEntity<Author>(),
        failsWith('Author is not described'),
      );
      expect(
        () => context.getRequiredPersistentEntityOfType(Author),
        failsWith('Author is not described'),
      );
      expect(() => context.entityOf(Author()), failsWith('Author'));
    });

    test('more than one @Id', () {
      expect(
        () =>
            with_(twoIdsIntrospection()).getRequiredPersistentEntity<TwoIds>(),
        failsWith('TwoIds has more than one @Id: a, b'),
      );
    });

    test('more than one @Version', () {
      expect(
        () =>
            with_(twoVersionsIntrospection())
                .getRequiredPersistentEntity<TwoVersions>(),
        failsWith('TwoVersions has more than one @Version'),
      );
    });

    test('@Version of the wrong type', () {
      expect(
        () =>
            with_(badVersionIntrospection())
                .getRequiredPersistentEntity<BadVersion>(),
        failsWith('BadVersion.v: @Version must be an int or a DateTime'),
      );
    });

    test('a DateTime @Version is accepted', () {
      final i = BeanIntrospection<_Stamped>(
        className: 'Stamped',
        properties: [
          prop<_Stamped>(
            'at',
            DateTime,
            const ClassType<DateTime>(nullable: true),
            (o) => o.at,
            set: (o, v) => o.at = v as DateTime?,
            annotations: const [Version()],
          ),
        ],
      );
      expect(with_(i).getRequiredPersistentEntity<_Stamped>().hasVersion, true);
    });

    test('@CreatedDate on a non-DateTime', () {
      expect(
        () =>
            with_(badDateIntrospection())
                .getRequiredPersistentEntity<BadDate>(),
        failsWith('BadDate.created: @CreatedDate must be a DateTime'),
      );
    });

    test('two audit annotations on one property', () {
      expect(
        () =>
            with_(badAuditIntrospection())
                .getRequiredPersistentEntity<BadAudit>(),
        failsWith('BadAudit.d has more than one audit annotation'),
      );
    });

    test('@Version on a child entity', () {
      expect(
        () =>
            with_(withVersionedChildIntrospection())
                .getRequiredPersistentEntity<WithVersionedChild>(),
        failsWith('VersionedChild.v: @Version is only allowed'),
      );
    });

    test('a child that is not @Table', () {
      expect(
        () =>
            with_(withPlainChildIntrospection())
                .getRequiredPersistentEntity<WithPlainChild>(),
        failsWith('WithPlainChild.children: the child class PlainChild'),
      );
    });

    test('a child that is not described', () {
      expect(
        () =>
            with_(withUnknownChildIntrospection())
                .getRequiredPersistentEntity<WithUnknownChild>(),
        failsWith('WithUnknownChild.children: the children of type Unknown'),
      );
    });

    test('an aggregate that contains itself', () {
      expect(
        () => with_(loopIntrospection()).getRequiredPersistentEntity<Loop>(),
        failsWith('Loop'),
      );
    });

    test('an @Id that is a mapped collection', () {
      final i = BeanIntrospection<_Odd>(
        className: 'Odd',
        properties: [
          prop<_Odd>(
            'items',
            List<Item>,
            const ListType<Item>(ClassType<Item>()),
            (o) => o.items,
            set: (o, v) => o.items = v! as List<Item>,
            annotations: const [Id(), MappedCollection()],
          ),
        ],
      );
      expect(
        () => with_(i).getRequiredPersistentEntity<_Odd>(),
        failsWith('Odd.items: a @MappedCollection cannot be'),
      );
    });

    test('an AggregateReference without its arguments', () {
      final i = BeanIntrospection<_Stamped>(
        className: 'Stamped',
        properties: [
          prop<_Stamped>(
            'at',
            AggregateReference<Author, int>,
            const GenericType<AggregateReference<Author, int>>([
              ClassType<Author>(),
            ]),
            (o) => o.at,
            set: (o, v) => o.at = v as DateTime?,
          ),
        ],
      );
      expect(
        () => with_(i).getRequiredPersistentEntity<_Stamped>(),
        failsWith('Stamped.at: an AggregateReference needs'),
      );
    });
  });
}

class _Stamped {
  DateTime? at;
}

class _Odd {
  List<Item> items = [];
}

class _Prefixed extends NamingStrategy {
  @override
  String columnName(String propertyName, Column? column) =>
      column?.value ?? 'c_${snakeCase(propertyName)}';
}
