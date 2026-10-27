// The MockMvc support of lib/test.dart, like spring-security-test: what each
// post-processor puts on the request and how the application's real
// security chain treats it: user(), userDetails(), authentication(),
// anonymous(), httpBasic(), csrf() and jwt().
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_security/testing.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/rules/rules.dart';
import 'support.dart';

/// The authentication [processor] puts on a bare request.
Authentication _authenticationOf(RequestPostProcessor processor) {
  final request = processor.postProcessRequest(
    MockServerHttpRequest(HttpMethod.get, '/'),
  );
  final context =
      request.attributes[RequestAttributeSecurityContextRepository
              .attributeName]!
          as SecurityContext;
  return context.authentication!;
}

List<String?> _authorities(Authentication authentication) => [
  for (final a in authentication.authorities) a.authority,
];

void main() {
  Future<void> app(Future<void> Function(MockMvc mvc) body) =>
      withApp(rulesSecurityBeans, (mvc, _) => body(mvc));

  ResultActions call(
    MockMvc mvc,
    String path,
    RequestPostProcessor processor, {
    HttpMethod method = HttpMethod.get,
    Map<String, String> headers = const {'accept': 'application/json'},
    String? body,
  }) => mvc.perform(
    request(
      method,
      path,
      processors: [processor],
      headers: headers,
      body: body,
    ),
  );

  group('user()', () {
    test('is USER with the password "password" unless told otherwise', () {
      final authentication = _authenticationOf(user('ada'));
      expect(authentication.name, 'ada');
      expect(authentication.isAuthenticated, isTrue);
      expect(_authorities(authentication), ['ROLE_USER']);
      expect(authentication.credentials, 'password');
      expect((authentication.principal! as UserDetails).username, 'ada');
    });

    test('password() sets the password of the user', () {
      final authentication = _authenticationOf(user('ada').password('s3cret'));
      expect(authentication.credentials, 's3cret');
      expect((authentication.principal! as UserDetails).password, 's3cret');
    });

    test('roles() add the ROLE_ prefix', () {
      final authentication = _authenticationOf(
        user('ada').roles(['ADMIN', 'AUDIT']),
      );
      expect(_authorities(authentication), ['ROLE_ADMIN', 'ROLE_AUDIT']);
    });

    test('authorities() are taken as they are and replace the roles', () {
      final authentication = _authenticationOf(
        user('ada').roles(['ADMIN']).authorities(['read', 'ROLE_X']),
      );
      expect(_authorities(authentication), unorderedEquals(['read', 'ROLE_X']));
    });

    test('the last of roles() and authorities() wins', () {
      final authentication = _authenticationOf(
        user('ada').authorities(['read']).roles(['ADMIN']),
      );
      expect(_authorities(authentication), ['ROLE_ADMIN']);
    });

    test('skips the login: the rules see the user', () {
      return app((mvc) async {
        await call(mvc, '/api/me', user('ada')).andExpect(
          status: 200,
          json: {
            'name': 'ada',
            'authorities': ['ROLE_USER'],
          },
        );
        await call(mvc, '/api/admin', user('ada')).andExpect(status: 403);
        await call(
          mvc,
          '/api/admin',
          user('ada').authorities(['ROLE_ADMIN']),
        ).andExpect(status: 200, body: 'admin');
      });
    });

    test('the user is no one of the user store: any name passes', () {
      return app((mvc) async {
        await call(
          mvc,
          '/api/user',
          user('nobody-in-the-store'),
        ).andExpect(status: 200, body: 'nobody-in-the-store');
      });
    });
  });

  group('userDetails()', () {
    final details = User.withUsername('grace')
        .password('{noop}pw')
        .authorities(AuthorityUtils.createAuthorityList(['ROLE_ADMIN']))
        .build();

    test('the principal is the UserDetails itself', () {
      final authentication = _authenticationOf(userDetails(details));
      expect(authentication.principal, same(details));
      expect(authentication.credentials, '{noop}pw');
      expect(authentication.isAuthenticated, isTrue);
      expect(_authorities(authentication), ['ROLE_ADMIN']);
    });

    test('the application sees that user', () {
      return app((mvc) async {
        await call(
          mvc,
          '/api/user',
          userDetails(details),
        ).andExpect(status: 200, body: 'grace');
        await call(
          mvc,
          '/api/admin',
          userDetails(details),
        ).andExpect(status: 200, body: 'admin');
      });
    });
  });

  group('authentication()', () {
    test('puts exactly that authentication on the request', () {
      final given = UsernamePasswordAuthenticationToken.authenticated(
        'svc',
        null,
        AuthorityUtils.createAuthorityList(['ROLE_ADMIN']),
      );
      expect(_authenticationOf(authentication(given)), same(given));
    });

    test('the rules decide by its authorities', () {
      return app((mvc) async {
        final admin = UsernamePasswordAuthenticationToken.authenticated(
          'svc',
          null,
          AuthorityUtils.createAuthorityList(['ROLE_ADMIN']),
        );
        final plain = UsernamePasswordAuthenticationToken.authenticated(
          'svc',
          null,
          AuthorityUtils.createAuthorityList(['ROLE_USER']),
        );
        await call(
          mvc,
          '/api/admin',
          authentication(admin),
        ).andExpect(status: 200);
        await call(
          mvc,
          '/api/admin',
          authentication(plain),
        ).andExpect(status: 403);
      });
    });
  });

  group('anonymous()', () {
    test('is an anonymous token with ROLE_ANONYMOUS', () {
      final authentication = _authenticationOf(anonymous());
      expect(authentication, isA<AnonymousAuthenticationToken>());
      expect(authentication.name, 'anonymousUser');
      expect(_authorities(authentication), ['ROLE_ANONYMOUS']);
    });

    test('reaches public paths, is asked to log in elsewhere', () {
      return app((mvc) async {
        await call(
          mvc,
          '/public/hello',
          anonymous(),
        ).andExpect(status: 200, body: 'hello');
        await call(mvc, '/api/me', anonymous()).andExpect(status: 401);
      });
    });
  });

  group('httpBasic()', () {
    test('sends the credentials Spring encodes: base64 of user:password', () {
      final request = httpBasic(
        'ada',
        'ada-pw',
      ).postProcessRequest(MockServerHttpRequest(HttpMethod.get, '/'));
      expect(request.headers['authorization'], 'Basic YWRhOmFkYS1wdw==');
    });

    test('non-ASCII credentials are UTF-8', () {
      final request = httpBasic(
        'zoë',
        'pä:ss',
      ).postProcessRequest(MockServerHttpRequest(HttpMethod.get, '/'));
      expect(request.headers['authorization'], 'Basic em/Dqzpww6Q6c3M=');
    });

    test('the real login runs: right password, wrong one, unknown user', () {
      return app((mvc) async {
        await call(mvc, '/api/me', httpBasic('ada', 'ada-pw')).andExpect(
          status: 200,
          json: {
            'name': 'ada',
            'authorities': ['ROLE_USER'],
          },
        );
        await call(
          mvc,
          '/api/me',
          httpBasic('ada', 'wrong'),
        ).andExpect(status: 401);
        await call(
          mvc,
          '/api/me',
          httpBasic('nobody', 'ada-pw'),
        ).andExpect(status: 401);
      });
    });
  });

  group('csrf()', () {
    test('a valid token lets a form post through', () {
      return app((mvc) async {
        await call(
          mvc,
          '/form',
          csrf(),
          method: HttpMethod.post,
          headers: {'content-type': 'application/x-www-form-urlencoded'},
          body: 'text=hi',
        ).andExpect(status: 200, body: 'submitted hi');
      });
    });

    test('useInvalidToken() is refused with 403', () {
      return app((mvc) async {
        await call(
          mvc,
          '/form',
          csrf().useInvalidToken(),
          method: HttpMethod.post,
          headers: {'content-type': 'application/x-www-form-urlencoded'},
          body: 'text=hi',
        ).andExpect(status: 403);
      });
    });

    test('without it the same post is refused', () {
      return app((mvc) async {
        await mvc
            .perform(
              request(
                HttpMethod.post,
                '/form',
                headers: {'content-type': 'application/x-www-form-urlencoded'},
                body: 'text=hi',
              ),
            )
            .andExpect(status: 403);
      });
    });
  });

  group('jwt()', () {
    test('is user, scope read, valid for five minutes by default', () {
      final authentication = _authenticationOf(jwt());
      expect(authentication, isA<JwtAuthenticationToken>());
      expect(authentication.name, 'user');
      expect(_authorities(authentication), ['SCOPE_read']);
      final token = (authentication as JwtAuthenticationToken).jwt;
      expect(token.subject, 'user');
      expect(token.getClaimAsString('scope'), 'read');
      expect(token.expiresAt!.difference(token.issuedAt!).inSeconds, 300);
      expect(token.tokenValue, isNot(isEmpty));
    });

    test('subject() names the user', () {
      final authentication = _authenticationOf(jwt().subject('svc'));
      expect(authentication.name, 'svc');
      expect((authentication as JwtAuthenticationToken).jwt.subject, 'svc');
    });

    test('claim() sets and overrides claims', () {
      final token = (_authenticationOf(
        jwt()
            .claim('iss', 'https://issuer.example')
            .claim('aud', ['api'])
            .claim('exp', 4102444800),
      ) as JwtAuthenticationToken).jwt;
      expect(token.issuer, 'https://issuer.example');
      expect(token.audience, ['api']);
      expect(token.expiresAt, DateTime.utc(2100));
    });

    test('the authorities come from the scope claim', () {
      final authentication = _authenticationOf(
        jwt().claim('scope', 'read write'),
      );
      expect(_authorities(authentication), ['SCOPE_read', 'SCOPE_write']);
    });

    test('authorities() replace those of the scope claim', () {
      final authentication = _authenticationOf(
        jwt().claim('scope', 'read').authorities(['ROLE_ADMIN']),
      );
      expect(_authorities(authentication), ['ROLE_ADMIN']);
    });

    test('authorities() may be empty: no scope grants anything', () {
      expect(_authorities(_authenticationOf(jwt().authorities([]))), isEmpty);
    });

    test('the application sees the subject and the authorities', () {
      return app((mvc) async {
        await call(
          mvc,
          '/api/me',
          jwt().subject('svc').claim('scope', 'read write'),
        ).andExpect(
          json: {
            'name': 'svc',
            'authorities': ['SCOPE_read', 'SCOPE_write'],
          },
        );
      });
    });

    test('a scope is not a role', () {
      return app((mvc) async {
        await call(
          mvc,
          '/api/admin',
          jwt().claim('scope', 'ROLE_ADMIN admin'),
        ).andExpect(status: 403);
        await call(
          mvc,
          '/api/admin',
          jwt().authorities(['ROLE_ADMIN']),
        ).andExpect(status: 200);
      });
    });
  });
}
