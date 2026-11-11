@Tags(['supabase'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'auth_support.dart';
import 'support.dart';

const _refresh = '/auth/v1/token?grant_type=refresh_token';

void main() {
  late AuthHarness harness;
  late MockHttpTransport transport;

  setUp(() {
    harness = AuthHarness();
    transport = harness.transport;
  });

  Map<String, Object?> second({int expiresIn = 3600}) => sessionJson(
    accessToken: 'access-token-2',
    refreshToken: 'refresh-token-2',
    expiresIn: expiresIn,
  );

  HttpResponse answer(int status, Object json) =>
      HttpResponse(status, body: utf8.encode(jsonEncode(json)));

  // A session as a run before left it in the store, received [age] ago.
  Future<void> storeSession({Duration age = Duration.zero}) =>
      harness.store.write(
        SupabaseAuth.sessionKey,
        SupabaseSession.fromResponse(
          sessionJson(),
          harness.clock.now.subtract(age),
        )!.encode(),
      );

  group('persistence', () {
    test('the session is kept under one key, as JSON', () async {
      await harness.signedIn();
      expect(await harness.store.keys(), {SupabaseAuth.sessionKey});
      final stored = await harness.storedSession();
      expect(stored!['access_token'], 'access-token-1');
      expect(stored['refresh_token'], 'refresh-token-1');
      expect(stored['issued_at'], harness.clock.now.millisecondsSinceEpoch);
      expect(
        stored['expires_at'],
        harness.clock.now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      expect((stored['user']! as Map)['id'], userId);
    });

    test('persist-session false keeps it in memory only', () async {
      final auth = harness.auth(persistSession: false);
      transport
          .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
          .respond(200, json: sessionJson());
      await auth.signInWithPassword(email: 'a@b.c', password: 'correct horse');
      expect(auth.isLoggedIn, isTrue);
      expect(await harness.store.keys(), isEmpty);
      expect(auth.secretStore, isNot(same(harness.store)));
    });

    test('a store that cannot write does not fail the login', () async {
      harness.store.failWrites = true;
      final auth = await harness.signedIn();
      expect(auth.isLoggedIn, isTrue);
      expect(await auth.accessToken(), 'access-token-1');
    });

    test('the expiry counts from the receipt, not from a clock of Auth', () {
      final session = SupabaseSession.fromResponse(
        sessionJson(expiresIn: 600),
        harness.clock.now,
      )!;
      expect(session.issuedAt, harness.clock.now);
      expect(
        session.expiresAt,
        harness.clock.now.add(const Duration(minutes: 10)),
      );
      final dated = SupabaseSession.fromResponse(
        sessionJson()..remove('expires_in'),
        harness.clock.now,
      )!;
      expect(
        dated.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1794312000 * 1000, isUtc: true),
      );
    });
  });

  group('restore', () {
    test('a session that is still good comes back without a request', () async {
      await storeSession(age: const Duration(minutes: 10));
      final auth = harness.auth();
      final authentication = await auth.restore();
      await settle();
      expect(transport.requests, isEmpty);
      expect(authentication!.name, userId);
      expect(authentication.credentials.tokenValue, 'access-token-1');
      expect(auth.isLoggedIn, isTrue);
      expect(
        harness.contexts.getContext().authentication,
        same(authentication),
      );
      expect(harness.changes, [same(authentication)]);
      expect(
        harness.publisher.events.single,
        isA<AuthenticationSuccessEvent>(),
      );
      expect(await auth.accessToken(), 'access-token-1');
    });

    test('nothing stored: nobody', () async {
      final auth = harness.auth();
      expect(await auth.restore(), isNull);
      expect(auth.isLoggedIn, isFalse);
      expect(transport.requests, isEmpty);
      expect(harness.publisher.events, isEmpty);
    });

    test('an expired session is refreshed first', () async {
      await storeSession(age: const Duration(hours: 2));
      transport.when(HttpMethod.post, _refresh).respond(200, json: second());
      final auth = harness.auth();
      final authentication = await auth.restore();
      await settle();
      final request = transport.requests.single;
      expect(bodyOf(request), {'refresh_token': 'refresh-token-1'});
      expect(request.headers['Authorization'], 'Bearer anon-key');
      expect(authentication!.credentials.tokenValue, 'access-token-2');
      expect(
        harness.contexts.getContext().authentication,
        same(authentication),
      );
      expect(harness.changes, [same(authentication)]);
      expect(
        harness.publisher.events.single,
        isA<AuthenticationSuccessEvent>().having(
          (e) => e.authentication,
          'authentication',
          same(authentication),
        ),
      );
      expect(
        (await harness.storedSession())!['refresh_token'],
        'refresh-token-2',
      );
    });

    test('a refused refresh token forgets the session', () async {
      await storeSession(age: const Duration(hours: 2));
      transport
          .when(HttpMethod.post, _refresh)
          .respond(
            400,
            json: errorJson(
              400,
              'refresh_token_not_found',
              'Invalid Refresh Token: Refresh Token Not Found',
            ),
          );
      final auth = harness.auth();
      expect(await auth.restore(), isNull);
      await settle();
      expect(auth.isLoggedIn, isFalse);
      expect(await harness.storedSession(), isNull);
      expect(harness.contexts.getContext().authentication, isNull);
      // Nobody was signed in for the listeners: nothing to tell.
      expect(harness.changes, isEmpty);
      expect(harness.publisher.events, isEmpty);
    });

    test('without a network the user is restored as stored', () async {
      await storeSession(age: const Duration(hours: 2));
      transport
          .when(HttpMethod.post, _refresh)
          .fail(HttpTransportException('no route to host'));
      final auth = harness.auth();
      final authentication = await auth.restore();
      expect(authentication!.name, userId);
      expect(authentication.credentials.tokenValue, 'access-token-1');
      expect(auth.isLoggedIn, isTrue);
      expect(
        (await harness.storedSession())!['refresh_token'],
        'refresh-token-1',
      );
      expect(
        harness.publisher.events.single,
        isA<AuthenticationSuccessEvent>(),
      );
      // The next use tries again, and fails while the network is down.
      await expectLater(
        auth.accessToken(),
        throwsA(isA<SupabaseUnavailableException>()),
      );
      expect(auth.isLoggedIn, isTrue);
    });

    test('a failure of Auth restores as stored, too', () async {
      await storeSession(age: const Duration(hours: 2));
      transport.when(HttpMethod.post, _refresh).respond(503, body: 'busy');
      final auth = harness.auth();
      expect(await auth.restore(), isNotNull);
      expect(auth.isLoggedIn, isTrue);
      expect(await harness.storedSession(), isNotNull);
    });

    test('a stored value that cannot be read is removed', () async {
      for (final value in [
        'not json',
        '[]',
        '{"version":2,"access_token":"a","refresh_token":"r"}',
        '{"version":1,"access_token":"a"}',
      ]) {
        await harness.store.write(SupabaseAuth.sessionKey, value);
        final auth = harness.auth();
        expect(await auth.restore(), isNull, reason: value);
        expect(await harness.storedSession(), isNull, reason: value);
        expect(auth.isLoggedIn, isFalse);
      }
      expect(transport.requests, isEmpty);
    });

    test('awaitStartup restores, once', () async {
      await storeSession();
      final auth = harness.auth();
      await auth.awaitStartup();
      await auth.awaitStartup();
      expect(auth.isLoggedIn, isTrue);
      expect(harness.publisher.events, hasLength(1));
    });

    test('awaitStartup never fails the start', () async {
      await storeSession(age: const Duration(hours: 2));
      transport
          .when(HttpMethod.post, _refresh)
          .fail(HttpTransportException('no route to host'));
      final offline = harness.auth();
      await offline.awaitStartup();
      expect(offline.isLoggedIn, isTrue);

      final broken = SupabaseAuth(
        http: http(MockHttpTransport()),
        secretStore: _UnreadableStore(),
      );
      await broken.awaitStartup();
      expect(broken.isLoggedIn, isFalse);
    });

    test('a login that is already there is kept', () async {
      final auth = await harness.signedIn();
      final authentication = auth.authentication;
      expect(await auth.restore(), same(authentication));
      expect(harness.publisher.events, hasLength(1));
    });
  });

  group('accessToken', () {
    test(
      'the stored token while it is good for longer than the margin',
      () async {
        final auth = await harness.signedIn();
        harness.clock.advance(const Duration(minutes: 59, seconds: 29));
        expect(await auth.accessToken(), 'access-token-1');
        expect(harness.requestsTo('/auth/v1/token'), hasLength(1));
      },
    );

    test('within the margin of its expiry it is refreshed first', () async {
      final auth = await harness.signedIn();
      transport.when(HttpMethod.post, _refresh).respond(200, json: second());
      await settle();
      final before = auth.authentication;
      harness.changes.clear();
      harness.publisher.events.clear();
      harness.clock.advance(const Duration(minutes: 59, seconds: 30));
      expect(await auth.accessToken(), 'access-token-2');
      await settle();
      final request = transport.requests.last;
      expect('${request.url}', '$projectUrl$_refresh');
      expect(request.headers['apikey'], 'anon-key');
      expect(request.headers['Authorization'], 'Bearer anon-key');
      expect(bodyOf(request), {'refresh_token': 'refresh-token-1'});
      // The login goes on with new tokens: the context and the stream
      // have them, and it is no new login for the listeners of events.
      final authentication = auth.authentication!;
      expect(authentication, isNot(same(before)));
      expect(authentication.credentials.tokenValue, 'access-token-2');
      expect(authentication.credentials.issuedAt, harness.clock.now);
      expect(
        harness.contexts.getContext().authentication,
        same(authentication),
      );
      expect(harness.changes, [same(authentication)]);
      expect(harness.publisher.events, isEmpty);
    });

    test('nobody signed in: null, no request', () async {
      expect(await harness.auth().accessToken(), isNull);
      expect(transport.requests, isEmpty);
    });

    test('ten callers, one request', () async {
      final auth = await harness.signedIn();
      final gate = Completer<void>();
      transport.when(HttpMethod.post, _refresh).respondWith((request) async {
        await gate.future;
        return answer(200, second());
      });
      harness.clock.advance(const Duration(hours: 1));
      final tokens = [for (var i = 0; i < 10; i++) auth.accessToken()];
      final explicit = auth.refreshSession();
      await settle();
      gate.complete();
      expect(await Future.wait(tokens), List.filled(10, 'access-token-2'));
      expect((await explicit).credentials.tokenValue, 'access-token-2');
      expect(harness.requestsTo('/auth/v1/token'), hasLength(2));
      await settle();
      // One refresh: the stream told once.
      expect(harness.changes, hasLength(2));
    });

    test(
      'ten callers share one failure, and the next call tries again',
      () async {
        final auth = await harness.signedIn();
        transport
            .when(HttpMethod.post, _refresh)
            .fail(HttpTransportException('connection reset'));
        transport.when(HttpMethod.post, _refresh).respond(200, json: second());
        harness.clock.advance(const Duration(hours: 1));
        final results = await Future.wait([
          for (var i = 0; i < 10; i++)
            auth.accessToken().then<Object?>(
              (t) => t,
              onError: (Object e) => e,
            ),
        ]);
        expect(results, everyElement(isA<SupabaseUnavailableException>()));
        expect(harness.requestsTo('/auth/v1/token'), hasLength(2));
        expect(await auth.accessToken(), 'access-token-2');
        expect(harness.requestsTo('/auth/v1/token'), hasLength(3));
      },
    );
  });

  group('rotation', () {
    test(
      'the new refresh token replaces the old one, here and stored',
      () async {
        final auth = await harness.signedIn();
        transport.when(HttpMethod.post, _refresh).respond(200, json: second());
        transport
            .when(HttpMethod.post, _refresh)
            .respond(
              200,
              json: sessionJson(
                accessToken: 'access-token-3',
                refreshToken: 'refresh-token-3',
              ),
            );
        await auth.refreshSession();
        expect(
          (await harness.storedSession())!['refresh_token'],
          'refresh-token-2',
        );
        expect(
          (await harness.storedSession())!['access_token'],
          'access-token-2',
        );
        await auth.refreshSession();
        final sent = [
          for (final request in harness.requestsTo('/auth/v1/token').skip(1))
            bodyOf(request)['refresh_token'],
        ];
        // Each refresh token is sent once.
        expect(sent, ['refresh-token-1', 'refresh-token-2']);
        expect(
          (await harness.storedSession())!['refresh_token'],
          'refresh-token-3',
        );
      },
    );

    test('it is stored before the listeners hear of the new tokens', () async {
      final auth = await harness.signedIn();
      transport.when(HttpMethod.post, _refresh).respond(200, json: second());
      await settle();
      // A second login over the same stored session, with a store that
      // looks at it at each write.
      final spy = _WriteSpy();
      await spy.write(
        SupabaseAuth.sessionKey,
        (await harness.store.read(SupabaseAuth.sessionKey))!,
      );
      final spied = SupabaseAuth(
        http: auth.http,
        secretStore: spy,
        securityContextHolderStrategy: harness.contexts,
        clock: harness.clock.call,
      );
      spy.auth = spied;
      addTearDown(spied.destroy);
      await spied.restore();
      final storedWhenTold = <Object?>[];
      spied.authenticationChanges.listen(
        (_) => storedWhenTold.add(spy.stored['refresh_token']),
      );
      await spied.refreshSession();
      await settle();
      // In memory first, then the store, then the listeners.
      expect(spy.inMemoryAtWrite, ['access-token-2']);
      expect(storedWhenTold, ['refresh-token-2']);
    });

    test('a refresh that answers without the user keeps the user', () async {
      final auth = await harness.signedIn();
      transport
          .when(HttpMethod.post, _refresh)
          .respond(200, json: second()..remove('user'));
      final authentication = await auth.refreshSession();
      expect(authentication.name, userId);
      expect(authentication.principal.email, 'ada@example.com');
    });

    test('new roles of the user arrive with the refresh', () async {
      final auth = await harness.signedIn();
      transport
          .when(HttpMethod.post, _refresh)
          .respond(
            200,
            json: sessionJson(
              accessToken: 'access-token-2',
              refreshToken: 'refresh-token-2',
              user: userJson(
                appMetadata: {
                  'roles': ['admin'],
                },
              ),
            ),
          );
      expect(auth.authentication!.authorities, isEmpty);
      final authentication = await auth.refreshSession();
      expect(authentication.authorities.single.authority, 'ROLE_admin');
    });
  });

  group('a refused refresh', () {
    Future<SupabaseAuth> refused(int status, Object json) async {
      final auth = await harness.signedIn();
      transport.when(HttpMethod.post, _refresh).respond(status, json: json);
      await settle();
      harness.changes.clear();
      harness.publisher.events.clear();
      harness.clock.advance(const Duration(hours: 1));
      return auth;
    }

    test(
      'a replayed refresh token signs out and tells the listeners',
      () async {
        final auth = await refused(
          400,
          errorJson(
            400,
            'refresh_token_already_used',
            'Invalid Refresh Token: Already Used',
          ),
        );
        expect(await auth.accessToken(), isNull);
        await settle();
        expect(auth.isLoggedIn, isFalse);
        expect(auth.authentication, isNull);
        expect(auth.user, isNull);
        expect(harness.contexts.getContext().authentication, isNull);
        expect(harness.changes, [isNull]);
        expect(await harness.storedSession(), isNull);
        // Not a logout of the user's: no LogoutSuccessEvent.
        expect(harness.publisher.events, isEmpty);
        // And nothing is tried again.
        expect(await auth.accessToken(), isNull);
        expect(harness.requestsTo('/auth/v1/token'), hasLength(2));
      },
    );

    test('refreshSession throws what ended the session', () async {
      final auth = await refused(
        400,
        errorJson(
          400,
          'session_expired',
          'Invalid Refresh Token: Session Expired',
        ),
      );
      await expectLater(
        auth.refreshSession(),
        throwsA(
          isA<SupabaseSessionExpiredException>()
              .having((e) => e.errorCode, 'errorCode', 'session_expired')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
      expect(auth.isLoggedIn, isFalse);
      await expectLater(
        auth.refreshSession(),
        throwsA(isA<AuthenticationCredentialsNotFoundException>()),
      );
    });

    test('every code that means the session is gone', () async {
      for (final (status, json) in <(int, Object)>[
        (400, errorJson(400, 'refresh_token_not_found', 'x')),
        (400, errorJson(400, 'refresh_token_already_used', 'x')),
        (400, errorJson(400, 'session_not_found', 'x')),
        (400, errorJson(400, 'session_expired', 'x')),
        (400, errorJson(400, 'user_banned', 'x')),
        (403, errorJson(403, 'user_not_found', 'x')),
        (
          400,
          errorJson(400, 'validation_failed', 'Refresh token is not valid'),
        ),
        (
          400,
          {
            'error': 'invalid_grant',
            'error_description': 'Invalid Refresh Token',
          },
        ),
        (
          401,
          {
            'error': 'invalid_grant',
            'error_description': 'Invalid Refresh Token',
          },
        ),
      ]) {
        harness = AuthHarness();
        transport = harness.transport;
        final auth = await refused(status, json);
        expect(await auth.accessToken(), isNull, reason: '$json');
        expect(auth.isLoggedIn, isFalse, reason: '$json');
        expect(await harness.storedSession(), isNull, reason: '$json');
      }
    });

    test('anything else keeps the session and fails the call', () async {
      for (final (status, json) in <(int, Object)>[
        (429, errorJson(429, 'over_request_rate_limit', 'Too many requests')),
        (500, errorJson(500, 'unexpected_failure', 'Database error')),
        (500, errorJson(500, 'refresh_token_not_found', 'x')),
        (503, {'message': 'upstream unavailable'}),
        (401, {'message': 'Invalid API key'}),
        (400, errorJson(400, 'bad_json', 'Could not parse request body')),
        (403, {'error': 'access_denied'}),
      ]) {
        harness = AuthHarness();
        transport = harness.transport;
        final auth = await refused(status, json);
        await expectLater(
          auth.accessToken(),
          throwsA(isA<AuthenticationException>()),
          reason: '$json',
        );
        expect(auth.isLoggedIn, isTrue, reason: '$json');
        expect(
          (await harness.storedSession())!['refresh_token'],
          'refresh-token-1',
          reason: '$json',
        );
        expect(harness.changes, isEmpty, reason: '$json');
      }
    });

    test('a network failure keeps the session and fails the call', () async {
      final auth = await harness.signedIn();
      transport
          .when(HttpMethod.post, _refresh)
          .fail(HttpTransportException('timed out', isTimeout: true));
      harness.clock.advance(const Duration(hours: 1));
      await expectLater(
        auth.accessToken(),
        throwsA(
          isA<SupabaseUnavailableException>().having(
            (e) => e.isTimeout,
            'isTimeout',
            isTrue,
          ),
        ),
      );
      await expectLater(
        auth.refreshSession(),
        throwsA(isA<SupabaseUnavailableException>()),
      );
      expect(auth.isLoggedIn, isTrue);
      expect(auth.authentication!.credentials.tokenValue, 'access-token-1');
      expect(
        (await harness.storedSession())!['refresh_token'],
        'refresh-token-1',
      );
    });

    test('a store that cannot delete still signs out', () async {
      final auth = await refused(
        400,
        errorJson(400, 'refresh_token_not_found', 'x'),
      );
      harness.store.failDeletes = true;
      expect(await auth.accessToken(), isNull);
      expect(auth.isLoggedIn, isFalse);
    });
  });

  group('auto-refresh', () {
    test('a timer fires the margin before the expiry', () async {
      final auth = await harness.signedIn(autoRefresh: true);
      transport.when(HttpMethod.post, _refresh).respond(200, json: second());
      final timer = harness.timers.active.single;
      expect(timer.delay, const Duration(minutes: 59, seconds: 30));
      harness.clock.advance(timer.delay);
      timer.fire();
      await settle();
      expect(bodyOf(transport.requests.last), {
        'refresh_token': 'refresh-token-1',
      });
      expect(auth.authentication!.credentials.tokenValue, 'access-token-2');
      // The next one, for the new token.
      expect(
        harness.timers.active.single.delay,
        const Duration(minutes: 59, seconds: 30),
      );
      expect(harness.timers.all, hasLength(2));
    });

    test('without auto-refresh there is no timer', () async {
      await harness.signedIn();
      expect(harness.timers.all, isEmpty);
    });

    test('a network failure is retried with a growing delay', () async {
      final auth = await harness.signedIn(autoRefresh: true);
      transport
          .when(HttpMethod.post, _refresh)
          .fail(HttpTransportException('down'));
      transport
          .when(HttpMethod.post, _refresh)
          .fail(HttpTransportException('down'));
      transport.when(HttpMethod.post, _refresh).respond(503, body: 'busy');
      transport.when(HttpMethod.post, _refresh).respond(200, json: second());
      final delays = <Duration>[];
      for (var i = 0; i < 3; i++) {
        harness.timers.active.single.fire();
        await settle();
        expect(auth.isLoggedIn, isTrue);
        delays.add(harness.timers.active.single.delay);
      }
      expect(delays, const [
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
      ]);
      harness.timers.active.single.fire();
      await settle();
      expect(auth.authentication!.credentials.tokenValue, 'access-token-2');
      expect(
        harness.timers.active.single.delay,
        const Duration(minutes: 59, seconds: 30),
      );
    });

    test('the delay between tries stops growing at a minute', () async {
      await harness.signedIn(autoRefresh: true);
      transport
          .when(HttpMethod.post, _refresh)
          .fail(HttpTransportException('down'));
      for (var i = 0; i < 8; i++) {
        harness.timers.active.single.fire();
        await settle();
      }
      expect(harness.timers.active.single.delay, const Duration(minutes: 1));
    });

    test('a refused refresh signs out and stops the timer', () async {
      final auth = await harness.signedIn(autoRefresh: true);
      transport
          .when(HttpMethod.post, _refresh)
          .respond(
            400,
            json: errorJson(400, 'refresh_token_already_used', 'x'),
          );
      harness.timers.active.single.fire();
      await settle();
      expect(auth.isLoggedIn, isFalse);
      expect(harness.changes.last, isNull);
      expect(harness.timers.active, isEmpty);
    });

    test(
      'a token shorter than twice the margin is refreshed at half its life',
      () async {
        await harness.signedIn(
          autoRefresh: true,
          session: sessionJson(expiresIn: 40),
        );
        expect(harness.timers.active.single.delay, const Duration(seconds: 20));
      },
    );

    test('never sooner than a second, whatever Auth answers', () async {
      await harness.signedIn(
        autoRefresh: true,
        session: sessionJson(expiresIn: 0),
      );
      expect(harness.timers.active.single.delay, const Duration(seconds: 1));
    });

    test('logout stops the timer', () async {
      final auth = await harness.signedIn(autoRefresh: true);
      transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
      await auth.logout();
      expect(harness.timers.active, isEmpty);
    });

    test(
      'the application stopping stops the timer and closes the stream',
      () async {
        final auth = await harness.signedIn(autoRefresh: true);
        var done = false;
        auth.authenticationChanges.listen(null, onDone: () => done = true);
        await auth.destroy();
        await settle();
        expect(harness.timers.active, isEmpty);
        expect(done, isTrue);
        // The session stays for the next run.
        expect(await harness.storedSession(), isNotNull);
      },
    );

    test('a restored session gets its timer', () async {
      await storeSession(age: const Duration(minutes: 30));
      final auth = harness.auth(autoRefresh: true);
      await auth.restore();
      expect(
        harness.timers.active.single.delay,
        const Duration(minutes: 29, seconds: 30),
      );
    });
  });

  group('logout', () {
    test('forgets the session here and revokes it at Auth', () async {
      final auth = await harness.signedIn();
      transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
      await settle();
      final authentication = auth.authentication;
      harness.changes.clear();
      harness.publisher.events.clear();
      await auth.logout();
      await settle();
      final request = transport.requests.last;
      expect('${request.url}', '$projectUrl/auth/v1/logout?scope=local');
      expect(request.method, HttpMethod.post);
      expect(request.headers['apikey'], 'anon-key');
      expect(request.headers['Authorization'], 'Bearer access-token-1');
      expect(request.body, isNull);
      expect(auth.isLoggedIn, isFalse);
      expect(auth.authentication, isNull);
      expect(auth.user, isNull);
      expect(await auth.accessToken(), isNull);
      expect(harness.contexts.getContext().authentication, isNull);
      expect(harness.changes, [isNull]);
      expect(
        harness.publisher.events.single,
        isA<LogoutSuccessEvent>().having(
          (e) => e.authentication,
          'authentication',
          same(authentication),
        ),
      );
      expect(await harness.store.keys(), isEmpty);
    });

    test('the scope is sent as asked', () async {
      final auth = await harness.signedIn();
      transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
      await auth.logout(scope: SupabaseLogoutScope.global);
      expect(
        '${transport.requests.last.url}',
        '$projectUrl/auth/v1/logout?scope=global',
      );
      expect(auth.isLoggedIn, isFalse);
    });

    test('the session is cleared here when Auth cannot be reached', () async {
      final auth = await harness.signedIn();
      transport
          .when(HttpMethod.post, '/auth/v1/logout')
          .fail(HttpTransportException('no route to host'));
      await auth.logout();
      await settle();
      expect(auth.isLoggedIn, isFalse);
      expect(harness.contexts.getContext().authentication, isNull);
      expect(harness.changes.last, isNull);
      expect(harness.publisher.events.last, isA<LogoutSuccessEvent>());
      expect(await harness.storedSession(), isNull);
    });

    test('and when Auth refuses or fails', () async {
      for (final status in [401, 403, 404, 500]) {
        harness = AuthHarness();
        transport = harness.transport;
        final auth = await harness.signedIn();
        transport
            .when(HttpMethod.post, '/auth/v1/logout')
            .respond(status, json: errorJson(status, 'bad_jwt', 'x'));
        await auth.logout();
        expect(auth.isLoggedIn, isFalse, reason: '$status');
        expect(await harness.storedSession(), isNull, reason: '$status');
      }
    });

    test('it is cleared before Auth is asked', () async {
      final auth = await harness.signedIn();
      late bool loggedInDuringRequest;
      late Object? storedDuringRequest;
      transport.when(HttpMethod.post, '/auth/v1/logout').respondWith((
        request,
      ) async {
        loggedInDuringRequest = auth.isLoggedIn;
        storedDuringRequest = await harness.storedSession();
        return HttpResponse(204);
      });
      await auth.logout();
      expect(loggedInDuringRequest, isFalse);
      expect(storedDuringRequest, isNull);
    });

    test(
      'an expired token cannot revoke: one last exchange gets one',
      () async {
        final auth = await harness.signedIn();
        transport.when(HttpMethod.post, _refresh).respond(200, json: second());
        transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
        harness.clock.advance(const Duration(hours: 2));
        await auth.logout();
        final requests = transport.requests.skip(1).toList();
        expect(requests, hasLength(2));
        expect(bodyOf(requests[0]), {'refresh_token': 'refresh-token-1'});
        expect(requests[1].headers['Authorization'], 'Bearer access-token-2');
        // The tokens of that exchange are never kept.
        expect(auth.isLoggedIn, isFalse);
        expect(await harness.store.keys(), isEmpty);
      },
    );

    test(
      'an expired token whose refresh is refused: nothing to revoke',
      () async {
        final auth = await harness.signedIn();
        transport
            .when(HttpMethod.post, _refresh)
            .respond(400, json: errorJson(400, 'refresh_token_not_found', 'x'));
        harness.clock.advance(const Duration(hours: 2));
        await auth.logout();
        expect(harness.requestsTo('/auth/v1/logout'), isEmpty);
        expect(auth.isLoggedIn, isFalse);
      },
    );

    test('nobody signed in: nothing happens', () async {
      final auth = harness.auth();
      await auth.logout();
      await settle();
      expect(transport.requests, isEmpty);
      expect(harness.changes, isEmpty);
      expect(harness.publisher.events, isEmpty);
    });

    test('scope others keeps this session', () async {
      final auth = await harness.signedIn();
      transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
      await auth.logout(scope: SupabaseLogoutScope.others);
      final request = transport.requests.last;
      expect('${request.url}', '$projectUrl/auth/v1/logout?scope=others');
      expect(request.headers['Authorization'], 'Bearer access-token-1');
      expect(auth.isLoggedIn, isTrue);
      expect(await harness.storedSession(), isNotNull);
    });

    test('scope others says when it failed', () async {
      final auth = await harness.signedIn();
      transport
          .when(HttpMethod.post, '/auth/v1/logout')
          .fail(HttpTransportException('down'));
      await expectLater(
        auth.logout(scope: SupabaseLogoutScope.others),
        throwsA(isA<SupabaseUnavailableException>()),
      );
      expect(auth.isLoggedIn, isTrue);
      await expectLater(
        harness.auth().logout(scope: SupabaseLogoutScope.others),
        throwsA(isA<AuthenticationCredentialsNotFoundException>()),
      );
    });

    test(
      'a store that cannot delete: signed out, revoked, then the error',
      () async {
        final auth = await harness.signedIn();
        transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
        harness.store.failDeletes = true;
        await expectLater(auth.logout(), throwsStateError);
        await settle();
        expect(auth.isLoggedIn, isFalse);
        expect(harness.contexts.getContext().authentication, isNull);
        expect(harness.changes.last, isNull);
        expect(harness.publisher.events.last, isA<LogoutSuccessEvent>());
        expect(harness.requestsTo('/auth/v1/logout'), hasLength(1));
      },
    );

    test(
      'a refresh that answers after the logout brings nothing back',
      () async {
        final auth = await harness.signedIn();
        final gate = Completer<void>();
        transport.when(HttpMethod.post, _refresh).respondWith((request) async {
          await gate.future;
          return answer(200, second());
        });
        transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
        final refreshing = auth.refreshSession();
        await settle();
        await auth.logout();
        gate.complete();
        await expectLater(
          refreshing,
          throwsA(isA<AuthenticationCredentialsNotFoundException>()),
        );
        await settle();
        expect(auth.isLoggedIn, isFalse);
        expect(harness.contexts.getContext().authentication, isNull);
        expect(await harness.storedSession(), isNull);
        expect(harness.changes.last, isNull);
      },
    );

    test('a logout while the login is being stored leaves nothing', () async {
      final slow = _SlowStore();
      final auth = SupabaseAuth(
        http: http(transport),
        secretStore: slow,
        securityContextHolderStrategy: harness.contexts,
        clock: harness.clock.call,
      );
      addTearDown(auth.destroy);
      transport
          .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
          .respond(200, json: sessionJson());
      transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
      final login = auth.signInWithPassword(
        email: 'a@b.c',
        password: 'correct horse',
      );
      await slow.writing.future;
      final logout = auth.logout();
      slow.release.complete();
      await login;
      await logout;
      expect(auth.isLoggedIn, isFalse);
      expect(await slow.read(SupabaseAuth.sessionKey), isNull);
    });
  });
}

final class _UnreadableStore extends InMemorySecretStore {
  @override
  Future<String?> read(String key) async =>
      throw StateError('the keychain is locked');
}

// Holds the first write until released.
final class _SlowStore extends InMemorySecretStore {
  final writing = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    if (!writing.isCompleted) {
      writing.complete();
      await release.future;
    }
    await super.write(key, value);
  }
}

// Notes, at each write of the session, the token the login has in memory.
final class _WriteSpy extends InMemorySecretStore {
  SupabaseAuth? auth;
  final inMemoryAtWrite = <String?>[];
  Map<String, Object?> stored = const {};

  @override
  Future<void> write(String key, String value) async {
    if (auth case final auth?) {
      inMemoryAtWrite.add(auth.authentication?.credentials.tokenValue);
    }
    stored = jsonDecode(value) as Map<String, Object?>;
    await super.write(key, value);
  }
}
