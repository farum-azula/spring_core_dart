// Entities and their BeanIntrospections written by hand, as the generator
// writes them for `@Table` classes (see any `*.spring.dart`): one
// BeanProperty per field, with its annotations and TypeInfo, and the
// constructor called with Function.apply.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

enum Genre { fiction, science }

class Author {}

BeanProperty<T> prop<T extends Object>(
  String name,
  Type type,
  TypeInfo<Object?> info,
  Object? Function(T) get, {
  void Function(T, Object?)? set,
  List<Object> annotations = const [],
}) => BeanProperty<T>(
  name,
  type: type,
  typeInfo: info,
  nullable: info.nullable,
  get: get,
  set: set,
  annotations: annotations,
);

BeanParameter param(
  String name,
  TypeInfo<Object?> info, {
  bool named = false,
  bool isRequired = false,
}) => BeanParameter(
  name,
  type: info,
  symbol: named ? Symbol(name) : null,
  isRequired: isRequired,
);

// ---------------------------------------------------------------- Book

@Table('books')
class Book {
  Book({
    required this.title,
    this.id,
    this.year,
    this.genre,
    this.price = 0,
    this.available = false,
    this.author,
    this.version = 0,
    this.createdAt,
    this.modifiedAt,
    this.createdBy,
    this.modifiedBy,
    this.note,
  });

  @Id()
  int? id;
  String title;
  int? year;
  Genre? genre;
  double price;
  bool available;
  @Column('writer_id')
  AggregateReference<Author, int>? author;
  @Version()
  int version;
  @CreatedDate()
  DateTime? createdAt;
  @LastModifiedDate()
  DateTime? modifiedAt;
  @CreatedBy()
  String? createdBy;
  @LastModifiedBy()
  String? modifiedBy;
  @Transient()
  String? note;
}

const _int = ClassType<int>();
const _intN = ClassType<int>(nullable: true);
const _string = ClassType<String>();
const _stringN = ClassType<String>(nullable: true);
const _date = ClassType<DateTime>(nullable: true);
const _genre = EnumType<Genre>(Genre.values, nullable: true);
const _authorRef = GenericType<AggregateReference<Author, int>>([
  ClassType<Author>(),
  ClassType<int>(),
], nullable: true);

BeanIntrospection<Book> bookIntrospection() => BeanIntrospection<Book>(
  className: 'Book',
  annotations: const [Table('books')],
  properties: [
    prop<Book>(
      'id',
      int,
      _intN,
      (b) => b.id,
      set: (b, v) => b.id = v as int?,
      annotations: const [Id()],
    ),
    prop<Book>(
      'title',
      String,
      _string,
      (b) => b.title,
      set: (b, v) => b.title = v! as String,
    ),
    prop<Book>(
      'year',
      int,
      _intN,
      (b) => b.year,
      set: (b, v) => b.year = v as int?,
    ),
    prop<Book>(
      'genre',
      Genre,
      _genre,
      (b) => b.genre,
      set: (b, v) => b.genre = v as Genre?,
    ),
    prop<Book>(
      'price',
      double,
      const ClassType<double>(),
      (b) => b.price,
      set: (b, v) => b.price = v! as double,
    ),
    prop<Book>(
      'available',
      bool,
      const ClassType<bool>(),
      (b) => b.available,
      set: (b, v) => b.available = v! as bool,
    ),
    prop<Book>(
      'author',
      AggregateReference<Author, int>,
      _authorRef,
      (b) => b.author,
      set: (b, v) => b.author = v as AggregateReference<Author, int>?,
      annotations: const [Column('writer_id')],
    ),
    prop<Book>(
      'version',
      int,
      _int,
      (b) => b.version,
      set: (b, v) => b.version = v! as int,
      annotations: const [Version()],
    ),
    prop<Book>(
      'createdAt',
      DateTime,
      _date,
      (b) => b.createdAt,
      set: (b, v) => b.createdAt = v as DateTime?,
      annotations: const [CreatedDate()],
    ),
    prop<Book>(
      'modifiedAt',
      DateTime,
      _date,
      (b) => b.modifiedAt,
      set: (b, v) => b.modifiedAt = v as DateTime?,
      annotations: const [LastModifiedDate()],
    ),
    prop<Book>(
      'createdBy',
      String,
      _stringN,
      (b) => b.createdBy,
      set: (b, v) => b.createdBy = v as String?,
      annotations: const [CreatedBy()],
    ),
    prop<Book>(
      'modifiedBy',
      String,
      _stringN,
      (b) => b.modifiedBy,
      set: (b, v) => b.modifiedBy = v as String?,
      annotations: const [LastModifiedBy()],
    ),
    prop<Book>(
      'note',
      String,
      _stringN,
      (b) => b.note,
      set: (b, v) => b.note = v as String?,
      annotations: const [Transient()],
    ),
  ],
  constructor: BeanConstructor<Book>(
    parameters: [
      param('id', _intN, named: true),
      param('title', _string, named: true, isRequired: true),
      param('year', _intN, named: true),
      param('genre', _genre, named: true),
      param('price', const ClassType<double>(), named: true),
      param('available', const ClassType<bool>(), named: true),
      param('author', _authorRef, named: true),
      param('version', _int, named: true),
      param('createdAt', _date, named: true),
      param('modifiedAt', _date, named: true),
      param('createdBy', _stringN, named: true),
      param('modifiedBy', _stringN, named: true),
      param('note', _stringN, named: true),
    ],
    create: (positional, named) =>
        Function.apply(Book.new, positional, named) as Book,
  ),
);

