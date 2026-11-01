// Entities and their EntityIntrospections written by hand, as the generator
// writes them for `@Table` classes (see any `*.spring.dart`): one
// EntityProperty per field, with its annotations and TypeInfo, and `read`,
// `create` and `write` functions.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

enum Genre { fiction, science }

/// A class nobody described.
class Unmapped {}

/// An aggregate the books reference.
@Table('authors')
class Author {
  Author({this.id, this.name = ''});

  @Id()
  int? id;

  String name;
}

EntityIntrospection<Author> authorIntrospection() =>
    EntityIntrospection<Author>(
      'Author',
      const [
        EntityProperty(
          'id',
          _intN,
          annotations: [Id()],
          parameter: true,
          writable: true,
        ),
        EntityProperty(
          'name',
          _string,
          parameter: true,
          writable: true,
          hasDefaultValue: true,
          defaultValue: '',
        ),
      ],
      annotations: const [Table('authors')],
      get: (a, i) => switch (i) {
        0 => a.id,
        _ => a.name,
      },
      create: (v) => Author(id: v[0] as int?, name: v[1]! as String),
      write: (a, i, v) => switch (i) {
        0 => a.id = v as int?,
        1 => a.name = v! as String,
        _ => null,
      },
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

EntityIntrospection<Book> bookIntrospection() => EntityIntrospection<Book>(
  'Book',
  const [
    EntityProperty(
      'id',
      _intN,
      annotations: [Id()],
      parameter: true,
      writable: true,
    ),
    EntityProperty('title', _string, parameter: true, writable: true),
    EntityProperty('year', _intN, parameter: true, writable: true),
    EntityProperty('genre', _genre, parameter: true, writable: true),
    // The constant is the int `0` of `this.price = 0`: the converter widens it.
    EntityProperty(
      'price',
      ClassType<double>(),
      parameter: true,
      writable: true,
      hasDefaultValue: true,
      defaultValue: 0,
    ),
    EntityProperty(
      'available',
      ClassType<bool>(),
      parameter: true,
      writable: true,
      hasDefaultValue: true,
      defaultValue: false,
    ),
    EntityProperty(
      'author',
      _authorRef,
      annotations: [Column('writer_id')],
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'version',
      _int,
      annotations: [Version()],
      parameter: true,
      writable: true,
      hasDefaultValue: true,
      defaultValue: 0,
    ),
    EntityProperty(
      'createdAt',
      _date,
      annotations: [CreatedDate()],
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'modifiedAt',
      _date,
      annotations: [LastModifiedDate()],
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'createdBy',
      _stringN,
      annotations: [CreatedBy()],
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'modifiedBy',
      _stringN,
      annotations: [LastModifiedBy()],
      parameter: true,
      writable: true,
    ),
    EntityProperty(
      'note',
      _stringN,
      annotations: [Transient()],
      parameter: true,
      writable: true,
    ),
  ],
  annotations: const [Table('books')],
  get: (b, i) => switch (i) {
    0 => b.id,
    1 => b.title,
    2 => b.year,
    3 => b.genre,
    4 => b.price,
    5 => b.available,
    6 => b.author,
    7 => b.version,
    8 => b.createdAt,
    9 => b.modifiedAt,
    10 => b.createdBy,
    11 => b.modifiedBy,
    _ => b.note,
  },
  create: (v) => Book(
    id: v[0] as int?,
    title: v[1]! as String,
    year: v[2] as int?,
    genre: v[3] as Genre?,
    price: v[4]! as double,
    available: v[5]! as bool,
    author: v[6] as AggregateReference<Author, int>?,
    version: v[7]! as int,
    createdAt: v[8] as DateTime?,
    modifiedAt: v[9] as DateTime?,
    createdBy: v[10] as String?,
    modifiedBy: v[11] as String?,
    note: v[12] as String?,
  ),
  write: (b, i, v) => switch (i) {
    0 => b.id = v as int?,
    1 => b.title = v! as String,
    2 => b.year = v as int?,
    3 => b.genre = v as Genre?,
    4 => b.price = v! as double,
    5 => b.available = v! as bool,
    6 => b.author = v as AggregateReference<Author, int>?,
    7 => b.version = v! as int,
    8 => b.createdAt = v as DateTime?,
    9 => b.modifiedAt = v as DateTime?,
    10 => b.createdBy = v as String?,
    11 => b.modifiedBy = v as String?,
    12 => b.note = v as String?,
    _ => null,
  },
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

EntityIntrospection<Item> itemIntrospection() => EntityIntrospection<Item>(
  'Item',
  const [
    EntityProperty(
      'id',
      _intN,
      annotations: [Id()],
      parameter: true,
      writable: true,
    ),
    EntityProperty('sku', _string, parameter: true, writable: true),
    EntityProperty(
      'qty',
      _int,
      parameter: true,
      writable: true,
      hasDefaultValue: true,
      defaultValue: 1,
    ),
  ],
  annotations: const [Table()],
  get: (item, i) => switch (i) {
    0 => item.id,
    1 => item.sku,
    _ => item.qty,
  },
  create: (v) =>
      Item(id: v[0] as int?, sku: v[1]! as String, qty: v[2]! as int),
  write: (i, n, v) => switch (n) {
    0 => i.id = v as int?,
    1 => i.sku = v! as String,
    2 => i.qty = v! as int,
    _ => null,
  },
);

EntityIntrospection<Tag> tagIntrospection() => EntityIntrospection<Tag>(
  'Tag',
  const [EntityProperty('label', _string, parameter: true, writable: true)],
  annotations: const [Table('tags')],
  get: (t, _) => t.label,
  create: (v) => Tag(v[0]! as String),
  write: (t, i, v) => t.label = v! as String,
);

EntityIntrospection<Note> noteIntrospection() => EntityIntrospection<Note>(
  'Note',
  const [EntityProperty('text', _string, parameter: true, writable: true)],
  annotations: const [Table()],
  get: (n, _) => n.text,
  create: (v) => Note(text: v[0]! as String),
  write: (n, i, v) => n.text = v! as String,
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

EntityIntrospection<OrderLine> orderLineIntrospection() =>
    EntityIntrospection<OrderLine>(
      'OrderLine',
      const [
        EntityProperty(
          'id',
          _intN,
          annotations: [Id()],
          parameter: true,
          writable: true,
        ),
        EntityProperty(
          'items',
          ListType<Item>(ClassType<Item>()),
          annotations: [
            MappedCollection(idColumn: 'line_ref', keyColumn: 'position'),
          ],
          parameter: true,
          writable: true,
        ),
        EntityProperty(
          'tags',
          SetType<Tag>(ClassType<Tag>()),
          annotations: [MappedCollection()],
          parameter: true,
          writable: true,
        ),
        EntityProperty(
          'notes',
          MapType<String, Note>(ClassType<String>(), ClassType<Note>()),
          annotations: [MappedCollection()],
          parameter: true,
          writable: true,
        ),
        EntityProperty(
          'extras',
          ListType<Item>(ClassType<Item>(), nullable: true),
          annotations: [MappedCollection()],
          parameter: true,
          writable: true,
        ),
      ],
      annotations: const [Table()],
      get: (o, i) => switch (i) {
        0 => o.id,
        1 => o.items,
        2 => o.tags,
        3 => o.notes,
        _ => o.extras,
      },
      create: (v) => OrderLine(
        id: v[0] as int?,
        items: v[1]! as List<Item>,
        tags: v[2]! as Set<Tag>,
        notes: v[3]! as Map<String, Note>,
        extras: v[4] as List<Item>?,
      ),
      write: (o, i, v) => switch (i) {
        0 => o.id = v as int?,
        1 => o.items = v! as List<Item>,
        2 => o.tags = v! as Set<Tag>,
        3 => o.notes = v! as Map<String, Note>,
        4 => o.extras = v as List<Item>?,
        _ => null,
      },
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

EntityIntrospection<Reading> readingIntrospection() =>
    EntityIntrospection<Reading>(
      'Reading',
      const [
        EntityProperty('id', _intN, annotations: [Id()], parameter: true),
        EntityProperty('text', _string, parameter: true),
        EntityProperty(
          'score',
          ClassType<double>(nullable: true),
          parameter: true,
        ),
        EntityProperty(
          'version',
          _int,
          annotations: [Version()],
          parameter: true,
          hasDefaultValue: true,
          defaultValue: 0,
        ),
        EntityProperty(
          'created',
          _date,
          annotations: [CreatedDate()],
          parameter: true,
        ),
        // Final, with an initializer and no parameter: never stored.
        EntityProperty(
          'kind',
          _string,
          hasDefaultValue: true,
          defaultValue: 'reading',
        ),
      ],
      annotations: const [Table()],
      get: (r, i) => switch (i) {
        0 => r.id,
        1 => r.text,
        2 => r.score,
        3 => r.version,
        4 => r.created,
        _ => r.kind,
      },
      create: (v) => Reading(
        v[0] as int?,
        v[1]! as String,
        v[2] as double?,
        v[3]! as int,
        v[4] as DateTime?,
      ),
    );

// --------- final fields the constructor takes; settable ones it does not

@Table()
class Gauge {
  Gauge(this.id, this.name);

  @Id()
  final int? id;
  final String name;

  /// Settable, not a constructor parameter, with an initializer.
  int level = 5;

  /// Settable, not a constructor parameter, nullable.
  String? label;

  /// Not stored, settable: a copy must carry it over.
  @Transient()
  String? scratch;
}

EntityIntrospection<Gauge> gaugeIntrospection() => EntityIntrospection<Gauge>(
  'Gauge',
  const [
    EntityProperty('id', _intN, annotations: [Id()], parameter: true),
    EntityProperty('name', _string, parameter: true),
    EntityProperty(
      'level',
      _int,
      writable: true,
      hasDefaultValue: true,
      defaultValue: 5,
    ),
    EntityProperty('label', _stringN, writable: true),
    EntityProperty(
      'scratch',
      _stringN,
      annotations: [Transient()],
      writable: true,
    ),
  ],
  annotations: const [Table()],
  get: (g, i) => switch (i) {
    0 => g.id,
    1 => g.name,
    2 => g.level,
    3 => g.label,
    _ => g.scratch,
  },
  create: (v) => Gauge(v[0] as int?, v[1]! as String),
  write: (g, i, v) => switch (i) {
    2 => g.level = v! as int,
    3 => g.label = v as String?,
    4 => g.scratch = v as String?,
    _ => null,
  },
);

/// A `late` field that is not stored and that nobody set: reading it
/// throws, so a save must never read it.
@Table()
class Draft {
  Draft({required this.title, this.id});

  @Id()
  int? id;
  String title;

  @Transient()
  late String display;
}

EntityIntrospection<Draft> draftIntrospection() => EntityIntrospection<Draft>(
  'Draft',
  const [
    EntityProperty(
      'id',
      _intN,
      annotations: [Id()],
      parameter: true,
      writable: true,
    ),
    EntityProperty('title', _string, parameter: true, writable: true),
    EntityProperty(
      'display',
      _string,
      annotations: [Transient()],
      writable: true,
    ),
  ],
  annotations: const [Table()],
  get: (d, i) => switch (i) {
    0 => d.id,
    1 => d.title,
    _ => d.display,
  },
  create: (v) => Draft(title: v[1]! as String, id: v[0] as int?),
  write: (d, i, v) => switch (i) {
    0 => d.id = v as int?,
    1 => d.title = v! as String,
    _ => d.display = v! as String,
  },
);

/// A required constructor parameter that is not stored.
@Table()
class Locked {
  Locked(this.id, this.pin);

  @Id()
  int? id;
  @Transient()
  final String pin;
}

EntityIntrospection<Locked> lockedIntrospection() =>
    EntityIntrospection<Locked>(
      'Locked',
      const [
        EntityProperty(
          'id',
          _intN,
          annotations: [Id()],
          parameter: true,
          writable: true,
        ),
        EntityProperty(
          'pin',
          _string,
          annotations: [Transient()],
          parameter: true,
        ),
      ],
      annotations: const [Table()],
      get: (l, i) => switch (i) {
        0 => l.id,
        _ => l.pin,
      },
      create: (v) => Locked(v[0] as int?, v[1]! as String),
      write: (l, i, v) => l.id = v as int?,
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

EntityIntrospection<TwoIds> twoIdsIntrospection() =>
    EntityIntrospection<TwoIds>(
      'TwoIds',
      const [
        EntityProperty('a', _intN, annotations: [Id()], writable: true),
        EntityProperty('b', _intN, annotations: [Id()], writable: true),
      ],
      get: (o, i) => switch (i) {
        0 => o.a,
        _ => o.b,
      },
      create: (v) => TwoIds(),
      write: (o, i, v) => i == 0 ? o.a = v as int? : o.b = v as int?,
    );

EntityIntrospection<TwoVersions> twoVersionsIntrospection() =>
    EntityIntrospection<TwoVersions>(
      'TwoVersions',
      const [
        EntityProperty('a', _int, annotations: [Version()], writable: true),
        EntityProperty('b', _int, annotations: [Version()], writable: true),
      ],
      get: (o, i) => switch (i) {
        0 => o.a,
        _ => o.b,
      },
      create: (v) => TwoVersions(),
      write: (o, i, v) => i == 0 ? o.a = v! as int : o.b = v! as int,
    );

EntityIntrospection<BadVersion> badVersionIntrospection() =>
    EntityIntrospection<BadVersion>(
      'BadVersion',
      const [
        EntityProperty('v', _string, annotations: [Version()], writable: true),
      ],
      get: (o, _) => o.v,
      create: (v) => BadVersion(),
      write: (o, i, v) => o.v = v! as String,
    );

EntityIntrospection<BadDate> badDateIntrospection() =>
    EntityIntrospection<BadDate>(
      'BadDate',
      const [
        EntityProperty(
          'created',
          _string,
          annotations: [CreatedDate()],
          writable: true,
        ),
      ],
      get: (o, _) => o.created,
      create: (v) => BadDate(),
      write: (o, i, v) => o.created = v! as String,
    );

EntityIntrospection<BadAudit> badAuditIntrospection() =>
    EntityIntrospection<BadAudit>(
      'BadAudit',
      const [
        EntityProperty(
          'd',
          _date,
          annotations: [CreatedDate(), LastModifiedDate()],
          writable: true,
        ),
      ],
      get: (o, _) => o.d,
      create: (v) => BadAudit(),
      write: (o, i, v) => o.d = v as DateTime?,
    );

EntityIntrospection<VersionedChild> versionedChildIntrospection() =>
    EntityIntrospection<VersionedChild>(
      'VersionedChild',
      const [
        EntityProperty('v', _int, annotations: [Version()], writable: true),
      ],
      annotations: const [Table()],
      get: (o, _) => o.v,
      create: (v) => VersionedChild(),
      write: (o, i, v) => o.v = v! as int,
    );

EntityIntrospection<WithVersionedChild> withVersionedChildIntrospection() =>
    _holder<WithVersionedChild, VersionedChild>(
      'WithVersionedChild',
      WithVersionedChild.new,
      (o) => o.children,
      (o, v) => o.children = v,
    );

EntityIntrospection<PlainChild> plainChildIntrospection() =>
    EntityIntrospection<PlainChild>(
      'PlainChild',
      const [EntityProperty('x', _int, writable: true)],
      get: (o, _) => o.x,
      create: (v) => PlainChild(),
      write: (o, i, v) => o.x = v! as int,
    );

EntityIntrospection<WithPlainChild> withPlainChildIntrospection() =>
    _holder<WithPlainChild, PlainChild>(
      'WithPlainChild',
      WithPlainChild.new,
      (o) => o.children,
      (o, v) => o.children = v,
    );

EntityIntrospection<WithUnknownChild> withUnknownChildIntrospection() =>
    _holder<WithUnknownChild, Unknown>(
      'WithUnknownChild',
      WithUnknownChild.new,
      (o) => o.children,
      (o, v) => o.children = v,
    );

EntityIntrospection<Loop> loopIntrospection() => EntityIntrospection<Loop>(
  'Loop',
  const [
    EntityProperty(
      'next',
      ListType<Loop>(ClassType<Loop>()),
      annotations: [MappedCollection()],
      writable: true,
    ),
  ],
  annotations: const [Table()],
  get: (o, _) => o.next,
  create: (v) => Loop(),
  write: (o, i, v) => o.next = v! as List<Loop>,
);

// A @Table class whose only property is a list of children of type C.
EntityIntrospection<H> _holder<H extends Object, C extends Object>(
  String name,
  H Function() create,
  List<C> Function(H) get,
  void Function(H, List<C>) set,
) => EntityIntrospection<H>(
  name,
  [
    EntityProperty(
      'children',
      ListType<C>(ClassType<C>()),
      annotations: const [MappedCollection()],
      writable: true,
    ),
  ],
  annotations: const [Table()],
  get: (o, _) => get(o),
  create: (v) => create(),
  write: (o, i, v) => set(o, v! as List<C>),
);

/// A context over every description above.
RelationalMappingContext testContext({NamingStrategy? naming}) =>
    RelationalMappingContext(
      introspections: [
        authorIntrospection(),
        bookIntrospection(),
        itemIntrospection(),
        tagIntrospection(),
        noteIntrospection(),
        orderLineIntrospection(),
        readingIntrospection(),
        gaugeIntrospection(),
        draftIntrospection(),
        lockedIntrospection(),
        versionedChildIntrospection(),
        plainChildIntrospection(),
        loopIntrospection(),
      ],
      namingStrategy: naming ?? const NamingStrategy(),
    );
