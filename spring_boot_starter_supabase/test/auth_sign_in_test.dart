@Tags(['supabase'])
library;

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'auth_support.dart';
import 'support.dart';

void main() {
  late AuthHarness harness;
  late MockHttpTransport transport;

  setUp(() {
    harness = AuthHarness();
    transport = harness.transport;
  });

  void expectAnonCall(HttpRequest request, String url) {
    expect('${request.url}', url);
    expect(request.headers['apikey'], 'anon-key');
    expect(request.headers['Authorization'], 'Bearer anon-key');
    expect(request.followRedirects, isFalse);
  }

  group('signInWithPassword', () {
    test('posts the email and the password as the anon key', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
          .respond(200, json: sessionJson());
      final auth = harness.auth();
      final authentication = await auth.signInWithPassword(
        email: ' ada@example.com ',
        password: 'correct horse',
      );
      final request = transport.requests.single;
      expectAnonCall(
        request,
        '$projectUrl/auth/v1/token?grant_type=password',
      );
      expect(request.method, HttpMethod.post);
      expect(request.headers['Content-Type'], 'application/json');
      expect(bodyOf(request), {
        'email': 'ada@example.com',
        'password': 'correct horse',
      });
      expect(authentication.name, userId);
      expect(authentication.isAuthenticated, isTrue);
      expect(authentication.principal.email, 'ada@example.com');
      expect(authentication.credentials.tokenValue, 'access-token-1');
      expect(authentication.credentials.issuedAt, harness.clock.now);
      expect(
        authentication.credentials.expiresAt,
        harness.clock.now.add(const Duration(hours: 1)),
      );
      expect(auth.isLoggedIn, isTrue);
      expect(auth.authentication, same(authentication));
      expect(auth.user!.id, userId);
      expect(await auth.accessToken(), 'access-token-1');
    });

    test('a phone instead of an email', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
          .respond(200, json: sessionJson());
      await harness.auth().signInWithPassword(
        phone: '+15550100',
        password: 'correct horse',
      );
      expect(bodyOf(transport.requests.single), {
        'phone': '+15550100',
        'password': 'correct horse',
      });
    });

    test('neither or both of email and phone, or no password: no request', () {
      final auth = harness.auth();
      expect(() => auth.signInWithPassword(password: 'p'), throwsArgumentError);
      expect(
        () =>
            auth.signInWithPassword(email: 'a@b.c', phone: '+1', password: 'p'),
        throwsArgumentError,
      );
      expect(
        () => auth.signInWithPassword(email: 'a@b.c', password: ''),
        throwsArgumentError,
      );
      expect(transport.requests, isEmpty);
    });

    test(
      'sets the context, tells the stream and publishes the event',
      () async {
        final auth = await harness.signedIn();
        await settle();
        final authentication = auth.authentication!;
        expect(
          harness.contexts.getContext().authentication,
          same(authentication),
        );
        expect(harness.changes, [same(authentication)]);
        expect(harness.publisher.events, hasLength(1));
        expect(
          harness.publisher.events.single,
          isA<AuthenticationSuccessEvent>().having(
            (e) => e.authentication,
            'authentication',
            same(authentication),
          ),
        );
      },
    );

    test(
      'without a strategy of its own it sets SecurityContextHolder',
      () async {
        final previous = SecurityContextHolder.getContextHolderStrategy();
        SecurityContextHolder.setContextHolderStrategy(
          GlobalSecurityContextHolderStrategy(),
        );
        addTearDown(
          () => SecurityContextHolder.setContextHolderStrategy(previous),
        );
        transport
            .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
            .respond(200, json: sessionJson());
        transport.when(HttpMethod.post, '/auth/v1/logout').respond(204);
        final auth = SupabaseAuth(http: http(transport));
        addTearDown(auth.destroy);
        await auth.signInWithPassword(
          email: 'a@b.c',
          password: 'correct horse',
        );
        expect(
          SecurityContextHolder.getContext().authentication,
          same(auth.authentication),
        );
        await auth.logout();
        expect(SecurityContextHolder.getContext().authentication, isNull);
      },
    );

    test(
      'wrong credentials are a BadCredentialsException with the code',
      () async {
        transport
            .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
            .respond(
              400,
              json: errorJson(
                400,
                'invalid_credentials',
                'Invalid login credentials',
              ),
            );
        final auth = harness.auth();
        await expectLater(
          auth.signInWithPassword(email: 'a@b.c', password: 'wrong horse'),
          throwsA(
            isA<BadCredentialsException>()
                .having(
                  (e) => e.message,
                  'message',
                  'Invalid login credentials',
                )
                .having(
                  (e) => (e as SupabaseAuthFailure).errorCode,
                  'errorCode',
                  'invalid_credentials',
                )
                .having(
                  (e) => (e as SupabaseAuthFailure).statusCode,
                  'statusCode',
                  400,
                ),
          ),
        );
        await settle();
        expect(auth.isLoggedIn, isFalse);
        expect(harness.contexts.getContext().authentication, isNull);
        expect(harness.changes, isEmpty);
        expect(harness.publisher.events, isEmpty);
        expect(await harness.store.keys(), isEmpty);
      },
    );

    test('an answer without a session signs nobody in', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
          .respond(200, json: {'access_token': 'access-token-1'});
      final auth = harness.auth();
      await expectLater(
        auth.signInWithPassword(email: 'a@b.c', password: 'correct horse'),
        throwsA(isA<SupabaseAuthenticationException>()),
      );
      expect(auth.isLoggedIn, isFalse);
    });

    test('no answer at all is a SupabaseUnavailableException', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
          .fail(HttpTransportException('connection refused'));
      final auth = harness.auth();
      await expectLater(
        auth.signInWithPassword(email: 'a@b.c', password: 'correct horse'),
        throwsA(isA<SupabaseUnavailableException>()),
      );
      expect(auth.isLoggedIn, isFalse);
    });
  });

  group('errors', () {
    Future<Object> failure(int status, Object json) async {
      transport
          .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
          .respond(status, json: json);
      try {
        await harness.auth().signInWithPassword(
          email: 'a@b.c',
          password: 'correct horse',
        );
      } on Object catch (e) {
        return e;
      }
      fail('The login did not fail');
    }

    test("each of Auth's codes has its Spring Security exception", () async {
      for (final (code, matcher) in <(String, Matcher)>[
        ('invalid_credentials', isA<BadCredentialsException>()),
        ('otp_expired', isA<BadCredentialsException>()),
        ('bad_code_verifier', isA<BadCredentialsException>()),
        ('flow_state_not_found', isA<BadCredentialsException>()),
        ('email_not_confirmed', isA<DisabledException>()),
        ('phone_not_confirmed', isA<DisabledException>()),
        ('user_banned', isA<LockedException>()),
        ('session_not_found', isA<CredentialsExpiredException>()),
        ('refresh_token_already_used', isA<CredentialsExpiredException>()),
        ('user_not_found', isA<UsernameNotFoundException>()),
        ('weak_password', isA<SupabaseWeakPasswordException>()),
        ('over_request_rate_limit', isA<SupabaseAuthenticationException>()),
        ('signup_disabled', isA<SupabaseAuthenticationException>()),
      ]) {
        transport.reset();
        final error = await failure(400, errorJson(400, code, 'refused'));
        expect(error, matcher, reason: code);
        expect(error, isA<AuthenticationException>(), reason: code);
        expect((error as SupabaseAuthFailure).errorCode, code);
        expect('$error', contains('[$code]'));
        expect('$error', contains('(400)'));
      }
    });

    test('the older shape: error and error_description', () async {
      final error = await failure(400, {
        'error': 'invalid_grant',
        'error_description': 'Invalid login credentials',
      });
      expect(
        error,
        isA<BadCredentialsException>()
            .having((e) => e.message, 'message', 'Invalid login credentials')
            .having(
              (e) => (e as SupabaseAuthFailure).errorCode,
              'errorCode',
              'invalid_grant',
            ),
      );
    });

    test('the versioned shape: a text code and message', () async {
      final error = await failure(400, {
        'code': 'email_not_confirmed',
        'message': 'Email not confirmed',
      });
      expect(
        error,
        isA<DisabledException>().having(
          (e) => e.message,
          'message',
          'Email not confirmed',
        ),
      );
    });

    test('the reasons of a weak password', () async {
      final error = await failure(422, {
        'code': 422,
        'error_code': 'weak_password',
        'msg': 'Password should be at least 12 characters',
        'weak_password': {
          'reasons': ['length', 'pwned'],
        },
      });
      expect(
        error,
        isA<SupabaseWeakPasswordException>()
            .having((e) => e.reasons, 'reasons', ['length', 'pwned'])
            .having((e) => e.statusCode, 'statusCode', 422),
      );
    });

    test(
      'a failure of the service is an AuthenticationServiceException',
      () async {
        final error = await failure(
          500,
          errorJson(500, 'unexpected_failure', 'Database error'),
        );
        expect(error, isA<AuthenticationServiceException>());
        expect((error as SupabaseAuthFailure).statusCode, 500);
      },
    );

    test('an answer that is no JSON keeps its status only', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
          .respond(502, body: '<html>Bad Gateway</html>');
      await expectLater(
        harness.auth().signInWithPassword(
          email: 'a@b.c',
          password: 'correct horse',
        ),
        throwsA(
          isA<SupabaseAuthServiceException>()
              .having((e) => e.message, 'message', 'Supabase Auth answered 502')
              .having((e) => e.errorCode, 'errorCode', isNull),
        ),
      );
    });

    test('a translator of the application is asked first', () async {
      final errors = SupabaseAuthErrors([
        SupabaseAuthErrorCodes(
          const {'invalid_credentials', 'trial_ended'},
          (e) => AccountExpiredException(e.message),
        ),
      ]);
      expect(
        errors.translate(
          SupabaseAuthError(
            statusCode: 400,
            code: 'trial_ended',
            message: 'over',
          ),
        ),
        isA<AccountExpiredException>(),
      );
      expect(
        errors.translate(
          SupabaseAuthError(
            statusCode: 400,
            code: 'invalid_credentials',
            message: 'no',
          ),
        ),
        isA<AccountExpiredException>(),
      );
      expect(
        errors.translate(
          SupabaseAuthError(
            statusCode: 400,
            code: 'user_banned',
            message: 'no',
          ),
        ),
        isA<LockedException>(),
      );
    });
  });

  group('authorities', () {
    Future<SupabaseAuthenticationToken> login(Map<String, Object?> user) async {
      transport
          .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
          .respond(200, json: sessionJson(user: user));
      return await harness.auth().signInWithPassword(
        email: 'a@b.c',
        password: 'correct horse',
      );
    }

    List<String> names(Authentication authentication) => [
      for (final authority in authentication.authorities) ?authority.authority,
    ];

    test('ROLE_<role> for each string of app_metadata.roles', () async {
      final authentication = await login(
        userJson(
          appMetadata: {
            'provider': 'email',
            'roles': ['editor', ' admin ', '', 7, null],
          },
        ),
      );
      expect(names(authentication), ['ROLE_editor', 'ROLE_admin']);
    });

    test('roles as one text are split at spaces', () async {
      final authentication = await login(
        userJson(appMetadata: {'roles': 'editor  admin'}),
      );
      expect(names(authentication), ['ROLE_editor', 'ROLE_admin']);
    });

    test('roles in user_metadata are ignored: the user can write it', () async {
      final authentication = await login(
        userJson(
          userMetadata: {
            'roles': ['admin'],
            'role': 'admin',
            'app_metadata': {
              'roles': ['admin'],
            },
          },
        ),
      );
      expect(authentication.authorities, isEmpty);
      expect(authentication.principal.roles, isEmpty);
      expect(authentication.principal.userMetadata['roles'], ['admin']);
    });

    test('the database role is no authority, nor is anything else', () async {
      final authentication = await login(
        userJson(
          appMetadata: {
            'provider': 'email',
            'providers': ['email'],
            'role': 'admin',
            'roles': {'admin': true},
          },
        ),
      );
      expect(authentication.authorities, isEmpty);
    });

    test('the user is read from the answer', () async {
      final authentication = await login(
        userJson(
          appMetadata: {'tenant': 't1'},
          userMetadata: {'name': 'Ada'},
        ),
      );
      final user = authentication.principal;
      expect(user.id, userId);
      expect(user.email, 'ada@example.com');
      expect(user.phone, isNull);
      expect(user.role, 'authenticated');
      expect(user.appMetadata, {'tenant': 't1'});
      expect(user.userMetadata, {'name': 'Ada'});
      expect(user.createdAt, DateTime.utc(2026, 11, 1, 9));
      expect(user.updatedAt, DateTime.utc(2026, 11, 10, 11, 59));
      expect(user.emailConfirmedAt, DateTime.utc(2026, 11, 1, 10));
      expect(user.phoneConfirmedAt, isNull);
      expect(user.lastSignInAt, DateTime.utc(2026, 11, 10, 11, 59));
      expect(user.isAnonymous, isFalse);
      expect(() => user.appMetadata['x'] = 1, throwsUnsupportedError);
      expect(SupabaseUser.fromJson(user.toJson())!.toJson(), user.toJson());
    });
  });

  group('signUp', () {
    test('a project that confirms by itself answers with a session', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/signup')
          .respond(200, json: sessionJson());
      final auth = harness.auth();
      final authentication = await auth.signUp(
        email: 'ada@example.com',
        password: 'correct horse',
        data: {'name': 'Ada'},
      );
      final request = transport.requests.single;
      expectAnonCall(request, '$projectUrl/auth/v1/signup');
      final body = bodyOf(request);
      expect(body['email'], 'ada@example.com');
      expect(body['password'], 'correct horse');
      expect(body['data'], {'name': 'Ada'});
      expect(body['code_challenge_method'], 's256');
      expect(body['code_challenge'], hasLength(43));
      expect(authentication, isNotNull);
      expect(auth.isLoggedIn, isTrue);
      expect(
        harness.publisher.events.single,
        isA<AuthenticationSuccessEvent>(),
      );
      // Signed in at once: no link comes back for the verifier.
      expect(await harness.store.read(SupabaseAuth.pkceKey), isNull);
    });

    test('a project that confirms by email signs nobody in yet', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/signup')
          .respond(200, json: userJson());
      final auth = harness.auth(redirectUrls: ['myapp://callback']);
      final authentication = await auth.signUp(
        email: 'ada@example.com',
        password: 'correct horse',
      );
      await settle();
      expect(authentication, isNull);
      expect(auth.isLoggedIn, isFalse);
      expect(harness.changes, isEmpty);
      expect(harness.publisher.events, isEmpty);
      expect(await harness.storedSession(), isNull);
      expect(
        '${transport.requests.single.url}',
        '$projectUrl/auth/v1/signup?redirect_to=myapp%3A%2F%2Fcallback',
      );
      // The link of the email is finished with the verifier.
      expect(await harness.store.read(SupabaseAuth.pkceKey), isNotNull);
    });

    test('a phone: no link, so no challenge and no redirect', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/signup')
          .respond(200, json: userJson());
      await harness
          .auth(redirectUrls: ['myapp://callback'])
          .signUp(phone: '+15550100', password: 'correct horse');
      final request = transport.requests.single;
      expect('${request.url}', '$projectUrl/auth/v1/signup');
      expect(bodyOf(request), {
        'phone': '+15550100',
        'password': 'correct horse',
        'data': <String, Object?>{},
        'channel': 'sms',
      });
      expect(await harness.store.read(SupabaseAuth.pkceKey), isNull);
    });

    test('a refused sign-up keeps no verifier', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/signup')
          .respond(
            422,
            json: errorJson(422, 'signup_disabled', 'Signups not allowed'),
          );
      await expectLater(
        harness.auth().signUp(email: 'a@b.c', password: 'correct horse'),
        throwsA(
          isA<SupabaseAuthenticationException>().having(
            (e) => e.errorCode,
            'errorCode',
            'signup_disabled',
          ),
        ),
      );
      expect(await harness.store.keys(), isEmpty);
    });
  });

  group('signInWithOtp and verifyOtp', () {
    test('asks for a code or a link by email', () async {
      transport.when(HttpMethod.post, '/auth/v1/otp').respond(200, json: {});
      final auth = harness.auth(redirectUrls: ['myapp://callback']);
      await auth.signInWithOtp(email: 'ada@example.com', createUser: false);
      final request = transport.requests.single;
      expectAnonCall(
        request,
        '$projectUrl/auth/v1/otp?redirect_to=myapp%3A%2F%2Fcallback',
      );
      final body = bodyOf(request);
      expect(body['email'], 'ada@example.com');
      expect(body['create_user'], isFalse);
      expect(body['code_challenge_method'], 's256');
      expect(body['code_challenge'], hasLength(43));
      expect(auth.isLoggedIn, isFalse);
    });

    test('asks for a code by SMS', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/otp')
          .respond(200, json: {'message_id': 'm1'});
      await harness.auth().signInWithOtp(phone: '+15550100');
      final request = transport.requests.single;
      expect('${request.url}', '$projectUrl/auth/v1/otp');
      expect(bodyOf(request), {
        'phone': '+15550100',
        'create_user': true,
        'channel': 'sms',
      });
    });

    test('the code signs in', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/verify')
          .respond(200, json: sessionJson());
      final auth = harness.auth();
      final authentication = await auth.verifyOtp(
        email: 'ada@example.com',
        token: '482913',
        type: SupabaseOtpType.email,
      );
      final request = transport.requests.single;
      expectAnonCall(request, '$projectUrl/auth/v1/verify');
      expect(bodyOf(request), {
        'email': 'ada@example.com',
        'token': '482913',
        'type': 'email',
      });
      expect(authentication.name, userId);
      expect(auth.isLoggedIn, isTrue);
    });

    test('every type has the name Auth knows', () {
      expect(
        {for (final type in SupabaseOtpType.values) type.value},
        {
          'email',
          'sms',
          'signup',
          'invite',
          'magiclink',
          'recovery',
          'email_change',
          'phone_change',
        },
      );
    });

    test('a wrong or old code is a BadCredentialsException', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/verify')
          .respond(
            403,
            json: errorJson(
              403,
              'otp_expired',
              'Token has expired or is invalid',
            ),
          );
      final auth = harness.auth();
      await expectLater(
        auth.verifyOtp(
          phone: '+15550100',
          token: '000000',
          type: SupabaseOtpType.sms,
        ),
        throwsA(isA<BadCredentialsException>()),
      );
      expect(auth.isLoggedIn, isFalse);
    });
  });

  group('signInWithIdToken', () {
    test('posts the provider and its tokens', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/token?grant_type=id_token')
          .respond(200, json: sessionJson());
      final auth = harness.auth();
      await auth.signInWithIdToken(
        provider: 'google',
        idToken: 'google-id-token',
        accessToken: 'google-access-token',
        nonce: 'nonce-1',
      );
      final request = transport.requests.single;
      expectAnonCall(request, '$projectUrl/auth/v1/token?grant_type=id_token');
      expect(bodyOf(request), {
        'provider': 'google',
        'id_token': 'google-id-token',
        'access_token': 'google-access-token',
        'nonce': 'nonce-1',
      });
      expect(auth.isLoggedIn, isTrue);
    });

    test('only what is given is sent', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/token?grant_type=id_token')
          .respond(200, json: sessionJson());
      await harness.auth().signInWithIdToken(
        provider: 'apple',
        idToken: 'apple-id-token',
      );
      expect(bodyOf(transport.requests.single), {
        'provider': 'apple',
        'id_token': 'apple-id-token',
      });
    });
  });

  group('resetPassword', () {
    test('asks for the email, to come back to the first redirect', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/recover')
          .respond(200, json: {});
      final auth = harness.auth(
        redirectUrls: ['myapp://callback', 'myapp://reset'],
      );
      await auth.resetPassword('ada@example.com', redirectTo: 'myapp://reset');
      final request = transport.requests.single;
      expectAnonCall(
        request,
        '$projectUrl/auth/v1/recover?redirect_to=myapp%3A%2F%2Freset',
      );
      final body = bodyOf(request);
      expect(body['email'], 'ada@example.com');
      expect(body['code_challenge_method'], 's256');
      expect(body['code_challenge'], hasLength(43));
      expect(body.keys, hasLength(3));
    });

    test('without redirect addresses none is sent', () async {
      transport
          .when(HttpMethod.post, '/auth/v1/recover')
          .respond(200, json: {});
      await harness.auth().resetPassword('ada@example.com');
      expect(
        '${transport.requests.single.url}',
        '$projectUrl/auth/v1/recover',
      );
    });
  });

  group('updateUser and reloadUser', () {
    test("puts the changes with the user's token", () async {
      final auth = await harness.signedIn();
      transport
          .when(HttpMethod.put, '/auth/v1/user')
          .respond(
            200,
            json: userJson(
              appMetadata: {
                'roles': ['editor'],
              },
              userMetadata: {'name': 'Ada L.'},
            ),
          );
      final before = auth.authentication;
      await settle();
      harness.changes.clear();
      harness.publisher.events.clear();
      final user = await auth.updateUser(
        password: 'new correct horse',
        data: {'name': 'Ada L.'},
      );
      await settle();
      final request = transport.requests.last;
      expect('${request.url}', '$projectUrl/auth/v1/user');
      expect(request.method, HttpMethod.put);
      expect(request.headers['apikey'], 'anon-key');
      expect(request.headers['Authorization'], 'Bearer access-token-1');
      expect(bodyOf(request), {
        'password': 'new correct horse',
        'data': {'name': 'Ada L.'},
      });
      expect(user.userMetadata, {'name': 'Ada L.'});
      // The new user is the login's, with the same tokens.
      expect(auth.user, same(user));
      expect(auth.authentication, isNot(same(before)));
      expect(auth.authentication!.credentials.tokenValue, 'access-token-1');
      expect(auth.authentication!.authorities.single.authority, 'ROLE_editor');
      expect(
        harness.contexts.getContext().authentication,
        same(auth.authentication),
      );
      expect(harness.changes, [same(auth.authentication)]);
      expect(harness.publisher.events, isEmpty);
      final stored = await harness.storedSession();
      expect((stored!['user']! as Map)['user_metadata'], {'name': 'Ada L.'});
      expect(stored['refresh_token'], 'refresh-token-1');
    });

    test('needs something to change and somebody signed in', () async {
      final auth = harness.auth();
      expect(auth.updateUser, throwsArgumentError);
      await expectLater(
        auth.updateUser(email: 'new@example.com'),
        throwsA(isA<AuthenticationCredentialsNotFoundException>()),
      );
      expect(transport.requests, isEmpty);
    });

    test('reloadUser reads the user again', () async {
      final auth = await harness.signedIn();
      transport
          .when(HttpMethod.get, '/auth/v1/user')
          .respond(200, json: userJson(email: 'new@example.com'));
      final user = await auth.reloadUser();
      final request = transport.requests.last;
      expect(request.method, HttpMethod.get);
      expect(request.headers['Authorization'], 'Bearer access-token-1');
      expect(request.body, isNull);
      expect(user.email, 'new@example.com');
      expect(auth.user!.email, 'new@example.com');
    });

    test('a session that is gone at Auth signs out here', () async {
      final auth = await harness.signedIn();
      transport
          .when(HttpMethod.put, '/auth/v1/user')
          .respond(
            403,
            json: errorJson(
              403,
              'session_not_found',
              'Session from session_id claim in JWT does not exist',
            ),
          );
      await expectLater(
        auth.updateUser(data: {'a': 1}),
        throwsA(isA<SupabaseSessionExpiredException>()),
      );
      await settle();
      expect(auth.isLoggedIn, isFalse);
      expect(harness.contexts.getContext().authentication, isNull);
      expect(harness.changes.last, isNull);
      expect(await harness.storedSession(), isNull);
    });

    test('any other refusal keeps the session', () async {
      final auth = await harness.signedIn();
      transport
          .when(HttpMethod.put, '/auth/v1/user')
          .respond(
            422,
            json: errorJson(422, 'same_password', 'New password should differ'),
          );
      await expectLater(
        auth.updateUser(password: 'correct horse'),
        throwsA(
          isA<SupabaseAuthenticationException>().having(
            (e) => e.errorCode,
            'errorCode',
            'same_password',
          ),
        ),
      );
      expect(auth.isLoggedIn, isTrue);
    });
  });
}