// ---------------------------------------------------------- the children

@Table()
class Item {
  Item({required this.sku, this.id, this.qty = 1});

  @Id()
  int? id;
  String sku;
  int qty;
}

@Table('tags')
class Tag {
  Tag(this.label);

  String label;
}

@Table()
class Note {
  Note({required this.text});

  String text;
}

BeanIntrospection<Item> itemIntrospection() => BeanIntrospection<Item>(
  className: 'Item',
  annotations: const [Table()],
  properties: [
    prop<Item>(
      'id',
      int,
      _intN,
      (i) => i.id,
      set: (i, v) => i.id = v as int?,
      annotations: const [Id()],
    ),
    prop<Item>(
      'sku',
      String,
      _string,
      (i) => i.sku,
      set: (i, v) => i.sku = v! as String,
    ),
    prop<Item>(
      'qty',
      int,
      _int,
      (i) => i.qty,
      set: (i, v) => i.qty = v! as int,
    ),
  ],
  constructor: BeanConstructor<Item>(
    parameters: [
      param('id', _intN, named: true),
      param('sku', _string, named: true, isRequired: true),
      param('qty', _int, named: true),
    ],
    create: (positional, named) =>
        Function.apply(Item.new, positional, named) as Item,
  ),
);

BeanIntrospection<Tag> tagIntrospection() => BeanIntrospection<Tag>(
  className: 'Tag',
  annotations: const [Table('tags')],
  properties: [
    prop<Tag>(
      'label',
      String,
      _string,
      (t) => t.label,
      set: (t, v) => t.label = v! as String,
    ),
  ],
  constructor: BeanConstructor<Tag>(
    parameters: [param('label', _string, isRequired: true)],
    create: (positional, named) =>
        Function.apply(Tag.new, positional, named) as Tag,
  ),
);

BeanIntrospection<Note> noteIntrospection() => BeanIntrospection<Note>(
  className: 'Note',
  annotations: const [Table()],
  properties: [
    prop<Note>(
      'text',
      String,
      _string,
      (n) => n.text,
      set: (n, v) => n.text = v! as String,
    ),
  ],
  constructor: BeanConstructor<Note>(
    parameters: [param('text', _string, named: true, isRequired: true)],
    create: (positional, named) =>
        Function.apply(Note.new, positional, named) as Note,
  ),
);

// ------------------------------------------------------------ OrderLine

@Table()
class OrderLine {
  OrderLine({
    required this.items,
    required this.tags,
    required this.notes,
    this.id,
    this.extras,
  });

  @Id()
  int? id;
  @MappedCollection(idColumn: 'line_ref', keyColumn: 'position')
  List<Item> items;
  @MappedCollection()
  Set<Tag> tags;
  @MappedCollection()
  Map<String, Note> notes;
  @MappedCollection()
  List<Item>? extras;
}

