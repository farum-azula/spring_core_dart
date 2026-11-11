// What the auto-configuration reads from `spring.security.*` and builds from
// it: every property has its effect, the default user keeps the password as
// it was given, the decoder checks what the properties tell it to, and the
// chains are checked at startup.

import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_security/src/properties/properties_beans.dart';
import 'package:test/test.dart';

import 'support.dart';

SecurityProperties _properties(Map<String, Object?> values) {
  final environment = StandardEnvironment(systemEnvironment: const {})
    ..propertySources.addFirst(MapPropertySource('test', values));
  ConfigurationPropertySources.attach(environment);
  final binder = ConfigurationPropertiesBinder(
    environment,
    BeanIntrospector(introspections: securityConfigBeans.introspections),
  );
  return binder.postProcessBeforeInitialization(
    SecurityProperties(),
    'securityProperties',
  ) as SecurityProperties;
}

const _password = 'spring.security.user.password=pw';
const _jwt = 'spring.security.oauth2.resourceserver.jwt';
const _secret = 'a-shared-secret-of-32-characters';

// An ArgumentError whose message has every one of [texts].
Matcher _argumentError(List<String> texts) => throwsA(
  isA<ArgumentError>().having(
    (e) => '${e.message}',
    'message',
    allOf([for (final text in texts) contains(text)]),
  ),
);

