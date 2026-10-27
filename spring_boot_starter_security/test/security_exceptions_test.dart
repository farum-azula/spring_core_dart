// How a web request answers the core's exceptions, which know nothing of
// HTTP: inside a chain the ExceptionTranslationFilter answers them (the
// login method's challenge, the access denied handler); a request outside
// every chain that calls a method with @PreAuthorize is answered by the
// FilterChainProxy itself, 401 or 403 with a generic ProblemDetail that
// never tells the exception's message.
import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

/// The rest of the request: a controller failing with [error].
final class _Failing implements WebFilterChain {
  _Failing(this.error);

  final Exception error;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async => throw error;
}

Future<MockServerHttpResponse> _answer(
  Exception error, {
  List<SecurityFilterChain> chains = const [],
}) async {
  final response = MockServerHttpResponse();
  await FilterChainProxy(chains).doFilter(
    MockServerHttpRequest(HttpMethod.get, '/reports/17'),
    response,
    _Failing(error),
  );
  return response;
}

void main() {
  group('outside every chain', () {
    final authenticationFailures = <AuthenticationException>[
      AuthenticationCredentialsNotFoundException('no user in the context'),
      BadCredentialsException('password of ada is wrong'),
      LockedException('ada locked after 5 attempts'),
      AuthenticationServiceException('jdbc://secret-host is down'),
    ];

    for (final failure in authenticationFailures) {
      test('${failure.runtimeType}: 401, nothing of the message', () async {
        final response = await _answer(failure);
        expect(response.statusCode, 401);
        expect(response.headers.contentType, 'application/problem+json');
        final problem = jsonDecode(response.bodyText) as Map<String, Object?>;
        expect(problem['status'], 401);
        expect(
          problem['detail'],
          'Full authentication is required to access this resource',
        );
        expect(problem['instance'], '/reports/17');
        expect(response.bodyText, isNot(contains(failure.message)));
      });
    }

    test('AccessDeniedException: 403, nothing of the message', () async {
      final response = await _answer(
        AuthorizationDeniedException(
          'needs ROLE_ADMIN for report 17',
          const AuthorityAuthorizationDecision(false, ['ROLE_ADMIN']),
        ),
      );
      expect(response.statusCode, 403);
      final problem = jsonDecode(response.bodyText) as Map<String, Object?>;
      expect(problem['status'], 403);
      expect(problem['detail'], 'Access Denied');
      expect(response.bodyText, isNot(contains('ROLE_ADMIN')));
    });

    test('any other error goes on to the web starter (a 500 there)', () async {
      await expectLater(
        _answer(const FormatException('database down')),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('a chain that does not match the request answers the same', () async {
    final apiOnly = DefaultSecurityFilterChain(
      PathPatternRequestMatcher('/api/**'),
      const [],
    );
    final response = await _answer(AccessDeniedException(), chains: [apiOnly]);
    expect(response.statusCode, 403);
  });
}
