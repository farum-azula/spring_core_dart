// How references, @OnDelete and the unique keys are mapped (and refused):
// classes described by hand, as the generator describes them.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

/// Every class of this file keeps its values in a map.
class Row {
  final values = <String, Object?>{};
}

class Writer extends Row {}

class Slug extends Row {}

class NoId extends Row {}

class P1 extends Row {}

class P2 extends Row {}

class P3 extends Row {}

class P4 extends Row {}

class P5 extends Row {}

class P6 extends Row {}

class P7 extends Row {}

class P8 extends Row {}

class P9 extends Row {}

class Child extends Row {}

const _int = ClassType<int>();
const _intN = ClassType<int>(nullable: true);
const _string = ClassType<String>();
const _stringN = ClassType<String>(nullable: true);

EntityProperty col(
  String name,
  TypeInfo<Object?> info, {
  List<Object> annotations = const [],
  bool hasDefaultValue = false,
  Object? defaultValue,
}) => EntityProperty(
  name,
  info,
  annotations: annotations,
  writable: true,
  hasDefaultValue: hasDefaultValue,
  defaultValue: defaultValue,
);

EntityIntrospection<T> describe<T extends Row>(
  String name,
  T Function() create,
  List<EntityProperty> properties, {
  List<Object> annotations = const [Table()],
}) => EntityIntrospection<T>(
  name,
  properties,
  annotations: annotations,
  get: (r, i) => r.values[properties[i].name],
  create: (v) => create(),
  write: (r, i, v) => r.values[properties[i].name] = v,
);

EntityIntrospection<Writer> writer() => describe<Writer>(
  'Writer',
  Writer.new,
  [
    col('id', _intN, annotations: const [Id()]),
    col('name', _string),
  ],
  annotations: const [Table('writers')],
);

EntityIntrospection<Slug> slug() => describe<Slug>(
  'Slug',
  Slug.new,
  [
    col('id', _string, annotations: const [Id()]),
  ],
  annotations: const [Table('slugs')],
);

EntityIntrospection<NoId> noId() => describe<NoId>('NoId', NoId.new, [
  col('name', _string),
]);

GenericType<AggregateReference<X, ID>> ref<X, ID>({bool nullable = false}) =>
    GenericType<AggregateReference<X, ID>>(
      [ClassType<X>(), ClassType<ID>()],
      nullable: nullable,
    );

RelationalMappingContext contextOf(
  List<EntityIntrospection<Object>> introspections,
) => RelationalMappingContext(introspections: introspections);

