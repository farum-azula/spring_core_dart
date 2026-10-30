import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

void main() {
  Map<String, String>? match(String pattern, String path) =>
      PathPattern.parse(pattern).match(path)?.variables;

  test('literals, variables and regexes', () {
    expect(match('/books', '/books'), isEmpty);
    expect(match('/books', '/books/'), isNull);
    expect(match('/books/{isbn}', '/books/978-0'), {'isbn': '978-0'});
    expect(match('/books/{isbn}', '/books'), isNull);
    expect(match(r'/books/{id:\d+}', '/books/12'), {'id': '12'});
    expect(match(r'/books/{id:\d+}', '/books/x'), isNull);
    expect(match(r'/v{major:\d+}.{minor:(\d+)}', '/v1.2'), {
      'major': '1',
      'minor': '2',
    });
    expect(match('/files/{name}.{ext}', '/files/a.txt'), {
      'name': 'a',
      'ext': 'txt',
    });
  });

  test('wildcards', () {
    expect(match('/static/*.css', '/static/a.css'), isEmpty);
    expect(match('/static/*.css', '/static/a/b.css'), isNull);
    expect(match('/b?ok', '/book'), isEmpty);
    expect(match('/static/**', '/static'), isEmpty);
    expect(match('/static/**', '/static/a/b'), isEmpty);
    expect(match('/files/{*path}', '/files/a/b%20c'), {'path': '/a/b c'});
    expect(match('/files/{*path}', '/files'), {'path': ''});
  });

  test('values are decoded, segments compared decoded', () {
    expect(match('/q/{text}', '/q/a%2Fb'), {'text': 'a/b'});
    expect(match('/a b', '/a%20b'), isEmpty);
  });

  test('malformed patterns', () {
    expect(() => PathPattern.parse('/**/x'), throwsFormatException);
    expect(() => PathPattern.parse('/{*a}/x'), throwsFormatException);
    expect(() => PathPattern.parse('/{a}/{a}'), throwsFormatException);
    expect(() => PathPattern.parse('/{a'), throwsFormatException);
  });

  test('combine and specificity', () {
    expect(
      PathPattern.parse('/api')
          .combine(PathPattern.parse('/books/{id}'))
          .pattern,
      '/api/books/{id}',
    );
    expect(
      PathPattern.parse('/').combine(PathPattern.parse('/x')).pattern,
      '/x',
    );
    final sorted = [
      '/books/**',
      '/books/{id}',
      '/books/new',
      '/books/{id}/{x}',
    ].map(PathPattern.parse).toList()..sort();
    expect(sorted.map((p) => p.pattern), [
      '/books/new',
      '/books/{id}',
      '/books/{id}/{x}',
      '/books/**',
    ]);
  });

  // Review before 0.5.0: `/api/books/1111;v=1` did not match
  // `/api/books/{isbn}` (Spring strips matrix parameters for matching).
  test('matrix parameters are left out of matching', () {
    final book = PathPattern.parse('/api/books/{isbn}');
    expect(book.match('/api/books/1111;v=1')?.variables, {'isbn': '1111'});
    expect(PathPattern.parse('/api/books').matches('/api;x=1/books'), isTrue);
    // An encoded semicolon is part of the value.
    expect(book.match('/api/books/a%3Bb')?.variables, {'isbn': 'a;b'});
    expect(
      PathPattern.parse('/files/{*rest}').match('/files/a;x/b')?.variables,
      {'rest': '/a/b'},
    );
  });

  // Second review before 0.5.0: an escape that is not UTF-8 threw a
  // FormatException (a 500); it is matched as written.
  test('an escape that is not UTF-8 is matched as written', () {
    final file = PathPattern.parse('/files/{name}');
    expect(file.match('/files/%FF')?.variables, {'name': '%FF'});
    expect(file.match('/files/%C0%AF')?.variables, {'name': '%C0%AF'});
    expect(file.match('/files/%G1')?.variables, {'name': '%G1'});
  });
}