BeanIntrospection<OrderLine> orderLineIntrospection() =>
    BeanIntrospection<OrderLine>(
      className: 'OrderLine',
      annotations: const [Table()],
      properties: [
        prop<OrderLine>(
          'id',
          int,
          _intN,
          (o) => o.id,
          set: (o, v) => o.id = v as int?,
          annotations: const [Id()],
        ),
        prop<OrderLine>(
          'items',
          List<Item>,
          const ListType<Item>(ClassType<Item>()),
          (o) => o.items,
          set: (o, v) => o.items = v! as List<Item>,
          annotations: const [
            MappedCollection(idColumn: 'line_ref', keyColumn: 'position'),
          ],
        ),
        prop<OrderLine>(
          'tags',
          Set<Tag>,
          const SetType<Tag>(ClassType<Tag>()),
          (o) => o.tags,
          set: (o, v) => o.tags = v! as Set<Tag>,
          annotations: const [MappedCollection()],
        ),
        prop<OrderLine>(
          'notes',
          Map<String, Note>,
          const MapType<String, Note>(ClassType<String>(), ClassType<Note>()),
          (o) => o.notes,
          set: (o, v) => o.notes = v! as Map<String, Note>,
          annotations: const [MappedCollection()],
        ),
        prop<OrderLine>(
          'extras',
          List<Item>,
          const ListType<Item>(ClassType<Item>(), nullable: true),
          (o) => o.extras,
          set: (o, v) => o.extras = v as List<Item>?,
          annotations: const [MappedCollection()],
        ),
      ],
      constructor: BeanConstructor<OrderLine>(
        parameters: [
          param('id', _intN, named: true),
          param(
            'items',
            const ListType<Item>(ClassType<Item>()),
            named: true,
            isRequired: true,
          ),
          param(
            'tags',
            const SetType<Tag>(ClassType<Tag>()),
            named: true,
            isRequired: true,
          ),
          param(
            'notes',
            const MapType<String, Note>(ClassType<String>(), ClassType<Note>()),
            named: true,
            isRequired: true,
          ),
          param(
            'extras',
            const ListType<Item>(ClassType<Item>(), nullable: true),
            named: true,
          ),
        ],
        create: (positional, named) =>
            Function.apply(OrderLine.new, positional, named) as OrderLine,
      ),
    );

// -------------------------------------------- an entity with final fields

@Table()
class Reading {
  Reading(this.id, this.text, [this.score, this.version = 0, this.created]);

  @Id()
  final int? id;
  final String text;
  final double? score;
  @Version()
  final int version;
  @CreatedDate()
  final DateTime? created;
  final String kind = 'reading';
}

Reading makeReading(
  int? id,
  String text, {
  double? score,
  int version = 0,
  DateTime? created,
}) => Reading(id, text, score, version, created);

BeanIntrospection<Reading> readingIntrospection() => BeanIntrospection<Reading>(
  className: 'Reading',
  annotations: const [Table()],
  properties: [
    prop<Reading>(
      'id',
      int,
      _intN,
      (r) => r.id,
      annotations: const [Id()],
    ),
    prop<Reading>('text', String, _string, (r) => r.text),
    prop<Reading>(
      'score',
      double,
      const ClassType<double>(nullable: true),
      (r) => r.score,
    ),
    prop<Reading>(
      'version',
      int,
      _int,
      (r) => r.version,
      annotations: const [Version()],
    ),
    prop<Reading>(
      'created',
      DateTime,
      _date,
      (r) => r.created,
      annotations: const [CreatedDate()],
    ),
    prop<Reading>('kind', String, _string, (r) => r.kind),
  ],
  constructor: BeanConstructor<Reading>(
    parameters: [
      param('id', _intN, isRequired: true),
      param('text', _string, isRequired: true),
      param('score', const ClassType<double>(nullable: true)),
      param('version', _int),
      param('created', _date),
    ],
    create: (positional, named) =>
        Function.apply(Reading.new, positional, named) as Reading,
  ),
);

// -------------------------------------------------- wrong mappings

class TwoIds {
  int? a;
  int? b;
}

class TwoVersions {
  int a = 0;
  int b = 0;
}

class BadVersion {
  String v = '';
}

class BadDate {
  String created = '';
}

class BadAudit {
  DateTime? d;
}

class VersionedChild {
  int v = 0;
}

class WithVersionedChild {
  List<VersionedChild> children = [];
}

class PlainChild {
  int x = 0;
}

class WithPlainChild {
  List<PlainChild> children = [];
}

class Unknown {}

class WithUnknownChild {
  List<Unknown> children = [];
}

class Loop {
  List<Loop> next = [];
}

BeanIntrospection<TwoIds> twoIdsIntrospection() => BeanIntrospection<TwoIds>(
  className: 'TwoIds',
  properties: [
    prop<TwoIds>(
      'a',
      int,
      _intN,
      (o) => o.a,
      set: (o, v) => o.a = v as int?,
      annotations: const [Id()],
    ),
    prop<TwoIds>(
      'b',
      int,
      _intN,
      (o) => o.b,
      set: (o, v) => o.b = v as int?,
      annotations: const [Id()],
    ),
  ],
);

