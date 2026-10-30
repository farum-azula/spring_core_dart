// Sessions: the cookie and its flags, the client never choosing an id
// (session fixation), id rotation, invalidation, expiry and the limit.
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final app = springBootTest(
    testApplication,
    properties: {'logging.level.root': 'warn'},
  );

  /// The session cookie a response set, or `null`.
  ResponseCookie? sessionCookie(MvcResult result) =>
      result.response.cookies.where((c) => c.name == 'JSESSIONID').lastOrNull;

  Map<String, String> withSession(String id) => {'cookie': 'JSESSIONID=$id'};

  test('a session starts with a secure-by-default cookie', () async {
    final result = await app.mockMvc
        .get('/session/count')
        .andExpect(status: 200, json: 1);
    final cookie = sessionCookie(result)!;
    expect(cookie.httpOnly, isTrue);
    expect(cookie.sameSite, 'Lax');
    expect(cookie.path, '/');
    expect(cookie.value, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
  });

  test('the cookie brings the session back; no new cookie', () async {
    final first = await app.mockMvc.get('/session/count');
    final id = sessionCookie(first)!.value;
    final second = await app.mockMvc
        .get('/session/count', headers: withSession(id))
        .andExpect(json: 2);
    expect(sessionCookie(second), isNull);
  });

  test('an unknown id is never adopted (session fixation)', () async {
    const planted = 'attacker-chosen-id';
    final result = await app.mockMvc
        .get('/session/count', headers: withSession(planted))
        .andExpect(json: 1);
    expect(sessionCookie(result)!.value, isNot(planted));
  });

  test('reading without create makes no session', () async {
    final result = await app.mockMvc
        .get('/session/peek')
        .andExpect(json: false);
    expect(sessionCookie(result), isNull);
  });

  test('rotating the id: the old one stops working', () async {
    final id = sessionCookie(await app.mockMvc.get('/session/count'))!.value;
    final rotated = await app.mockMvc.post(
      '/session/rotate',
      headers: withSession(id),
    );
    final newId = sessionCookie(rotated)!.value;
    expect(newId, isNot(id));
    await app.mockMvc
        .get('/session/count', headers: withSession(newId))
        .andExpect(json: 2);
    await app.mockMvc
        .get('/session/count', headers: withSession(id))
        .andExpect(json: 1);
  });

  test('an invalidated session is gone', () async {
    final id = sessionCookie(await app.mockMvc.get('/session/count'))!.value;
    await app.mockMvc.post('/session/invalidate', headers: withSession(id));
    await app.mockMvc
        .get('/session/peek', headers: withSession(id))
        .andExpect(json: false);
  });

  group('the in-memory repository', () {
    test('sessions expire after their timeout', () {
      var now = DateTime(2026);
      final repository = InMemoryHttpSessionRepository(clock: () => now);
      final session = repository.createSession()..setAttribute('a', 1);
      now = now.add(const Duration(minutes: 29));
      expect(repository.findById(session.id), same(session));
      session.touch(now);
      now = now.add(const Duration(minutes: 31));
      expect(repository.findById(session.id), isNull);
      expect(session.isInvalidated, isTrue);
      expect(() => session.getAttribute('a'), throwsStateError);
    });

    test('the limit drops the least recently used session', () {
      final repository = InMemoryHttpSessionRepository(maxSessions: 2);
      final a = repository.createSession();
      final b = repository.createSession();
      repository.findById(a.id); // a used last
      final c = repository.createSession();
      expect(repository.size, 2);
      expect(repository.findById(b.id), isNull);
      expect(repository.findById(a.id), same(a));
      expect(repository.findById(c.id), same(c));
    });

    test('the limit first drops a session its client never came back '
        'with', () {
      final repository = InMemoryHttpSessionRepository(maxSessions: 3);
      final a = repository.createSession();
      final b = repository.createSession();
      final c = repository.createSession();
      repository
        ..findById(a.id)
        ..findById(c.id); // a and c came back; b, newer than a, did not
      final d = repository.createSession();
      expect(repository.findById(b.id), isNull);
      expect(b.isInvalidated, isTrue);
      // New sessions push out each other, not the returned ones.
      final e = repository.createSession();
      expect(d.isInvalidated, isTrue);
      expect(repository.findById(a.id), same(a));
      expect(repository.findById(c.id), same(c));
      expect(repository.findById(e.id), same(e));
    });

    test('a session holding a login is never pushed out: a new session '
        'is refused with 503 instead', () {
      final repository = InMemoryHttpSessionRepository(maxSessions: 2);
      const login = InMemoryHttpSessionRepository.loginAttribute;
      expect(login, 'SPRING_SECURITY_CONTEXT');
      final a = repository.createSession()..setAttribute(login, 'ada');
      final b = repository.createSession()..setAttribute(login, 'bob');
      for (var i = 0; i < 20; i++) {
        expect(
          repository.createSession,
          throwsA(
            isA<TooManyActiveSessionsException>()
                .having((e) => e.statusCode, 'status', 503)
                .having((e) => e.maxActiveSessions, 'limit', 2),
          ),
        );
      }
      expect(repository.size, 2);
      expect(repository.findById(a.id), same(a));
      // A logout (the login removed): b may go again.
      b.removeAttribute(login);
      final c = repository.createSession();
      expect(b.isInvalidated, isTrue);
      expect(repository.findById(a.id), same(a));
      expect(repository.findById(c.id), same(c));
    });

    test('the login keeps its place across a new id', () {
      final repository = InMemoryHttpSessionRepository(maxSessions: 2);
      final a = repository.createSession();
      repository.changeSessionId(a);
      a.setAttribute(InMemoryHttpSessionRepository.loginAttribute, 'ada');
      final b = repository.createSession();
      final c = repository.createSession();
      expect(b.isInvalidated, isTrue);
      expect(repository.findById(a.id), same(a));
      expect(repository.findById(c.id), same(c));
    });

    test('an expired session goes first, a logged-in one included', () {
      var now = DateTime(2026);
      final repository = InMemoryHttpSessionRepository(
        maxSessions: 3,
        clock: () => now,
      );
      final a = repository.createSession()
        ..setAttribute(InMemoryHttpSessionRepository.loginAttribute, 'ada');
      now = now.add(const Duration(minutes: 20));
      final b = repository.createSession();
      now = now.add(const Duration(minutes: 9, seconds: 30));
      final c = repository.createSession(); // purges: nothing expired yet
      // a expires at minute 30; the next purge is not due before 30:30.
      now = now.add(const Duration(seconds: 40));
      final d = repository.createSession();
      expect(a.isInvalidated, isTrue);
      for (final kept in [b, c, d]) {
        expect(repository.findById(kept.id), same(kept));
      }
    });

    // A login as the security starter stores it: the user's name next to
    // the context.
    StoredHttpSession loginOf(
      InMemoryHttpSessionRepository repository,
      String user,
    ) => repository.createSession()
      ..setAttribute(InMemoryHttpSessionRepository.principalNameAttribute, user)
      ..setAttribute(InMemoryHttpSessionRepository.loginAttribute, user);

    test('one user cannot lock the others out: with logins only, the user '
        'holding the most gives up their least recently used session', () {
      expect(
        InMemoryHttpSessionRepository.principalNameAttribute,
        'org.springframework.session.FindByIndexNameSessionRepository'
        '.PRINCIPAL_NAME_INDEX_NAME',
      );
      final repository = InMemoryHttpSessionRepository(maxSessions: 3);
      final ada1 = loginOf(repository, 'ada');
      final ada2 = loginOf(repository, 'ada');
      final ada3 = loginOf(repository, 'ada');
      repository.findById(ada1.id); // ada2 is the least recently used now
      // root's login starts with a new session: one of ada's makes room.
      final root = loginOf(repository, 'root');
      expect(ada2.isInvalidated, isTrue);
      for (final kept in [ada1, ada3, root]) {
        expect(repository.findById(kept.id), same(kept));
      }
      // ada logs in again: her own oldest session goes, root's stays.
      final ada4 = loginOf(repository, 'ada');
      expect(ada1.isInvalidated, isTrue);
      for (final kept in [ada3, root, ada4]) {
        expect(repository.findById(kept.id), same(kept));
      }
    });

    test('the same name from two login sources counts as two users', () {
      // The security starter keys a login by its source and name: an
      // identity provider's `ada` cannot push the form login's `ada` out
      // of her last session.
      StoredHttpSession keyed(
        InMemoryHttpSessionRepository repository,
        String key,
      ) => loginOf(
        repository,
        'ada',
      )..setAttribute(InMemoryHttpSessionRepository.principalKeyAttribute, key);
      final repository = InMemoryHttpSessionRepository(maxSessions: 3);
      final local = keyed(repository, 'local\u0000ada');
      final idp1 = keyed(repository, 'oauth2/keycloak\u0000ada');
      final idp2 = keyed(repository, 'oauth2/keycloak\u0000ada');
      // The provider's ada logs in once more: her own oldest goes.
      final idp3 = keyed(repository, 'oauth2/keycloak\u0000ada');
      expect(idp1.isInvalidated, isTrue);
      for (final kept in [local, idp2, idp3]) {
        expect(repository.findById(kept.id), same(kept));
      }
    });

    test('among users holding as many, the least recently used session '
        'goes', () {
      final repository = InMemoryHttpSessionRepository(maxSessions: 4);
      final ada1 = loginOf(repository, 'ada');
      final bob1 = loginOf(repository, 'bob');
      final ada2 = loginOf(repository, 'ada');
      final bob2 = loginOf(repository, 'bob');
      repository
        ..findById(ada1.id) // bob1 is the least recently used now
        ..createSession();
      expect(bob1.isInvalidated, isTrue);
      for (final kept in [ada1, ada2, bob2]) {
        expect(repository.findById(kept.id), same(kept));
      }
    });

    test('every login of another user: a new session is refused (503), '
        'a login without a name counting as a user of its own', () {
      final repository = InMemoryHttpSessionRepository(maxSessions: 4);
      final logins = [
        loginOf(repository, 'ada'),
        loginOf(repository, 'bob'),
        loginOf(repository, 'carol'),
        // Logged in by code that names no user.
        repository.createSession()
          ..setAttribute(InMemoryHttpSessionRepository.loginAttribute, 'x'),
      ];
      for (var i = 0; i < 20; i++) {
        expect(
          repository.createSession,
          throwsA(isA<TooManyActiveSessionsException>()),
        );
      }
      for (final kept in logins) {
        expect(repository.findById(kept.id), same(kept));
      }
    });

    test('an anonymous flood at the limit costs the user holding the most '
        'one session, and nobody else anything', () {
      final repository = InMemoryHttpSessionRepository(maxSessions: 3);
      final ada1 = loginOf(repository, 'ada');
      final ada2 = loginOf(repository, 'ada');
      final root = loginOf(repository, 'root');
      for (var i = 0; i < 100; i++) {
        repository.createSession();
      }
      expect(ada1.isInvalidated, isTrue);
      expect(repository.findById(ada2.id), same(ada2));
      expect(repository.findById(root.id), same(root));
      expect(repository.size, 3);
      // Each user has one session left: the next ones push out each other.
      for (var i = 0; i < 100; i++) {
        repository.createSession();
      }
      expect(repository.findById(ada2.id), same(ada2));
      expect(repository.findById(root.id), same(root));
    });

    test("a session counts for its user only while it holds the user's "
        'login, across a new id too', () {
      const name = InMemoryHttpSessionRepository.principalNameAttribute;
      final repository = InMemoryHttpSessionRepository(maxSessions: 3);
      final ada1 = loginOf(repository, 'ada');
      final ada2 = loginOf(repository, 'ada');
      repository.changeSessionId(ada2);
      final bob = loginOf(repository, 'bob');
      // ada1 is the least recently used login of the user holding the
      // most, ada2 counted under its new id.
      repository.createSession();
      expect(ada1.isInvalidated, isTrue);
      expect(repository.findById(ada2.id), same(ada2));
      // A name without a login protects nothing.
      final named = repository.createSession()..setAttribute(name, 'bob');
      repository.createSession();
      expect(named.isInvalidated, isTrue);
      // A login that ended counts for nobody: it goes like any session
      // without a login.
      ada2.removeAttribute(InMemoryHttpSessionRepository.loginAttribute);
      final returning = repository.createSession();
      expect(repository.findById(ada2.id), same(ada2));
      repository
        ..findById(returning.id) // returned, after ada2
        ..createSession();
      expect(ada2.isInvalidated, isTrue);
      expect(repository.findById(bob.id), same(bob));
      // Another name: bob's session now counts for root.
      bob.setAttribute(name, 'root');
      final root = loginOf(repository, 'root');
      final carol = loginOf(repository, 'carol');
      expect(repository.size, 3);
      repository.createSession();
      expect(bob.isInvalidated, isTrue);
      expect(repository.findById(root.id), same(root));
      expect(repository.findById(carol.id), same(carol));
    });

    test('ids are random and long', () {
      final ids = {for (var i = 0; i < 1000; i++) newSessionId()};
      expect(ids, hasLength(1000));
    });
  });

  test('properties', () {
    final properties = HttpSessionProperties.of(
      StandardEnvironment()
        ..propertySources.addFirst(
          const MapPropertySource('t', {
            'server.servlet.session.timeout': '15m',
            'server.servlet.session.cookie.name': 'SID',
            'server.servlet.session.cookie.same-site': 'strict',
            'server.servlet.session.cookie.secure': 'true',
            'server.servlet.session.max-sessions': '-1',
          }),
        ),
      contextPath: '/shop',
    );
    expect(properties.timeout, const Duration(minutes: 15));
    expect(properties.cookieName, 'SID');
    expect(properties.sameSite, 'Strict');
    expect(properties.secure, isTrue);
    expect(properties.cookiePath, '/shop');
    expect(properties.maxSessions, -1);
  });
}
