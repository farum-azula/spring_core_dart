import 'dart:async';

import 'package:spring_boot_starter_web/src/config/web_properties.dart';
import 'package:spring_boot_starter_web/src/http_session.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

// Sessions without a server: the cookie settings the properties give, the
// attributes, requests the filter never saw, committed responses and a
// repository that answers with futures.

// A repository that answers asynchronously, over the in-memory one.
class _AsyncRepository implements HttpSessionRepository {
  final inner = InMemoryHttpSessionRepository();

  @override
  Future<StoredHttpSession> createSession() async => inner.createSession();

  @override
  Future<StoredHttpSession?> findById(String id) async => inner.findById(id);

  @override
  Future<void> changeSessionId(StoredHttpSession session) async =>
      inner.changeSessionId(session);

  @override
  Future<void> deleteById(String id) async => inner.deleteById(id);
}

void main() {
  Future<(MockServerHttpRequest, MockServerHttpResponse)> attached(
    HttpSessionRepository repository, {
    String? cookie,
    HttpSessionProperties properties = const HttpSessionProperties(),
  }) async {
    final request = MockServerHttpRequest(HttpMethod.get, '/');
    if (cookie != null) request.headers.set('cookie', cookie);
    final response = MockServerHttpResponse();
    await HttpSessionManager(repository, properties).attach(request, response);
    return (request, response);
  }

  group('the cookie settings of the properties', () {
    HttpSessionProperties from(ServerSessionSettings settings) =>
        HttpSessionProperties.from(settings, contextPath: '/shop');

    test('say how the SameSite attribute is written', () {
      String? sameSite(SessionSameSite value) => from(
        ServerSessionSettings()..cookie.sameSite = value,
      ).sameSite;
      expect(sameSite(SessionSameSite.lax), 'Lax');
      expect(sameSite(SessionSameSite.strict), 'Strict');
      expect(sameSite(SessionSameSite.none), 'None');
      expect(sameSite(SessionSameSite.unset), isNull);
    });

    test('use the context path unless the cookie path is set', () {
      expect(from(ServerSessionSettings()).cookiePath, '/shop');
      expect(
        from(ServerSessionSettings()..cookie.path = ' /x ').cookiePath,
        '/x',
      );
    });

    test('carry the timeout, the limit and a blank name as the default', () {
      final settings = ServerSessionSettings()
        ..timeout = const Duration(minutes: 5)
        ..maxSessions = 7
        ..cookie.name = '  ';
      final properties = from(settings);
      expect(properties.timeout, const Duration(minutes: 5));
      expect(properties.maxSessions, 7);
      expect(properties.cookieName, 'JSESSIONID');
    });
  });

  group('session attributes', () {
    test(
      'are set, listed, overwritten, and removed by null or by name',
      () async {
        final (request, _) = await attached(InMemoryHttpSessionRepository());
        final session = request.getSession()!
          ..setAttribute('a', 1)
          ..setAttribute('b', 2)
          ..setAttribute('a', 3);
        expect(session.getAttribute('a'), 3);
        expect(session.attributeNames, unorderedEquals(['a', 'b']));
        session
          ..setAttribute('a', null)
          ..removeAttribute('b');
        expect(session.attributeNames, isEmpty);
      },
    );

    test('cannot be used after the session was invalidated', () async {
      final (request, _) = await attached(InMemoryHttpSessionRepository());
      final session = request.getSession()!..invalidate();
      expect(session.isInvalidated, isTrue);
      expect(() => session.setAttribute('a', 1), throwsStateError);
      expect(() => session.removeAttribute('a'), throwsStateError);
      expect(() => session.attributeNames, throwsStateError);
      expect(request.getSession(create: false), isNull);
    });
  });

  group('a request the session filter never saw', () {
    test('cannot get a session and says why', () async {
      final request = MockServerHttpRequest(HttpMethod.get, '/');
      expect(
        request.getSession,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('HttpSessionFilter'),
          ),
        ),
      );
      await expectLater(request.getSessionAsync(), throwsStateError);
      await expectLater(request.changeSessionId(), throwsStateError);
      expect(request.requestedSessionId, isNull);
      expect(request.isRequestedSessionIdValid, isFalse);
    });

    test('has no session to rotate even after the filter', () async {
      final (request, _) = await attached(InMemoryHttpSessionRepository());
      await expectLater(request.changeSessionId(), throwsStateError);
    });
  });

  test('a committed response gets no session cookie', () async {
    final (request, response) = await attached(
      InMemoryHttpSessionRepository(),
    );
    await response.flush();
    final session = request.getSession()!;
    expect(session.id, isNotEmpty);
    expect(response.cookies, isEmpty);
  });

  group('with a repository that answers with futures', () {
    test('getSession explains that the async variant is needed', () async {
      final (request, _) = await attached(_AsyncRepository());
      expect(
        request.getSession,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('getSessionAsync'),
          ),
        ),
      );
    });

    test('getSessionAsync creates, finds and rotates a session', () async {
      final repository = _AsyncRepository();
      final (request, response) = await attached(repository);
      expect(await request.getSessionAsync(create: false), isNull);
      final session = (await request.getSessionAsync())!;
      expect(response.cookies.single.value, session.id);
      expect(await request.getSessionAsync(), same(session));
      final old = session.id;
      final id = await request.changeSessionId();
      expect(id, isNot(old));
      expect(response.cookies.last.value, id);
      expect(await repository.findById(old), isNull);

      final (next, _) = await attached(repository, cookie: 'JSESSIONID=$id');
      expect(next.requestedSessionId, id);
      expect(next.isRequestedSessionIdValid, isTrue);
      expect((await next.getSessionAsync())?.id, id);
      // The rotated-away id is not valid any more.
      final (stale, _) = await attached(repository, cookie: 'JSESSIONID=$old');
      expect(stale.isRequestedSessionIdValid, isFalse);
    });
  });
}