BeanIntrospection<TwoVersions> twoVersionsIntrospection() =>
    BeanIntrospection<TwoVersions>(
      className: 'TwoVersions',
      properties: [
        for (final n in ['a', 'b'])
          prop<TwoVersions>(
            n,
            int,
            _int,
            (o) => n == 'a' ? o.a : o.b,
            set: (o, v) => n == 'a' ? o.a = v! as int : o.b = v! as int,
            annotations: const [Version()],
          ),
      ],
    );

BeanIntrospection<BadVersion> badVersionIntrospection() =>
    BeanIntrospection<BadVersion>(
      className: 'BadVersion',
      properties: [
        prop<BadVersion>(
          'v',
          String,
          _string,
          (o) => o.v,
          set: (o, v) => o.v = v! as String,
          annotations: const [Version()],
        ),
      ],
    );

BeanIntrospection<BadDate> badDateIntrospection() => BeanIntrospection<BadDate>(
  className: 'BadDate',
  properties: [
    prop<BadDate>(
      'created',
      String,
      _string,
      (o) => o.created,
      set: (o, v) => o.created = v! as String,
      annotations: const [CreatedDate()],
    ),
  ],
);

BeanIntrospection<BadAudit> badAuditIntrospection() =>
    BeanIntrospection<BadAudit>(
      className: 'BadAudit',
      properties: [
        prop<BadAudit>(
          'd',
          DateTime,
          _date,
          (o) => o.d,
          set: (o, v) => o.d = v as DateTime?,
          annotations: const [CreatedDate(), LastModifiedDate()],
        ),
      ],
    );

BeanIntrospection<VersionedChild> versionedChildIntrospection() =>
    BeanIntrospection<VersionedChild>(
      className: 'VersionedChild',
      annotations: const [Table()],
      properties: [
        prop<VersionedChild>(
          'v',
          int,
          _int,
          (o) => o.v,
          set: (o, v) => o.v = v! as int,
          annotations: const [Version()],
        ),
      ],
    );

BeanIntrospection<WithVersionedChild> withVersionedChildIntrospection() =>
    _holder<WithVersionedChild, VersionedChild>(
      'WithVersionedChild',
      (o) => o.children,
      (o, v) => o.children = v,
    );

BeanIntrospection<PlainChild> plainChildIntrospection() =>
    BeanIntrospection<PlainChild>(
      className: 'PlainChild',
      properties: [
        prop<PlainChild>(
          'x',
          int,
          _int,
          (o) => o.x,
          set: (o, v) => o.x = v! as int,
        ),
      ],
    );

BeanIntrospection<WithPlainChild> withPlainChildIntrospection() =>
    _holder<WithPlainChild, PlainChild>(
      'WithPlainChild',
      (o) => o.children,
      (o, v) => o.children = v,
    );

BeanIntrospection<WithUnknownChild> withUnknownChildIntrospection() =>
    _holder<WithUnknownChild, Unknown>(
      'WithUnknownChild',
      (o) => o.children,
      (o, v) => o.children = v,
    );

BeanIntrospection<Loop> loopIntrospection() => BeanIntrospection<Loop>(
  className: 'Loop',
  annotations: const [Table()],
  properties: [
    prop<Loop>(
      'next',
      List<Loop>,
      const ListType<Loop>(ClassType<Loop>()),
      (o) => o.next,
      set: (o, v) => o.next = v! as List<Loop>,
      annotations: const [MappedCollection()],
    ),
  ],
);

BeanIntrospection<H> _holder<H extends Object, C extends Object>(
  String name,
  List<C> Function(H) get,
  void Function(H, List<C>) set,
) => BeanIntrospection<H>(
  className: name,
  annotations: const [Table()],
  properties: [
    prop<H>(
      'children',
      List<C>,
      ListType<C>(ClassType<C>()),
      get,
      set: (o, v) => set(o, v! as List<C>),
      annotations: const [MappedCollection()],
    ),
  ],
);

/// A context over every description above.
RelationalMappingContext testContext({NamingStrategy? naming}) {
  final introspector = BeanIntrospector(
    introspections: [
      bookIntrospection(),
      itemIntrospection(),
      tagIntrospection(),
      noteIntrospection(),
      orderLineIntrospection(),
      readingIntrospection(),
      versionedChildIntrospection(),
      plainChildIntrospection(),
      loopIntrospection(),
    ],
  );
  return RelationalMappingContext(
    introspector: introspector,
    namingStrategy: naming ?? const NamingStrategy(),
  );
}
