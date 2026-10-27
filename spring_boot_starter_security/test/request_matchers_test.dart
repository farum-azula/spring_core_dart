// Request matchers on their own: the path variables an And matcher keeps,
// the header matcher's value test, and the media type matcher's default of
// "compatible", not "equal".
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

MockServerHttpRequest _get(String target, {Map<String, String>? headers}) {
  final request = MockServerHttpRequest(HttpMethod.get, target);
  headers?.forEach(request.headers.set);
  return request;
}

void main() {
  group('AndRequestMatcher.matcher', () {
    final matcher = AndRequestMatcher([
      const HttpMethodRequestMatcher(HttpMethod.get),
      PathPatternRequestMatcher('/users/{id}'),
    ]);

    test('matches with the path variables of its matchers', () {
      final result = matcher.matcher(_get('/users/42'));
      expect(result.isMatch, isTrue);
      expect(result.variables, {'id': '42'});
    });

    test('does not match when one matcher does not', () {
      final other = matcher.matcher(_get('/books/42'));
      expect(other.isMatch, isFalse);
      expect(other.variables, isEmpty);
      final post = matcher.matcher(
        MockServerHttpRequest(HttpMethod.post, '/users/42'),
      );
      expect(post.isMatch, isFalse);
    });
  });

  group('RequestHeaderRequestMatcher', () {
    test('without a value, any value of the header matches', () {
      const matcher = RequestHeaderRequestMatcher('X-Token');
      expect(matcher.matches(_get('/', headers: {'x-token': 'a'})), isTrue);
      expect(matcher.matches(_get('/')), isFalse);
    });

    test('with a value, only that value matches', () {
      const matcher = RequestHeaderRequestMatcher('X-Token', 'a');
      expect(matcher.matches(_get('/', headers: {'x-token': 'a'})), isTrue);
      expect(matcher.matches(_get('/', headers: {'x-token': 'b'})), isFalse);
      expect(matcher.matches(_get('/')), isFalse);
    });
  });

  group('MediaTypeRequestMatcher', () {
    test('is compatible, not equal, unless useEquals', () {
      const compatible = MediaTypeRequestMatcher(['application/json']);
      const equal = MediaTypeRequestMatcher([
        'application/json',
      ], useEquals: true);
      for (final accept in ['application/*', '*/*']) {
        final request = _get('/', headers: {'accept': accept});
        expect(compatible.matches(request), isTrue, reason: accept);
        expect(equal.matches(request), isFalse, reason: accept);
      }
      final exact = _get('/', headers: {'accept': 'application/json'});
      expect(compatible.matches(exact), isTrue);
      expect(equal.matches(exact), isTrue);
    });

    test('a type that is not accepted does not match', () {
      const matcher = MediaTypeRequestMatcher(['application/json']);
      expect(
        matcher.matches(_get('/', headers: {'accept': 'text/html'})),
        isFalse,
      );
    });
  });
}
