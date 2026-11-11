@Tags(['supabase', 'supabase-stack'])
library;

// Level 4, Auth: what only the real service answers. Sign-up, sign-in,
// the rotation of refresh tokens and their replay, what a logout revokes,
// codes and links of mails (PKCE), the redirect allow-list as the server
// applies it, the admin API, and the keys the project's tokens are
// checked with on a server.
import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:test/test.dart';

import 'server_support.dart' show TestServer;
import 'stack_support.dart';

void main() {
  group('Auth of the stack', skip: Stack.skip, () {
    // Never signed in: the admin API, and the users it deletes at the end.
    late StackApp project;

    setUpAll(() async {
      Stack.require();
      project = await StackApp.start();
    });

    tearDownAll(() => project.close());

    // A fresh application (one login) for [body], run as that application.
    Future<void> withApp(
      Future<void> Function(StackApp app) body, {
      List<String>? redirectUrls,
    }) async {
      final app = await StackApp.start(redirectUrls: redirectUrls);
      try {
        await app.run(() => body(app));
      } finally {
        await app.close();
      }
    }

    Future<HttpResponse> refreshWith(StackApp app, String refreshToken) =>
        app.http.send(
          SupabaseService.auth,
          HttpMethod.post,
          '/token',
          query: const [MapEntry('grant_type', 'refresh_token')],
          json: {'refresh_token': refreshToken},
          bearer: Stack.anonKey,
        );

    // Auth's error code of a refused request.
    String? errorCode(HttpResponse response) =>
        switch (jsonDecode(response.bodyText)) {
          {'error_code': final String code} => code,
          {'code': final String code} => code,
          {'error': final String code} => code,
          _ => null,
        };

    final badCredentials = isA<BadCredentialsException>().having(
      (e) => switch (e as Object) {
        SupabaseAuthFailure(:final errorCode) => errorCode,
        _ => null,
      },
      'errorCode',
      'invalid_credentials',
    );

    group('passwords', () {
      test('a sign-up signs the user in, and the project takes their '
          'token', () async {
        await withApp((app) async {
          final (:email, :password) = StackUser.credentials();
          final signedUp = await app.auth.signUp(
            email: email,
            password: password,
            data: {'name': 'Ada'},
          );
          if (signedUp == null) {
            // A project that confirms addresses first (not the local
            // stack): confirmed here, then the password signs in.
            final id = await project.userIdOf(email);
            expect(id, isNotNull, reason: 'the sign-up made no user');
            project.deleteAtClose(id!);
            await project.admin.updateUser(id, emailConfirm: true);
            await app.auth.signInWithPassword(
              email: email,
              password: password,
            );
          }
          final id = app.userId;
          project.deleteAtClose(id);

          expect(app.auth.isLoggedIn, isTrue);
          expect(app.auth.user?.email, email);
          expect(app.auth.user?.userMetadata['name'], 'Ada');
          expect(app.credentials.caller, SupabaseCaller.user(id));

          // Auth knows the token, and so does the REST API: a row saved
          // through it is the user's.
          expect((await app.auth.reloadUser()).id, id);
          final saved = await app.todos.save(
            Todo(title: 'mine', listId: Stack.unique('l')),
          );
          try {
            expect((await app.todos.findById(saved.id!))?.title, 'mine');
          } finally {
            await app.todos.deleteById(saved.id!);
          }
        });
      });

      test("a sign-in gives a session whose token is the project's; a "
          'wrong password is refused with invalid_credentials', () async {
        await withApp((app) async {
          final user = await app.createUser();
          await expectLater(
            app.auth.signInWithPassword(
              email: user.email,
              password: 'not-${user.password}',
            ),
            throwsA(badCredentials),
          );
          expect(app.auth.isLoggedIn, isFalse);

          final signedIn = await app.auth.signInWithPassword(
            email: user.email,
            password: user.password,
          );
          expect(signedIn.name, user.id);
          expect(signedIn.principal.email, user.email);
          expect(signedIn.principal.role, 'authenticated');

          final session = (await app.session())!;
          expect(session.refreshToken, isNotEmpty);
          expect(session.expiresAt!.isAfter(DateTime.now()), isTrue);
          expect(signedIn.credentials.tokenValue, session.accessToken);
          // What the server's defaults of the starter check.
          final claims = supabaseTokenClaims(session.accessToken)!;
          expect(claims['iss'], '${Stack.url}/auth/v1');
          expect(claims['aud'], 'authenticated');
          expect(claims['role'], 'authenticated');
          expect(claims['sub'], user.id);
        });
      });

      test('updateUser: the metadata is merged, a new password replaces '
          'the old one', () async {
        await withApp((app) async {
          final user = await app.signInAsNewUser();
          final changed = await app.auth.updateUser(data: {'theme': 'dark'});
          expect(changed.id, user.id);
          expect(changed.userMetadata['theme'], 'dark');
          expect(app.auth.user?.userMetadata['theme'], 'dark');

          final password = Stack.unique('New-');
          await app.auth.updateUser(password: password);
          // Still signed in, with a session Auth knows.
          expect((await app.auth.reloadUser()).id, user.id);
          await app.auth.logout();

          await expectLater(
            app.auth.signInWithPassword(
              email: user.email,
              password: user.password,
            ),
            throwsA(badCredentials),
          );
          await app.auth.signInWithPassword(
            email: user.email,
            password: password,
          );
          expect(
            (await app.auth.reloadUser()).userMetadata['theme'],
            'dark',
          );
        });
      });
    });

    group('the session', () {
      test('a refresh gives a new pair of tokens, and the project takes '
          'the new access token', () async {
        await withApp((app) async {
          final user = await app.signInAsNewUser();
          final first = (await app.session())!;
          // A token says when it was made, to the second.
          await Future<void>.delayed(const Duration(milliseconds: 1100));

          final refreshed = await app.auth.refreshSession();
          final second = (await app.session())!;
          expect(refreshed.name, user.id);
          expect(refreshed.credentials.tokenValue, second.accessToken);
          expect(second.refreshToken, isNot(first.refreshToken));
          expect(second.accessToken, isNot(first.accessToken));
          expect(await app.credentials.accessToken(), second.accessToken);

          expect((await app.auth.reloadUser()).id, user.id);
          // A call the anon key is refused: the new token is a user's.
          expect(await app.todos.count(), 0);
        });
      });

      test('a refresh token of two rotations ago is refused, and its '
          'replay ends the session', () async {
        await withApp((app) async {
          await app.signInAsNewUser();
          final old = (await app.session())!.refreshToken;
          await app.auth.refreshSession();
          final parent = (await app.session())!.refreshToken;
          await app.auth.refreshSession();
          final current = (await app.session())!.refreshToken;
          expect({old, parent, current}, hasLength(3));

          // Auth takes a used token again for a while
          // (refresh_token_reuse_interval), and the parent of the current
          // one always: neither is the case of `old` after the wait.
          await Future<void>.delayed(
            Stack.refreshReuseInterval + const Duration(milliseconds: 1500),
          );
          final replay = await refreshWith(app, old);
          expect(replay.statusCode.value, 400, reason: replay.bodyText);
          expect(SupabaseAuth.sessionEndingCodes, contains(errorCode(replay)));

          // The replay revoked the whole session: its newest refresh
          // token is refused too, and the starter signs the user out.
          expect(app.auth.isLoggedIn, isTrue);
          await expectLater(
            app.auth.refreshSession(),
            throwsA(
              isA<SupabaseSessionExpiredException>().having(
                (e) => e.errorCode,
                'errorCode',
                isIn(SupabaseAuth.sessionEndingCodes),
              ),
            ),
          );
          expect(app.auth.isLoggedIn, isFalse);
          expect(await app.session(), isNull);
          expect(app.credentials.caller, const SupabaseCaller.anon());
        });
      });

      test('a logout revokes the session at Auth: its refresh token and '
          'its access token are refused there', () async {
        await withApp((app) async {
          await app.signInAsNewUser();
          final session = (await app.session())!;

          await app.auth.logout();
          expect(app.auth.isLoggedIn, isFalse);
          expect(await app.session(), isNull);
          expect(app.credentials.caller, const SupabaseCaller.anon());
          expect(await app.credentials.accessToken(), Stack.anonKey);

          final refresh = await refreshWith(app, session.refreshToken);
          expect(refresh.isSuccess, isFalse, reason: 'the token was taken');
          expect(
            SupabaseAuth.sessionEndingCodes,
            contains(errorCode(refresh)),
          );
          // The access token is still a signed token until it expires,
          // but Auth no longer has its session.
          final me = await app.http.send(
            SupabaseService.auth,
            HttpMethod.get,
            '/user',
            bearer: session.accessToken,
          );
          expect(me.isSuccess, isFalse, reason: 'the session was not ended');
        });
      });
    });

    group('mails', skip: Stack.skipMail, () {
      final mails = MailCatcher();

      test('a one-time code signs in, once', () async {
        await withApp((app) async {
          final user = await app.createUser();
          await app.auth.signInWithOtp(email: user.email, createUser: false);
          expect(app.auth.isLoggedIn, isFalse);

          final mail = await mails.next(user.email);
          final signedIn = await app.auth.verifyOtp(
            email: user.email,
            token: mail.code,
            type: SupabaseOtpType.email,
          );
          expect(signedIn.name, user.id);
          expect((await app.auth.reloadUser()).email, user.email);

          await app.auth.logout();
          await expectLater(
            app.auth.verifyOtp(
              email: user.email,
              token: mail.code,
              type: SupabaseOtpType.email,
            ),
            throwsA(isA<AuthenticationException>()),
          );
          expect(app.auth.isLoggedIn, isFalse);
        });
      });

      test('a code sent to a new address makes the user', () async {
        await withApp((app) async {
          final (:email, password: _) = StackUser.credentials();
          await app.auth.signInWithOtp(email: email);
          final mail = await mails.next(email);
          final signedIn = await app.auth.verifyOtp(
            email: email,
            token: mail.code,
            type: SupabaseOtpType.email,
          );
          project.deleteAtClose(signedIn.name);
          expect(signedIn.principal.email, email);
          expect(await project.admin.user(signedIn.name), isNotNull);
        });
      });

      test('a magic link comes back to the allowed address with a code, '
          'which the verifier of the login exchanges (PKCE)', () async {
        await withApp((app) async {
          final user = await app.createUser();
          await app.auth.signInWithOtp(
            email: user.email,
            createUser: false,
            redirectTo: Stack.redirectUrl,
          );
          final mail = await mails.next(user.email);
          // The link of a login with a code challenge.
          expect(mail.link.path, endsWith('/auth/v1/verify'));
          expect(mail.link.queryParameters['token'], startsWith('pkce_'));
          expect(mail.link.queryParameters['redirect_to'], Stack.redirectUrl);

          final redirect = await mail.follow();
          expect('$redirect', startsWith(Stack.redirectUrl));
          expect(redirect.queryParameters['code'], isNotEmpty);
          expect(app.auth.isLoggedIn, isFalse);

          final signedIn = await app.auth.completeSignIn(redirect);
          expect(signedIn.name, user.id);
          expect((await app.auth.reloadUser()).id, user.id);
          // The verifier is spent.
          expect(await app.secrets.read(SupabaseAuth.pkceKey), isNull);
        });
      });

      test('the code of a link is worth nothing without the verifier of '
          'the login that asked for it', () async {
        await withApp((app) async {
          final user = await app.createUser();
          await app.auth.signInWithOtp(
            email: user.email,
            createUser: false,
            redirectTo: Stack.redirectUrl,
          );
          final redirect = await (await mails.next(user.email)).follow();
          final code = redirect.queryParameters['code']!;

          // Another application, with a login of its own waiting.
          final thief = await StackApp.start();
          try {
            await thief.run(() async {
              final other = await thief.createUser();
              await thief.auth.signInWithOtp(
                email: other.email,
                createUser: false,
              );
              await expectLater(
                thief.auth.exchangeCode(code),
                throwsA(isA<AuthenticationException>()),
              );
              expect(thief.auth.isLoggedIn, isFalse);
            });
          } finally {
            await thief.close();
          }
        });
      });

      test('a password reset: the link signs in, updateUser sets the new '
          'password', () async {
        await withApp((app) async {
          final user = await app.createUser();
          await app.auth.resetPassword(
            user.email,
            redirectTo: Stack.redirectUrl,
          );
          final mail = await mails.next(user.email);
          expect(mail.link.queryParameters['type'], 'recovery');

          final signedIn = await app.auth.completeSignIn(await mail.follow());
          expect(signedIn.name, user.id);

          final password = Stack.unique('Reset-');
          await app.auth.updateUser(password: password);
          await app.auth.logout();
          await app.auth.signInWithPassword(
            email: user.email,
            password: password,
          );
          expect(app.userId, user.id);
        });
      });

      test("an address that is not in the project's list is replaced by "
          'the site URL, and the starter does not finish that '
          'login', () async {
        await withApp(
          redirectUrls: [Stack.redirectUrl, Stack.strangerRedirectUrl],
          (app) async {
            final user = await app.createUser();
            // The application's own list allows it; the project's does
            // not.
            await app.auth.signInWithOtp(
              email: user.email,
              createUser: false,
              redirectTo: Stack.strangerRedirectUrl,
            );
            final mail = await mails.next(user.email);
            final stranger = Uri.parse(Stack.strangerRedirectUrl).host;
            expect(
              mail.link.queryParameters['redirect_to'],
              isNot(contains(stranger)),
            );

            final redirect = await mail.follow();
            expect(redirect.host, isNot(stranger));
            expect('$redirect', startsWith(Stack.siteUrl));

            await expectLater(
              app.auth.completeSignIn(redirect),
              throwsA(isA<AuthenticationException>()),
            );
            expect(app.auth.isLoggedIn, isFalse);
          },
        );
      });
    });

    group('the admin API', () {
      test('creates, reads, changes and deletes a user; the roles it '
          'writes are the authorities of their login', () async {
        final (:email, :password) = StackUser.credentials();
        final created = await project.admin.createUser(
          email: email,
          password: password,
          emailConfirm: true,
          appMetadata: {
            'roles': ['editor'],
          },
          userMetadata: {'name': 'Grace'},
        );
        try {
          expect(created.email, email);
          expect(created.emailConfirmedAt, isNotNull);
          expect(created.roles, ['editor']);
          expect(created.userMetadata['name'], 'Grace');

          final read = await project.admin.user(created.id);
          expect(read?.email, email);
          expect(read?.roles, ['editor']);
          expect(await project.userIdOf(email), created.id);

          final changed = await project.admin.updateUser(
            created.id,
            appMetadata: {
              'roles': ['editor', 'admin'],
            },
          );
          expect(changed.roles, ['editor', 'admin']);

          await withApp((app) async {
            final signedIn = await app.auth.signInWithPassword(
              email: email,
              password: password,
            );
            expect(signedIn.authorities.map((a) => a.authority).toSet(), {
              'ROLE_editor',
              'ROLE_admin',
            });
            // In the token too, where a server reads them.
            final claims = supabaseTokenClaims(
              signedIn.credentials.tokenValue,
            )!;
            expect(
              claims['app_metadata'],
              containsPair('roles', ['editor', 'admin']),
            );
          });
        } finally {
          await project.admin.deleteUser(created.id);
        }
        expect(await project.admin.user(created.id), isNull);
        await withApp((app) async {
          await expectLater(
            app.auth.signInWithPassword(email: email, password: password),
            throwsA(badCredentials),
          );
        });
      });
    });

    group('the keys of the tokens', () {
      Future<List<Map<String, Object?>>> keySet() async {
        final response = await Stack.get(
          Uri.parse('${Stack.url}/auth/v1/.well-known/jwks.json'),
        );
        // No key of the project is sent: a server fetches the key set
        // without one.
        expect(response.statusCode.value, 200, reason: response.bodyText);
        return switch (jsonDecode(response.bodyText)) {
          {'keys': final List<Object?> keys} => [
            for (final key in keys)
              if (key is Map<String, Object?>) key,
          ],
          _ => fail('no key set: ${response.bodyText}'),
        };
      }

      test("the key set Auth serves has the public key the users' "
          'tokens are signed with (or the stack signs with its '
          'secret)', () async {
        await withApp((app) async {
          await app.signInAsNewUser();
          final token = jwtHeader((await app.session())!.accessToken);
          final anon = jwtHeader(Stack.anonKey);
          final keys = await keySet();
          String kid(Map<String, Object?> header) =>
              header.containsKey('kid') ? 'a kid' : 'no kid';
          final served = [
            for (final key in keys) '${key['kty']} ${key['alg']}',
          ].join(', ');
          // For whoever reads the run: what this stack does.
          // ignore: avoid_print
          print(
            'level 4: the tokens of users are signed with ${token['alg']} '
            '(${kid(token)}), the anon key with ${anon['alg']} '
            '(${kid(anon)}); the key set has ${keys.length} key(s): $served',
          );

          expect(token['typ'], 'JWT');
          expect(token['alg'], isIn(['ES256', 'RS256', 'HS256']));
          for (final key in keys) {
            // Public halves only.
            expect(key.keys, isNot(contains('d')));
            expect(key['kty'], isNot('oct'));
          }
          if (token['alg'] == 'HS256') {
            // A legacy secret: spring.supabase.auth.jwt-secret on a
            // server (the next test), nothing to find in the key set.
            return;
          }
          final key = keys.where((key) => key['kid'] == token['kid']);
          expect(key, hasLength(1), reason: 'no key with the kid of the token');
          expect(key.single['alg'] ?? token['alg'], token['alg']);
          expect(key.single['kty'], token['alg'] == 'ES256' ? 'EC' : 'RSA');
        });
      });

      test("a server with the starter's defaults accepts a user's token "
          "of the stack, with their roles, and refuses the project's "
          'keys', () async {
        await withApp((app) async {
          final user = await app.createUser(
            appMetadata: {
              'roles': ['editor'],
            },
          );
          await app.signIn(user);
          final token = (await app.session())!.accessToken;
          final legacy = jwtHeader(token)['alg'] == 'HS256';
          if (legacy && Stack.jwtSecret == null) {
            markTestSkipped(
              'the stack signs with HS256 and SUPABASE_JWT_SECRET is not '
              'set: nothing to check its tokens with',
            );
            return;
          }
          // ES256 or RS256: the key set of the project, the defaults.
          // HS256: the legacy secret.
          final server = await TestServer.start(
            projectUrl: Stack.url,
            properties: [
              if (legacy) 'spring.supabase.auth.jwt-secret=${Stack.jwtSecret}',
            ],
          );
          try {
            final answer = await server.me(token);
            expect(
              answer.status,
              200,
              reason: '${answer.headers['www-authenticate']}',
            );
            expect(answer.json, {
              'name': user.id,
              'authorities': ['ROLE_editor'],
            });

            // Signed tokens too, of another role.
            expect((await server.me(Stack.anonKey)).status, 401);
            expect((await server.me(Stack.serviceRoleKey)).status, 401);
            expect((await server.me(null)).status, 401);
          } finally {
            await server.close();
          }
        });
      });
    });
  });
}
