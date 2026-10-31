// The sessions per user: SessionRegistryImpl over the in-memory session
// repository and the strategies of a login (ConcurrentSessionControl...,
// RegisterSession...). One account cannot hold more than its sessions.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

Authentication _user(String name) =>
    UsernamePasswordAuthenticationToken.authenticated(name, null, const []);

void main() {
  late InMemoryHttpSessionRepository repository;
  late SessionRegistryImpl registry;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 10, 31, 12);
    repository = InMemoryHttpSessionRepository(clock: () => now);
    registry = SessionRegistryImpl(repository, clock: () => now);
  });

  // A login in a new browser (a request without a session), or in the
  // browser of [sessionId].
  Future<String> login(
    Authentication user,
    SessionAuthenticationStrategy strategy, {
    String? sessionId,
  }) async {
    final request = MockServerHttpRequest(HttpMethod.post, '/login');
    if (sessionId != null) {
      request.addCookie('JSESSIONID', sessionId);
    }
    final response = MockServerHttpResponse();
    await HttpSessionManager(
      repository,
      const HttpSessionProperties(),
    ).attach(request, response);
    await strategy.onAuthentication(user, request, response);
    now = now.add(const Duration(seconds: 1));
    return request.getSession(create: false)!.id;
  }

  SessionAuthenticationStrategy limit(int maximum, {bool refuse = false}) =>
      CompositeSessionAuthenticationStrategy([
        ConcurrentSessionControlAuthenticationStrategy(
          registry,
          maximumSessions: maximum,
          exceptionIfMaximumExceeded: refuse,
        ),
        const ChangeSessionIdAuthenticationStrategy(),
        RegisterSessionAuthenticationStrategy(registry),
      ]);

  test('above the limit the least recently used sessions end', () async {
    final strategy = limit(2);
    final first = await login(_user('ada'), strategy);
    final second = await login(_user('ada'), strategy);
    final third = await login(_user('ada'), strategy);
    expect(repository.findById(first), isNull);
    expect(repository.findById(second), isNotNull);
    expect(repository.findById(third), isNotNull);
    expect(
      [
        for (final s in await registry.getAllSessions(_user('ada')))
          s.sessionId,
      ],
      [second, third],
    );
  });

  test(
    'maxSessionsPreventsLogin: the new login fails, the others stay',
    () async {
      final strategy = limit(1, refuse: true);
      final first = await login(_user('ada'), strategy);
      await expectLater(
        login(_user('ada'), strategy),
        throwsA(isA<SessionAuthenticationException>()),
      );
      expect(repository.findById(first), isNotNull);
      // Once it is logged out, the next login is let in.
      repository.deleteById(first);
      await login(_user('ada'), strategy);
    },
  );

  test('logging in again in the same browser takes no new place', () async {
    final strategy = limit(1, refuse: true);
    final first = await login(_user('ada'), strategy);
    final again = await login(_user('ada'), strategy, sessionId: first);
    expect(again, isNot(first), reason: 'a new id at login (fixation)');
    expect((await registry.getAllSessions(_user('ada'))).length, 1);
  });

  test(
    'users are counted apart, by name and by where the login came from',
    () async {
      final strategy = limit(1, refuse: true);
      await login(_user('ada'), strategy);
      await login(_user('root'), strategy);
      final provider = OAuth2AuthenticationToken(
        DefaultOAuth2User(const [], const {'sub': 'ada'}, 'sub'),
        const [],
        'keycloak',
      );
      await login(provider, strategy);
      expect(
        SessionRegistry.principalKey(provider),
        isNot(SessionRegistry.principalKey(_user('ada'))),
      );
    },
  );

  test('ended and expired sessions are forgotten', () async {
    final strategy = limit(5);
    final ended = await login(_user('ada'), strategy);
    await login(_user('ada'), strategy);
    repository.deleteById(ended);
    expect((await registry.getAllSessions(_user('ada'))).length, 1);
    now = now.add(const Duration(hours: 1)); // past the 30 minutes
    expect(await registry.getAllSessions(_user('ada')), isEmpty);
  });

  test('-1: no limit', () async {
    final strategy = limit(-1);
    for (var i = 0; i < 20; i++) {
      await login(_user('ada'), strategy);
    }
    expect(repository.size, 20);
  });

  test('maximumSessions refuses 0 and values below -1', () {
    final http = HttpSecurity(null);
    expect(
      () => http.sessionManagement((s) => s.maximumSessions(0)),
      throwsArgumentError,
    );
    expect(
      () => http.sessionManagement((s) => s.maximumSessions(-2)),
      throwsArgumentError,
    );
  });
}
