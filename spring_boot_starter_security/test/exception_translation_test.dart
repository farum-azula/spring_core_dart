// ExceptionTranslationFilter and the delegating handlers on their own: what
// each security exception becomes (a login challenge for the anonymous and
// for failed authentication, a 403 for a logged-in user), that the request
// is saved and the context cleared before asking to log in, that nothing is
// asked of a response already sent, and which handler or entry point a
// request is given.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

final class _Throws implements WebFilterChain {
  _Throws(this.error);

  final Object error;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) => Future.error(error);
}

final class _Entry implements AuthenticationEntryPoint {
  _Entry(this.name, this.log);

  final String name;
  final List<String> log;
  AuthenticationException? reason;
  Authentication? userSeen;

  @override
  void commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  ) {
    reason = authException;
    userSeen = SecurityContextHolder.getContext().authentication;
    log.add('entry $name');
  }
}

final class _Denied implements AccessDeniedHandler {
  _Denied(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  void handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AccessDeniedException accessDeniedException,
  ) => log.add('denied $name');
}

final class _Saves implements RequestCache {
  final saved = <String>[];

  @override
  void saveRequest(ServerHttpRequest request, ServerHttpResponse response) =>
      saved.add(request.path);

  @override
  String? getRedirectUrl(ServerHttpRequest request) => null;

  @override
  void removeRequest(ServerHttpRequest request, ServerHttpResponse response) {}
}

Authentication get _ada =>
    UsernamePasswordAuthenticationToken.authenticated('ada', null, []);

Authentication get _anonymous => AnonymousAuthenticationToken(
  'key',
  'anonymousUser',
  AuthorityUtils.createAuthorityList(['ROLE_ANONYMOUS']),
);

MockServerHttpRequest _get(
  String path, {
  Map<String, String> headers = const {},
}) {
  final request = MockServerHttpRequest(HttpMethod.get, path);
  headers.forEach(request.headers.set);
  return request;
}

void main() {
  group('ExceptionTranslationFilter', () {
    late List<String> log;
    late _Entry entry;
    late _Saves cache;
    late ExceptionTranslationFilter filter;

    setUp(() {
      log = [];
      entry = _Entry('login', log);
      cache = _Saves();
      filter = ExceptionTranslationFilter(
        entry,
        accessDeniedHandler: _Denied('403', log),
        requestCache: cache,
      );
    });

    Future<MockServerHttpResponse> run(
      Object error, {
      Authentication? user,
      MockServerHttpResponse? response,
    }) => SecurityContextHolder.runWithContext(() async {
      SecurityContextHolder.getContext().authentication = user;
      final result = response ?? MockServerHttpResponse();
      await filter.doFilter(_get('/secret'), result, _Throws(error));
      return result;
    });

    test('a failed authentication asks to log in, with the reason', () async {
      final reason = BadCredentialsException('no');
      await run(reason, user: _ada);
      expect(log, ['entry login']);
      expect(entry.reason, same(reason));
    });

    test('the request is saved and the user forgotten first', () async {
      await run(BadCredentialsException('no'), user: _ada);
      expect(cache.saved, ['/secret']);
      expect(entry.userSeen, isNull, reason: 'the context was cleared');
    });

    test('a missing authentication asks to log in as well', () async {
      await run(AuthenticationCredentialsNotFoundException('none'));
      expect(log, ['entry login']);
    });

    test('a denial for no one or an anonymous user asks to log in', () async {
      for (final user in [null, _anonymous]) {
        log.clear();
        await run(AccessDeniedException('no'), user: user);
        expect(log, ['entry login'], reason: '$user');
        expect(entry.reason, isA<InsufficientAuthenticationException>());
        expect(
          entry.reason!.message,
          'Full authentication is required to access this resource',
        );
      }
    });

    test('a denial for a logged-in user is a 403, nothing is saved', () async {
      await run(AccessDeniedException('no'), user: _ada);
      expect(log, ['denied 403']);
      expect(cache.saved, isEmpty);
    });

    test('other errors go on, not swallowed', () async {
      await expectLater(run(StateError('bug'), user: _ada), throwsStateError);
      expect(log, isEmpty);
    });

    test('a response already sent is not asked to authenticate', () async {
      final response = MockServerHttpResponse();
      await response.close();
      await run(BadCredentialsException('no'), user: _ada, response: response);
      expect(log, isEmpty);
      expect(cache.saved, isEmpty);
    });

    test('nothing is thrown: the chain goes on untouched', () async {
      await SecurityContextHolder.runWithContext(() async {
        final chain = _Passes();
        await filter.doFilter(_get('/'), MockServerHttpResponse(), chain);
        expect(chain.reached, isTrue);
      });
      expect(log, isEmpty);
    });
  });

  group('DelegatingAccessDeniedHandler', () {
    test('the first matching handler answers', () async {
      final log = <String>[];
      await DelegatingAccessDeniedHandler([
        (PathPatternRequestMatcher('/api/**'), _Denied('api', log)),
        (AnyRequestMatcher.instance, _Denied('any', log)),
      ], defaultHandler: _Denied('default', log)).handle(
        _get('/api/x'),
        MockServerHttpResponse(),
        AccessDeniedException('n'),
      );
      expect(log, ['denied api']);
    });

    test('the default handler answers the rest', () async {
      final log = <String>[];
      await DelegatingAccessDeniedHandler([
        (PathPatternRequestMatcher('/api/**'), _Denied('api', log)),
      ], defaultHandler: _Denied('default', log)).handle(
        _get('/web'),
        MockServerHttpResponse(),
        AccessDeniedException('n'),
      );
      expect(log, ['denied default']);
    });

    test('without handlers of its own: a 403 problem', () async {
      final response = MockServerHttpResponse();
      await DelegatingAccessDeniedHandler(const [])
          .handle(_get('/web'), response, AccessDeniedException('n'));
      expect(response.statusCode, 403);
      expect(response.headers['content-type'], contains('problem+json'));
    });
  });

  group('DelegatingAuthenticationEntryPoint', () {
    test('picks by request, else the default', () async {
      final log = <String>[];
      final delegating = DelegatingAuthenticationEntryPoint([
        (
          const RequestHeaderRequestMatcher('X-Requested-With'),
          _Entry('ajax', log),
        ),
        (PathPatternRequestMatcher('/api/**'), _Entry('api', log)),
      ], defaultEntryPoint: _Entry('page', log));
      final response = MockServerHttpResponse();
      final reason = BadCredentialsException('n');
      await delegating.commence(_get('/api/x'), response, reason);
      await delegating.commence(
        _get('/api/x', headers: {'X-Requested-With': 'XMLHttpRequest'}),
        response,
        reason,
      );
      await delegating.commence(_get('/home'), response, reason);
      expect(log, ['entry api', 'entry ajax', 'entry page']);
    });
  });
}

final class _Passes implements WebFilterChain {
  bool reached = false;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    reached = true;
  }
}
