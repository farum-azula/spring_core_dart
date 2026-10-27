// Every setting of the HttpSecurity DSL takes effect: each option of each
// configurer is set on a hand-built chain and its consequence is seen in
// the filters of the chain, in the answers, or in the session.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'chain_support.dart';

/// `/open/**` for everyone, `/admin/**` for admins, the rest for users.
HttpSecurity rules([HttpSecurity? http]) =>
    (http ?? newHttp()).authorizeHttpRequests(
      (auth) => auth
          .requestMatchers('/open/**')
          .permitAll()
          .requestMatchers('/admin/**')
          .hasRole('ADMIN')
          .anyRequest()
          .authenticated(),
    );

bool _matches(SecurityFilterChain chain, String path) =>
    chain.matches(MockServerHttpRequest(HttpMethod.get, path));

Future<ChainClient> _loggedIn(
  SecurityFilterChain chain, {
  String page = '/login',
  String action = '/login',
  String user = 'ada',
  String password = 'ada-pw',
  String usernameField = 'username',
  String passwordField = 'password',
}) async {
  final client = ChainClient(chain);
  final reply = await client.login(
    user,
    password,
    page: page,
    action: action,
    usernameField: usernameField,
    passwordField: passwordField,
  );
  expect(reply.status, 302, reason: 'the login');
  expect(reply.header('location'), isNot(contains('error')));
  return client;
}

