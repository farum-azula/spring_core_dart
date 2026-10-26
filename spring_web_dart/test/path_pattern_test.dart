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
}
