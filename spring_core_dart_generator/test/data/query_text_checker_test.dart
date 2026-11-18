// What the build checks in the SQL of a `@Query`: the placeholders, the
// parameters, and the tables and columns that are misspelled. These are
// plain unit tests of the text checks (no build); the same checks inside a
// build are in data_query_test.dart.
import 'package:spring_core_dart_generator/src/data_schema.dart';
import 'package:spring_core_dart_generator/src/did_you_mean.dart';
import 'package:spring_core_dart_generator/src/query_text_checker.dart';
import 'package:spring_core_dart_generator/src/sql_lexer.dart';
import 'package:test/test.dart';

const _entities = [
  EntityDescription(
    'Book',
    'package:pkg/model.dart',
    [
      EntityProperty('id', EntityPropertyKind.column),
      EntityProperty('title', EntityPropertyKind.column),
      EntityProperty('year', EntityPropertyKind.column),
      EntityProperty('authorId', EntityPropertyKind.column),
      EntityProperty('writtenBy', EntityPropertyKind.column, column: 'writer'),
      EntityProperty('cache', EntityPropertyKind.transient),
      EntityProperty(
        'chapters',
        EntityPropertyKind.collection,
        child: 'Chapter',
      ),
    ],
    table: 'books',
  ),
  EntityDescription(
    'Author',
    'package:pkg/model.dart',
    [
      EntityProperty('id', EntityPropertyKind.column),
      EntityProperty('name', EntityPropertyKind.column),
    ],
    table: 'authors',
  ),
  // No @Table: the table is the class name in snake case.
  EntityDescription('Publisher', 'package:pkg/model.dart', [
    EntityProperty('id', EntityPropertyKind.column),
  ]),
  EntityDescription(
    'Chapter',
    'package:pkg/model.dart',
    [EntityProperty('number', EntityPropertyKind.column)],
    table: 'chapters',
  ),
];

// The entities above, a table and a view of migrations.
DataSchema _schema({bool customNaming = false, String? migration}) {
  final schema = DataSchema();
  if (migration != null) {
    schema.apply(migration);
  }
  return schema..addEntities(_entities, customNaming: customNaming);
}

const _migration = '''
create table accounts (
  iban text primary key,
  owner text not null,
  balance integer
);
create view author_book_counts as
select a.id, a.name, count(b.id) as books
from authors a left join books b on b.author_id = a.id
group by a.id, a.name;
''';

List<String> _problems(
  String sql, {
  List<String> names = const ['year', 'title'],
  DataSchema? schema,
  String where = 'Books.query',
}) {
  final problems = <String>[];
  QueryTextChecker(
    schema ?? _schema(migration: _migration),
  ).check(sql, where: where, names: names, problem: problems.add);
  return problems;
}

Matcher _one(String text) => equals(['Books.query: $text']);

