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