void main() {
  group('SecurityProperties', () {
    test('the defaults', () {
      final properties = _properties({});
      expect(properties.userName, 'user');
      expect(properties.userPassword, isNull);
      expect(properties.userRoles, isEmpty);
      expect(properties.filterOrder, -100);
      expect(properties.issuerUri, isNull);
      expect(properties.jwkSetUri, isNull);
      expect(properties.jwsAlgorithms, {JwsAlgorithm.rs256});
      expect(properties.audiences, isEmpty);
      expect(properties.secretKey, isNull);
      expect(properties.macAlgorithm, JwsAlgorithm.hs256);
      expect(properties.requiredClaims, isEmpty);
      expect(properties.hasResourceServer, isFalse);
    });

    test('the user, the roles without blanks, the filter order', () {
      final properties = _properties({
        'spring.security.user.name': ' bob ',
        'spring.security.user.password': ' pw ',
        'spring.security.user.roles': 'ADMIN, ,USER,',
        'spring.security.filter.order': '5',
      });
      expect(properties.userName, 'bob');
      expect(properties.userPassword, 'pw');
      expect(properties.userRoles, ['ADMIN', 'USER']);
      expect(properties.filterOrder, 5);
      expect(
        _properties({
          'spring.security.user.roles[0]': ' A ',
          'spring.security.user.roles[1]': ' ',
          'spring.security.user.roles[2]': 'B',
        }).userRoles,
        ['A', 'B'],
      );
      expect(
        () => _properties({'spring.security.filter.order': 'x'}),
        throwsA(isA<ConfigurationPropertiesBindException>()),
      );
      expect(_properties({'spring.security.user.name': ' '}).userName, 'user');
    });

    test('a resource server is there with an issuer or a key set', () {
      expect(
        _properties({'$_jwt.issuer-uri': 'https://i.example'})
            .hasResourceServer,
        isTrue,
      );
      expect(
        _properties({'$_jwt.jwk-set-uri': 'https://i.example/jwks'})
            .hasResourceServer,
        isTrue,
      );
      expect(
        _properties({
          '$_jwt.issuer-uri': 'https://i.example',
          '$_jwt.jwk-set-uri': 'https://i.example/jwks',
        }).hasResourceServer,
        isTrue,
      );
      expect(
        _properties({'$_jwt.audiences': 'api'}).hasResourceServer,
        isFalse,
      );
      expect(_properties({'$_jwt.issuer-uri': ' '}).hasResourceServer, isFalse);
      expect(
        _properties({'$_jwt.secret-key': _secret}).hasResourceServer,
        isTrue,
      );
      expect(_properties({'$_jwt.secret-key': ' '}).hasResourceServer, isFalse);
    });

    test('the shared secret is its UTF-8 bytes; blank is unset', () {
      expect(
        _properties({'$_jwt.secret-key': _secret}).secretKey,
        _secret.codeUnits,
      );
      final accented = 'é' * 16;
      expect(
        _properties({'$_jwt.secret-key': accented}).secretKey,
        utf8.encode(accented),
        reason: '32 bytes in 16 characters',
      );
      expect(_properties({'$_jwt.secret-key': ''}).secretKey, isNull);
      expect(_properties({'$_jwt.secret-key': '   '}).secretKey, isNull);
      expect(
        _properties({
          '$_jwt.secret-key': _secret,
          '$_jwt.issuer-uri': 'https://i.example',
        }).secretKey,
        isNotNull,
      );
    });

    test('a shared secret beside jwk-set-uri is refused', () {
      expect(
        () => _properties({
          '$_jwt.secret-key': _secret,
          '$_jwt.jwk-set-uri': 'https://i.example/jwks',
        }).secretKey,
        _argumentError(['$_jwt.secret-key', '$_jwt.jwk-set-uri']),
      );
      // A blank one is not set.
      expect(
        _properties({
          '$_jwt.secret-key': ' ',
          '$_jwt.jwk-set-uri': 'https://i.example/jwks',
        }).secretKey,
        isNull,
      );
    });

    test('the algorithm of a shared secret: one of HS256, HS384, HS512', () {
      JwsAlgorithm algorithm(String names) =>
          _properties({'$_jwt.jws-algorithms': names}).macAlgorithm;
      expect(algorithm(' , '), JwsAlgorithm.hs256);
      expect(algorithm('HS256'), JwsAlgorithm.hs256);
      expect(algorithm('HS384'), JwsAlgorithm.hs384);
      expect(algorithm(' HS512 ,'), JwsAlgorithm.hs512);
      expect(algorithm('HS256,HS256'), JwsAlgorithm.hs256);
      for (final names in [
        'RS256',
        'ES256',
        'PS256',
        'HS256,RS256',
        'RS256,HS256',
      ]) {
        expect(
          () => algorithm(names),
          _argumentError(['$_jwt.jws-algorithms', '$_jwt.secret-key', 'HS256']),
          reason: names,
        );
      }
      expect(
        () => algorithm('HS256,HS512'),
        _argumentError(['$_jwt.jws-algorithms', 'one algorithm']),
      );
      for (final names in ['none', 'hs256', 'HS128']) {
        expect(
          () => algorithm(names),
          _argumentError(['$_jwt.jws-algorithms', 'unknown']),
          reason: names,
        );
      }
    });

    test('a shared secret is at least as long as the hash', () {
      List<int>? secret(int length, [String? algorithm]) => _properties({
        '$_jwt.secret-key': 'k' * length,
        '$_jwt.jws-algorithms': ?algorithm,
      }).secretKey;
      expect(secret(32), hasLength(32));
      expect(secret(48, 'HS384'), hasLength(48));
      expect(secret(64, 'HS512'), hasLength(64));
      for (final (length, algorithm) in [
        (31, null),
        (31, 'HS256'),
        (47, 'HS384'),
        (63, 'HS512'),
      ]) {
        expect(
          () => secret(length, algorithm),
          throwsA(
            isA<ArgumentError>()
                .having(
                  (e) => '${e.message}',
                  'message',
                  allOf(
                    contains('$_jwt.secret-key'),
                    contains('$length bytes'),
                    contains(algorithm ?? 'HS256'),
                  ),
                )
                .having(
                  (e) => '$e',
                  'never the secret',
                  isNot(contains('k' * length)),
                ),
          ),
          reason: '$length $algorithm',
        );
      }
      // The algorithm is checked with the secret.
      expect(
        () => secret(64, 'RS256'),
        _argumentError(['$_jwt.jws-algorithms']),
      );
    });

    test('the required claims, by name', () {
      expect(
        _properties({
          '$_jwt.required-claims.role': 'authenticated',
          '$_jwt.required-claims.email_verified': 'true',
        }).requiredClaims,
        {'role': 'authenticated', 'email_verified': 'true'},
      );
      // A name with dots or a URL, in brackets; the case is kept.
      expect(
        _properties({
          '$_jwt.required-claims[https://example.com/tenant]': 'shop',
          '$_jwt.required-claims[app.tenantId]': '7',
        }).requiredClaims,
        {'https://example.com/tenant': 'shop', 'app.tenantId': '7'},
      );
      expect(
        () => _properties({'$_jwt.required-claims[ ]': 'x'}).requiredClaims,
        _argumentError(['$_jwt.required-claims', 'blank']),
      );
      expect(
        () => _properties({}).requiredClaims['role'] = 'x',
        throwsUnsupportedError,
      );
    });

    test('algorithms and audiences', () {
      expect(
        _properties({'$_jwt.jws-algorithms': 'ES256, PS256'}).jwsAlgorithms,
        {JwsAlgorithm.es256, JwsAlgorithm.ps256},
      );
      expect(_properties({'$_jwt.jws-algorithms': ' , '}).jwsAlgorithms, {
        JwsAlgorithm.rs256,
      }, reason: 'blank entries are not algorithms');
      expect(
        () => _properties({'$_jwt.jws-algorithms': 'ES256,nope'}).jwsAlgorithms,
        throwsArgumentError,
      );
      expect(_properties({'$_jwt.audiences': 'api, ,web'}).audiences, [
        'api',
        'web',
      ]);
    });

    test('the authorities and the user name of a JWT', () {
      final jwt = Jwt(
        'token',
        headers: const {'alg': 'none'},
        claims: const {
          'sub': 'ada',
          'email': 'ada@example.test',
          'scope': 'read write',
          'roles': 'admin,staff',
          'groups': ['g1', 'g2'],
          'realm_access': {
            'roles': ['r1', 'r2'],
          },
        },
      );
      List<String> authorities(SecurityProperties properties) => [
        for (final a
            in properties.jwtAuthenticationConverter.convert(jwt).authorities)
          ?a.authority,
      ];

      final defaults = _properties({}).jwtAuthenticationConverter.convert(jwt);
      expect(defaults.name, 'ada');
      expect(authorities(_properties({})), ['SCOPE_read', 'SCOPE_write']);
      expect(authorities(_properties({'$_jwt.authority-prefix': 'AUTH_'})), [
        'AUTH_read',
        'AUTH_write',
      ]);
      expect(authorities(_properties({'$_jwt.authority-prefix': ''})), [
        'read',
        'write',
      ]);
      expect(
        authorities(
          _properties({
            '$_jwt.authorities-claim-name': 'roles',
            '$_jwt.authorities-claim-delimiter': ',',
          }),
        ),
        ['SCOPE_admin', 'SCOPE_staff'],
      );
      expect(
        authorities(_properties({'$_jwt.authorities-claim-name': 'groups'})),
        ['SCOPE_g1', 'SCOPE_g2'],
      );
      expect(
        authorities(
          _properties({
            '$_jwt.authorities-claim-name': 'realm_access.roles',
            '$_jwt.authority-prefix': 'ROLE_',
          }),
        ),
        ['ROLE_r1', 'ROLE_r2'],
      );
      expect(
        authorities(
          _properties({'$_jwt.authorities-claim-name': 'realm_access.groups'}),
        ),
        isEmpty,
      );
      expect(
        _properties({'$_jwt.principal-claim-name': 'email'})
            .jwtAuthenticationConverter
            .convert(jwt)
            .name,
        'ada@example.test',
      );
    });
  });

  group('the default user', () {
    Future<UserDetails> user(
      List<String> properties, {
      PasswordEncoder? encoder,
    }) async {
      var runner = securityRunner(null, properties);
      if (encoder != null) {
        runner = runner.withBean<PasswordEncoder>(() => encoder);
      }
      late UserDetails loaded;
      await runner.runAsync((started) async {
        expect(started.startupFailure, isNull);
        loaded = await started.context
            .getBean<UserDetailsService>()
            .loadUserByUsername(_nameOf(properties));
      });
      return loaded;
    }

    test('a name, roles and a password stored as {noop}', () async {
      final loaded = await user([
        'spring.security.user.name=bob',
        'spring.security.user.password=pw',
        'spring.security.user.roles=ADMIN,USER',
      ]);
      expect(loaded.username, 'bob');
      expect(loaded.password, '{noop}pw');
      expect(
        [for (final a in loaded.authorities) a.authority],
        ['ROLE_ADMIN', 'ROLE_USER'],
      );
    });

    test('a password with an encoding prefix is kept as it is', () async {
      final loaded = await user(['spring.security.user.password={noop}pw']);
      expect(loaded.password, '{noop}pw');
      final hashed = await user([
        r'spring.security.user.password={bcrypt}$2a$10$abc',
      ]);
      expect(hashed.password, r'{bcrypt}$2a$10$abc');
    });

    test('with an encoder bean the password is the encoded one', () async {
      final encoder =
          PasswordEncoderFactories.createDelegatingPasswordEncoder();
      final stored = encoder.encode('secret');
      final loaded = await user([
        'spring.security.user.password=$stored',
      ], encoder: encoder);
      expect(loaded.password, stored);
      final unprefixed = await user([
        'spring.security.user.password=whatever',
      ], encoder: encoder);
      expect(unprefixed.password, 'whatever');
    });

    test('with resource server properties there is no default user', () async {
      await securityRunner(null, [
        '$_jwt.jwk-set-uri=https://issuer.example/jwks',
      ]).runAsync((started) async {
        expect(
          started.context.containsBean('inMemoryUserDetailsManager'),
          isFalse,
        );
        expect(started.context.getBean<JwtDecoder>(), isNotNull);
      });
      await securityRunner(null, [
        '$_jwt.issuer-uri=https://issuer.example',
      ]).runAsync((started) async {
        expect(
          started.context.containsBean('inMemoryUserDetailsManager'),
          isFalse,
        );
      });
      await securityRunner(null, [
        '$_jwt.secret-key=$_secret',
      ]).runAsync((started) async {
        expect(started.startupFailure, isNull);
        expect(
          started.context.containsBean('inMemoryUserDetailsManager'),
          isFalse,
        );
        expect(started.context.getBean<JwtDecoder>(), isNotNull);
      });
    });
  });

  group('the chains', () {
    test(
      'HttpSecurity is a new builder for each chain, under the context path',
      () async {
        await securityRunner(null, [
          'server.context-path=/app',
        ]).runAsync((started) async {
          final first = started.context.getBean<HttpSecurity>();
          final second = started.context.getBean<HttpSecurity>();
          expect(first, isNot(same(second)));
          expect(first.contextPath, '/app');
        });
      },
    );

    test('the proxy is at the configured order', () async {
      await securityRunner(null, [
        _password,
        'spring.security.filter.order=7',
      ]).runAsync((started) async {
        expect(started.context.getBean<FilterChainProxy>().order, 7);
      });
      await securityRunner(null, [_password]).runAsync((started) async {
        expect(started.context.getBean<FilterChainProxy>().order, -100);
      });
    });

    test('a chain matching every request must come last', () async {
      SecurityFilterChain chain(String pattern) =>
          (HttpSecurity(null)
                ..authorizeHttpRequests((a) => a.anyRequest().permitAll())
                ..securityMatcher(pattern))
              .build();
      final everything = HttpSecurity(null)
          .authorizeHttpRequests((a) => a.anyRequest().permitAll())
          .build();
      final failed = securityRunner(null, [_password])
          .withBean<SecurityFilterChain>(() => everything, name: 'a')
          .withBean<SecurityFilterChain>(() => chain('/api/**'), name: 'b')
          .run((started) => started.startupFailure);
      expect(failed.toString(), contains('matches any request'));
      final fine = securityRunner(null, [_password])
          .withBean<SecurityFilterChain>(() => chain('/api/**'), name: 'a')
          .withBean<SecurityFilterChain>(() => everything, name: 'b')
          .run((started) => started.startupFailure);
      expect(fine, isNull);
    });

    test(
      'the default chain asks for a login, with a decoder for a bearer token',
      () async {
        await securityRunner(null, [_password]).runAsync((started) async {
          final chains = started.context.getBeansOfType<SecurityFilterChain>();
          expect(chains, hasLength(1));
          expect(
            [for (final f in chains.values.single.filters) f.runtimeType],
            containsAll([
              UsernamePasswordAuthenticationFilter,
              BasicAuthenticationFilter,
            ]),
          );
        });
        await securityRunner(null, [
          '$_jwt.jwk-set-uri=https://issuer.example/jwks',
        ]).runAsync((started) async {
          final chain = started.context
              .getBeansOfType<SecurityFilterChain>()
              .values
              .single;
          final types = [for (final f in chain.filters) f.runtimeType];
          expect(types, contains(BearerTokenAuthenticationFilter));
          expect(types, isNot(contains(UsernamePasswordAuthenticationFilter)));
        });
      },
    );
  });
}

String _nameOf(List<String> properties) {
  for (final property in properties) {
    if (property.startsWith('spring.security.user.name=')) {
      return property.substring('spring.security.user.name='.length);
    }
  }
  return 'user';
}