void main() {
  group('the lexer', () {
    List<String> kinds(String sql) => [
      for (final t in SqlLexer.tokenize(sql)) '${t.kind.name}:${t.value}',
    ];

    test(
      'leaves comments and white space out, and keeps quoted text apart',
      () {
        expect(
          kinds("select 'a -- b', \"x y\" -- one\n/* two */ from `t`"),
          [
            'word:select',
            "string:'a -- b'",
            'symbol:,',
            'quoted:x y',
            'word:from',
            'quoted:t',
          ],
        );
      },
    );

    test('reads parameters, expressions and placeholders', () {
      expect(
        kinds(
          r'a = :x and b = :{y z} and c = :#{#p.title} and d = ${n:1} '
          'and e = #{#entityName} and {Book.authorId} = ? and f::text',
        ),
        containsAllInOrder([
          'parameter:x',
          'parameter:y z',
          'expression:#p.title',
          'property:n:1',
          'elExpression:#entityName',
          'entity:Book',
          'question:?',
          'symbol:::',
        ]),
      );
      final entity = SqlLexer.tokenize('{Book.authorId}').single;
      expect((entity.value, entity.member), ('Book', 'authorId'));
      expect(kinds('a = :book.year'), [
        'word:a',
        'symbol:=',
        'parameter:book.year',
      ]);
    });

    test('a quote doubled inside, dollar quoting, an unclosed expression', () {
      expect(kinds("'it''s' \"a\"\"b\""), ["string:'it''s'", 'quoted:a"b']);
      expect(kinds(r'x $$ select ; $$ y'), [
        'word:x',
        r'string:$$ select ; $$',
        'word:y',
      ]);
      expect(kinds('a :#{#x'), ['word:a', 'unclosed::#{#x']);
      expect(kinds('a :{x'), ['word:a', startsWith('badParameter:')]);
    });
  });

  group('parameters and placeholders', () {
    test('a clean query has no problem', () {
      expect(
        _problems(
          'select * from books where year = :year and title = :title '
          'and id in (:ids)',
          names: ['year', 'title', 'ids'],
        ),
        isEmpty,
      );
    });

    test('a name that is no parameter of the method', () {
      expect(
        _problems('select * from books where year = :yeer'),
        _one(':yeer matches no parameter of the method (it has year, title)'),
      );
      expect(
        _problems('select * from books where year = :year', names: []),
        _one(':year matches no parameter of the method (it has none)'),
      );
      expect(
        _problems('select * from books where year = :book.year'),
        _one(
          ':book.year matches no parameter of the method (it has year, '
          'title) (to read a property write :#{#book.year})',
        ),
      );
    });

    test('a name is reported once', () {
      expect(
        _problems('select * from books where year = :a or year = :a'),
        hasLength(1),
      );
    });

    test('a plain ? marker', () {
      expect(
        _problems('select * from books where year = ? or year = ?'),
        _one(
          'the query has a plain ? marker: write :name and bind it by the '
          'name of a parameter of the method',
        ),
      );
    });

    test('#{...} outside a parameter, and an expression not closed', () {
      expect(
        _problems('select * from #{#tableName} where year = :year'),
        _one(
          '#{#tableName} is not allowed in the SQL text: only '
          '#{#entityName} is; to bind a value write :#{#tableName}',
        ),
      );
      expect(
        _problems('select * from #{#entityName} where year = :year'),
        isEmpty,
      );
      expect(
        _problems('select * from books where year = :#{#year'),
        _one('an expression is not closed: :#{#year'),
      );
    });

    test('a malformed :{name}', () {
      expect(_problems('select :{} '), hasLength(1));
      expect(_problems('select :{x'), hasLength(1));
      expect(_problems('select :{year}'), isEmpty);
    });

    test('expressions are counted in text order, in quotes they are text', () {
      final result = QueryTextChecker(_schema()).check(
        "select ':#{#no}' from books where a = :#{#year} and b = :#{[1]} "
        '-- :#{#c}',
        where: 'X.y',
        names: ['year'],
        problem: (_) {},
      );
      expect(result.expressions, ['#year', '[1]']);
    });

    test('quotes, comments and strings hide everything', () {
      expect(
        _problems(
          "select 'a ? :nope {Nowhere} #{#x}', \"?\" from books -- ? :no\n"
          "/* ? :no */ where title = 'bokks'",
        ),
        isEmpty,
      );
    });
  });

  group('entity placeholders', () {
    test('the table and the column of a property', () {
      final result = QueryTextChecker(_schema()).check(
        'select {Book.title} from {Book} b where b.{Book.authorId} = :year',
        where: 'X.y',
        names: ['year'],
        problem: fail,
      );
      expect(result.entities, {'Book'});
    });

    test('an unknown entity, with a suggestion', () {
      expect(
        _problems('select * from {Bok}'),
        _one(
          "{Bok}: no @Table class Bok in the application, did you mean 'Book'?",
        ),
      );
    });

    test('a name close to none may be an entity of another module', () {
      // Not a problem: the run time resolves it, or fails with a message
      // when the repository is created.
      final problems = <String>[];
      final result = QueryTextChecker(_schema()).check(
        'select {Zzzzzzzz.title} from {Zzzzzzzz} z '
        'join {Book} b on b.id = z.id',
        where: 'X.y',
        names: const [],
        problem: problems.add,
      );
      expect(problems, isEmpty);
      expect(result.unresolved, {'Zzzzzzzz'});
      expect(result.entities, {'Book'});
    });

    test('an unknown property, a transient one, a collection', () {
      expect(
        _problems('select {Book.titel} from books'),
        _one(
          "{Book.titel}: Book has no property titel, did you mean 'title'? "
          '(stored properties: id, title, year, authorId, writtenBy)',
        ),
      );
      expect(
        _problems('select {Book.cache} from books'),
        _one('{Book.cache}: Book.cache is @Transient: it has no column'),
      );
      expect(
        _problems('select {Book.chapters} from books'),
        _one(
          '{Book.chapters}: Book.chapters is a @MappedCollection: its rows '
          'are in the table of its children, not in a column of Book',
        ),
      );
    });

    test('two classes of one name are ambiguous', () {
      final schema = DataSchema()
        ..addEntities([
          const EntityDescription('Book', 'package:a/a.dart', []),
          const EntityDescription('Book', 'package:b/b.dart', []),
        ]);
      expect(
        _problems('select * from {Book}', schema: schema),
        _one(
          '{Book}: Book names 2 @Table classes (package:a/a.dart, '
          'package:b/b.dart): rename one',
        ),
      );
    });

    test('a placeholder is a table the typo check knows', () {
      expect(
        _problems('select b.titel from {Book} b'),
        _one(
          "b.titel: no column titel in books, did you mean 'title'?",
        ),
      );
    });
  });

  group('typos in tables and columns', () {
    test('a table after from, join, update, into, delete from', () {
      for (final sql in [
        'select * from bokks',
        'select * from authors a join bokks b on b.author_id = a.id',
        'update bokks set year = 1',
        'insert into bokks (year) values (1)',
        'delete from bokks',
        'select * from books, bokks',
      ]) {
        expect(
          _problems(sql),
          contains("Books.query: bokks: no table bokks, did you mean 'books'?"),
          reason: sql,
        );
      }
    });

    test('a qualified column of a table or an alias', () {
      expect(
        _problems('select books.titel from books'),
        _one("books.titel: no column titel in books, did you mean 'title'?"),
      );
      expect(
        _problems('select b.titel from books as b'),
        _one("b.titel: no column titel in books, did you mean 'title'?"),
      );
      expect(
        _problems('select b.titel from books b where b.year = :year'),
        hasLength(1),
      );
    });

    test('an alias that is not one in sight, near one that is', () {
      expect(
        _problems('select bkk.title from books bk'),
        _one("bkk.title: no table or alias bkk here, did you mean 'bk'?"),
      );
      // One or two characters: every short name is one change from another.
      expect(_problems('select bk.title from books b'), isEmpty);
      expect(_problems('select t.id from books b'), isEmpty);
      expect(
        _problems('select bokks.title from books'),
        _one(
          "bokks.title: no table or alias bokks here, did you mean 'books'?",
        ),
      );
    });

    test('an unqualified column that nothing in sight has', () {
      expect(
        _problems('select titel from books'),
        _one("titel: no column titel in books, did you mean 'title'?"),
      );
      expect(
        _problems('select * from books where yeer = :year'),
        _one("yeer: no column yeer in books, did you mean 'year'?"),
      );
      expect(
        _problems('select * from books order by yeer'),
        hasLength(1),
      );
      expect(
        _problems('update books set titel = :title where id = 1'),
        _one("titel: no column titel in books, did you mean 'title'?"),
      );
      expect(
        _problems('insert into books (titel, year) values (:title, :year)'),
        _one("titel: no column titel in books, did you mean 'title'?"),
      );
    });

    test('the columns of several tables are all in sight', () {
      expect(
        _problems(
          'select title, name from books '
          'join authors on author_id = authors.id',
        ),
        isEmpty,
      );
      expect(
        _problems(
          'select titel from books join authors on author_id = authors.id',
        ),
        _one(
          "titel: no column titel in books, authors, did you mean 'title'?",
        ),
      );
    });

    test('names far from every known one are left alone', () {
      expect(
        _problems(
          'select zzzzzz from books where qqqqqq = 1 and external_things.x = 2',
        ),
        isEmpty,
      );
      expect(_problems('select * from external_things'), isEmpty);
      expect(_problems('select * from information_schema.tables'), isEmpty);
      expect(_problems('select * from main.bokks'), isEmpty);
      expect(
        _problems('select b.zzzzzz from books b where b.qqqqqq = 1'),
        isEmpty,
      );
    });

    test('keywords, functions, casts, literals and numbers', () {
      expect(
        _problems(
          'select count(*), max(year), lower(title)::text, '
          "cast(year as integer), current_timestamp, coalesce(title, 'x') "
          'from books where title is not null and year between 1 and 2 '
          r"and title like :title escape '\' order by year desc nulls last "
          'limit 10 offset 5',
        ),
        isEmpty,
      );
      expect(
        _problems(
          'select case when year > 2000 then true else false end as modern '
          'from books',
        ),
        isEmpty,
      );
      expect(
        _problems('select extract(year from created) from books'),
        isEmpty,
      );
      expect(
        _problems('select substring(title from 2 for 3) from books'),
        isEmpty,
      );
      expect(
        _problems('select * from books where year is distinct from :year'),
        isEmpty,
      );
    });

    test('column aliases, explicit and implicit, in later clauses', () {
      expect(
        _problems(
          'select title as headline, year yr, count(*) total from books '
          'group by headline, yr order by total, headline having total > 1',
        ),
        isEmpty,
      );
      expect(
        _problems('select upper(title) shouting from books order by shouting'),
        isEmpty,
      );
      expect(
        _problems(
          'select title as "My Title" from books order by "My Title"',
        ),
        isEmpty,
      );
    });

    test('table aliases, with and without as, and derived tables', () {
      expect(
        _problems(
          'select b.title, a.name from books b, authors as a '
          'where b.author_id = a.id',
        ),
        isEmpty,
      );
      expect(
        _problems(
          'select s.title from (select title, year from books) s '
          'where s.year = :year',
        ),
        isEmpty,
      );
      expect(
        _problems('select s.titel from (select title, year from books) s'),
        _one("s.titel: no column titel in the subquery, did you mean 'title'?"),
      );
      // `select *` in a derived table: its columns are not known.
      expect(
        _problems('select s.titel from (select * from books) s'),
        isEmpty,
      );
    });

    test('CTEs: their names, columns and recursion', () {
      expect(
        _problems(
          'with recent as (select id, title from books where year > :year) '
          'select r.id from recent r join authors a on a.id = r.id',
        ),
        isEmpty,
      );
      expect(
        _problems(
          'with recent as (select id, title from books) '
          'select r.titel from recent r',
        ),
        _one("r.titel: no column titel in recent, did you mean 'title'?"),
      );
      expect(
        _problems(
          'with book as (select id from books) select * from book',
        ),
        isEmpty,
      );
      expect(
        _problems(
          'with recursive t(n) as (select 1 union all select n + 1 from t '
          'where n < 5) select n from t',
        ),
        isEmpty,
      );
      expect(
        _problems(
          'with a as (select id from books), b as (select id from a) '
          'select * from b',
        ),
        isEmpty,
      );
    });

    test('subqueries, correlated ones, exists and in', () {
      expect(
        _problems(
          'select title from books b where exists '
          '(select 1 from authors a where a.id = b.author_id '
          'and a.name = :title) '
          'and year in (select year from books where id > 1)',
        ),
        isEmpty,
      );
      expect(
        _problems(
          'select title from books b where exists '
          '(select 1 from authors a where a.nme = b.title)',
        ),
        _one("a.nme: no column nme in authors, did you mean 'name'?"),
      );
      expect(
        _problems(
          'select (select max(year) from books) as latest, name from authors',
        ),
        isEmpty,
      );
    });

    test('unions: each side has its own tables, aliases are shared', () {
      expect(
        _problems(
          'select title as label from books union select name from authors '
          'order by label',
        ),
        isEmpty,
      );
      expect(
        _problems('select title from books union select nme from authors'),
        _one("nme: no column nme in authors, did you mean 'name'?"),
      );
    });

    test('joins of entity tables, a table of a migration and a view', () {
      expect(
        _problems(
          'select b.title, a.name, v.books, ac.iban '
          'from books b join authors a on a.id = b.author_id '
          'join author_book_counts v on v.id = a.id '
          'cross join accounts ac '
          'where ac.balance > :year',
        ),
        isEmpty,
      );
      expect(
        _problems('select v.bokks from author_book_counts v'),
        _one(
          'v.bokks: no column bokks in author_book_counts, '
          "did you mean 'books'?",
        ),
      );
      expect(
        _problems('select * from accounts where ownr = :title'),
        _one("ownr: no column ownr in accounts, did you mean 'owner'?"),
      );
      expect(
        _problems('select * from author_book_count'),
        _one(
          'author_book_count: no table author_book_count, did you mean '
          "'author_book_counts'?",
        ),
      );
    });

    test('children tables have the columns of the collection', () {
      expect(
        _problems('select books_id, books_key, number from chapters'),
        isEmpty,
      );
      expect(
        _problems('select numbr from chapters'),
        _one("numbr: no column numbr in chapters, did you mean 'number'?"),
      );
    });

    test('joins with using, natural, lateral and functions', () {
      expect(
        _problems(
          'select title from books join authors using (id) '
          'natural join accounts',
        ),
        isEmpty,
      );
      expect(
        _problems(
          'select t.n from books b, lateral (select b.year as n) t '
          'cross join generate_series(1, 3) g',
        ),
        isEmpty,
      );
      expect(
        _problems('select * from unnest(:year) as u(x) where x > 1'),
        isEmpty,
      );
    });

    test('Postgres and SQLite dialects pass', () {
      expect(
        _problems(
          "select title::varchar(20), data->>'k', tags @> :title, "
          r"'{1,2}'::int[], $1, @param, rowid from books "
          'where title ilike :title and year = any(:ids)',
          names: ['title', 'ids'],
        ),
        isEmpty,
      );
      expect(
        _problems(
          'insert into books (title) values (:title) '
          'on conflict (title) do update set title = excluded.title '
          'returning id',
          names: ['title'],
        ),
        isEmpty,
      );
      expect(
        _problems(
          'insert or replace into books (id, title) '
          'select id, title from books',
        ),
        isEmpty,
      );
      expect(
        _problems(
          'select * from books for update',
        ),
        isEmpty,
      );
    });

    test('property placeholders are opaque', () {
      expect(
        _problems(r'select * from ${table} where year = :year'),
        isEmpty,
      );
      expect(
        _problems(r'select titel from books, ${table}'),
        isEmpty,
      );
      expect(
        _problems(
          r'select * from books order by ${sort.column} limit ${page.size:3}',
        ),
        isEmpty,
      );
    });

    test('a corpus of valid queries raises nothing', () {
      // One query to a paragraph.
      const corpus = r'''
select title, row_number() over (partition by author_id order by year desc)
  rn, rank() over w from books window w as (order by year)

select count(*) filter (where year > :year) as recent,
  percentile_cont(0.5) within group (order by year) from books

select sum(year) over (order by id rows between unbounded preceding and
  current row) from books

select coalesce(title, 'none'), nullif(year, 0)::text, cast(id as varchar(10)),
  created + interval '1 day', extract(epoch from created) from books

select case when year < 1900 then 'old' when year < 2000 then 'mid'
  else 'new' end as era, count(*) from books group by era

select "title", `year`, books."id" from "books" where title = :title
  collate nocase and title like '%x%' escape '!'

select (select count(*) from books b2 where b2.author_id = a.id) as n, a.name
  from authors a where a.id in (select author_id from books where year > :year)
  and not exists (select 1 from books where author_id = a.id and year < 1000)
  order by n

select * from (select author_id, max(year) as latest from books
  group by author_id) t join authors a on a.id = t.author_id
  where t.latest > :year

select * from books b left outer join authors a on a.id = b.author_id
  right join books c on c.id = b.id full join authors d using (id)
  natural join authors

select * from books b inner join authors a on a.id = b.author_id
  and (a.name like :title or a.name is null), authors z

select id from books where id in (values (1), (2)) union all
  select id from authors except select id from books
  order by 1 limit :year offset 2

select * from (values (1, 'a'), (2, 'b')) as v(num, letter) where v.num > 1

insert into books (title, year) values (:title, :year)
  on conflict (id) do update set title = excluded.title,
  year = books.year + 1 where books.year < :year returning id

insert into books (title) select name from authors where id > 1

update books set year = year + 1, title = upper(title) where id in
  (select id from books order by id limit 2) returning title

update books b set year = a.id from authors a where a.id = b.id

delete from books where author_id in (select id from authors
  where name = :title) returning id

delete from books using authors a where books.author_id = a.id

with doomed as (select id from books where year < 1000)
  delete from books where id in (select id from doomed)

with moved as (update books set year = 1 where id = 1 returning id)
  select * from moved

select * from books where id = :year for update skip locked

select * from books for share nowait

select * from books indexed by idx_title where title = :title

select * from books where year between :year and :year + 10
  and title not like :title and id is not null

select count(distinct author_id), max(year) - min(year) from books

select 'it''s', "a""b" from books -- trailing; comment

select /* inline */ title from books /* more */ where /* x */ id = 1

select data->>'k', data #> '{a,b}', tags && :title, id::int8 from books

select date(created), strftime('%Y', created), length(title) from books

select title from books where year = any(:ids) and id <> all(:ids)

select * from generate_series(1, :year) as g(n) where n > 1

select b.* from books b, lateral (select * from authors a
  where a.id = b.author_id limit 1) l

select {Book.title}, b.{Book.year} from {Book} b where {Book.id} = :#{#year}
  and b.title = ${book.title} order by b.id

select * from books where title = :title limit ${page.size:10}
''';
      for (final sql in corpus.trim().split('\n\n')) {
        expect(
          _problems(sql, names: ['year', 'title', 'ids']),
          isEmpty,
          reason: sql,
        );
      }
    });

    test('a corpus of broken queries finds the typo in each', () {
      const corpus = {
        'select titel, row_number() over (partition by author_id) from books':
            'titel',
        'select * from books where id in (select author_id from bokks)':
            'bokks',
        'select a.name from authors a join books b on b.author_idd = a.id':
            'b.author_idd',
        'select count(*) over (partition by author_idd) from books':
            'author_idd',
        'with x as (select id, title from books) select x.titel from x':
            'x.titel',
        'update books set yeer = 1 where id = 2': 'yeer',
        'delete from books where author_idd = 1': 'author_idd',
        'insert into books (titel) values (:title)': 'titel',
        'select * from books order by yeer desc nulls last': 'yeer',
        'select t.titel from (select title from books) t': 't.titel',
        'select * from books b where exists (select 1 from authors a where '
                'a.id = b.author_idd)':
            'b.author_idd',
        'select * from books group by author_id having max(yeer) > 1': 'yeer',
      };
      for (final MapEntry(key: sql, value: name) in corpus.entries) {
        final problems = _problems(sql, names: ['title']);
        expect(
          problems.where((p) => p.startsWith('Books.query: $name:')),
          hasLength(1),
          reason: '$sql -> $problems',
        );
      }
    });

    test('a table with columns unknown to the build is not checked', () {
      final schema = _schema(
        migration:
            'create table legacy (like books);\n'
            'create table legacy_two (a int);\n'
            'alter table legacy_two add (b int, c int);',
      );
      expect(
        _problems('select titel from legacy', schema: schema),
        isEmpty,
      );
      expect(
        _problems('select b.zzzz from legacy_two b', schema: schema),
        isEmpty,
      );
    });

    test(
      'a customised naming strategy hides the names derived from entities',
      () {
        final schema = _schema(customNaming: true);
        // `books` is named by @Table; its derived columns are not known.
        expect(
          _problems('select b.titel from books b', schema: schema),
          isEmpty,
        );
        // Names spelled out are known (@Table, @Column('writer')), the table
        // is not complete.
        expect(schema.table('books')!.columns, ['writer']);
        expect(schema.table('books')!.complete, isFalse);
        expect(schema.table('publisher'), isNull);
        expect(_schema().table('publisher'), isNotNull);
      },
    );

    test(
      r'a table a ${placeholder} writes hides the tables that are not there',
      () {
        final schema = _schema(
          migration: r'create table ${schema}_${name} (id int);',
        );
        expect(_problems('select * from bokks', schema: schema), isEmpty);
        expect(_problems('select titel from books', schema: schema), isEmpty);
      },
    );

    test('a schema the build cannot read is not checked', () {
      final schema = _schema()..reliable = false;
      expect(_problems('select titel from bokks', schema: schema), isEmpty);
    });

    test('the problems of one text are all reported', () {
      // `bokks` is unknown, so the columns of the query are not checked.
      expect(
        _problems('select titel from bokks where yeer = :yeer'),
        hasLength(2),
      );
      expect(
        _problems('select titel from books where yeer = :yeer'),
        hasLength(3),
      );
    });
  });

  group('valid SQL is never an error', () {
    // Tables whose columns are close to words of SQL, so a name the checker
    // takes for a column gives a suggestion.
    const migration = '''
create table events (
  id integer primary key,
  title text,
  created_at timestamp,
  info text,
  points text
);
create table labels_a (id integer, label text);
create table labels_b (id integer, labels text);
''';

    List<String> problems(String sql, {List<String> names = const ['ids']}) =>
        _problems(
          sql,
          names: names,
          schema: _schema(migration: migration),
        );

    test('a short name has no close name', () {
      expect(closestName('b', ['a', 'id']), isNull);
      expect(closestName('bk', ['b', 'bl']), isNull);
      expect(closestName('id', ['ie']), isNull);
      expect(closestName('abc', ['abd']), 'abd');
      expect(closestName('titel', ['id', 'title']), 'title');
    });

    test('the alias of a values list', () {
      expect(
        problems(
          'select * from events e join (values (1)) v on v.column1 = e.id',
        ),
        isEmpty,
      );
      expect(
        problems(
          'select * from events e join (values (1, 2)) as v(a, b) '
          'on v.a = e.id and v.b > 1',
        ),
        isEmpty,
      );
      // A typo next to it is still found.
      expect(
        problems(
          'select * from events e join (values (1)) v on v.column1 = e.id '
          "where e.titel = 'x'",
        ),
        _one("e.titel: no column titel in events, did you mean 'title'?"),
      );
    });

    test(r'a table or alias that a ${property} writes', () {
      expect(
        problems(
          r'select * from ${table} t join ${schema}.events b on b.id = t.id',
        ),
        isEmpty,
      );
      expect(
        problems(r'select * from events_${year} e where e.id = 1'),
        isEmpty,
      );
      expect(
        problems(
          r'update ${table} set title = :title where id = 1',
          names: ['title'],
        ),
        isEmpty,
      );
      expect(
        problems(r'insert into ${table} (created) values (1) returning id'),
        isEmpty,
      );
    });

    test('parenthesized joins', () {
      expect(
        problems(
          'select * from (events e join labels_a l on l.id = e.id) '
          "where e.title = 'x' and l.label = 'y'",
        ),
        isEmpty,
      );
      expect(
        problems(
          'select * from ((events e join labels_a l on l.id = e.id) '
          'join labels_b m on m.id = e.id) where m.labels = l.label',
        ),
        isEmpty,
      );
      expect(
        problems(
          'select j.title from (events e join labels_a l on l.id = e.id) as j',
        ),
        isEmpty,
      );
      // The names after the group are still the query's own.
      expect(
        problems(
          'select * from (events e join labels_a l on l.id = e.id) '
          "where (select max(year) from (values (1)) y) > 1 and e.titel = 'x'",
        ),
        _one("e.titel: no column titel in events, did you mean 'title'?"),
      );
    });

    test('with ordinality', () {
      expect(
        problems(
          'select t.n from unnest(:ids) with ordinality as t(id, n) '
          'join events e on e.id = t.id',
        ),
        isEmpty,
      );
      expect(
        problems('select x.n from unnest(array[1, 2]) with ordinality x(v, n)'),
        isEmpty,
      );
    });

    test('an alias after returning', () {
      expect(
        problems(
          'insert into events (title) values (:title) '
          'returning created_at as created, id new_id',
          names: ['title'],
        ),
        isEmpty,
      );
      expect(
        problems(
          'with moved as (update events set title = :title '
          'returning created_at as created) select created from moved',
          names: ['title'],
        ),
        isEmpty,
      );
    });

    test('the names of constraints and indexes', () {
      expect(
        problems(
          'insert into events (title) values (:title) '
          'on conflict on constraint uq_title do nothing',
          names: ['title'],
        ),
        isEmpty,
      );
      expect(
        problems(
          'select * from events indexed by ix_title where title = :title',
          names: ['title'],
        ),
        isEmpty,
      );
      expect(
        problems('select * from events e for update of events, e'),
        isEmpty,
      );
    });

    test('the type of a cast is no column', () {
      expect(
        problems(
          'select cast(title as inet), cast(id as numeric(10, 2)) from events',
        ),
        isEmpty,
      );
      expect(
        problems(
          'select title::geography(Point, 4326), id::inet[] from events',
        ),
        isEmpty,
      );
      // The value is still checked.
      expect(
        problems('select cast(titel as inet) from events'),
        _one("titel: no column titel in events, did you mean 'title'?"),
      );
    });

    test("the order of a union is the union's, not the last side's", () {
      expect(
        problems(
          'select label from labels_a union select labels from labels_b '
          'order by label limit 5',
        ),
        isEmpty,
      );
      expect(
        problems(
          'select label from labels_a union all select labels from labels_b '
          'order by label desc offset 1',
        ),
        isEmpty,
      );
      // A side's own names are still checked.
      expect(
        problems(
          'select label from labels_a union select labelz from labels_b',
        ),
        _one(
          "labelz: no column labelz in labels_b, did you mean 'labels'?",
        ),
      );
    });

    test('the CTEs after a values list or a data change', () {
      expect(
        problems(
          'with v as (values (1)), eventz as (select id from events) '
          'select * from eventz, v',
        ),
        isEmpty,
      );
      expect(
        problems(
          'with moved as (update events set title = :title returning id), '
          'eventz as (select id from events) select * from eventz',
          names: ['title'],
        ),
        isEmpty,
      );
    });

    test('a corpus of valid Postgres queries', () {
      for (final sql in _validPostgres.trim().split('\n\n')) {
        expect(
          _problems(sql, names: ['year', 'title', 'ids']),
          isEmpty,
          reason: sql,
        );
      }
    });

    test('a corpus of valid SQLite queries', () {
      for (final sql in _validSqlite.trim().split('\n\n')) {
        expect(
          _problems(sql, names: ['year', 'title', 'ids']),
          isEmpty,
          reason: sql,
        );
      }
    });
  });

  group('the schema of migrations', () {
    DataSchema read(String sql) => DataSchema()..apply(sql);

    test('create table: columns, constraints, quoted names', () {
      final schema = read(r'''
create table if not exists main.books (
  id integer primary key autoincrement,
  "Title" text not null default 'a,b',
  price numeric(10, 2),
  $gone text,
  key text,
  author_id integer references authors (id) on delete cascade,
  primary key (id),
  unique (title),
  constraint fk foreign key (author_id) references authors (id),
  check (price > 0)
) without rowid;
''');
      expect(schema.table('books')!.columns, [
        'id',
        'Title',
        'price',
        'key',
        'author_id',
      ]);
      expect(schema.table('books')!.complete, isFalse);
    });

    test('a complete table', () {
      final schema = read(
        'create table t (a int, b text, primary key (a), unique key u (b));',
      );
      expect(schema.table('t')!.columns, ['a', 'b']);
      expect(schema.table('t')!.complete, isTrue);
    });

    test('alter table: add, rename, drop, in file order', () {
      final schema = read('''
create table books (id int, title text, year int);
alter table books add column isbn text;
alter table books add if not exists subtitle text;
alter table books add constraint u unique (isbn);
alter table books add primary key (id);
alter table books rename column title to name;
alter table books drop column year;
alter table books drop constraint u;
alter table books add column a int, add column b int;
alter table books rename to volumes;
alter table volumes alter column a set not null;
''');
      expect(schema.table('books'), isNull);
      expect(
        schema.table('volumes')!.columns,
        unorderedEquals(['id', 'isbn', 'subtitle', 'name', 'a', 'b']),
      );
      expect(schema.table('volumes')!.complete, isTrue);
    });

    test('mysql and sqlite forms', () {
      final schema = read('''
create table t (a int, b int, c int);
alter table t change b bb int;
alter table t modify c bigint;
alter table t rename a to aa;
alter table t add d int;
''');
      expect(
        schema.table('t')!.columns,
        unorderedEquals(['aa', 'bb', 'c', 'd']),
      );
      expect(schema.table('t')!.complete, isTrue);
    });

    test('drop table and drop view', () {
      final schema = read('''
create table a (x int);
create table b (x int);
create table c (x int);
create view v as select x from a;
drop table if exists a, b cascade;
drop view v;
''');
      expect(schema.tableNames, ['c']);
    });

    test('views: their select list, an explicit list, a star', () {
      final schema = read('''
create view v1 as select a.id, a.name as title, count(*) n, 1 + 2 from t a;
create or replace view v2 (x, y) as select 1, 2;
create view v3 as select * from t;
create view v4 as with c as (select 1) select id, name from c;
create materialized view v5 as select distinct on (id) id, "name" from t;
''');
      expect(schema.table('v1')!.columns, ['id', 'title', 'n']);
      expect(schema.table('v1')!.complete, isFalse);
      expect(schema.table('v2')!.columns, ['x', 'y']);
      expect(schema.table('v2')!.complete, isTrue);
      expect(schema.table('v3')!.complete, isFalse);
      expect(schema.table('v4')!.columns, ['id', 'name']);
      expect(schema.table('v4')!.complete, isTrue);
      expect(schema.table('v5')!.columns, ['id', 'name']);
      expect(schema.table('v1')!.isView, isTrue);
    });

    test('what is not understood is tolerated', () {
      final schema = read(r'''
-- a comment; with a semicolon
create index i on t (a);
create trigger trg after insert on t begin update t set a = 1; end;
create function f() returns trigger as $$ begin return new; end; $$ language plpgsql;
insert into t values (1);
create table ok (a int);
alter table ok set unlogged;
alter table unseen add column z int;
create table ${flyway:schema}.other (a int);
vacuum;
''');
      expect(schema.table('ok')!.columns, ['a']);
      expect(schema.table('ok')!.complete, isTrue);
      expect(schema.table('unseen')!.columns, ['z']);
      expect(schema.table('unseen')!.complete, isFalse);
      // The schema is a qualifier, which is not part of the name.
      expect(schema.table('other')!.columns, ['a']);
    });

    test('create table if not exists leaves a table that is there', () {
      final schema = read('''
create table books (id int, title text);
alter table books add column year int;
create table if not exists books (id int);
create view if not exists bv as select id from books;
create view if not exists bv as select title from books;
create table books2 (id int);
create table books2 (id int, other int);
''');
      expect(schema.table('books')!.columns, ['id', 'title', 'year']);
      expect(schema.table('bv')!.columns, ['id']);
      // Without `if not exists` a table is made again.
      expect(schema.table('books2')!.columns, ['id', 'other']);
    });

    test('a column of a type with arguments is no constraint', () {
      final schema = read('''
create table plan (
  id int,
  period varchar(16),
  key varchar(255),
  index int(11),
  check boolean,
  unique_name char(4),
  primary key (id),
  key idx_period (period),
  index idx_key (key),
  unique key u_period (period),
  fulltext key ft (period),
  unique (key),
  check (id > 0),
  period for system_time (a, b)
);
alter table plan add period2 varchar(8);
alter table plan add period varchar(8);
alter table plan add key idx (id);
alter table plan add index idx2 (id);
alter table plan add unique key u2 (id);
alter table plan add constraint c check (id > 0);
alter table plan drop index idx;
alter table plan drop key idx2;
alter table plan drop primary key;
''');
      expect(schema.table('plan')!.columns, [
        'id',
        'period',
        'key',
        'index',
        'check',
        'unique_name',
        'period2',
      ]);
      expect(schema.table('plan')!.complete, isTrue);
    });

    test(r'a table a ${placeholder} names is unknown, a schema is not', () {
      final schema = read(r'''
create table books (id int);
alter table ${schema}.books add column year int;
create table ${schema}.authors (id int);
''');
      expect(schema.table('books')!.columns, ['id', 'year']);
      expect(schema.table('books')!.complete, isTrue);
      expect(schema.table('authors')!.columns, ['id']);
      expect(schema.unknownTables, isFalse);

      for (final statement in [
        r'alter table ${table} add column year int',
        r'alter table books_${year} add column year int',
        r'create table ${table} (id int)',
        r'create table books_${year} (id int)',
        r'create view ${view} as select 1',
        r'drop table ${table}',
      ]) {
        final unknown = read('create table books (id int); $statement;');
        expect(unknown.unknownTables, isTrue, reason: statement);
        expect(unknown.table('books')!.complete, isFalse, reason: statement);
      }
    });

    test('the alternatives of several databases give any column of any', () {
      final schema = DataSchema.fromScripts([
        [
          'create table notes (id int, body text);',
          'alter table notes add isbn text;',
        ],
        [
          'create table notes (id int, bodyx text);',
          'create table only_here (a int);',
          'create table partial (a int, like other);',
        ],
        ['create table partial (a int);'],
      ]);
      expect(
        schema.table('notes')!.columns,
        unorderedEquals(['id', 'body', 'isbn', 'bodyx']),
      );
      expect(schema.table('notes')!.complete, isTrue);
      expect(schema.table('only_here')!.columns, ['a']);
      // Complete only where it is complete in every alternative.
      expect(schema.table('partial')!.complete, isFalse);
    });

    test('create table as select, and a rename of an unknown column', () {
      final schema = read('''
create table copy as select id, title from books;
create table t (a int);
alter table t rename column nope to b;
''');
      expect(schema.table('copy')!.columns, ['id', 'title']);
      expect(schema.table('t')!.complete, isFalse);
    });

    test('entities add to the tables of migrations, never take away', () {
      final schema = DataSchema()
        ..apply('create table books (id int, legacy text); drop table books;')
        ..apply('create table authors (id int, legacy text);')
        ..addEntities(_entities);
      expect(schema.table('books')!.columns, containsAll(['id', 'title']));
      expect(
        schema.table('authors')!.columns,
        containsAll(['id', 'name', 'legacy']),
      );
    });

    test('default names are snake case, as the starter writes them', () {
      expect(DataSchema.snakeCase('OrderLine'), 'order_line');
      expect(DataSchema.snakeCase('HTTPRequest'), 'http_request');
      expect(DataSchema.snakeCase('authorId'), 'author_id');
      expect(DataSchema.snakeCase('line2Item'), 'line2_item');
      expect(DataSchema.snakeCase('URL'), 'url');
    });
  });
}

