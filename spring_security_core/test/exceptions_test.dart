// The exceptions of the core: their types, messages (for logs) and causes.
// They know nothing of HTTP: the security starter answers them 401 or 403
// with a generic body (spring_boot_starter_security/test/
// security_exceptions_test.dart).
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

void main() {
  final authenticationFailures = <String, AuthenticationException>{
    'BadCredentialsException': BadCredentialsException(
      'password of ada is wrong',
    ),
    'UsernameNotFoundException': UsernameNotFoundException(
      'ada does not exist',
    ),
    'DisabledException': DisabledException('ada is disabled by admin root'),
    'LockedException': LockedException('ada locked after 5 attempts'),
    'AccountExpiredException': AccountExpiredException('ada expired 2020'),
    'CredentialsExpiredException': CredentialsExpiredException('stale'),
    'InsufficientAuthenticationException': InsufficientAuthenticationException(
      'remembered only',
    ),
    'AuthenticationCredentialsNotFoundException':
        AuthenticationCredentialsNotFoundException('nothing in the context'),
    'ProviderNotFoundException': ProviderNotFoundException('no provider'),
    'AuthenticationServiceException': AuthenticationServiceException(
      'jdbc://secret-host is down',
    ),
    'InternalAuthenticationServiceException':
        InternalAuthenticationServiceException('NullPointer in the store'),
  };

  group('authentication failures', () {
    authenticationFailures.forEach((name, exception) {
      test('$name keeps its message for logs', () {
        expect(exception.message, isNotEmpty);
        expect('$exception', '$name: ${exception.message}');
      });
    });

    test('every one is an AuthenticationException and an Exception', () {
      for (final exception in authenticationFailures.values) {
        expect(exception, isA<AuthenticationException>());
        expect(exception, isA<Exception>());
      }
    });

    test('toString names the type and the message, for logs', () {
      expect(
        BadCredentialsException('password of ada is wrong').toString(),
        'BadCredentialsException: password of ada is wrong',
      );
      expect(
        LockedException().toString(),
        'LockedException: User account is locked',
      );
    });
  });

  group('messages and causes', () {
    test('defaults', () {
      expect(BadCredentialsException().message, 'Bad credentials');
      expect(DisabledException().message, 'User is disabled');
      expect(LockedException().message, 'User account is locked');
      expect(AccountExpiredException().message, 'User account has expired');
      expect(
        CredentialsExpiredException().message,
        'User credentials have expired',
      );
      expect(
        InsufficientAuthenticationException().message,
        'Full authentication is required to access this resource',
      );
      expect(
        AuthenticationCredentialsNotFoundException().message,
        'An Authentication object was not found in the SecurityContext',
      );
    });

    test('the cause is kept for logs', () {
      final cause = StateError('database down');
      expect(BadCredentialsException('x', cause).cause, same(cause));
      expect(DisabledException('x', cause).cause, same(cause));
      expect(LockedException('x', cause).cause, same(cause));
      expect(AccountExpiredException('x', cause).cause, same(cause));
      expect(CredentialsExpiredException('x', cause).cause, same(cause));
      expect(
        InsufficientAuthenticationException('x', cause).cause,
        same(cause),
      );
      expect(
        AuthenticationCredentialsNotFoundException('x', cause).cause,
        same(cause),
      );
      expect(UsernameNotFoundException('x', cause).cause, same(cause));
      expect(ProviderNotFoundException('x', cause).cause, same(cause));
      expect(AuthenticationServiceException('x', cause).cause, same(cause));
      expect(
        InternalAuthenticationServiceException('x', cause).cause,
        same(cause),
      );
      expect(BadCredentialsException().cause, isNull);
    });

    test('the request that failed can be attached', () {
      final exception = BadCredentialsException();
      expect(exception.authenticationRequest, isNull);
      final request = UsernamePasswordAuthenticationToken.unauthenticated(
        'a',
        'b',
      );
      exception.authenticationRequest = request;
      expect(exception.authenticationRequest, same(request));
    });

    test('the hierarchy: account problems are status exceptions, the '
        'internal error is a service error', () {
      for (final exception in [
        DisabledException(),
        LockedException(),
        AccountExpiredException(),
        CredentialsExpiredException(),
      ]) {
        expect(exception, isA<AccountStatusException>());
      }
      expect(BadCredentialsException(), isNot(isA<AccountStatusException>()));
      expect(
        InternalAuthenticationServiceException('x'),
        isA<AuthenticationServiceException>(),
      );
      expect(
        AuthenticationServiceException('x'),
        isNot(isA<InternalAuthenticationServiceException>()),
      );
    });
  });

  group('AccessDeniedException', () {
    test('keeps its message for logs', () {
      final denied = AccessDeniedException('needs ROLE_ADMIN for order 17');
      expect(denied.message, 'needs ROLE_ADMIN for order 17');
      expect(denied, isA<Exception>());
    });

    test('toString names the type and the message, for logs', () {
      expect(
        AccessDeniedException('needs ROLE_ADMIN').toString(),
        'AccessDeniedException: needs ROLE_ADMIN',
      );
      expect(
        AccessDeniedException().toString(),
        'AccessDeniedException: Access Denied',
      );
    });

    test('keeps its cause', () {
      final cause = StateError('why');
      expect(AccessDeniedException('x', cause).cause, same(cause));
      expect(AccessDeniedException().cause, isNull);
    });

    test('AuthorizationDeniedException carries the decision', () {
      final denied = AuthorizationDeniedException(
        'Access Denied',
        const AuthorityAuthorizationDecision(false, ['ROLE_ADMIN']),
      );

      expect(denied, isA<AccessDeniedException>());
      expect(denied.result.isGranted, isFalse);
      expect((denied.result as AuthorityAuthorizationDecision).authorities, [
        'ROLE_ADMIN',
      ]);
    });

    test('is not an authentication failure (403 and 401 stay apart)', () {
      expect(AccessDeniedException(), isNot(isA<AuthenticationException>()));
      expect(BadCredentialsException(), isNot(isA<AccessDeniedException>()));
    });
  });
}
