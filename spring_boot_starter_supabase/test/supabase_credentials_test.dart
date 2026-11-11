@Tags(['supabase'])
library;

import 'dart:async';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:test/test.dart';

import 'support.dart';

final class _Session implements LoginSession {
  _Session(this.token);

  String? token;
  final String user = 'user-1';
  int asked = 0;

  @override
  Authentication? get authentication =>
      token == null ? null : TestingAuthenticationToken(user, null);

  @override
  bool get isLoggedIn => token != null;

  @override
  Stream<Authentication?> get authenticationChanges => const Stream.empty();

  @override
  Future<String?> accessToken() async {
    asked++;
    return token;
  }

  @override
  Future<Authentication?> restore() async => authentication;

  @override
  Future<void> logout() async => token = null;
}

Authentication _bearer(Map<String, Object?> claims) =>
    TestingAuthenticationToken('p', TestToken(unsignedToken(claims)));

void main() {
  DefaultSupabaseCredentials credentials({
    _Session? session,
    Authentication? request,
    bool serviceRole = true,
  }) => DefaultSupabaseCredentials(
    properties: properties(serviceRole: serviceRole),
    session: () => session,
    authentication: () => request,
  );

  const user = {
    'iss': '$projectUrl/auth/v1',
    'role': 'authenticated',
    'sub': 'user-7',
  };

  test('nobody signed in: the anon key', () async {
    final c = credentials();
    expect(c.apiKey, 'anon-key');
    expect(await c.accessToken(), 'anon-key');
    expect(c.caller, const SupabaseCaller.anon());
    expect(c.caller.key, 'anon');
  });

  test('a signed-in user of the application: their fresh token', () async {
    final session = _Session('user-token');
    final c = credentials(session: session);
    expect(await c.accessToken(), 'user-token');
    expect(session.asked, 1);
    expect(c.apiKey, 'anon-key');
    expect(c.caller, const SupabaseCaller.user('user-1'));
    await session.logout();
    expect(await c.accessToken(), 'anon-key');
    expect(c.caller, const SupabaseCaller.anon());
  });

  test("a request's bearer token of this project is passed on", () async {
    final request = _bearer(user);
    final c = credentials(request: request);
    expect(
      await c.accessToken(),
      (request.credentials! as OAuth2Token).tokenValue,
    );
    expect(c.caller, const SupabaseCaller.user('user-7'));
  });

  group('a token that is not a user of this project is never passed on', () {
    for (final (name, claims) in [
      ('another issuer', {...user, 'iss': 'https://keycloak.example/realms/x'}),
      (
        'another project',
        {...user, 'iss': 'https://other.supabase.co/auth/v1'},
      ),
      ('the anon role', {...user, 'role': 'anon'}),
      ('the service role', {...user, 'role': 'service_role'}),
      ('no subject', {...user, 'sub': ''}),
    ]) {
      test(name, () async {
        final c = credentials(request: _bearer(claims));
        expect(await c.accessToken(), 'anon-key');
        expect(c.caller, const SupabaseCaller.anon());
      });
    }

    test('credentials that are no token, and text that is no JWT', () async {
      for (final request in [
        TestingAuthenticationToken('p', 'password'),
        TestingAuthenticationToken('p', TestToken('not-a-jwt')),
        TestingAuthenticationToken('p', TestToken('a.%%.c')),
      ]) {
        expect(await credentials(request: request).accessToken(), 'anon-key');
      }
    });

    test('an authentication that is not authenticated', () async {
      final request = _bearer(user)..isAuthenticated = false;
      expect(await credentials(request: request).accessToken(), 'anon-key');
    });
  });

  test('spring.supabase.auth.issuer replaces <url>/auth/v1', () async {
    final all = properties()..auth.issuer = 'https://auth.example.com';
    final c = DefaultSupabaseCredentials(
      properties: all,
      authentication: () =>
          _bearer({...user, 'iss': 'https://auth.example.com'}),
    );
    expect(c.caller, const SupabaseCaller.user('user-7'));
  });

  group('asServiceRole', () {
    test('the service role key, inside only, and in what it starts', () async {
      final c = credentials(session: _Session('user-token'));
      late Future<String> later;
      final inside = await c.asServiceRole(() async {
        later = Future<void>.delayed(
          Duration.zero,
        ).then((_) => c.accessToken());
        return (c.apiKey, await c.accessToken(), c.caller);
      });
      expect(inside, (
        'service-key',
        'service-key',
        const SupabaseCaller.service(),
      ));
      expect(await later, 'service-key');
      expect(c.apiKey, 'anon-key');
      expect(await c.accessToken(), 'user-token');
    });

    test('without the key it fails before the body runs', () {
      var ran = false;
      expect(
        () => credentials(serviceRole: false).asServiceRole(() => ran = true),
        throwsStateError,
      );
      expect(ran, isFalse);
    });

    test('an error of the body comes out', () async {
      await expectLater(
        credentials().asServiceRole<void>(() => throw const FormatException()),
        throwsFormatException,
      );
    });
  });

  test('no anon key is an error that names the property', () {
    final c = DefaultSupabaseCredentials(
      properties: SupabaseProperties()..url = projectUrl,
      authentication: () => null,
    );
    expect(
      () => c.apiKey,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('spring.supabase.anon-key'),
        ),
      ),
    );
  });
}