void main() {
  group('build', () {
    test('a builder builds once', () {
      final http = rules()..build();
      expect(http.build, throwsStateError);
    });

    test('a manager is needed by the login methods that use one', () {
      expect(
        () => rules(HttpSecurity(null)).httpBasic().build(),
        throwsStateError,
      );
      expect(
        () => rules(HttpSecurity(null)).formLogin().build(),
        throwsStateError,
      );
    });

    test('the manager and the users of the chain are the ones given', () async {
      final custom = ProviderManager([
        DaoAuthenticationProvider(
          InMemoryUserDetailsManager([
            User.withUsername('zed').password('{noop}z').roles([]).build(),
          ]),
        ),
      ]);
      final chain = rules(HttpSecurity(null))
          .authenticationManager(custom)
          .httpBasic()
          .build();
      final client = ChainClient(chain);
      expect(
        (await client.get('/x', headers: basicHeader('zed', 'z'))).reached,
        isTrue,
      );
      expect(
        (await client.get('/x', headers: basicHeader('ada', 'ada-pw'))).status,
        401,
      );
      final users = rules(HttpSecurity(null))
          .userDetailsService(testUsers())
          .httpBasic()
          .build();
      expect(
        (await ChainClient(
          users,
        ).get('/x', headers: basicHeader('ada', 'ada-pw'))).reached,
        isTrue,
      );
    });

    test('a chain without rules lets everything through', () async {
      final chain = HttpSecurity(null).build();
      expect((await ChainClient(chain).get('/anything')).reached, isTrue);
    });
  });

  group('securityMatcher', () {
    test('one pattern, and up to four', () {
      final one = rules().securityMatcher('/a/**').build();
      expect(_matches(one, '/a/x'), isTrue);
      expect(_matches(one, '/b/x'), isFalse);
      final four = rules()
          .securityMatcher('/a/**', '/b/**', '/c/**', '/d/**')
          .build();
      for (final path in ['/a/x', '/b/x', '/c/x', '/d/x']) {
        expect(_matches(four, path), isTrue, reason: path);
      }
      expect(_matches(four, '/e/x'), isFalse);
      final two = rules().securityMatcher('/a/**', '/b/**').build();
      expect(_matches(two, '/b/x'), isTrue);
      expect(_matches(two, '/c/x'), isFalse);
    });

    test('a matcher of your own', () {
      final chain = rules()
          .securityMatcherOf(const HttpMethodRequestMatcher(HttpMethod.post))
          .build();
      expect(
        chain.matches(MockServerHttpRequest(HttpMethod.post, '/')),
        isTrue,
      );
      expect(
        chain.matches(MockServerHttpRequest(HttpMethod.get, '/')),
        isFalse,
      );
    });

    test('every request without one', () {
      final chain = rules().build();
      expect(_matches(chain, '/anything'), isTrue);
    });
  });

  group('the order of the filters', () {
    test('built-in filters keep their place whatever the call order', () {
      final expected = [
        SecurityContextHolderFilter,
        HeaderWriterFilter,
        CorsFilter,
        CsrfFilter,
        LogoutFilter,
        UsernamePasswordAuthenticationFilter,
        DefaultLoginPageGeneratingFilter,
        DefaultLogoutPageGeneratingFilter,
        BasicAuthenticationFilter,
        SecurityContextHolderAwareRequestFilter,
        AnonymousAuthenticationFilter,
        ExceptionTranslationFilter,
        AuthorizationFilter,
      ];
      expect(filterTypes(rules().httpBasic().formLogin().build()), expected);
      expect(filterTypes(rules().formLogin().httpBasic().build()), expected);
    });

    test('filters of your own go before, after or at a built-in one', () {
      final chain = rules()
          .httpBasic()
          .addFilterBefore(_Mark('before-basic'), BasicAuthenticationFilter)
          .addFilterAfter(_Mark('after-csrf'), CsrfFilter)
          .addFilterAt(_Mark('at-logout'), LogoutFilter)
          .addFilterBefore(_Mark('first'), SecurityContextHolderFilter)
          .addFilterAfter(_Mark('last'), AuthorizationFilter)
          .build();
      expect(
        [
          for (final f in chain.filters)
            if (f is _Mark) f.name else f.runtimeType,
        ],
        [
          'first',
          SecurityContextHolderFilter,
          HeaderWriterFilter,
          CorsFilter,
          CsrfFilter,
          'after-csrf',
          LogoutFilter,
          'at-logout',
          'before-basic',
          BasicAuthenticationFilter,
          SecurityContextHolderAwareRequestFilter,
          AnonymousAuthenticationFilter,
          ExceptionTranslationFilter,
          AuthorizationFilter,
          'last',
        ],
      );
    });

    test('filters at one place keep the order they were added in', () {
      final chain = rules()
          .httpBasic()
          .addFilterBefore(_Mark('1'), BasicAuthenticationFilter)
          .addFilterBefore(_Mark('2'), BasicAuthenticationFilter)
          .addFilterBefore(_Mark('3'), BasicAuthenticationFilter)
          .build();
      expect(
        [for (final f in chain.filters.whereType<_Mark>()) f.name],
        ['1', '2', '3'],
      );
    });

    test('they run in that order', () async {
      final calls = <String>[];
      final chain = rules()
          .addFilterBefore(_Mark('b', calls), AuthorizationFilter)
          .addFilterBefore(_Mark('a', calls), CsrfFilter)
          .build();
      await ChainClient(chain).get('/open/x');
      expect(calls, ['a', 'b']);
    });

    test('only built-in filters are places', () {
      expect(
        () => rules().addFilterBefore(_Mark('x'), _Mark),
        throwsArgumentError,
      );
    });
  });

  group('sessionManagement', () {
    Future<(String?, String?, ChainClient)> ids(HttpSecurity http) async {
      final client = ChainClient(http.formLogin().build());
      await client.get('/login');
      final before = client.cookies['JSESSIONID'];
      final reply = await client.login('ada', 'ada-pw');
      expect(reply.status, 302);
      return (before, client.cookies['JSESSIONID'], client);
    }

    test('a login gives the session a new id', () async {
      final (before, after, _) = await ids(rules());
      expect(before, isNotNull);
      expect(after, isNotNull);
      expect(after, isNot(before));
    });

    test('the id stays when the protection is switched off', () async {
      final (before, after, _) = await ids(
        rules().sessionManagement(
          (s) => s.sessionFixation(changeSessionId: false),
        ),
      );
      expect(before, isNotNull);
      expect(after, before);
    });

    test('a stateless chain leaves the session alone at login', () async {
      final (before, after, client) = await ids(
        rules().sessionManagement(
          (s) => s.sessionCreationPolicy(SessionCreationPolicy.stateless),
        ),
      );
      expect(before, isNotNull, reason: 'the CSRF token made one');
      expect(after, before);
      final next = await client.get('/private');
      expect(next.reached, isFalse, reason: 'the login was not kept');
      expect(next.status, 302);
    });

    test('by default the login is kept in the session', () async {
      final (_, _, client) = await ids(rules());
      expect((await client.get('/private')).reached, isTrue);
    });

    test(
      'the saved request is used by default, never when stateless',
      () async {
        final chain = rules().formLogin().build();
        final client = ChainClient(chain);
        expect((await client.get('/private?x=1')).status, 302);
        final login = await client.login('ada', 'ada-pw');
        expect(login.header('location'), '/private?x=1&continue');

        final stateless = ChainClient(
          rules()
              .sessionManagement(
                (s) => s.sessionCreationPolicy(SessionCreationPolicy.stateless),
              )
              .formLogin()
              .build(),
        );
        await stateless.get('/private');
        expect(
          (await stateless.login('ada', 'ada-pw')).header('location'),
          '/',
        );
      },
    );

    test('a request cache of your own, or none', () async {
      final none = ChainClient(
        rules()
            .requestCache((c) => c.requestCache(const NullRequestCache()))
            .formLogin()
            .build(),
      );
      await none.get('/private');
      expect((await none.login('ada', 'ada-pw')).header('location'), '/');
    });

    test(
      'a context repository of your own keeps and gives the context',
      () async {
        final repository = _Memory();
        final chain = rules()
            .securityContext((c) => c.securityContextRepository(repository))
            .formLogin()
            .build();
        final client = ChainClient(chain);
        expect((await client.get('/private')).reached, isFalse);
        await client.login('ada', 'ada-pw');
        expect(repository.saved.single.authentication!.name, 'ada');
        final other = ChainClient(chain, sessions: client.sessions);
        final reply = await other.get('/private');
        expect(reply.reached, isTrue, reason: 'loaded from the repository');
        expect(reply.authentication!.name, 'ada');
      },
    );
  });

  group('formLogin', () {
    test('the defaults: a page, POST /login, back to /', () async {
      final chain = rules().formLogin().build();
      final client = ChainClient(chain);
      final page = await client.get('/login');
      expect(page.status, 200);
      expect(page.body, contains('Please sign in'));
      final wrong = await client.post('/login', {
        'username': 'ada',
        'password': 'nope',
        '_csrf': page.csrfField,
      });
      expect(wrong.header('location'), '/login?error');
      final right = await client.login('ada', 'ada-pw');
      expect(right.header('location'), '/');
      expect((await client.get('/private')).authentication!.name, 'ada');
    });

    test(
      'a page of your own: none is generated, the URL is the target',
      () async {
        HttpSecurity http() =>
            rules().formLogin((f) => f.loginPage('/open/signin'));
        final chain = http().build();
        expect(
          filterTypes(chain),
          isNot(contains(DefaultLoginPageGeneratingFilter)),
        );
        expect(
          filterTypes(chain),
          isNot(contains(DefaultLogoutPageGeneratingFilter)),
        );
        final client = ChainClient(chain);
        expect(
          (await client.get('/private')).header('location'),
          '/open/signin',
        );
        final page = await client.get('/open/signin');
        expect(page.reached, isTrue, reason: 'the application renders it');
        expect(page.body, 'ok');

        final open = ChainClient(http().csrf((c) => c.disable()).build());
        final wrong = await open.post('/open/signin', {
          'username': 'ada',
          'password': 'nope',
        });
        expect(wrong.header('location'), '/open/signin?error');
        final right = await open.post('/open/signin', {
          'username': 'ada',
          'password': 'ada-pw',
        });
        expect(right.header('location'), '/');
        final notTheUrl = await ChainClient(
          http().csrf((c) => c.disable()).build(),
        ).post('/login', {'username': 'ada', 'password': 'ada-pw'});
        expect(notTheUrl.reached, isFalse);
        expect(notTheUrl.header('location'), '/open/signin');
      },
    );

    test('loginProcessingUrl, field names, URLs after the login', () async {
      final chain = rules()
          .formLogin(
            (f) => f
                .loginProcessingUrl('/auth')
                .usernameParameter('who')
                .passwordParameter('secret')
                .defaultSuccessUrl('/home')
                .failureUrl('/oops'),
          )
          .build();
      final client = ChainClient(chain);
      final page = await client.get('/login');
      expect(page.body, contains('action="&#47;auth"'));
      expect(page.body, contains('name="who"'));
      expect(page.body, contains('name="secret"'));
      final token = page.csrfField;
      final wrong = await client.post('/auth', {
        'who': 'ada',
        'secret': 'nope',
        '_csrf': token,
      });
      expect(wrong.header('location'), '/oops');
      final oldNames = await client.post('/auth', {
        'username': 'ada',
        'password': 'ada-pw',
        '_csrf': token,
      });
      expect(oldNames.header('location'), '/oops', reason: 'other fields');
      final notTheUrl = await client.post('/login', {
        'who': 'ada',
        'secret': 'ada-pw',
        '_csrf': token,
      });
      expect(notTheUrl.reached, isFalse, reason: 'not a login any more');
      expect(notTheUrl.header('location'), '/login');
      final right = await client.post('/auth', {
        'who': 'ada',
        'secret': 'ada-pw',
        '_csrf': token,
      });
      expect(right.header('location'), '/home');
    });

    test(
      'defaultSuccessUrl yields to the saved request unless always',
      () async {
        Future<String?> where({required bool alwaysUse}) async {
          final client = ChainClient(
            rules()
                .formLogin(
                  (f) => f.defaultSuccessUrl('/home', alwaysUse: alwaysUse),
                )
                .build(),
          );
          await client.get('/private');
          return (await client.login('ada', 'ada-pw')).header('location');
        }

        expect(await where(alwaysUse: false), '/private?continue');
        expect(await where(alwaysUse: true), '/home');
        final plain = ChainClient(
          rules().formLogin((f) => f.defaultSuccessUrl('/home')).build(),
        );
        expect(
          (await plain.login('ada', 'ada-pw')).header('location'),
          '/home',
        );
      },
    );

    test(
      'defaultSuccessUrl without alwaysUse still yields to the saved request',
      () async {
        final client = ChainClient(
          rules().formLogin((f) => f.defaultSuccessUrl('/home')).build(),
        );
        await client.get('/private');
        expect(
          (await client.login('ada', 'ada-pw')).header('location'),
          '/private?continue',
        );
      },
    );

    test('the handlers of your own answer the login', () async {
      final chain = rules()
          .formLogin(
            (f) => f
                .successHandler(const _Status(201))
                .failureHandler(const _Status(202)),
          )
          .build();
      final client = ChainClient(chain);
      expect((await client.login('ada', 'ada-pw')).status, 201);
      expect((await client.login('ada', 'nope')).status, 202);
    });

    test('redirects go under the context path', () async {
      final chain = rules(newHttp(contextPath: '/app')).formLogin().build();
      final client = ChainClient(chain);
      expect((await client.get('/private')).header('location'), '/app/login');
      final page = await client.get('/login');
      expect(page.body, contains('action="&#47;app&#47;login"'));
      final wrong = await client.post('/login', {
        'username': 'ada',
        'password': 'nope',
        '_csrf': page.csrfField,
      });
      expect(wrong.header('location'), '/app/login?error');
      final right = await client.login('ada', 'ada-pw');
      expect(right.header('location'), '/private?continue');
      final plain = ChainClient(
        rules(newHttp(contextPath: '/app')).formLogin().build(),
      );
      expect((await plain.login('ada', 'ada-pw')).header('location'), '/app/');
    });

    test('a login names the user for the events and the details', () async {
      final chain = rules().formLogin().build();
      final client = await _loggedIn(chain);
      final seen = (await client.get('/private')).authentication!;
      expect(seen.name, 'ada');
      expect(seen.details, isA<WebAuthenticationDetails>());
    });
  });

  group('httpBasic', () {
    test('without credentials: a challenge with the realm', () async {
      final client = ChainClient(rules().httpBasic().build());
      final reply = await client.get('/private', accept: 'application/json');
      expect(reply.status, 401);
      expect(
        reply.header('www-authenticate'),
        'Basic realm="Realm", charset="UTF-8"',
      );
      final named = ChainClient(
        rules().httpBasic((b) => b.realmName('Mine')).build(),
      );
      final other = await named.get('/private', accept: 'application/json');
      expect(other.header('www-authenticate'), contains('realm="Mine"'));
      final wrong = await named.get(
        '/private',
        headers: basicHeader('ada', 'nope'),
      );
      expect(wrong.status, 401);
      expect(wrong.header('www-authenticate'), contains('realm="Mine"'));
    });

    test('scripts get a 401 without the challenge', () async {
      final client = ChainClient(rules().httpBasic().build());
      for (final headers in [<String, String>{}, basicHeader('ada', 'nope')]) {
        final reply = await client.get(
          '/private',
          headers: {'x-requested-with': 'XMLHttpRequest', ...headers},
        );
        expect(reply.status, 401);
        expect(reply.header('www-authenticate'), isNull);
      }
    });

    test('an entry point of your own answers everyone', () async {
      final client = ChainClient(
        rules()
            .httpBasic((b) => b.authenticationEntryPoint(const _Entry(407)))
            .build(),
      );
      for (final headers in [
        <String, String>{},
        {'x-requested-with': 'XMLHttpRequest'},
        basicHeader('ada', 'nope'),
      ]) {
        expect((await client.get('/private', headers: headers)).status, 407);
      }
    });

    test('valid credentials log in for the request, with no session', () async {
      final client = ChainClient(rules().httpBasic().build());
      final reply = await client.get(
        '/private',
        headers: basicHeader('ada', 'ada-pw'),
      );
      expect(reply.authentication!.name, 'ada');
      expect(client.cookies, isEmpty);
      expect((await client.get('/private')).reached, isFalse);
    });

    test('called twice, it is one mechanism', () {
      final chain = rules().httpBasic().httpBasic().build();
      expect(
        filterTypes(chain).where((t) => t == BasicAuthenticationFilter),
        hasLength(1),
      );
    });
  });

  group('which entry point answers', () {
    Future<Reply> ask(HttpSecurity http, String accept) =>
        ChainClient(http.build()).get('/private', accept: accept);

    test('browsers are sent to the login page, programs get Basic', () async {
      for (final both in [
        () => rules().httpBasic().formLogin(),
        () => rules().formLogin().httpBasic(),
      ]) {
        final html = await ask(both(), 'text/html,application/xhtml+xml');
        expect(html.status, 302);
        expect(html.header('location'), '/login');
        for (final accept in ['application/json', '*/*']) {
          final program = await ask(both(), accept);
          expect(program.status, 401, reason: accept);
          expect(program.header('www-authenticate'), contains('Basic'));
        }
      }
    });

    test('with no login method nobody is challenged: 403', () async {
      final reply = await ask(rules(), 'text/html');
      expect(reply.status, 403);
      expect(reply.header('www-authenticate'), isNull);
    });

    test(
      'exceptionHandling: an entry point of your own for everything',
      () async {
        final http = rules().httpBasic().formLogin().exceptionHandling(
          (e) => e.authenticationEntryPoint(const _Entry(418)),
        );
        expect((await ask(http, 'text/html')).status, 418);
      },
    );

    test('exceptionHandling: a handler of your own for denied users', () async {
      final custom = ChainClient(
        rules()
            .httpBasic()
            .exceptionHandling((e) => e.accessDeniedHandler(const _Denied(418)))
            .build(),
      );
      final denied = await custom.get(
        '/admin/x',
        headers: basicHeader('ada', 'ada-pw'),
      );
      expect(denied.status, 418);
      final plain = ChainClient(rules().httpBasic().build());
      expect(
        (await plain.get(
          '/admin/x',
          headers: basicHeader('ada', 'ada-pw'),
        )).status,
        403,
      );
      expect(
        (await plain.get(
          '/admin/x',
          headers: basicHeader('root', 'root-pw'),
        )).reached,
        isTrue,
      );
    });
  });

  group('csrf', () {
    test('on by default: a POST needs a token', () async {
      final client = ChainClient(rules().build());
      final reply = await client.send(HttpMethod.post, '/open/x');
      expect(reply.status, 403);
      expect(reply.reached, isFalse);
    });

    test('disable: no filter, no token needed', () async {
      final chain = rules().csrf((c) => c.disable()).build();
      expect(filterTypes(chain), isNot(contains(CsrfFilter)));
      final reply = await ChainClient(chain).send(HttpMethod.post, '/open/x');
      expect(reply.reached, isTrue);
    });

    test('requests that are ignored need no token, the others do', () async {
      final chain = rules()
          .csrf(
            (c) =>
                c.ignoringRequestMatchers('/open/h1', '/open/h2', '/open/h3'),
          )
          .build();
      final client = ChainClient(chain);
      for (final path in ['/open/h1', '/open/h2', '/open/h3']) {
        expect(
          (await client.send(HttpMethod.post, path)).reached,
          isTrue,
          reason: path,
        );
      }
      final other = await client.send(HttpMethod.post, '/open/h4');
      expect(other.status, 403);
      final more = rules()
          .csrf(
            (c) => c
                .ignoringRequestMatchers('/open/a')
                .ignoringRequestMatchers('/open/b'),
          )
          .build();
      for (final path in ['/open/a', '/open/b']) {
        expect(
          (await ChainClient(more).send(HttpMethod.post, path)).reached,
          isTrue,
        );
      }
    });

    test(
      'a cookie repository and the plain handler: the script sends the cookie',
      () async {
        final chain = rules()
            .csrf(
              (c) => c
                  .csrfTokenRepository(
                    const CookieCsrfTokenRepository.withHttpOnlyFalse(),
                  )
                  .csrfTokenRequestHandler(
                    const CsrfTokenRequestAttributeHandler(),
                  ),
            )
            .formLogin()
            .build();
        final client = ChainClient(chain);
        final page = await client.get('/login');
        final cookie = page.cookie('XSRF-TOKEN')!;
        expect(cookie.httpOnly, isFalse);
        expect(page.csrfField, cookie.value, reason: 'the plain handler');
        final ok = await client.send(
          HttpMethod.post,
          '/open/x',
          headers: {'x-xsrf-token': cookie.value},
        );
        expect(ok.reached, isTrue);
        final wrong = await client.send(
          HttpMethod.post,
          '/open/x',
          headers: {'x-xsrf-token': 'other'},
        );
        expect(wrong.status, 403);
        final sessionOnly = await client.send(
          HttpMethod.post,
          '/open/x',
          headers: {'x-csrf-token': cookie.value},
        );
        expect(
          sessionOnly.status,
          403,
          reason: 'the repository names the header',
        );
      },
    );

    test('the default handler masks the token of the page', () async {
      final chain = rules()
          .csrf((c) => c.csrfTokenRepository(const CookieCsrfTokenRepository()))
          .formLogin()
          .build();
      final page = await ChainClient(chain).get('/login');
      expect(page.csrfField, isNot(page.cookie('XSRF-TOKEN')!.value));
    });

    test(
      'a failed check goes to the access denied handler of the chain',
      () async {
        final chain = rules()
            .exceptionHandling((e) => e.accessDeniedHandler(const _Denied(418)))
            .build();
        final reply = await ChainClient(chain).send(HttpMethod.post, '/open/x');
        expect(reply.status, 418);
      },
    );

    test('a login drops the token seen before it', () async {
      final chain = rules().formLogin().build();
      final client = ChainClient(chain);
      final page = await client.get('/login');
      final old = page.csrfField;
      await client.post('/login', {
        'username': 'ada',
        'password': 'ada-pw',
        '_csrf': old,
      });
      final replay = await client.send(
        HttpMethod.post,
        '/open/x',
        headers: {'x-csrf-token': old},
      );
      expect(replay.status, 403);
    });
  });

  group('logout', () {
    test('on by default at POST /logout, ending the session', () async {
      final chain = rules().formLogin().build();
      final client = await _loggedIn(chain);
      final id = client.cookies['JSESSIONID']!;
      expect(await client.sessions.repository.findById(id), isNotNull);
      final confirm = await client.get('/logout');
      expect(confirm.body, contains('Are you sure'));
      final reply = await client.post('/logout', {'_csrf': confirm.csrfField});
      expect(reply.status, 302);
      expect(reply.header('location'), '/login?logout');
      expect(await client.sessions.repository.findById(id), isNull);
      expect((await client.get('/private')).reached, isFalse);
    });

    test('GET is no logout while CSRF protection is on', () async {
      final client = ChainClient(rules().httpBasic().build());
      final reply = await client.get(
        '/logout',
        headers: basicHeader('ada', 'ada-pw'),
      );
      expect(reply.reached, isTrue);
    });

    test(
      'without CSRF protection any of GET, POST, PUT and DELETE logs out',
      () async {
        final chain = rules()
            .csrf((c) => c.disable())
            .logout((l) => l.logoutSuccessUrl('/bye'))
            .build();
        for (final method in [
          HttpMethod.get,
          HttpMethod.post,
          HttpMethod.put,
          HttpMethod.delete,
        ]) {
          final reply = await ChainClient(chain).send(method, '/logout');
          expect(reply.header('location'), '/bye', reason: '$method');
        }
        final patch = await ChainClient(chain)
            .send(HttpMethod.patch, '/logout');
        expect(patch.header('location'), isNull);
        expect(patch.status, 403);
      },
    );

    test('logoutUrl moves the endpoint', () async {
      final chain = rules()
          .csrf((c) => c.disable())
          .logout((l) => l.logoutUrl('/signout'))
          .build();
      final client = ChainClient(chain);
      expect((await client.send(HttpMethod.post, '/signout')).status, 302);
      expect((await client.send(HttpMethod.post, '/logout')).status, 403);
      final page = rules()
          .logout((l) => l.logoutUrl('/signout'))
          .formLogin()
          .build();
      final confirm = await ChainClient(page).get('/signout');
      expect(confirm.body, contains('action="&#47;signout"'));
    });

    test(
      'where to go: the URL, the login page of the chain, the context path',
      () async {
        Future<String?> where(HttpSecurity http) async => (await ChainClient(
          http.csrf((c) => c.disable()).build(),
        ).send(HttpMethod.post, '/logout')).header('location');

        expect(await where(rules()), '/login?logout');
        expect(
          await where(rules().formLogin((f) => f.loginPage('/signin'))),
          '/signin?logout',
        );
        expect(
          await where(rules().logout((l) => l.logoutSuccessUrl('/goodbye'))),
          '/goodbye',
        );
        expect(
          await where(
            rules(newHttp(contextPath: '/app'))
                .logout((l) => l.logoutSuccessUrl('/goodbye')),
          ),
          '/app/goodbye',
        );
      },
    );

    test('a success handler of your own', () async {
      final chain = rules()
          .csrf((c) => c.disable())
          .logout(
            (l) => l.logoutSuccessHandler(
              const HttpStatusReturningLogoutSuccessHandler(
                HttpStatus.noContent,
              ),
            ),
          )
          .build();
      expect(
        (await ChainClient(chain).send(HttpMethod.post, '/logout')).status,
        204,
      );
    });

    test('the session ends unless told not to', () async {
      Future<bool> stays(HttpSecurity http) async {
        final client = ChainClient(
          http.csrf((c) => c.disable()).formLogin().build(),
        );
        final login = await client.post('/login', {
          'username': 'ada',
          'password': 'ada-pw',
        });
        expect(login.status, 302);
        final id = client.cookies['JSESSIONID']!;
        await client.send(HttpMethod.post, '/logout');
        return await client.sessions.repository.findById(id) != null;
      }

      expect(await stays(rules()), isFalse);
      expect(
        await stays(
          rules().logout((l) => l.invalidateHttpSession(invalidate: true)),
        ),
        isFalse,
      );
      expect(
        await stays(
          rules().logout((l) => l.invalidateHttpSession(invalidate: false)),
        ),
        isTrue,
      );
    });

    test('cookies to delete are expired', () async {
      final chain = rules()
          .csrf((c) => c.disable())
          .logout((l) => l.deleteCookies('a', 'b', 'c'))
          .build();
      final reply = await ChainClient(chain).send(HttpMethod.post, '/logout');
      expect([for (final c in reply.response.cookies) c.name], ['a', 'b', 'c']);
      for (final cookie in reply.response.cookies) {
        expect(cookie.maxAge, Duration.zero);
        expect(cookie.path, '/');
      }
      final nested = rules(newHttp(contextPath: '/app'))
          .csrf((c) => c.disable())
          .logout((l) => l.deleteCookies('a'))
          .build();
      final under = await ChainClient(nested).send(HttpMethod.post, '/logout');
      expect(under.response.cookies.single.path, '/app');
      final none = await ChainClient(rules().csrf((c) => c.disable()).build())
          .send(HttpMethod.post, '/logout');
      expect(none.response.cookies, isEmpty);
    });

    test('a handler of your own runs, in front of the built-in ones', () async {
      final calls = <String>[];
      final chain = rules()
          .csrf((c) => c.disable())
          .logout((l) => l.addLogoutHandler(_Seen(calls)))
          .build();
      await ChainClient(chain).send(HttpMethod.post, '/logout');
      expect(calls, ['logout']);
    });

    test('the CSRF cookie is expired with the logout', () async {
      final chain = rules()
          .csrf(
            (c) => c
                .csrfTokenRepository(const CookieCsrfTokenRepository())
                .csrfTokenRequestHandler(
                  const CsrfTokenRequestAttributeHandler(),
                ),
          )
          .build();
      final client = ChainClient(chain)..cookies['XSRF-TOKEN'] = 'abc';
      final reply = await client.send(
        HttpMethod.post,
        '/logout',
        headers: {'x-xsrf-token': 'abc'},
      );
      expect(reply.status, 302);
      expect(reply.cookie('XSRF-TOKEN')!.maxAge, Duration.zero);
    });

    test('disable: no endpoint, no page', () async {
      final chain = rules()
          .csrf((c) => c.disable())
          .logout((l) => l.disable())
          .formLogin()
          .build();
      expect(filterTypes(chain), isNot(contains(LogoutFilter)));
      expect(
        filterTypes(chain),
        isNot(contains(DefaultLogoutPageGeneratingFilter)),
      );
      final reply = await ChainClient(chain).send(HttpMethod.post, '/logout');
      expect(reply.status, 302);
      expect(
        reply.header('location'),
        '/login',
        reason: 'the rules, not a logout',
      );
    });
  });

  group('anonymous', () {
    test('requests without credentials are anonymous users', () async {
      final reply = await ChainClient(rules().build()).get('/open/x');
      expect(reply.authentication, isA<AnonymousAuthenticationToken>());
    });

    test('disable: no authentication at all', () async {
      final chain = rules().anonymous((a) => a.disable()).build();
      expect(
        filterTypes(chain),
        isNot(contains(AnonymousAuthenticationFilter)),
      );
      final reply = await ChainClient(chain).get('/open/x');
      expect(reply.reached, isTrue);
      expect(reply.authentication, isNull);
    });
  });

  group('headers', () {
    Future<Reply> get(HttpSecurity http, {String path = '/open/x'}) =>
        ChainClient(http.build()).get(path);

    const all = [
      'x-content-type-options',
      'x-xss-protection',
      'cache-control',
      'x-frame-options',
      'strict-transport-security',
      'content-security-policy',
      'referrer-policy',
    ];

    List<String> present(Reply reply) => [
      for (final name in all)
        if (reply.header(name) != null) name,
    ];

    test('the defaults', () async {
      final reply = await get(rules(), path: 'https://localhost/open/x');
      expect(reply.header('x-content-type-options'), 'nosniff');
      expect(reply.header('x-xss-protection'), '0');
      expect(reply.header('cache-control'), contains('no-store'));
      expect(reply.header('x-frame-options'), 'DENY');
      expect(
        reply.header('strict-transport-security'),
        'max-age=31536000 ; includeSubDomains',
      );
      expect(present(reply), hasLength(5));
    });

    test('disable: none, and no filter', () async {
      final chain = rules().headers((h) => h.disable()).build();
      expect(filterTypes(chain), isNot(contains(HeaderWriterFilter)));
      final reply = await ChainClient(chain).get('/open/x');
      expect(present(reply), isEmpty);
    });

    test('defaultsDisabled: only what is added', () async {
      final reply = await get(
        rules().headers(
          (h) => h
              .defaultsDisabled()
              .contentSecurityPolicy("default-src 'self'")
              .referrerPolicy('no-referrer')
              .addHeaderWriter(const StaticHeadersWriter('X-Extra', '1')),
        ),
        path: 'https://localhost/open/x',
      );
      expect(present(reply), ['content-security-policy', 'referrer-policy']);
      expect(reply.header('content-security-policy'), "default-src 'self'");
      expect(reply.header('referrer-policy'), 'no-referrer');
      expect(reply.header('x-extra'), '1');
    });

    test('each default can be switched off or changed', () async {
      Future<Reply> with_(Customizer<HeadersConfigurer> customizer) =>
          get(rules().headers(customizer), path: 'https://localhost/open/x');

      expect(
        (await with_((h) => h.frameOptions(XFrameOptionsMode.sameOrigin)))
            .header('x-frame-options'),
        'SAMEORIGIN',
      );
      expect(
        (await with_((h) => h.frameOptions(null))).header('x-frame-options'),
        isNull,
      );
      expect(
        (await with_((h) => h.httpStrictTransportSecurity(null)))
            .header('strict-transport-security'),
        isNull,
      );
      expect(
        (await with_(
          (h) => h.httpStrictTransportSecurity(
            const HstsHeaderWriter(
              maxAge: Duration(days: 1),
              includeSubDomains: false,
              preload: true,
            ),
          ),
        )).header('strict-transport-security'),
        'max-age=86400 ; preload',
      );
      expect(
        (await with_((h) => h.contentTypeOptions(enabled: false)))
            .header('x-content-type-options'),
        isNull,
      );
      expect(
        (await with_((h) => h.xssProtection(enabled: false)))
            .header('x-xss-protection'),
        isNull,
      );
      expect(
        (await with_((h) => h.cacheControl(enabled: false)))
            .header('cache-control'),
        isNull,
      );
      final extra = await with_(
        (h) => h
            .contentSecurityPolicy("default-src 'none'")
            .referrerPolicy('same-origin'),
      );
      expect(extra.header('content-security-policy'), "default-src 'none'");
      expect(extra.header('referrer-policy'), 'same-origin');
      expect(extra.header('x-frame-options'), 'DENY');
    });

    test('no HSTS over plain HTTP', () async {
      final reply = await get(rules());
      expect(reply.header('strict-transport-security'), isNull);
    });
  });

  group('cors', () {
    Future<Reply> preflight(HttpSecurity http) => ChainClient(http.build())
        .send(
          HttpMethod.options,
          '/open/x',
          headers: {
            'origin': 'https://app.example',
            'access-control-request-method': 'GET',
          },
        );

    test('with no configuration a preflight is refused', () async {
      final reply = await preflight(rules());
      expect(reply.status, 403);
      expect(reply.reached, isFalse);
    });

    test('the configuration source is the one given', () async {
      final source = UrlBasedCorsConfigurationSource()
        ..registerCorsConfiguration(
          '/open/**',
          CorsConfiguration(
            allowedOrigins: ['https://app.example'],
            allowedMethods: ['GET'],
          ),
        );
      final reply = await preflight(
        rules().cors((c) => c.configurationSource(source)),
      );
      expect(reply.status, 200);
      expect(
        reply.header('access-control-allow-origin'),
        'https://app.example',
      );
      final other =
          await ChainClient(
            rules().cors((c) => c.configurationSource(source)).build(),
          ).send(
            HttpMethod.options,
            '/open/x',
            headers: {
              'origin': 'https://evil.example',
              'access-control-request-method': 'GET',
            },
          );
      expect(other.status, 403);
    });

    test('disable: no filter, the application answers', () async {
      final chain = rules().cors((c) => c.disable()).build();
      expect(filterTypes(chain), isNot(contains(CorsFilter)));
      final reply = await preflight(rules().cors((c) => c.disable()));
      expect(reply.reached, isTrue);
    });
  });

  group('authorizeHttpRequests', () {
    test(
      'a rule after anyRequest is an error, and so is a second anyRequest',
      () {
        expect(
          () => newHttp().authorizeHttpRequests(
            (auth) => auth.anyRequest().authenticated().requestMatchers('/x'),
          ),
          throwsStateError,
        );
        expect(
          () => newHttp().authorizeHttpRequests((auth) {
            auth.anyRequest().authenticated();
            auth.anyRequest();
          }),
          throwsStateError,
        );
        expect(
          () => newHttp().authorizeHttpRequests(
            (auth) => auth.requestMatchersFor(null, const []),
          ),
          throwsArgumentError,
        );
      },
    );

    test('a chain with an empty rule set is refused', () {
      expect(
        () => newHttp().authorizeHttpRequests((auth) {}).build(),
        throwsStateError,
      );
    });

    test('the first matching rule decides', () async {
      final client = ChainClient(rules().httpBasic().build());
      expect((await client.get('/open/x')).reached, isTrue);
      expect(
        (await client.get(
          '/admin/x',
          headers: basicHeader('ada', 'ada-pw'),
        )).status,
        403,
      );
      expect(
        (await client.get(
          '/admin/x',
          headers: basicHeader('root', 'root-pw'),
        )).reached,
        isTrue,
      );
      expect((await client.get('/other')).status, 401);
    });
  });

  group('oauth2ResourceServer', () {
    test('needs jwt() and a decoder', () {
      expect(
        () => rules().oauth2ResourceServer((s) {}).build(),
        throwsStateError,
      );
      expect(
        () => rules().oauth2ResourceServer((s) => s.jwt()).build(),
        throwsStateError,
      );
    });
  });
}

