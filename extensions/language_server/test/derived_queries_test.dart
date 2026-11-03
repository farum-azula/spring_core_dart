// Derived query methods (`findByTitleAndYearGreaterThan`, `countByAuthor`,
// ...): read with the grammar of the build, against the entity of the
// repository.
import 'package:test/test.dart';

import 'support/data_fixture.dart';
import 'support/editor_fixture.dart';

String _repository(String methods, {String header = ''}) =>
    '''
$dataShopSource
$header
abstract interface class CaseRepository
    implements ListCrudRepository<Book, int> {
$methods
}
''';

void main() {
  group('checks', () {
    List<String> check(String methods, {String header = ''}) {
      final (fixture, path) = dataFixture(
        source: _repository(methods, header: header),
      );
      addTearDown(fixture.dispose);
      return messages(fixture.workspace.problems(path));
    }

    test('the names of the shop are fine', () {
      final (fixture, path) = dataFixture();
      addTearDown(fixture.dispose);
      expect(fixture.workspace.problems(path), isEmpty);
    });

    test('every operator, Top, Distinct, Or, IgnoreCase and OrderBy', () {
      expect(
        check('''
  Future<List<Book>> findByTitleLike(String p);
  Future<List<Book>> findByTitleNotContainingIgnoreCase(String p);
  Future<List<Book>> findByYearBetween(int a, int b);
  Future<List<Book>> findByTitleIsNull();
  Future<List<Book>> findByInStockTrue();
  Future<List<Book>> findByYearIn(List<int> years);
  Future<List<Book>> findTop3ByOrderByYearDesc();
  Future<List<Book>> findDistinctByTitleOrYear(String t, int y);
  Future<List<Book>> findAllByOrderByTitleAsc();
  Stream<Book> streamByInStock(bool b);
  Future<Page<Book>> findByYearAfter(int y, Pageable page);
  Future<List<Book>> findByYearNot(int y, Sort sort);
'''),
        isEmpty,
      );
    });

    test('an unknown property: error on the property, with a suggestion', () {
      const methods = 'Future<List<Book>> findByTitelAndYear(String t, int y);';
      final (fixture, path) = dataFixture(source: _repository(methods));
      addTearDown(fixture.dispose);
      final problem = fixture.workspace.problems(path).single;
      expect(problem.error, isTrue);
      expect(problem.message, contains("No property 'titel' found"));
      expect(problem.message, contains("did you mean 'title'?"));
      final line = _repository(methods).split('\n')[problem.range.startLine];
      expect(
        line.substring(problem.range.startColumn, problem.range.endColumn),
        'Titel',
      );
    });

    test('also in OrderBy', () {
      final texts = check('Future<List<Book>> findByYearOrderByTitl(int y);');
      expect(texts.single, contains("did you mean 'title'?"));
    });

    test('a collection, a nested path', () {
      final texts = check('''
  Future<List<Book>> findByNotes(String n);
  Future<List<Book>> findByAuthorName(String n);
''');
      expect(texts, hasLength(2));
      expect(texts[0], contains('child entities'));
      expect(texts[1], contains('nested property path'));
    });

    test('the number of parameters, without Sort and Pageable', () {
      final texts = check('''
  Future<List<Book>> findByTitleAndYear(String title);
  Future<List<Book>> findByYearBetween(int a, int b, Pageable page);
''');
      expect(texts, hasLength(1));
      expect(texts.single, contains('needs 2 parameter(s)'));
      expect(texts.single, contains('declares 1'));
    });

    test('a method that is no derived query is a warning', () {
      final (fixture, path) = dataFixture(
        source: _repository('Future<void> doSomething();'),
      );
      addTearDown(fixture.dispose);
      final problem = fixture.workspace.problems(path).single;
      expect(problem.error, isFalse);
      expect(problem.message, contains('is not a derived query'));
    });

    test("the starter's own methods and @override are left alone", () {
      expect(
        check('''
  Future<Book?> findById(int id);
  Future<bool> existsById(int id);
  Future<int> count();
  Future<void> deleteAllById(Iterable<int> ids);
  @override
  Future<List<Book>> findAll();
'''),
        isEmpty,
      );
    });

    test('the entity comes through a base repository', () {
      expect(
        check(
          'Future<List<Book>> findByTitel(String t);',
          header: '''
abstract interface class BaseBookRepository
    implements ListCrudRepository<Book, int> {}
''',
        ),
        hasLength(1),
      );
      final (fixture, path) = dataFixture(
        source:
            '''
$dataShopSource
abstract interface class BaseBookRepository
    implements ListCrudRepository<Book, int> {}
abstract interface class DerivedRepository implements BaseBookRepository {
  Future<List<Book>> findByTitel(String t);
}
''',
      );
      addTearDown(fixture.dispose);
      expect(fixture.workspace.problems(path), hasLength(1));
    });

    test('an entity the editor cannot see completely is not checked', () {
      final (fixture, path) = dataFixture(
        source:
            '''
$dataShopSource
class Audited {}
@Table('things')
class Thing extends Audited {
  @Id()
  int? id;
  String name = '';
}
abstract interface class ThingRepository
    implements ListCrudRepository<Thing, int> {
  Future<List<Thing>> findByCreatedAt(int t);
  Future<List<Thing>> findByName(String t);
}
''',
      );
      addTearDown(fixture.dispose);
      // Audited is a class of the workspace without fields: complete, so
      // `createdAt` is unknown.
      expect(fixture.workspace.problems(path), hasLength(1));
      final (other, otherPath) = dataFixture(
        source:
            '''
$dataShopSource
@Table('things')
class Thing extends FromADependency {
  @Id()
  int? id;
}
abstract interface class ThingRepository
    implements ListCrudRepository<Thing, int> {
  Future<List<Thing>> findByCreatedAt(int t);
}
''',
      );
      addTearDown(other.dispose);
      expect(other.workspace.problems(otherPath), isEmpty);
    });
  });

  group('hover and navigation', () {
    late EditorFixture fixture;
    late String path;
    setUp(() {
      (fixture, path) = dataFixture();
    });
    tearDown(() => fixture.dispose());

    String? hover(String marker) =>
        fixture.workspace.hover(path, at(dataShopSource, marker));

    test('the name stands for a SQL', () {
      final text = hover('findByTitleA|ndYearGreaterThan')!;
      expect(text, contains('derived query of `Book`'));
      expect(
        text,
        contains(
          'select * from books where title = :title and year > :year',
        ),
      );
    });

    test('count, exists, delete, order and parameters of other names', () {
      expect(
        hover('count|ByAuthor'),
        contains('select count(*) from books where author = :author'),
      );
      expect(
        hover('exists|ByTitle'),
        contains('select 1 from books where title = :title limit 1'),
      );
      expect(
        hover('delete|ByYearLessThan'),
        contains('delete from books where year < :year'),
      );
      expect(
        hover('findByInStockOrd|erByYearDescTitleAsc'),
        contains(
          'select * from books where in_stock = :inStock '
          'order by year desc, title',
        ),
      );
    });

    test('a property of the name: its column and type', () {
      final text = hover('findByTitleAndYear|GreaterThan')!;
      expect(text, contains('**Book.year**'));
      expect(text, contains('column `year`'));
      expect(hover('findByTi|tleAndYear'), contains('**Book.title**'));
    });

    test('go to definition of the property goes to the field', () {
      final ranges = fixture.workspace.definition(
        path,
        at(dataShopSource, 'findByTitleAnd|YearGreaterThan'),
      );
      expect(ranges.single.startLine, _fieldLine('int year'));
      final inStock = fixture.workspace.definition(
        path,
        at(dataShopSource, 'findByInSto|ckOrderBy'),
      );
      expect(inStock.single.startLine, _fieldLine('bool inStock'));
    });

    test('ignore case, Top and Distinct show in the SQL', () {
      final (other, otherPath) = dataFixture(
        source: _repository('''
  Future<List<Book>> findDistinctTop2ByTitleIgnoreCaseOrYear(String t, int y);
'''),
      );
      addTearDown(other.dispose);
      final text = other.workspace.hover(
        otherPath,
        at(
          _repository(
            '  Future<List<Book>> '
            'findDistinctTop2ByTitleIgnoreCaseOrYear(String t, int y);',
          ),
          'findDistinct|Top2',
        ),
      )!;
      expect(text, contains('select distinct *'));
      expect(text, contains('lower(title) = lower(:t) or year = :y'));
      expect(text, contains('limit 2'));
    });
  });
}

int _fieldLine(String text) =>
    dataShopSource
        .substring(0, dataShopSource.indexOf(text))
        .split('\n')
        .length -
    1;
