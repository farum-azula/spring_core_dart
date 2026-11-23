// Where the cache annotations may go (CacheGeneration.placements).
import 'package:test/test.dart';

import '../support/placements.dart';

void main() {
  group('misplaced', () {
    misplacedCases({
      'on a static method': (
        "@Component() class Books { @Cacheable('k') static int count() => 1; }",
        [
          '@Cacheable on Books.count: a static member',
          'nothing would be cached or evicted',
        ],
      ),
      'on a class that is no bean': (
        "class Plain { @CacheEvict('k') void clear() {} }",
        ['@CacheEvict on Plain.clear, and Plain is no bean'],
      ),
      'on an aspect': (
        "@Aspect() @Component() class Audit { @CachePut('k') int log() => 1; }",
        ['@CachePut on Audit.log, a bean the container does not proxy'],
      ),
      '@CacheConfig on a class without cache methods': (
        "@CacheConfig(cacheNames: ['books']) @Component() class Books { "
            'int count() => 1; }',
        ['@CacheConfig on class Books', 'Books has none'],
      ),
      'a syntax error in a key': (
        "@Component() class Books { @Cacheable('k', key: '#id +') int f(int "
            'id) => id; }',
        ["@Cacheable on Books.f: the key expression '#id +' is not valid SpEL"],
      ),
      'a syntax error in a condition': (
        "@Component() class Books { @CachePut('k', condition: '#id >') int "
            'f(int id) => id; }',
        ["@CachePut on Books.f: the condition expression '#id >'"],
      ),
      'a syntax error in unless': (
        "@Component() class Books { @Cacheable('k', unless: '#result ==') int "
            'f() => 1; }',
        ["@Cacheable on Books.f: the unless expression '#result =='"],
      ),
      'a syntax error of @CacheEvict': (
        "@Component() class Books { @CacheEvict('k', key: '(') void f() {} }",
        ["@CacheEvict on Books.f: the key expression '('"],
      ),
      'a syntax error inside @Caching': (
        '@Component() class Books { @Caching(evict: '
            "[CacheEvict('k', key: '#id +')]) void f(int id) {} }",
        ["@CacheEvict on Books.f: the key expression '#id +'"],
      ),
      'a syntax error of a composed annotation': (
        'class Keyed extends Cacheable { const Keyed() : '
            "super('k', key: '#id +'); }\n"
            '@Component() class Books { @Keyed() int f(int id) => id; }',
        ["@Keyed on Books.f: the key expression '#id +'"],
      ),
      'a syntax error on the class': (
        "@Cacheable('k', key: '#id +') @Component() class Books { int f(int "
            'id) => id; }',
        ["@Cacheable on class Books: the key expression '#id +'"],
      ),
      '@CacheConfig on a method': (
        "@Component() class Books { @CacheConfig(cacheNames: ['b']) void m() "
            '{} }',
        ['@CacheConfig on Books.m: it belongs on a class'],
      ),
    });
  });

  placedCase('valid expressions build', '''
@Component()
class Keys {
  @Cacheable('k', key: "#id + '-' + target.prefix", condition: '#id > 0',
      unless: '#result == null')
  int? find(int id) => id;
  String get prefix => 'p';
  @Caching(evict: [CacheEvict('k', key: '#id')], put: [CachePut('j', key: '#id')])
  int both(int id) => id;
}
''');

  placedCase('in their places they build', '''
@Component()
@CacheConfig(cacheNames: ['books'])
class Books {
  @Cacheable('books')
  int count() => 1;

  @CacheEvict('books')
  void clear() {}
}
''');
}