// Queries that are right in Postgres, and in SQLite: the checker must find
// nothing in them, whatever the names of their aliases and columns.
const _validPostgres = r'''
select distinct on (author_id) title, author_id from books
  order by author_id, year desc

select author_id, array_agg(title order by year) as titles,
  string_agg(title, ', ' order by title) from books group by author_id

select title from books where (author_id, year) in ((1, 2000), (2, 2001))

select * from books b join lateral (select count(*) as n from books x
  where x.author_id = b.author_id) c on true where c.n > 1

select * from books tablesample system (10)

select * from only books

select author_id, count(*) from books group by rollup (author_id)

select author_id, year, count(*) from books
  group by grouping sets ((author_id), (year), ())

select b.title, t.tag from books b,
  unnest(string_to_array(b.title, ' ')) as t(tag) where t.tag <> ''

select b.title, t.tag, t.ord from books b
  cross join unnest(array['a', 'b']) with ordinality as t(tag, ord)

select * from books where title ~ :title or title ~* :title
  or title similar to :title

select * from books where id = any(array[1, 2, 3]) and year <@ int4range(1, 2)

select title::jsonb->'a'->>'b', title::jsonb#>>'{a,b}',
  jsonb_build_object('k', title) from books

select * from jsonb_to_recordset(:ids) as x(a int, b text)

select * from books b where b.year > (select avg(year) from books)
  and b.id not in (select author_id from books where author_id is not null)

select title, lag(title) over (partition by author_id order by year) prev,
  first_value(title) over w from books window w as (partition by author_id
  order by year rows between unbounded preceding and unbounded following)

with recursive tree(id, depth) as (select id, 1 from authors union all
  select a.id, t.depth + 1 from authors a join tree t on t.id = a.id
  where t.depth < 3) select * from tree order by depth

with a as (select 1 as n), b as (select n + 1 as m from a)
  select a.n, b.m from a, b

with ins as (insert into books (title) values (:title) returning id, title)
  select ins.id, ins.title from ins

with ins as (insert into books (title) values (:title) returning id as new_id),
  upd as (update books set year = 1 where id in (select new_id from ins)
  returning id) select count(*) from upd

update books set year = b2.year from (select id, year from books) b2
  where books.id = b2.id

update books as b set title = a.name from authors as a
  where a.id = b.author_id returning b.id, b.title as new_title

insert into books (title, year) select name, 0 from authors where id > :year
  on conflict on constraint books_pkey do nothing returning id

insert into books (title) values (:title), (:title) on conflict (id)
  do update set title = excluded.title || ' copy'

delete from books b using authors a where a.id = b.author_id
  and a.name = :title returning b.id

select * from books where title = $$it's$$ and year = $1

select coalesce(nullif(title, ''), 'untitled') as t,
  year::text || '-' || id::text as k from books order by 1, t

select * from books order by title collate "C" desc nulls first

select * from books fetch first 10 rows only

select (array[1, 2, 3])[1] from books

select * from books where id = :year for update of books skip locked

select b.id from books b where b.author_id is not distinct from :year

select * from books b where b.title = any(select name from authors)

select a.name, (select count(*) from books where author_id = a.id) as total
  from authors a order by total desc, a.name

select * from generate_series(1, 10) as g(n) join books on books.id = g.n

select now(), current_date, current_setting('x') from books

select "Title" from books

select * from books where year between symmetric 1 and 2

values (1, 'a'), (2, 'b')

select * from (values (1, 'a')) as v

select * from books union all select * from books order by 1

(select title from books) union (select name from authors) order by title
  limit 3

select title from books intersect select name from authors

select count(*) from books where exists (select 1 from authors
  where authors.id = books.author_id)

select * from books b where not exists (select 1 from (select id from authors)
  x where x.id = b.author_id)

select * from books where (select count(*) from authors) > 0

select * from books b join (values (1), (2)) v on v.column1 = b.id

select * from books b join (values (1, 'a')) as v(num, letter)
  on v.num = b.id where v.letter = :title

select * from ${table} t join ${schema}.books b on b.id = t.id
  where t.anything = :year and b.title = :title

select * from books_${year} b where b.id = 1

select * from (books b join authors a on a.id = b.author_id)
  where b.title = :title and a.name = :title

select * from ((books b join authors a on a.id = b.author_id)
  join books c on c.id = b.id) where c.title = a.name

select * from (books b join authors a on a.id = b.author_id) as j
  where j.title = :title

select t.n, b.title from unnest(:ids) with ordinality as t(id, n)
  join books b on b.id = t.id

select x.n from unnest(array[1, 2]) with ordinality x(v, n)

update books set year = 1 returning title as headline, year yr

with moved as (update books set year = 1 returning id), bks as
  (select id from books) select bks.id from bks join moved on moved.id = bks.id

with v as (values (1)), recent as (select id from books)
  select recent.id from recent, v

select cast(year as citext), id::geography(Point, 4326), cast(id as numeric(10, 2))
  from books

select * from books b where b.title = :title order by b.year
  fetch first :year rows with ties

select * from books for no key update

select * from books for key share of books nowait

select title from books where year > 2000 union all select name from authors
  order by 1 desc limit 5 offset 1
''';

