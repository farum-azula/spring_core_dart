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

    test('at the limit an expired session is removed for the new one', () {
      var now = DateTime(2026);
      final repository = InMemoryHttpSessionRepository(
        maxSessions: 2,
        clock: () => now,
      );
      final a = repository.createSession();
      now = now.add(const Duration(minutes: 20));
      final b = repository.createSession();
      // a expires at minute 30; the purge is not due before minute 21 + 1
      // after the one at minute 20, so only the limit finds it.
      now = now.add(const Duration(minutes: 10, seconds: 10));
      final c = repository.createSession();
      expect(a.isInvalidated, isTrue);
      expect(repository.size, 2);
      expect(repository.findById(b.id), same(b));
      expect(repository.findById(c.id), same(c));
    });

    test('at the limit with live sessions only a new session is refused '
        '(503) and every live session is kept', () {
      final repository = InMemoryHttpSessionRepository(maxSessions: 2);
      final a = repository.createSession();
      final b = repository.createSession();
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
      expect(repository.findById(b.id), same(b));
      // A session that ends makes room again.
      a.invalidate();
      final c = repository.createSession();
      expect(repository.findById(b.id), same(b));
      expect(repository.findById(c.id), same(c));
    });

    test('a session keeps its place across a new id', () {
      final repository = InMemoryHttpSessionRepository(maxSessions: 1);
      final a = repository.createSession();
      repository.changeSessionId(a);
      expect(repository.size, 1);
      expect(repository.findById(a.id), same(a));
      expect(
        repository.createSession,
        throwsA(isA<TooManyActiveSessionsException>()),
      );
    });

    test('without a limit (-1) nothing is refused', () {
      final repository = InMemoryHttpSessionRepository(maxSessions: -1);
      for (var i = 0; i < 50; i++) {
        repository.createSession();
      }
      expect(repository.size, 50);
    });

    test('the refusal is logged as a warning at most once a minute', () {
      var now = DateTime(2026);
      final repository = InMemoryHttpSessionRepository(
        maxSessions: 1,
        clock: () => now,
      )..createSession();
      final messages = <String>[];
      final stop = SpringLog.listen((record) {
        if (record.loggerName == 'spring.web.session') {
          messages.add(record.message);
        }
      });
      addTearDown(stop);
      void refuse() => expect(
        repository.createSession,
        throwsA(isA<TooManyActiveSessionsException>()),
      );
      refuse();
      refuse();
      now = now.add(const Duration(seconds: 30));
      refuse();
      expect(messages, hasLength(1));
      now = now.add(const Duration(seconds: 31));
      refuse();
      expect(messages, hasLength(2));
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
