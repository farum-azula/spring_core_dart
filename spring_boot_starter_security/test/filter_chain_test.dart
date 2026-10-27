// The security context repositories on their own: what is stored in the
// session, that asking never starts a session, and what a delegating
// repository reports.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

final class _Exchange {
  _Exchange._(this.request, this.response);

  final MockServerHttpRequest request;
  final MockServerHttpResponse response;

  static Future<_Exchange> start([HttpSessionManager? manager]) async {
    final exchange = _Exchange._(
      MockServerHttpRequest(HttpMethod.get, '/'),
      MockServerHttpResponse(),
    );
    await (manager ?? _manager()).attach(exchange.request, exchange.response);
    return exchange;
  }

  static HttpSessionManager _manager() => HttpSessionManager(
    InMemoryHttpSessionRepository(),
    const HttpSessionProperties(),
  );

  bool get hasSession => request.getSession(create: false) != null;

  Object? get stored => request
      .getSession(create: false)
      ?.getAttribute(
        HttpSessionSecurityContextRepository.springSecurityContextKey,
      );
}

Authentication get _ada => UsernamePasswordAuthenticationToken.authenticated(
  'ada',
  null,
  AuthorityUtils.createAuthorityList(['ROLE_USER']),
);

Authentication get _anonymous => AnonymousAuthenticationToken(
  'key',
  'anonymousUser',
  AuthorityUtils.createAuthorityList(['ROLE_ANONYMOUS']),
);

void main() {
  const repository = HttpSessionSecurityContextRepository();

  group('HttpSessionSecurityContextRepository', () {
    test('stores an authenticated user and loads a copy', () async {
      final e = await _Exchange.start();
      final ada = _ada;
      repository.saveContext(SecurityContextImpl(ada), e.request, e.response);
      expect(e.stored, isA<SecurityContext>());
      final loaded = repository.loadContext(e.request)!;
      expect(loaded.authentication, same(ada));
      expect(loaded, isNot(same(e.stored)));
    });

    for (final (name, authentication) in <(String, Authentication?)>[
      ('anonymous', _anonymous),
      ('no', null),
    ]) {
      test('$name user: no session is started to store it', () async {
        final e = await _Exchange.start();
        repository.saveContext(
          SecurityContextImpl(authentication),
          e.request,
          e.response,
        );
        expect(e.hasSession, isFalse);
        expect(e.response.cookies, isEmpty);
        expect(repository.loadContext(e.request), isNull);
      });

      test('$name user: the stored context is removed', () async {
        final e = await _Exchange.start();
        repository.saveContext(
          SecurityContextImpl(_ada),
          e.request,
          e.response,
        );
        expect(repository.containsContext(e.request), isTrue);
        repository.saveContext(
          SecurityContextImpl(authentication),
          e.request,
          e.response,
        );
        expect(e.stored, isNull);
        expect(repository.containsContext(e.request), isFalse);
      });
    }

    test('containsContext is true only for a stored context', () async {
      final e = await _Exchange.start();
      expect(repository.containsContext(e.request), isFalse);
      repository.saveContext(SecurityContextImpl(_ada), e.request, e.response);
      expect(repository.containsContext(e.request), isTrue);
    });

    test('asking never starts a session', () async {
      final e = await _Exchange.start();
      expect(repository.containsContext(e.request), isFalse);
      expect(repository.loadContext(e.request), isNull);
      expect(e.hasSession, isFalse);
      expect(e.response.cookies, isEmpty);
    });

    test('a session without a context holds none', () async {
      final e = await _Exchange.start();
      e.request.getSession()!.setAttribute('other', 'x');
      expect(repository.containsContext(e.request), isFalse);
    });
  });

  group('DelegatingSecurityContextRepository.containsContext', () {
    const request = RequestAttributeSecurityContextRepository();
    const none = NullSecurityContextRepository();

    test('is true when any repository has a context', () async {
      final e = await _Exchange.start();
      request.saveContext(SecurityContextImpl(_ada), e.request, e.response);
      for (final repositories in [
        [none, request],
        [request, none],
        [request, repository],
        [repository, request],
      ]) {
        expect(
          DelegatingSecurityContextRepository(repositories)
              .containsContext(e.request),
          isTrue,
        );
      }
    });

    test('is false when none has one', () async {
      final e = await _Exchange.start();
      expect(
        DelegatingSecurityContextRepository([none, request, repository])
            .containsContext(e.request),
        isFalse,
      );
      expect(
        DelegatingSecurityContextRepository([]).containsContext(e.request),
        isFalse,
      );
    });
  });

  group('NullSecurityContextRepository', () {
    test('keeps nothing', () async {
      final e = await _Exchange.start();
      const none = NullSecurityContextRepository();
      none.saveContext(SecurityContextImpl(_ada), e.request, e.response);
      expect(none.loadContext(e.request), isNull);
      expect(none.containsContext(e.request), isFalse);
    });
  });
}
