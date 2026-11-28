// Method security and @Retryable together, through the generated proxies
// of test/app: the security check runs before the retries, so a
// @PreAuthorize denial runs nothing and a @PostAuthorize denial is not
// retried (unlike Spring, where the retries come first).
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_security_core/spring_auto_configuration.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

import 'app/app.dart';
import 'app/retried_orders.dart';

ApplicationContextRunner _runner() => const ApplicationContextRunner()
    .withUserConfiguration(securityTestBeans)
    .withAutoConfiguration(springBootAutoConfiguration)
    .withAutoConfiguration(springBootResilienceAutoConfiguration)
    .withAutoConfiguration(springSecurityCoreAutoConfiguration)
    .withPropertyValues(['logging.level.root=warn']);

Future<T> _as<T>(String name, List<String> roles, Future<T> Function() body) {
  final user = User.withUsername(name).password(null).roles(roles).build();
  return SecurityContextHolder.runWithContext(
    body,
    SecurityContextImpl(
      UsernamePasswordAuthenticationToken.authenticated(
        user,
        null,
        user.authorities,
      ),
    ),
  );
}

void main() {
  test('an allowed call is retried', () async {
    await _runner().runAsync((context) async {
      final orders = context.getBean<RetriedOrders>();
      expect(
        await _as('ada', ['ADMIN'], () => orders.cancel('7')),
        'cancelled 7',
      );
      expect(orders.calls, ['cancel 7', 'cancel 7']);
    });
  });

  test('a @PreAuthorize denial runs nothing and is not retried', () async {
    await _runner().runAsync((context) async {
      final orders = context.getBean<RetriedOrders>();
      await expectLater(
        _as('bob', ['USER'], () => orders.cancel('7')),
        throwsA(isA<AccessDeniedException>()),
      );
      expect(orders.calls, isEmpty);
    });
  });

  test('a @PostAuthorize denial is not retried', () async {
    await _runner().runAsync((context) async {
      final orders = context.getBean<RetriedOrders>();
      await expectLater(
        _as('ada', ['USER'], () => orders.owner('7')),
        throwsA(isA<AccessDeniedException>()),
      );
      expect(orders.calls, ['owner 7']);
    });
  });

  test('an AccessDeniedException thrown by the method is never retried', () {
    expect(
      RetryPolicy.withDefaults().shouldRetry(AccessDeniedException()),
      isFalse,
    );
    expect(
      RetryPolicy.withDefaults().shouldRetry(BadCredentialsException()),
      isFalse,
    );
  });

  test('method security is the outermost advice', () async {
    await _runner().runAsync((context) async {
      final advisors =
          (context.getBean<RetriedOrders>() as Advised).aopAdvisors;
      expect(
        [for (final a in advisors) (a as DefaultPointcutAdvisor).order],
        [AdvisorOrder.methodSecurity, AdvisorOrder.retry],
      );
    });
  });
}