final class _Mark implements WebFilter {
  _Mark(this.name, [this.calls]);

  final String name;
  final List<String>? calls;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    calls?.add(name);
    return chain.doFilter(request, response);
  }
}

final class _Status
    implements AuthenticationSuccessHandler, AuthenticationFailureHandler {
  const _Status(this.status);

  final int status;

  @override
  Future<void> onAuthenticationSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication authentication,
  ) async {
    response.statusCode = status;
    await response.close();
  }

  @override
  Future<void> onAuthenticationFailure(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException exception,
  ) async {
    response.statusCode = status;
    await response.close();
  }
}

final class _Entry implements AuthenticationEntryPoint {
  const _Entry(this.status);

  final int status;

  @override
  Future<void> commence(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException authException,
  ) async {
    response.statusCode = status;
    await response.close();
  }
}

final class _Denied implements AccessDeniedHandler {
  const _Denied(this.status);

  final int status;

  @override
  Future<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AccessDeniedException accessDeniedException,
  ) async {
    response.statusCode = status;
    await response.close();
  }
}

final class _Seen implements LogoutHandler {
  _Seen(this.calls);

  final List<String> calls;

  @override
  void logout(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  ) => calls.add('logout');
}

final class _Memory implements SecurityContextRepository {
  final saved = <SecurityContext>[];
  SecurityContext? _context;

  @override
  SecurityContext? loadContext(ServerHttpRequest request) => _context;

  @override
  void saveContext(
    SecurityContext context,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    saved.add(context);
    _context = context;
  }

  @override
  bool containsContext(ServerHttpRequest request) => _context != null;
}
