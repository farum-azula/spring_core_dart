// Generated inputs (roadmap/security_verification.md, section 4): random
// and mutated paths, credentials, tokens and rule sets, with invariants that
// must hold for every one. Seeded, so a failure is reproducible; the seed
// and the input are in the failure message.
import 'dart:convert';
import 'dart:math';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_security/src/jwt/jose.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';

const _iterations = 3000;

/// Path pieces that make paths ambiguous, mixed with ordinary ones.
const _pieces = [
  'api',
  'admin',
  'public',
  'users',
  'a',
  'b',
  '1',
  '',
  '.',
  '..',
  '%2e',
  '%2E%2e',
  ';',
  ';x=1',
  '%3b',
  '%2f',
  '%2F',
  '%5c',
  r'\',
  '%25',
  '%00',
  '%0a',
  '%0D',
  '%E2%80%A8',
  '//',
  '%41',
  '~',
  '-',
  '_',
  'ü',
  '%c3%bc',
  ' ',
  '%20',
  '*',
  '{id}',
  '?',
  '#',
];

String _randomPath(Random random) {
  final segments = random.nextInt(5);
  final buffer = StringBuffer();
  for (var i = 0; i <= segments; i++) {
    buffer.write('/');
    final parts = random.nextInt(3);
    for (var j = 0; j <= parts; j++) {
      buffer.write(_pieces[random.nextInt(_pieces.length)]);
    }
  }
  return '$buffer';
}

