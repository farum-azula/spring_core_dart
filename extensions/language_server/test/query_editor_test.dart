// The SQL of `@Query` methods of a repository: colours, navigation, hovers,
// completion and checks, with the entities of the source and of the
// metadata.
import 'package:dart_spring_language_server/src/config_editor.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

import 'support/data_fixture.dart';
import 'support/editor_fixture.dart';

// The shop plus a repository with the given methods.
String _repository(String methods) =>
    '''
$dataShopSource
abstract interface class CaseRepository
    implements ListCrudRepository<Book, int> {
$methods
}
''';

// A `@Query` method with [sql] and the parameters (int year, Pageable page).
String _query(String sql) {
  final literal = sql.contains("'") ? '"$sql"' : "'$sql'";
  return '@Query($literal)\n  Future<List<Book>> a(int year, Pageable page);';
}

List<Problem> _problems(String methods) {
  final (fixture, path) = dataFixture(source: _repository(methods));
  addTearDown(fixture.dispose);
  return fixture.workspace.problems(path);
}

int _line(String text) =>
    dataShopSource
        .substring(0, dataShopSource.indexOf(text))
        .split('\n')
        .length -
    1;

void main() {
  late EditorFixture fixture;
  late String path;

  setUp(() {
    (fixture, path) = dataFixture();
  });
  tearDown(() => fixture.dispose());

  group('colours', () {
    String? colourAt(String marker) {
      final offset = at(dataShopSource, marker);
      final position = fixture.workspace
          .file(path)!
          .lineInfo
          .getLocation(offset);
      for (final token in fixture.workspace.semanticTokens(path)) {
        if (token.line == position.lineNumber - 1 &&
            token.column <= position.columnNumber - 1 &&
            position.columnNumber - 1 < token.column + token.length) {
          return semanticTokenTypes[token.type];
        }
      }
      return null;
    }

    test('keywords, names, entities, parameters and operators', () {
      expect(colourAt('|select b.title'), 'keyword');
      expect(colourAt('select |b.title'), 'variable'); // before a dot
      expect(colourAt('b.|title, a.name'), 'property'); // a column
      expect(colourAt('from {|Book} b'), 'class');
      expect(colourAt('from {Book} |b'), 'variable'); // the alias
      expect(colourAt('{Book.|author}'), 'property');
      expect(colourAt('{|Book.author}'), 'class');
      expect(colourAt('>|= :year'), 'operator');
      expect(colourAt('>= |:year'), 'variable');
      expect(colourAt('|order by'), 'keyword');
    });

    test('SpEL inside :#{...} and comments', () {
      expect(colourAt('where title = |:#{#book.title}'), 'keyword');
      expect(colourAt(':#{|#book.title}'), 'variable'); // #book
      expect(colourAt(':#{#book.|title}'), 'property');
      expect(colourAt('|-- by title'), 'comment');
    });

    test('numbers and strings', () {
      final (other, otherPath) = dataFixture(
        source: _repository(
          "@Query(\"select 42 as n, 'it''s' as s from {Book} where x = 1.5\")\n"
          '  Future<int> odd();',
        ),
      );
      addTearDown(other.dispose);
      final types = {
        for (final token in other.workspace.semanticTokens(otherPath))
          semanticTokenTypes[token.type],
      };
      expect(types, containsAll(['number', 'string']));
    });

    test('a multi-line SQL is cut at the line ends', () {
      final (other, otherPath) = dataFixture(
        source: _repository(
          "@Query('''\n"
          '    select title /* a\n'
          '    note */ from {Book}\n'
          "    ''')\n"
          '  Future<List<String>> titles();',
        ),
      );
      addTearDown(other.dispose);
      final firstLine = dataShopSource.split('\n').length;
      final comments = [
        for (final t in other.workspace.semanticTokens(otherPath))
          if (semanticTokenTypes[t.type] == 'comment' && t.line > firstLine) t,
      ];
      // one token for each line of the comment
      expect(comments, hasLength(2));
    });
  });

  group('go to definition', () {
    List<String> go(String marker) => [
      for (final r in fixture.workspace.definition(
        path,
        at(dataShopSource, marker),
      ))
        '${r.path.split('/').last}:${r.startLine}:${r.startColumn}',
    ];

    test('{Book} goes to the entity class', () {
      expect(go('from {|Book} b'), ['shop.dart:${_line('class Book')}:6']);
      expect(go('join {|Author} a'), ['shop.dart:${_line('class Author')}:6']);
    });

    test('{Book.author} goes to the field', () {
      final result = go('b.{Book.|author}');
      expect(result, hasLength(1));
      expect(
        result.single,
        startsWith(
          'shop.dart:${_line('AggregateReference<Author, int>? author')}:',
        ),
      );
    });

    test(':year goes to the method parameter', () {
      const column = '  Future<List<BookCard>> cardsSince(int '.length;
      final line = _line('Future<List<BookCard>> cardsSince');
      expect(go('b.year >= |:year'), ['shop.dart:$line:$column']);
    });

    test('#book in SpEL goes to the method parameter', () {
      expect(
        go(':#{|#book.title}').single,
        startsWith('shop.dart:${_line('sameTitle(Book book)')}:'),
      );
    });

    test('an entity of the metadata only goes to its line', () {
      final changed = dataShopSource.replaceFirst(
        "@Table('authors')\nclass Author {",
        'class AuthorGone {',
      );
      final (other, otherPath) = dataFixture(source: changed);
      addTearDown(other.dispose);
      final ranges = other.workspace.definition(
        otherPath,
        at(changed, 'join {|Author} a'),
      );
      expect(ranges.single.path, endsWith('lib/shop.dart'));
      expect(ranges.single.startLine, 3); // line 4 of the metadata
    });
  });

  group('hovers', () {
    String? hover(String marker) =>
        fixture.workspace.hover(path, at(dataShopSource, marker));

    test('an entity: table, id and properties', () {
      final text = hover('from {|Book} b')!;
      expect(text, contains('**Book**'));
      expect(text, contains('table `books`'));
      expect(text, contains('id: `id`'));
      expect(text, contains('`title`'));
    });

    test('a property: column, type and reference', () {
      final text = hover('b.{Book.|author}')!;
      expect(text, contains('**Book.author**'));
      expect(text, contains('column `author`'));
      expect(text, contains('AggregateReference<Author, int>?'));
      expect(text, contains('references `Author`'));
    });

    test('a parameter: its type and method', () {
      final text = hover('>= |:year')!;
      expect(text, contains('int year'));
      expect(text, contains('cardsSince'));
    });

    test('a table name, an alias and a qualified column', () {
      const methods =
          "@Query('select b.title from books b where b.year > 1')\n"
          '  Future<List<String>> plain();';
      final text = _repository(methods);
      final (other, otherPath) = dataFixture(source: text);
      addTearDown(other.dispose);
      String? on(String marker) =>
          other.workspace.hover(otherPath, at(text, marker));
      expect(on('from |books b'), contains('**Book**'));
      expect(
        on('b.|title from'),
        allOf(contains('**Book.title**'), contains('column `title`')),
      );
      expect(on('books |b where'), contains('**Book**'));
    });
  });

  group('checks', () {
    test('the shop has no problem', () {
      expect(problemsOf(fixture.workspace, path), isEmpty);
    });

    test('an unknown entity, with a suggestion', () {
      final problems = _problems(
        "@Query('select * from {Bok} where year = :year')\n"
        '  Future<List<Book>> a(int year);',
      );
      expect(problems, hasLength(1));
      expect(problems.single.error, isTrue);
      expect(
        problems.single.message,
        contains(
          "no @Table class Bok in the application, did you mean 'Book'?",
        ),
      );
    });

    test('a class that is no @Table is named', () {
      final problems = _problems(
        "@Query('select * from {BookCard}')\n  Future<List<Book>> a();",
      );
      expect(problems.single.message, contains('is not marked @Table'));
    });

    test('an unknown property, a transient one and a collection', () {
      const methods =
          "@Query('select {Book.titel}, {Book.cache}, {Book.notes} "
          "from {Book}')\n"
          '  Future<List<Book>> a();';
      final problems = _problems(methods);
      expect(problems, hasLength(3));
      expect(problems[0].message, contains("did you mean 'title'?"));
      expect(problems[0].message, contains('stored properties:'));
      expect(problems[1].message, contains('@Transient'));
      expect(problems[2].message, contains('@MappedCollection'));
      // the range is the property name
      final range = problems[0].range;
      expect(
        _repository(methods)
            .split('\n')[range.startLine]
            .substring(range.startColumn, range.endColumn),
        'titel',
      );
    });

    test('a :param that is no parameter, with the ones there are', () {
      final problems = _problems(
        "@Query('select * from {Book} where year = :yaer')\n"
        '  Future<List<Book>> a(int year);',
      );
      final unknown = problems.firstWhere((p) => p.error);
      expect(unknown.message, contains(':yaer'));
      expect(unknown.message, contains('year'));
      expect(unknown.message, contains("Did you mean ':year'?"));
      // and `year` is never used: a warning on the parameter
      expect(
        problems.where((p) => !p.error).single.message,
        contains("Parameter 'year' is not used"),
      );
    });

    test('a parameter never used is a warning, Pageable and Sort are not', () {
      final problems = _problems(
        "@Query('select * from {Book} where year = :year')\n"
        '  Future<Page<Book>> a(int year, int unused, Pageable page, Sort s);',
      );
      expect(problems, hasLength(1));
      expect(problems.single.error, isFalse);
      expect(
        problems.single.message,
        "Parameter 'unused' is not used in the query",
      );
    });

    test('the count query counts as a use', () {
      final problems = _problems(
        "@Query('select * from {Book}', countQuery: 'select count(*) from "
        "{Book} where year = :year')\n"
        '  Future<Page<Book>> a(int year, Pageable page);',
      );
      expect(problems, isEmpty);
    });

    test('SpEL: parse errors and unknown variables', () {
      final problems = _problems(
        "@Query('select * from {Book} where a = :#{#bok.title} "
        "and b = :#{1 +}')\n"
        '  Future<List<Book>> a(Book book);',
      );
      final texts = [for (final p in problems) p.message];
      expect(texts, anyElement(contains("Unknown variable '#bok'")));
      expect(texts, anyElement(contains("Did you mean '#book'?")));
      expect(texts, anyElement(startsWith('SpEL:')));
    });

    test('SpEL: beans of the metadata, @environment, #p0, #entityName', () {
      final problems = _problems(
        '@Query("select * from {Book} where a = :#{@mailer.host} and "\n'
        '''  "b = :#{@environment.getProperty('x', 'y')} and "\n'''
        '''  "c = :#{#p0} and d = :#{#entityName}")\n'''
        '  Future<List<Book>> a(String s);',
      );
      expect(problems, isEmpty);
      final unknown = _problems(
        "@Query('select * from {Book} where a = :#{@mailr.host} and b = :s')\n"
        '  Future<List<Book>> a(String s);',
      );
      expect(unknown.single.message, contains("Unknown bean 'mailr'"));
    });

    test('a plain ? marker, #{...} and an unclosed expression', () {
      final problems = _problems(
        "@Query('select * from {Book} where a = ? and b = #{x} and c = :#{1')\n"
        '  Future<List<Book>> a();',
      );
      final texts = [for (final p in problems) p.message];
      expect(texts, anyElement(contains('plain ? marker')));
      expect(texts, anyElement(contains('#{x} is not allowed')));
      expect(texts, anyElement(contains('Unclosed SpEL expression')));
    });

    test('unbalanced quotes, parentheses and a stray brace', () {
      final quote = _problems(
        "@Query(\"select (a from {Book} where b = 'open\")\n"
        '  Future<List<Book>> a();',
      );
      final quoteTexts = [for (final p in quote) p.message];
      expect(quoteTexts, anyElement(startsWith('Unclosed string')));
      expect(quoteTexts, anyElement(contains("Unclosed '('")));
      final parens = _problems(
        "@Query('select a) from {Book where (b')\n"
        '  Future<List<Book>> a();',
      );
      final parenTexts = [for (final p in parens) p.message];
      expect(parenTexts, anyElement(contains("Unmatched ')'")));
      expect(parenTexts, anyElement(contains('no placeholder')));
      expect(parenTexts, anyElement(contains("Unclosed '('")));
    });

    test('quotes and comments hide what looks like a parameter', () {
      final problems = _problems(
        "@Query(\"select ':nope' as a, 'x:y' from {Book} -- :gone (\")\n"
        '  Future<List<Book>> a();',
      );
      expect(problems, isEmpty);
    });

    test('adjacent strings are one query, ranges map to the literals', () {
      final text = _repository(
        "@Query(\n  'select * from {Book} '\n  'where year = :yaer',\n)\n"
        '  Future<List<Book>> a(int year);',
      );
      final (other, otherPath) = dataFixture(source: text);
      addTearDown(other.dispose);
      final error = other.workspace
          .problems(otherPath)
          .firstWhere((p) => p.error);
      expect(error.range.startLine, error.range.endLine);
      expect(
        text
            .split('\n')[error.range.startLine]
            .substring(error.range.startColumn, error.range.endColumn),
        ':yaer',
      );
    });

    test('an entity not built yet is known from the source', () {
      // A new field the metadata does not have: no false error.
      final source = _repository(
        "@Query('select {Book.subtitle} from {Book}')\n"
        '  Future<List<String>> a();',
      ).replaceFirst('  bool inStock;', '  bool inStock;\n  String? subtitle;');
      final (other, otherPath) = dataFixture(source: source);
      addTearDown(other.dispose);
      expect(problemsOf(other.workspace, otherPath), isEmpty);
    });

    test('without any metadata the entities of the source count', () {
      final bare = EditorFixture.create(withAppMetadata: false);
      addTearDown(bare.dispose);
      final file = bare.open(
        'lib/shop.dart',
        _repository(
          "@Query('select {Book.titel} from {Book}')\n"
          '  Future<List<String>> a();',
        ),
      );
      expect(
        messages(bare.workspace.problems(file)),
        anyElement(contains("did you mean 'title'?")),
      );
    });

    test('@Query outside a repository is left to the generic checks', () {
      final bare = EditorFixture.create(withAppMetadata: false);
      addTearDown(bare.dispose);
      final file = bare.open('lib/other.dart', '''
class Query {
  const Query(this.value);
  final String value;
}

class NotARepository {
  @Query('select :nothing')
  void run() {}
}
''');
      expect(bare.workspace.problems(file), isEmpty);
    });
  });

  group('completion', () {
    List<String> complete(String sql, String marker) {
      final text = _repository(_query(sql));
      final (other, otherPath) = dataFixture(source: text);
      addTearDown(other.dispose);
      final result = other.workspace.completion(otherPath, at(text, marker));
      return [for (final item in result?.items ?? <Completion>[]) item.label];
    }

    test('entities after {', () {
      expect(complete('select * from {', 'from {|'), [
        'Author',
        'Book',
        'Note',
      ]);
      expect(complete('select * from {Bo', 'from {Bo|'), [
        'Author',
        'Book',
        'Note',
      ]);
    });

    test('properties after {Entity.', () {
      final labels = complete('select {Book.', 'select {Book.|');
      expect(labels, containsAll(['id', 'title', 'year', 'inStock', 'author']));
      expect(labels, isNot(contains('cache'))); // @Transient
      expect(labels, isNot(contains('notes'))); // @MappedCollection
    });

    test('a property is closed with } unless it is there', () {
      final text = _repository(_query('select {Book.ti'));
      final (other, otherPath) = dataFixture(source: text);
      addTearDown(other.dispose);
      final result = other.workspace.completion(
        otherPath,
        at(text, 'select {Book.ti|'),
      )!;
      expect(
        result.items.firstWhere((i) => i.label == 'title').insertText,
        'title}',
      );
      // the range replaces what was typed
      expect(result.replace.endColumn - result.replace.startColumn, 2);
      final closed = _repository(_query('select {Book.ti}'));
      final (other2, path2) = dataFixture(source: closed);
      addTearDown(other2.dispose);
      final again = other2.workspace.completion(
        path2,
        at(closed, 'select {Book.ti|}'),
      )!;
      expect(
        again.items.firstWhere((i) => i.label == 'title').insertText,
        'title',
      );
    });

    test('method parameters after :, not Pageable', () {
      expect(complete('where year = :', 'where year = :|'), ['year']);
      expect(complete('where year = :ye', 'where year = :ye|'), ['year']);
    });

    test('not after :: (a cast), in a string or in a comment', () {
      expect(complete('select a::', 'select a::|'), isEmpty);
      expect(complete("where a = ':", "where a = ':|"), isEmpty);
      expect(complete('where a = 1 -- :', '-- :|'), isEmpty);
    });

    test('in :#{ the parameters as #name, then the beans', () {
      expect(
        complete('where a = :#{#', 'where a = :#{#|'),
        containsAll(['year', 'root', 'entityName']),
      );
      expect(
        complete('where a = :#{@', 'where a = :#{@|'),
        contains('mailer'),
      );
      expect(
        complete('where a = :#{@mailer.', '@mailer.|'),
        containsAll(['host', 'sent']),
      );
    });

    test('nothing outside a @Query', () {
      expect(
        fixture.workspace.completion(path, at(dataShopSource, 'class Au|thor')),
        isNull,
      );
    });
  });
}
