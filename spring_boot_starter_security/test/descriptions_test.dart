// What the security classes say about themselves in logs and debug output
// (matchers, chains, rejected requests, login details), and that the
// session id of a login never shows there. Plus the Or and Negated
// matchers' results, which only toString-based rules relied on.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'chain_support.dart';

MockServerHttpRequest _get(String target) =>
    MockServerHttpRequest(HttpMethod.get, target);

void main() {
  group('request matchers describe what they match', () {
    test('any request, path, method, header, media type', () {
      expect(AnyRequestMatcher.instance.toString(), 'any request');
      expect(
        PathPatternRequestMatcher('/api/**').toString(),
        'PathPattern [/api/**]',
      );
      expect(
        PathPatternRequestMatcher(
          '/api/**',
          method: HttpMethod.post,
        ).toString(),
        'PathPattern [POST /api/**]',
      );
      expect(
        const HttpMethodRequestMatcher(HttpMethod.delete).toString(),
        'method DELETE',
      );
      expect(
        const RequestHeaderRequestMatcher('X-Id').toString(),
        'header X-Id',
      );
      expect(
        const RequestHeaderRequestMatcher('X-Id', '7').toString(),
        'header X-Id=7',
      );
      expect(
        const MediaTypeRequestMatcher(['text/html']).toString(),
        'Accept [text/html]',
      );
    });

    test('and, or, not wrap what they combine', () {
      const get = HttpMethodRequestMatcher(HttpMethod.get);
      const post = HttpMethodRequestMatcher(HttpMethod.post);
      expect(
        AndRequestMatcher([get, post]).toString(),
        'And [method GET, method POST]',
      );
      expect(
        OrRequestMatcher([get, post]).toString(),
        'Or [method GET, method POST]',
      );
      expect(const NegatedRequestMatcher(get).toString(), 'Not [method GET]');
    });

    test('the CSRF matcher names the methods that need no token', () {
      expect(
        const DefaultRequiresCsrfMatcher().toString(),
        'CsrfNotRequired [GET, HEAD, TRACE, OPTIONS]',
      );
    });

    test('a chain names its matcher and its filters', () {
      final chain = DefaultSecurityFilterChain(
        PathPatternRequestMatcher('/api/**'),
        [AnonymousAuthenticationFilter()],
      );
      expect(
        chain.toString(),
        'DefaultSecurityFilterChain [RequestMatcher=PathPattern [/api/**], '
        'Filters=[AnonymousAuthenticationFilter]]',
      );
    });
  });

  group('OrRequestMatcher.matcher', () {
    final matcher = OrRequestMatcher([
      PathPatternRequestMatcher('/users/{id}'),
      PathPatternRequestMatcher('/books/{isbn}'),
    ]);

    test('gives the variables of the first matcher that matches', () {
      final result = matcher.matcher(_get('/books/978-0'));
      expect(result.isMatch, isTrue);
      expect(result.variables, {'isbn': '978-0'});
      expect(matcher.matcher(_get('/users/7')).variables, {'id': '7'});
    });

    test('does not match when none does, with no variables', () {
      final result = matcher.matcher(_get('/other/1'));
      expect(result.isMatch, isFalse);
      expect(result.variables, isEmpty);
      expect(matcher.matches(_get('/other/1')), isFalse);
    });

    test('an empty Or matches nothing, an empty And everything', () {
      expect(OrRequestMatcher(const []).matches(_get('/')), isFalse);
      expect(AndRequestMatcher(const []).matches(_get('/')), isTrue);
    });
  });

  group('NegatedRequestMatcher', () {
    test('matches what the other does not, and gives no variables', () {
      final matcher = NegatedRequestMatcher(
        PathPatternRequestMatcher('/a/{x}'),
      );
      expect(matcher.matches(_get('/b')), isTrue);
      expect(matcher.matches(_get('/a/1')), isFalse);
      expect(matcher.matcher(_get('/b')).isMatch, isTrue);
      expect(matcher.matcher(_get('/b')).variables, isEmpty);
    });
  });

  group('RequestRejectedException', () {
    test('toString gives the reason, for the logs', () {
      expect(
        RequestRejectedException('bad ;').toString(),
        'RequestRejectedException: bad ;',
      );
    });

    test('is a 400 Bad Request whatever the reason', () {
      final exception = RequestRejectedException('secret reason');
      expect(exception.statusCode, HttpStatus.badRequest);
    });
  });

  group('WebAuthenticationDetails.toString', () {
    test('shows the address and hides the session id', () async {
      final sessions = newSessions();
      final (request, _) = await exchange(sessions);
      final id = request.getSession()!.id;
      request.remoteAddress = '10.1.2.3';
      final text = WebAuthenticationDetails.of(request).toString();
      expect(text, contains('RemoteIpAddress=10.1.2.3'));
      expect(text, contains('SessionId=[PROTECTED]'));
      expect(text, isNot(contains(id)));
    });

    test('without a session there is nothing to hide', () {
      final request = _get('/')..remoteAddress = '10.1.2.3';
      expect(
        WebAuthenticationDetails.of(request).toString(),
        'WebAuthenticationDetails [RemoteIpAddress=10.1.2.3, SessionId=null]',
      );
    });
  });

  group('NullAuthenticatedSessionStrategy', () {
    test('leaves the session and its id alone', () async {
      final sessions = newSessions();
      final (request, response) = await exchange(sessions);
      final id = request.getSession()!.id;
      const NullAuthenticatedSessionStrategy().onAuthentication(
        UsernamePasswordAuthenticationToken.authenticated('ada', null, []),
        request,
        response,
      );
      expect(request.getSession(create: false)!.id, id);
    });
  });
}