bool _looksAmbiguous(String path) {
  final lower = path.toLowerCase();
  return path.contains(';') ||
      lower.contains('%2f') ||
      lower.contains('%5c') ||
      path.contains(r'\') ||
      lower.contains('%25') ||
      lower.contains('%2e') ||
      lower.contains('%00') ||
      path.contains('//') ||
      path.split('/').any((s) => s == '.' || s == '..');
}

void main() {
  group('firewall', () {
    test('never throws anything but RequestRejectedException, and lets '
        'nothing ambiguous through', () {
      final firewall = StrictHttpFirewall();
      final random = Random(20261027);
      var passed = 0;
      for (var i = 0; i < _iterations; i++) {
        final path = _randomPath(random);
        final MockServerHttpRequest request;
        try {
          request = MockServerHttpRequest(HttpMethod.get, path);
        } on FormatException {
          continue; // not even a URL: the server would not get this far
        }
        try {
          firewall.check(request);
          passed++;
          expect(
            _looksAmbiguous(request.path),
            isFalse,
            reason: 'let through: $path (seen as ${request.path})',
          );
        } on RequestRejectedException {
          // Refused: fine.
        } on Object catch (e) {
          fail('$path threw ${e.runtimeType}: $e');
        }
      }
      expect(
        passed,
        greaterThan(50),
        reason: 'the generator makes clean paths too',
      );
    });
  });

  group('access rules', () {
    // A random rule set; the rules deny a request when the first matching
    // rule denies it (or none matches): the filter must deny it too.
    test('"denied by the rules" implies "denied by the filter"', () async {
      final random = Random(7);
      const patterns = [
        '/api/**',
        '/api/admin',
        '/api/admin/**',
        '/public/**',
        '/users/{id}',
        '/**',
      ];
      const paths = [
        '/api/admin',
        '/api/admin/x',
        '/api/me',
        '/public/a',
        '/users/ada',
        '/other',
      ];
      final users = <Authentication?>[
        null,
        AnonymousAuthenticationToken(
          'k',
          'anonymousUser',
          AuthorityUtils.createAuthorityList(['ROLE_ANONYMOUS']),
        ),
        TestingAuthenticationToken('ada', null, ['ROLE_USER']),
        TestingAuthenticationToken('root', null, ['ROLE_ADMIN']),
      ];
      for (var i = 0; i < 400; i++) {
        final rules = <(String, String)>[
          for (var r = random.nextInt(4); r >= 0; r--)
            (
              patterns[random.nextInt(patterns.length)],
              [
                'permitAll',
                'denyAll',
                'authenticated',
                'admin',
                'anonymous',
              ][random.nextInt(5)],
            ),
        ];
        final manager = RequestMatcherDelegatingAuthorizationManager([
          for (final (pattern, access) in rules)
            (
              PathPatternRequestMatcher(pattern),
              switch (access) {
                'permitAll' =>
                  const SingleResultAuthorizationManager<
                    RequestAuthorizationContext
                  >.permitAll(),
                'denyAll' =>
                  const SingleResultAuthorizationManager<
                    RequestAuthorizationContext
                  >.denyAll(),
                'authenticated' =>
                  const AuthenticatedAuthorizationManager<
                    RequestAuthorizationContext
                  >.authenticated(),
                'anonymous' =>
                  const AuthenticatedAuthorizationManager<
                    RequestAuthorizationContext
                  >.anonymous(),
                _ =>
                  AuthorityAuthorizationManager<
                    RequestAuthorizationContext
                  >.hasRole('ADMIN'),
              },
            ),
        ]);
        final filter = AuthorizationFilter(manager);
        for (final path in paths) {
          for (final user in users) {
            // The reference: the first matching rule, deny otherwise.
            final first = rules
                .where((r) => PathPattern.parse(r.$1).matches(path))
                .firstOrNull;
            final roles =
                user?.authorities.map((a) => a.authority).toSet() ?? {};
            final real = user != null && user is! AnonymousAuthenticationToken;
            final expectedAllowed = switch (first?.$2) {
              'permitAll' => true,
              'authenticated' => real,
              'anonymous' => user is AnonymousAuthenticationToken,
              'admin' => roles.contains('ROLE_ADMIN'),
              _ => false,
            };
            var reached = false;
            Object? thrown;
            await SecurityContextHolder.runWithContext(() async {
              try {
                await filter.doFilter(
                  MockServerHttpRequest(HttpMethod.get, path),
                  MockServerHttpResponse(),
                  _Reached(() => reached = true),
                );
              } on Object catch (e) {
                thrown = e;
              }
            }, SecurityContextImpl(user));
            if (!expectedAllowed) {
              expect(
                reached,
                isFalse,
                reason: 'rules $rules let $user reach $path',
              );
              expect(thrown, isA<Exception>());
            } else {
              expect(
                reached,
                isTrue,
                reason: 'rules $rules blocked $user on $path',
              );
            }
          }
        }
      }
    });
  });

  group('Basic credentials', () {
    test('any header is a login, nothing, or bad credentials', () {
      final filter = BasicAuthenticationFilter(_NoManager());
      final random = Random(42);
      for (var i = 0; i < _iterations; i++) {
        final bytes = List.generate(
          random.nextInt(40),
          (_) => random.nextInt(256),
        );
        final header = switch (random.nextInt(4)) {
          0 => 'Basic ${base64.encode(bytes)}',
          1 => 'Basic ${latin1.decode(bytes)}',
          2 => 'basic${base64.encode(bytes)}',
          _ => latin1.decode(bytes),
        };
        final request = MockServerHttpRequest(HttpMethod.get, '/')
          ..headers.set('authorization', header);
        try {
          final token = filter.convert(request);
          if (token != null) {
            expect(token.credentials, isA<String>());
          }
        } on BadCredentialsException {
          // Refused: fine.
        } on Object catch (e) {
          fail('${jsonEncode(header)} threw ${e.runtimeType}: $e');
        }
      }
    });
  });

  group('JWT', () {
    final decoder = NimbusJwtDecoder.withJwkSource(
      StaticJwkSource([
        testKeys.rsa.verificationKey,
        testKeys.ec.verificationKey,
      ]),
    );

    test('a mutated valid token never verifies, and never throws anything '
        'but a JwtException', () async {
      final random = Random(99);
      const alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.=+/ ';
      for (var i = 0; i < 600; i++) {
        final original = testKeys.token(
          alg: random.nextBool() ? 'RS256' : 'ES256',
        );
        final chars = original.split('');
        for (var m = random.nextInt(3); m >= 0; m--) {
          final at = random.nextInt(chars.length);
          switch (random.nextInt(3)) {
            case 0:
              chars[at] = alphabet[random.nextInt(alphabet.length)];
            case 1:
              chars.removeAt(at);
            default:
              chars.insert(at, alphabet[random.nextInt(alphabet.length)]);
          }
        }
        final mutated = chars.join();
        if (mutated == original) {
          continue;
        }
        try {
          final jwt = await decoder.decode(mutated);
          // A change only in base64 padding bits may decode to the same
          // bytes: then the token must be the same token.
          expect(
            jwt.claims,
            (await decoder.decode(original)).claims,
            reason: 'accepted a changed token: $mutated',
          );
          expect(
            base64Url.normalize(mutated.split('.').last).length,
            base64Url.normalize(original.split('.').last).length,
          );
        } on JwtException {
          // Refused: fine.
        } on Object catch (e) {
          fail('$mutated threw ${e.runtimeType}: $e');
        }
      }
    });

    test('random bytes are never a token', () {
      final random = Random(5);
      for (var i = 0; i < _iterations; i++) {
        final text = String.fromCharCodes(
          List.generate(random.nextInt(120), (_) => random.nextInt(128)),
        );
        try {
          parseJws(text);
        } on JoseException {
          // Refused: fine.
        } on Object catch (e) {
          fail('${jsonEncode(text)} threw ${e.runtimeType}: $e');
        }
      }
    });
  });
}

final class _Reached implements WebFilterChain {
  _Reached(this.onReach);

  final void Function() onReach;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async => onReach();
}

final class _NoManager implements AuthenticationManager {
  @override
  Future<Authentication> authenticate(Authentication authentication) =>
      throw BadCredentialsException();
}
