import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/src/client/rest/uri_template.dart';
import 'package:test/test.dart';

enum _Format { paperback }

void main() {
  group('UriTemplate', () {
    test('values by position, by name and alone', () {
      final template = UriTemplate('https://h/books/{isbn}/pages/{page}');
      expect(
        '${template.expand(['978-0', 12])}',
        'https://h/books/978-0/pages/12',
      );
      expect(
        '${template.expand({'page': 3, 'isbn': '1'})}',
        'https://h/books/1/pages/3',
      );
      expect('${UriTemplate('/b/{isbn}').expand('42')}', '/b/42');
    });

    test('a name used twice takes two positional values, one named', () {
      final template = UriTemplate('/{a}/{a}');
      expect('${template.expand(['x', 'y'])}', '/x/y');
      expect('${template.expand({'a': 'z'})}', '/z/z');
    });

    test('default values fill the names a map lacks', () {
      final template = UriTemplate('/{tenant}/books/{isbn}');
      expect(
        '${template.expand({'isbn': '1'}, {'tenant': 'eu'})}',
        '/eu/books/1',
      );
      expect(
        '${template.expand(null, {'tenant': 'eu', 'isbn': '2'})}',
        '/eu/books/2',
      );
    });

    test(
      'values are encoded strictly, the template text keeps its delimiters',
      () {
        final template = UriTemplate('/search/{term}?q={q}&lang=en#top');
        expect(
          '${template.expand(['a/b c', 'x&y=z+1 ü'])}',
          '/search/a%2Fb%20c?q=x%26y%3Dz%2B1%20%C3%BC&lang=en#top',
        );
        expect(
          '${UriTemplate('/a b/ü/%2F/50%').expand(null)}',
          '/a%20b/%C3%BC/%2F/50%25',
        );
      },
    );

    test('null, lists, dates and enums as text', () {
      final template = UriTemplate('/x?a={a}&b={b}&c={c}&d={d}');
      expect(
        '${template.expand([
          null,
          ['p', 'q'],
          DateTime.utc(2026, 11, 27),
          _Format.paperback,
        ])}',
        '/x?a=&b=p%2Cq&c=2026-11-27T00%3A00%3A00.000Z&d=paperback',
      );
    });

    test('a pattern after the name is ignored', () {
      expect(
        '${UriTemplate('/books/{isbn:[0-9]{3}}').expand(['978'])}',
        '/books/978',
      );
      expect(UriTemplate('/books/{isbn:[0-9]{3}}').variableNames, ['isbn']);
    });

    test('misuse: too few, too many, a missing name, an unclosed brace', () {
      final template = UriTemplate('/{a}/{b}');
      expect(() => template.expand(['x']), throwsArgumentError);
      expect(() => template.expand(['x', 'y', 'z']), throwsArgumentError);
      expect(() => template.expand({'a': 'x'}), throwsArgumentError);
      expect(() => template.expand('x'), throwsArgumentError);
      expect(() => template.expand(null), throwsArgumentError);
      expect(() => UriTemplate('/static').expand(['x']), throwsArgumentError);
      expect(() => UriTemplate('/{a'), throwsFormatException);
    });

    test('a path variable "." or ".." is refused, in a query it is data', () {
      final template = UriTemplate('/books/{id}?from={from}');
      expect(() => template.expand(['..', 'x']), throwsArgumentError);
      expect(() => template.expand(['.', 'x']), throwsArgumentError);
      expect('${template.expand(['a..b', '..'])}', '/books/a..b?from=..');
    });

    test('a template without variables is parsed once', () {
      final template = UriTemplate('https://h/books');
      expect(identical(template.expand(null), template.expand(null)), isTrue);
    });
  });

  group('UriBuilder', () {
    test('path, query parameters, fragment from a base URL', () {
      final uri = UriBuilder('https://api.neon.books/v1?key=k')
          .path('/books/')
          .path('{isbn}')
          .queryParam('author', 'Le Guin')
          .queryParam('tag', ['sf', 'a&b'])
          .queryParamIfPresent('year', null)
          .queryParamIfPresent('page', 2)
          .queryParam('flag')
          .fragment('top')
          .build(['978 0']);
      expect(
        '$uri',
        'https://api.neon.books/v1/books/978%200?key=k&author=Le%20Guin'
            '&tag=sf&tag=a%26b&page=2&flag#top',
      );
    });

    test('query values are data: their braces are no variables', () {
      expect(
        '${UriBuilder('/s').queryParam('q', 'a{b}').build()}',
        '/s?q=a%7Bb%7D',
      );
      expect(
        '${UriBuilder('/s').queryParam('q', '{q}').build({'q': 'x y'})}',
        '/s?q=x%20y',
      );
    });

    test('segments keep their slash encoded; replace methods', () {
      final builder = UriBuilder('https://h/a')
        ..pathSegment(['b/c', 'd'])
        ..queryParam('x', 1)
        ..replaceQueryParam('x', 2);
      expect('${builder.build()}', 'https://h/a/b%2Fc/d?x=2');
      builder
        ..replacePath('/z')
        ..host('other.h')
        ..port(8443)
        ..scheme('http');
      expect('${builder.build()}', 'http://other.h:8443/z?x=2');
    });
  });
}
