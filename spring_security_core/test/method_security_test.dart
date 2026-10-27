// Method security through the generated proxies of test/app: who may call
// what, with the arguments, results and collections in the expressions;
// failures as 401/403 exceptions; security before @Cacheable; and the
// documented limit (calls through `this` are not checked).
import 'package:spring_boot_starter_cache/spring_auto_configuration.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_security_core/spring_auto_configuration.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

import 'app/app.dart';
import 'app/orders.dart';

ApplicationContextRunner _runner() => const ApplicationContextRunner()
    .withUserConfiguration(securityTestBeans)
    .withAutoConfiguration(springBootAutoConfiguration)
    .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
    .withAutoConfiguration(springBootStarterCacheAutoConfiguration)
    .withAutoConfiguration(springSecurityCoreAutoConfiguration)
    .withPropertyValues(['logging.level.root=warn']);

/// Runs [body] as [name] with [roles] (a `User` principal).
Future<T> as<T>(String name, List<String> roles, Future<T> Function() body) {
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

Future<T> anonymous<T>(Future<T> Function() body) =>
    SecurityContextHolder.runWithContext(
      body,
      SecurityContextImpl(
        AnonymousAuthenticationToken(
          'key',
          'anonymousUser',
          AuthorityUtils.createAuthorityList(['ROLE_ANONYMOUS']),
        ),
      ),
    );

final Matcher _denied = throwsA(isA<AuthorizationDeniedException>());

void main() {
  late ApplicationContext context;
  late OrderService orders;

  // A test with the application started (and closed after it).
  void appTest(String name, Future<void> Function() body) => test(
    name,
    () => _runner().runAsync((started) async {
      context = started.context;
      orders = context.getBean<OrderService>();
      await body();
    }),
  );

  group('@PreAuthorize', () {
    appTest('roles and arguments decide', () async {
      await as('ada', ['USER'], () async {
        orders.cancel(Purchase('1', 'ada'));
        expect(() => orders.cancel(Purchase('2', 'bob')), _denied);
      });
      await as('root', [
        'ADMIN',
      ], () async => orders.cancel(Purchase('2', 'bob')));
      expect(orders.calls, ['cancel 1', 'cancel 2']);
    });

    appTest(
      'async methods fail through their Future, before running',
      () async {
        await as('ada', ['USER'], () async {
          expect(await orders.cancelLater(Purchase('1', 'ada')), 'cancelled 1');
          await expectLater(orders.cancelLater(Purchase('2', 'bob')), _denied);
        });
        expect(orders.calls, ['cancelLater 1']);
      },
    );

    appTest('no authentication at all fails the call, not a pass', () async {
      await SecurityContextHolder.runWithContext(() async {
        expect(
          () => orders.cancel(Purchase('1', 'ada')),
          throwsA(isA<AuthenticationCredentialsNotFoundException>()),
        );
      });
    });

    appTest('anonymous users are denied and can match isAnonymous()', () async {
      await anonymous(() async {
        await expectLater(
          orders.cancelLater(Purchase('1', 'ada')),
          throwsA(isA<AccessDeniedException>()),
        );
        // As in Spring: the anonymous principal is a String, so
        // `principal.username` is an error — the call still fails.
        expect(() => orders.cancel(Purchase('1', 'ada')), throwsArgumentError);
        expect(orders.anonymousOnly(), 'anonymous');
        expect(() => orders.staff(), _denied);
      });
      await as('ada', ['USER'], () async {
        expect(() => orders.anonymousOnly(), _denied);
      });
    });

    appTest('permitAll, denyAll, hasAnyRole with the role hierarchy', () async {
      await as('ada', ['USER'], () async {
        expect(orders.open(), 'open');
        expect(() => orders.closed(), _denied);
        expect(() => orders.staff(), _denied);
      });
      // ROLE_ADMIN > ROLE_SUPPORT (HierarchyConfig).
      await as('root', ['ADMIN'], () async {
        expect(orders.staff(), 'staff');
        expect(() => orders.closed(), _denied);
      });
    });

    appTest('hasPermission uses the PermissionEvaluator bean', () async {
      await as('ada', ['USER'], () async {
        expect(orders.mayCancel(Purchase('1', 'ada')), isTrue);
        expect(() => orders.mayCancel(Purchase('2', 'bob')), _denied);
      });
    });

    appTest('bean references', () async {
      await as('ada', ['USER'], () async {
        expect(orders.shopping(), 'shopping');
        context.getBean<Shop>().open = false;
        expect(() => orders.shopping(), _denied);
      });
    });

    appTest('an expression that is not a boolean fails closed', () async {
      await as('root', ['ADMIN'], () async {
        expect(() => orders.broken(), throwsArgumentError);
      });
    });

    appTest('on the class: every method, a method annotation wins', () async {
      final admin = context.getBean<AdminService>();
      await as('ada', ['USER'], () async {
        expect(admin.report, _denied);
        expect(admin.status(), 'ok');
      });
      await as('root', ['ADMIN'], () async => expect(admin.report(), 'report'));
    });

    appTest('methods without annotations are not checked', () async {
      await SecurityContextHolder.runWithContext(() async {
        expect(orders.unsecured(), 'unsecured');
      });
    });

    appTest(
      'a call through `this` inside the bean is not checked (as Spring)',
      () async {
        await as('ada', ['USER'], () async {
          orders.cancelInside(Purchase('2', 'bob'));
        });
        expect(orders.calls, ['cancel 2']);
      },
    );
  });

  appTest(
    '@Secured: authorities with their prefix and the hierarchy',
    () async {
      await as('ada', ['USER'], () async {
        expect(() => orders.refund('1'), _denied);
      });
      await as('sam', ['SUPPORT'], () async {
        expect(orders.refund('1'), 'refunded 1');
      });
      await as('root', ['ADMIN'], () async {
        expect(orders.refund('2'), 'refunded 2');
      });
    },
  );

  group('@PostAuthorize', () {
    appTest('checks the result; the method has run', () async {
      await as('ada', ['USER'], () async {
        expect(orders.find('1').owner, 'ada');
        expect(() => orders.find('2'), _denied);
      });
      expect(orders.calls, ['find 1', 'find 2']);
    });

    appTest('async results', () async {
      await as('ada', ['USER'], () async {
        expect((await orders.findLater('1')).owner, 'ada');
        await expectLater(orders.findLater('2'), _denied);
      });
    });
  });

  group('filters', () {
    appTest('@PreFilter keeps the allowed elements of the argument', () async {
      await as('ada', ['USER'], () async {
        final kept = orders.keep([Purchase('1', 'ada'), Purchase('2', 'bob')]);
        expect(kept.map((o) => o.id), ['1']);
        expect(
          orders.count(
            [Purchase('1', 'ada'), Purchase('2', 'bob')],
            [Purchase('3', 'bob')],
          ),
          2,
        );
      });
    });

    appTest('@PostFilter keeps the allowed elements of the result', () async {
      await as('ada', ['USER'], () async {
        expect(orders.all().map((o) => o.id), ['1', '3']);
        expect((await orders.allLater()).map((o) => o.id), ['1', '3']);
        expect(orders.owners(), {'1': 'ada'});
      });
    });
  });

  appTest(
    'security runs before @Cacheable: no cached result for the denied',
    () async {
      final reports = context.getBean<Reports>();
      await as('root', ['ADMIN'], () async {
        expect(reports.report('q1'), 'report q1');
        expect(reports.report('q1'), 'report q1');
      });
      expect(reports.runs, 1); // the second call was a cache hit
      await as('ada', ['USER'], () async {
        expect(() => reports.report('q1'), _denied);
      });
    },
  );

  appTest("two concurrent scopes never see each other's user", () async {
    final results = await Future.wait([
      as('ada', ['USER'], () async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return SecurityContextHolder.getContext().authentication!.name;
      }),
      as('bob', ['USER'], () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return SecurityContextHolder.getContext().authentication!.name;
      }),
    ]);
    expect(results, ['ada', 'bob']);
  });
}
