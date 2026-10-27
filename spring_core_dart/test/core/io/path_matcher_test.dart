import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

// Cases ported from Spring's AntPathMatcherTests.
void main() {
  final m = AntPathMatcher();

  test('match', () {
    expect(m.match('test', 'test'), isTrue);
    expect(m.match('/test', '/test'), isTrue);
    expect(m.match('/test.jpg', 'test.jpg'), isFalse);
    expect(m.match('test', '/test'), isFalse);
    expect(m.match('/test', 'test'), isFalse);
    expect(m.match('t?st', 'test'), isTrue);
    expect(m.match('??st', 'test'), isTrue);
    expect(m.match('tes?', 'tes'), isFalse);
    expect(m.match('tes?', 'testt'), isFalse);
    expect(m.match('*', 'test'), isTrue);
    expect(m.match('test*', 'testTest'), isTrue);
    expect(m.match('test/*', 'test/Test'), isTrue);
    expect(m.match('test/*', 'test/'), isTrue);
    expect(m.match('test/*', 'test'), isFalse);
    expect(m.match('*test*', 'AnothertestTest'), isTrue);
    expect(m.match('*.*', 'test.test'), isTrue);
    expect(m.match('*.*', 'tsttst'), isFalse);
    expect(m.match('/????', '/bala/bla'), isFalse);
    expect(m.match('/**', '/testing/testing'), isTrue);
    expect(m.match('/*/**', '/testing/testing'), isTrue);
    expect(m.match('/**/*', '/testing/testing'), isTrue);
    expect(m.match('/bla/**/bla', '/bla/testing/testing/bla'), isTrue);
    expect(m.match('/bla/**/bla', '/bla/testing/testing/bla/bla'), isTrue);
    expect(m.match('/**/test', '/bla/bla/test'), isTrue);
    expect(m.match('/bla/**/**/bla', '/bla/bla/bla/bla/bla/bla'), isTrue);
    expect(m.match('/bla*bla/test', '/blaXXXbla/test'), isTrue);
    expect(m.match('/*bla/test', '/XXXbla/test'), isTrue);
    expect(m.match('/bla*bla/test', '/blaXXXbl/test'), isFalse);
    expect(m.match('/*bla/test', 'XXXblab/test'), isFalse);
    expect(m.match('/*bla/test', 'XXXbl/test'), isFalse);
    expect(m.match('/????', '/bala'), isTrue);
    expect(m.match('/**/*bla', '/bla/bla/bla/bbb'), isFalse);
    expect(
      m.match(
        '/*bla*/**/bla/**',
        '/XXXblaXXXX/testing/testing/bla/testing/testing/',
      ),
      isTrue,
    );
    expect(
      m.match('/*bla*/**/bla/*', '/XXXblaXXXX/testing/testing/bla/testing'),
      isTrue,
    );
    expect(
      m.match(
        '/*bla*/**/bla/**',
        '/XXXblaXXXX/testing/testing/bla/testing/testing.jpg',
      ),
      isTrue,
    );
    expect(
      m.match(
        '*bla*/**/bla/**',
        'XXXblaXXXX/testing/testing/bla/testing/testing/',
      ),
      isTrue,
    );
    expect(
      m.match('*bla*/**/bla/*', 'XXXblaXXXX/testing/testing/bla/testing'),
      isTrue,
    );
    expect(
      m.match(
        '*bla*/**/bla/*',
        'XXXblaXXXX/testing/testing/bla/testing/testing',
      ),
      isFalse,
    );
    expect(m.match('/x/x/**/bla', '/x/x/x/'), isFalse);
    expect(m.match('/foo/bar/**', '/foo/bar'), isTrue);
    expect(m.match('', ''), isTrue);
    expect(m.match('/{bla}.*', '/testing.html'), isTrue);
    expect(m.match('/{bla}', '//x\ny'), isTrue);
    expect(m.match('/x/**/y/**/z', '/x/a/y/b'), isFalse);
    expect(m.match('/x/*', '/x/a/'), isFalse);
  });

  test('matchStart', () {
    expect(m.matchStart('test', 'test'), isTrue);
    expect(m.matchStart('test/*', 'test'), isTrue);
    expect(m.matchStart('/test/**', '/test'), isTrue);
    expect(m.matchStart('/bla/**/bla', '/bla/testing'), isTrue);
    expect(m.matchStart('/x/x/**/bla', '/x/x/x/'), isTrue);
    expect(m.matchStart('/foo/bar', '/foo'), isTrue);
    expect(m.matchStart('/foo', '/foo/bar'), isFalse);
    expect(m.matchStart('/bla', '/blub'), isFalse);
    expect(m.matchStart('/**/x', '/a/b'), isTrue);
  });

  test('case insensitive and trimmed tokens', () {
    final insensitive = AntPathMatcher(caseSensitive: false);
    expect(
      insensitive.match('/group/{groupName}/members', '/Group/Sales/Members'),
      isTrue,
    );
    expect(insensitive.match('/Test', '/test'), isTrue);
    final trimming = AntPathMatcher(trimTokens: true);
    expect(trimming.match('/foo/bar', '/foo /bar'), isTrue);
  });

  test('custom separator', () {
    final dots = AntPathMatcher(pathSeparator: '.');
    expect(dots.match('test.*', 'test.foo'), isTrue);
    expect(dots.match('test.**.bar', 'test.a.b.bar'), isTrue);
  });

  test('pattern cache turns off after the threshold', () {
    final matcher = AntPathMatcher();
    for (var i = 0; i < AntPathMatcher.cacheTurnoffThreshold; i++) {
      matcher.match('/p$i*', '/p${i}x');
    }
    expect(matcher.cachedPatternCount, AntPathMatcher.cacheTurnoffThreshold);
    expect(matcher.match('/one*', '/onemore'), isTrue);
    expect(matcher.cachedPatternCount, 0, reason: 'cleared and disabled');
    expect(matcher.match('/two*', '/two'), isTrue);
    expect(matcher.cachedPatternCount, 0);
  });

  test('isPattern', () {
    expect(m.isPattern('/test/*'), isTrue);
    expect(m.isPattern('/te?t'), isTrue);
    expect(m.isPattern('/{name}'), isTrue);
    expect(m.isPattern('/test{'), isFalse);
    expect(m.isPattern('/plain'), isFalse);
  });

  test('extractPathWithinPattern', () {
    const cases = [
      ('/docs/commit.html', '/docs/commit.html', ''),
      ('/docs/*', '/docs/cvs/commit', 'cvs/commit'),
      ('/docs/cvs/*.html', '/docs/cvs/commit.html', 'commit.html'),
      ('/docs/**', '/docs/cvs/commit', 'cvs/commit'),
      ('/docs/**/*.html', '/docs/cvs/commit.html', 'cvs/commit.html'),
      ('/docs/**/*.html', '/docs/commit.html', 'commit.html'),
      ('/*.html', '/commit.html', 'commit.html'),
      ('/*.html', '/docs/commit.html', 'docs/commit.html'),
      ('*.html', '/commit.html', '/commit.html'),
      ('*.html', '/docs/commit.html', '/docs/commit.html'),
      ('**/*.*', '/docs/commit.html', '/docs/commit.html'),
      ('*', '/docs/commit.html', '/docs/commit.html'),
      (
        '**/commit.html',
        '/docs/cvs/other/commit.html',
        '/docs/cvs/other/commit.html',
      ),
      (
        '/docs/**/commit.html',
        '/docs/cvs/other/commit.html',
        'cvs/other/commit.html',
      ),
      (
        '/docs/**/**/**/**',
        '/docs/cvs/other/commit.html',
        'cvs/other/commit.html',
      ),
      ('/d?cs/*', '/docs/cvs/commit', 'docs/cvs/commit'),
      ('/docs/c?s/*.html', '/docs/cvs/commit.html', 'cvs/commit.html'),
      ('/d?cs/**', '/docs/cvs/commit', 'docs/cvs/commit'),
      ('/d?cs/**/*.html', '/docs/cvs/commit.html', 'docs/cvs/commit.html'),
    ];
    for (final (pattern, path, expected) in cases) {
      expect(
        m.extractPathWithinPattern(pattern, path),
        expected,
        reason: '$pattern $path',
      );
    }
  });

  test('extractUriTemplateVariables', () {
    expect(m.extractUriTemplateVariables('/hotels/{hotel}', '/hotels/1'), {
      'hotel': '1',
    });
    expect(m.extractUriTemplateVariables('/h?tels/{hotel}', '/hotels/1'), {
      'hotel': '1',
    });
    expect(
      m.extractUriTemplateVariables(
        '/hotels/{hotel}/bookings/{booking}',
        '/hotels/1/bookings/2',
      ),
      {'hotel': '1', 'booking': '2'},
    );
    expect(
      m.extractUriTemplateVariables(
        '/**/hotels/**/{hotel}',
        '/foo/hotels/bar/1',
      ),
      {'hotel': '1'},
    );
    expect(m.extractUriTemplateVariables('/{page}.html', '/42.html'), {
      'page': '42',
    });
    expect(
      m.extractUriTemplateVariables(
        r'/{symbolicName:[\w\.]+}-{version:[\w\.]+}.jar',
        '/com.example-1.0.0.jar',
      ),
      {'symbolicName': 'com.example', 'version': '1.0.0'},
    );
    expect(
      () => m.extractUriTemplateVariables('/a/{x}', '/b/1'),
      throwsStateError,
    );
    expect(
      () => m.extractUriTemplateVariables('/{x}/{x}', '/1/2'),
      throwsArgumentError,
    );
    expect(
      () => m.extractUriTemplateVariables('/{x:(a|b)}', '/a'),
      throwsArgumentError,
    );
  });

  test('combine', () {
    expect(m.combine('', ''), '');
    expect(m.combine('/hotels', ''), '/hotels');
    expect(m.combine('', '/hotels'), '/hotels');
    expect(m.combine('/hotels/*', 'booking'), '/hotels/booking');
    expect(m.combine('/hotels/*', '/booking'), '/hotels/booking');
    expect(m.combine('/hotels/**', 'booking'), '/hotels/**/booking');
    expect(m.combine('/hotels/**', '/booking'), '/hotels/**/booking');
    expect(m.combine('/hotels', '/booking'), '/hotels/booking');
    expect(m.combine('/hotels', 'booking'), '/hotels/booking');
    expect(m.combine('/hotels/', 'booking'), '/hotels/booking');
    expect(m.combine('/hotels/', '/booking'), '/hotels/booking');
    expect(m.combine('/hotels/*', '{hotel}'), '/hotels/{hotel}');
    expect(m.combine('/hotels/**', '{hotel}'), '/hotels/**/{hotel}');
    expect(m.combine('/hotels', '{hotel}'), '/hotels/{hotel}');
    expect(m.combine('/hotels', '{hotel}.*'), '/hotels/{hotel}.*');
    expect(
      m.combine('/hotels/*/booking', '{booking}'),
      '/hotels/*/booking/{booking}',
    );
    expect(m.combine('/*.html', '/hotel.html'), '/hotel.html');
    expect(m.combine('/*.html', '/hotel'), '/hotel.html');
    expect(m.combine('/*.html', '/hotel.*'), '/hotel.html');
    expect(m.combine('/**', '/*.html'), '/*.html');
    expect(m.combine('/*', '/*.html'), '/*.html');
    expect(m.combine('/*.*', '/*.html'), '/*.html');
    expect(m.combine('/{foo}', '/bar'), '/{foo}/bar');
    expect(m.combine('/user', '/user'), '/user/user');
    expect(m.combine('/{foo:.*[^0-9].*}', '/edit/'), '/{foo:.*[^0-9].*}/edit/');
    expect(m.combine('/1.0', '/foo/test'), '/1.0/foo/test');
    expect(m.combine('/', '/hotel'), '/hotel');
    expect(m.combine('/hotel/', '/booking'), '/hotel/booking');
    expect(() => m.combine('/*.html', '/*.txt'), throwsArgumentError);
    expect(AntPathMatcher(pathSeparator: '.').combine('a.*', 'b'), 'a.b');
  });

  test('pattern comparator', () {
    final c = m.getPatternComparator('/hotels/new');
    expect(c('/hotels/new', '/hotels/new'), 0);
    expect(c('/hotels/new', '/hotels/*'), lessThan(0));
    expect(c('/hotels/*', '/hotels/new'), greaterThan(0));
    expect(c('/hotels/*', '/hotels/*'), 0);
    expect(c('/hotels/new', '/hotels/{hotel}'), lessThan(0));
    expect(c('/hotels/{hotel}', '/hotels/*'), lessThan(0));
    expect(c('/hotels/*', '/hotels/{hotel}'), greaterThan(0));
    expect(
      c('/hotels/{hotel}/booking', '/hotels/{hotel}/bookings/{booking}'),
      lessThan(0),
    );
    expect(c('/**', '/**'), 0);
    expect(c('/**', '/hotels/*'), greaterThan(0));
    expect(c('/hotels/*', '/**'), lessThan(0));
    expect(c('/hotels/**', '/hotels/*'), greaterThan(0));
    expect(c('/hotels/*', '/hotels/**'), lessThan(0));
    expect(c('/hotels/a/**', '/hotels/**'), lessThan(0));
    expect(c('/hotels/**', '/hotels/a/**'), greaterThan(0));
    expect(c('/hotels/{hotel}', '/hotels/{hotel}.*'), 2); // SPR-6741
    expect(c('/hotels/ne*', '/hotels/n*'), lessThan(0));
    expect(c('/hotels/*', '/hotels/{a}'), greaterThan(0));
    expect(c('/x/{a}', '/x/{b}'), 0);
    expect(c('/a/{b}/c', '/a/*/c'), lessThan(0));
    expect(c('/a/*/{c}', '/a/{b}/*'), 0);
    expect(c('/a/**/b', '/a/*/b'), greaterThan(0));
    final sorted = ['/hotels/**', '/hotels/new', '/hotels/{hotel}', '/**']
      ..sort(c);
    expect(sorted, ['/hotels/new', '/hotels/{hotel}', '/hotels/**', '/**']);
    final other = m.getPatternComparator('/hotels/x');
    expect(other('/hotels/new', '/hotels/new'), 0);
  });
}