Matcher failsWith(String text) => throwsA(
  isA<MappingException>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  group('the two forms of reference', () {
    late PersistentEntity<P1> post;

    setUp(() {
      final p = describe<P1>('P1', P1.new, [
        col('id', _intN, annotations: const [Id()]),
        col(
          'writer',
          ref<Writer, int>(),
          annotations: const [OnDelete(OnDeleteAction.cascade)],
        ),
        col(
          'editorId',
          _intN,
          annotations: const [Reference(Writer)],
        ),
        col('plain', _int),
      ]);
      post = contextOf([
        p,
        writer(),
      ]).getRequiredPersistentEntity<P1>();
    });

    test('an AggregateReference references the aggregate of its type', () {
      final p = post.property('writer')!;
      expect(p.isReference, isTrue);
      expect(p.isAggregateReference, isTrue);
      expect(p.referencedEntityType, Writer);
      expect(p.referencedEntity!().tableName, 'writers');
      expect(p.referencedEntity!().idProperty!.columnName, 'id');
      expect(p.onDelete, OnDeleteAction.cascade);
      expect(p.hasExplicitOnDelete, isTrue);
    });

    test('a property marked @Reference keeps its own type', () {
      final p = post.property('editorId')!;
      expect(p.isReference, isTrue);
      expect(p.isAggregateReference, isFalse);
      expect(p.referencedEntityType, Writer);
      expect(p.type.type, int);
      expect(p.referencedType, isNull);
      expect(p.columnName, 'editor_id');
      // The default action, not asked for.
      expect(p.onDelete, OnDeleteAction.noAction);
      expect(p.hasExplicitOnDelete, isFalse);
    });

    test('the other properties reference nothing', () {
      expect(post.property('plain')!.isReference, isFalse);
      expect(post.property('plain')!.referencedEntity, isNull);
      expect(post.references.map((p) => p.name), ['writer', 'editorId']);
    });
  });

  group('refused', () {
    test("an id type that is not the target's: both types are named", () {
      final p = describe<P2>('P2', P2.new, [
        col(
          'writerId',
          _string,
          annotations: const [Reference(Writer)],
        ),
      ]);
      expect(
        () => contextOf([p, writer()]).getRequiredPersistentEntity<P2>(),
        failsWith(
          'P2.writerId is a @Reference(Writer) of type String, but '
          'Writer.id is a int',
        ),
      );
    });

    test('an AggregateReference with the wrong id type', () {
      final p = describe<P3>('P3', P3.new, [
        col(
          'slug',
          ref<Slug, int>(),
        ),
      ]);
      expect(
        () => contextOf([p, slug()]).getRequiredPersistentEntity<P3>(),
        failsWith('Slug.id is a String'),
      );
    });

    test('a target that is not described, or has no @Id', () {
      final p = describe<P4>('P4', P4.new, [
        col(
          'writerId',
          _int,
          annotations: const [Reference(Writer)],
        ),
      ]);
      expect(
        () => contextOf([p]).getRequiredPersistentEntity<P4>(),
        failsWith('P4.writerId references Writer, which is not described'),
      );
      final q = describe<P5>('P5', P5.new, [
        col('target', _int, annotations: const [Reference(NoId)]),
      ]);
      expect(
        () => contextOf([q, noId()]).getRequiredPersistentEntity<P5>(),
        failsWith('which has no @Id'),
      );
    });

    test('a field of an entity type: the hint names both ways', () {
      final p = describe<P6>('P6', P6.new, [
        col('author', const ClassType<Writer>()),
      ]);
      expect(
        () => contextOf([p, writer()]).getRequiredPersistentEntity<P6>(),
        failsWith(
          'P6.author is another aggregate: use '
          'AggregateReference<Writer, int> or @Reference(Writer) int '
          'authorId',
        ),
      );
    });

    test('both an AggregateReference and @Reference', () {
      final p = describe<P7>('P7', P7.new, [
        col(
          'writer',
          ref<Writer, int>(),
          annotations: const [Reference(Writer)],
        ),
      ]);
      expect(
        () => contextOf([p, writer()]).getRequiredPersistentEntity<P7>(),
        failsWith('use one of the two'),
      );
    });

    test('setNull needs a nullable property', () {
      EntityIntrospection<P8> p({required bool nullable}) =>
          describe<P8>('P8', P8.new, [
            col(
              'writerId',
              nullable ? _intN : _int,
              annotations: const [
                Reference(Writer),
                OnDelete(OnDeleteAction.setNull),
              ],
            ),
          ]);
      expect(
        () => contextOf([
          p(nullable: false),
          writer(),
        ]).getRequiredPersistentEntity<P8>(),
        failsWith('P8.writerId: @OnDelete(OnDeleteAction.setNull) needs a '),
      );
      final entity = contextOf([
        p(nullable: true),
        writer(),
      ]).getRequiredPersistentEntity<P8>();
      expect(entity.property('writerId')!.onDelete, OnDeleteAction.setNull);
    });

    test('@OnDelete on something that is no reference', () {
      final p = describe<P9>('P9', P9.new, [
        col(
          'count',
          _int,
          annotations: const [OnDelete(OnDeleteAction.cascade)],
        ),
      ]);
      expect(
        () => contextOf([p]).getRequiredPersistentEntity<P9>(),
        failsWith('P9.count: @OnDelete applies to a reference only'),
      );
    });
  });

  group('unique keys', () {
    EntityIntrospection<P1> post(
      List<Object> classAnnotations, {
      List<Object> titleAnnotations = const [],
    }) => describe<P1>(
      'P1',
      P1.new,
      [
        col('id', _intN, annotations: const [Id()]),
        col('title', _string, annotations: titleAnnotations),
        col('writerId', _int, annotations: const [Column('w_id')]),
      ],
      annotations: [const Table('posts'), ...classAnnotations],
    );

    PersistentEntity<P1> entity(
      List<Object> classAnnotations, {
      List<Object> titleAnnotations = const [],
    }) => contextOf([
      post(classAnnotations, titleAnnotations: titleAnnotations),
    ]).getRequiredPersistentEntity<P1>();

    test('a @Unique property is a constraint named after the column', () {
      final e = entity(const [], titleAnnotations: const [Unique()]);
      expect(e.uniqueConstraints, hasLength(1));
      expect(e.uniqueConstraints.single.name, 'uq_posts_title');
      expect(e.uniqueConstraints.single.columnNames, ['title']);
      expect(e.property('title')!.isUnique, isTrue);
    });

    test('a @UniqueConstraint names properties, the columns follow', () {
      final e = entity(const [
        UniqueConstraint(['writerId', 'title']),
        UniqueConstraint(['title'], name: 'uq_title_only'),
      ]);
      expect(e.uniqueConstraints.map((c) => c.name), [
        'uq_posts_w_id_title',
        'uq_title_only',
      ]);
      expect(e.uniqueConstraints.first.columnNames, ['w_id', 'title']);
    });

    test('an unknown property is refused, naming the ones there are', () {
      expect(
        () => entity(const [
          UniqueConstraint(['title', 'nope']),
        ]),
        failsWith(
          "P1: @UniqueConstraint names the property 'nope', which is not a "
          'stored property of P1 (the stored properties: id, title, '
          'writerId)',
        ),
      );
    });

    test('an empty list, a property twice and a name twice are refused', () {
      expect(
        () => entity(const [UniqueConstraint([])]),
        failsWith('needs at least one property'),
      );
      expect(
        () => entity(const [
          UniqueConstraint(['title', 'title']),
        ]),
        failsWith("names the property 'title' twice"),
      );
      expect(
        () => entity(
          const [
            UniqueConstraint(['writerId'], name: 'uq_posts_title'),
          ],
          titleAnnotations: const [Unique()],
        ),
        failsWith("two unique constraints named 'uq_posts_title'"),
      );
    });

    test('a mapped collection cannot be unique', () {
      final p = describe<P2>('P2', P2.new, [
        col(
          'children',
          const ListType<Child>(ClassType<Child>()),
          annotations: const [MappedCollection(), Unique()],
        ),
      ]);
      final c = describe<Child>('Child', Child.new, [
        col('x', _stringN),
      ]);
      expect(
        () => contextOf([p, c]).getRequiredPersistentEntity<P2>(),
        failsWith('P2.children: a @MappedCollection cannot be @Unique'),
      );
    });
  });
}