const _validSqlite = '''
select * from books where rowid = :year

insert or ignore into books (title) values (:title)

insert or replace into books (id, title) values (1, :title)

replace into books (id, title) values (1, :title)

update or fail books set title = :title where id = 1

select typeof(year), ifnull(title, ''), strftime('%Y-%m', 'now'),
  group_concat(title, ',') from books group by author_id

select * from books indexed by ix_title where title = :title

select * from books not indexed

select * from books where title glob 'a*' and year is not :year

select * from books b left join authors a on a.id = b.author_id
  and a.name <> '' where a.id is null

select * from books limit :year, 5

select * from books where title like :title || '%'

select count(*) from books, authors where books.author_id = authors.id

insert into books (title) select :title
  where not exists (select 1 from books where title = :title)

with c(n) as (values (1), (2)) select n from c

select * from json_each(:ids) as j where j.value > 1

select b.title from books b, json_each(b.title) j where j.key = 'k'

select * from pragma_table_info('books') where name = 'x'

select * from books natural join authors

select title, year from books order by year desc, title collate nocase

update books set year = year + 1
  where id in (select id from books order by id limit 5)

select cast(year as text), cast(title as blob), typeof(cast(1 as real))
  from books

select title from books where title in (select name from authors)
  union select name from authors order by 1

select * from books where id = :year returning id

insert into books default values

insert into books (title) values (:title) on conflict (title) do nothing

insert into books (title) values (:title) on conflict (title)
  do update set title = excluded.title where books.year < excluded.year
''';
