// Where the data starter's annotations may go (dataPlacements), and the
// mapping rules the build checks before the start does.
import 'package:test/test.dart';

import '../support/placements.dart';

void main() {
  group('misplaced', () {
    misplacedCases({
      '@Transactional on a private method': (
        '@Component() class Orders { @Transactional() void _save() {} '
            'void call() => _save(); }',
        [
          '@Transactional on Orders._save: a private member',
          'the transaction would not start',
        ],
      ),
      '@Transactional on an entity': (
        '@Table() class Book { @Id() int? id; @Transactional() void save() '
            '{} }',
        ['@Transactional on Book.save, and Book is no bean'],
      ),
      'a private @Version': (
        '@Table() class Book { @Id() int? id; @Version() int _version = 0; '
            'int get version => _version; }',
        ['@Version on the field Book._version', 'a private member is not'],
      ),
      'a static @Column': (
        "@Table() class Book { @Id() int? id; @Column('t') static String x = "
            "''; }",
        ['@Column on the field Book.x'],
      ),
      'an audit annotation on a getter without a setter': (
        '@Table() class Book { @Id() int? id; @CreatedDate() DateTime? get at '
            '=> null; }',
        ['@CreatedDate on the getter Book.at', 'computed, not stored'],
      ),
      'a mapping annotation on a class that is no entity': (
        'class Dto { @Id() int? id; }',
        ['@Id on the field Dto.id: Dto is no entity'],
      ),
      '@UniqueConstraint without @Table': (
        "@UniqueConstraint(['a']) class Plain { String a = ''; }",
        ['@UniqueConstraint on class Plain'],
      ),
      '@Query outside a repository': (
        "@Component() class Reports { @Query('select 1') Future<List<int>> "
            'all() async => []; }',
        ['@Query on Reports.all: queries are run by repositories'],
      ),
      '@Query in an interface that is no repository': (
        "abstract interface class Q { @Query('select 1') Future<List<int>> "
            'all(); }',
        [
          '@Query on Q.all: queries are run by repositories, and Q is no '
              'repository',
        ],
      ),
      '@UseStore on a component': (
        "@UseStore('memory') @Component() class S {}",
        ['@UseStore on class S: it chooses the store of a repository'],
      ),
      'a paging default off a handler': (
        '@Service() class S { void run(@PageableDefault() Pageable p) {} }',
        ['@PageableDefault on parameter p of S.run'],
      ),
      'two @Id (checked at build time, S8)': (
        '@Table() class Book { @Id() int? id; @Id() int? other; }',
        ['Book has more than one @Id: id, other'],
      ),
      'a @Version that is no int or DateTime': (
        "@Table() class Book { @Id() int? id; @Version() String v = ''; }",
        ['Book.v: @Version must be an int or a DateTime, not String'],
      ),
      'a @CreatedDate that is no DateTime': (
        '@Table() class Book { @Id() int? id; @CreatedDate() String? at; }',
        ['Book.at: @CreatedDate must be a DateTime, not String'],
      ),
      'a @UniqueConstraint over an unknown property': (
        "@Table() @UniqueConstraint(['nope']) class Book { @Id() int? id; }",
        ['@UniqueConstraint names nope, which is no property of Book'],
      ),
      '@Scope on a repository': (
        "@Table() class Book { @Id() int? id; }\n"
            "@Scope('prototype') abstract interface class Books implements "
            'CrudRepository<Book, int> {}',
        ['@Scope on Books: its bean is made by the starter'],
      ),
    });
  });

  placedCase('in their places they build', '''
@Table()
@UniqueConstraint(['title'])
class Book {
  @Id()
  int? id;
  String title = '';
  @Version()
  int version = 0;
  @CreatedDate()
  DateTime? created;
}

abstract interface class Books implements CrudRepository<Book, int> {
  @Query('select * from book')
  Future<List<Book>> everyone();
}

@Table()
class Note {
  @Id()
  int? id;
}

@UseStore('memory')
abstract interface class Notes implements CrudRepository<Note, int> {}

@Service()
class Shelf {
  @Transactional()
  Future<void> move() async {}
}
''');

  group('auditing, test and store annotations', () {
    misplacedCases({
      '@EnableDataAuditing on a class that is no bean': (
        '@EnableDataAuditing() class Plain {}',
        ['@EnableDataAuditing on class Plain: it is read'],
      ),
      '@Rollback in the application': (
        '@Component() class A { @Rollback() void m() {} }',
        ['@Rollback on A.m: it belongs on a @DataTest class'],
      ),
      '@Commit in the application': (
        'class A { @Commit() void m() {} }',
        ['@Commit on A.m: it belongs on a @DataTest class'],
      ),
      '@DataTest in the application': (
        '@DataTest() @Component() class A {}',
        ['@DataTest on class A: it belongs on a @DataTest class'],
      ),
      '@DataStoreDeclaration on a variable that is not constant': (
        '@DataStoreDeclaration() final store = Object();',
        ['@DataStoreDeclaration on store, in the top level'],
      ),
    });
  });

  placedCase('@EnableDataAuditing on a @Configuration class', '''
@EnableDataAuditing() @Configuration() class Audit {}
''');
}
