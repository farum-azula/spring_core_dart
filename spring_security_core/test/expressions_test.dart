// The expressions of method security without a running application: the
// functions (hasRole, hasAuthority, hasPermission, ...), what an expression
// can read from the authentication and the user (and that it can never
// read or change a password), customizers, and a broken expression failing
// closed.
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_security_core/spring_auto_configuration.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

const _signature = MethodSignature(
  name: 'cancel',
  declaringType: 'OrderService',
  targetType: 'OrderService',
  parameterNames: ['order', 'reason'],
);

/// Remembered logins are those of the principal `remembered`.
final class _RememberMeAware implements AuthenticationTrustResolver {
  const _RememberMeAware();

  static const _base = AuthenticationTrustResolverImpl();

  @override
  bool isAnonymous(Authentication? authentication) =>
      _base.isAnonymous(authentication);

  @override
  bool isRememberMe(Authentication? authentication) =>
      authentication?.principal == 'remembered';

  @override
  bool isAuthenticated(Authentication? authentication) =>
      _base.isAuthenticated(authentication);

  @override
  bool isFullyAuthenticated(Authentication? authentication) =>
      isAuthenticated(authentication) && !isRememberMe(authentication);
}

/// Remembers every question and answers with [answer].
final class RecordingPermissions implements PermissionEvaluator {
  RecordingPermissions({this.answer = true});

  final bool answer;
  final asked = <List<Object?>>[];

  @override
  bool hasPermission(
    Authentication authentication,
    Object? targetDomainObject,
    Object permission,
  ) {
    asked.add(['object', authentication.name, targetDomainObject, permission]);
    return answer;
  }

  @override
  bool hasPermissionById(
    Authentication authentication,
    Object? targetId,
    String targetType,
    Object permission,
  ) {
    asked.add(['id', authentication.name, targetId, targetType, permission]);
    return answer;
  }
}

/// An authentication of the user `ada` with [roles] and [authorities].
Authentication ada({
  List<String> roles = const [],
  List<String> authorities = const [],
  Object? details,
  bool enabled = true,
}) {
  final user = User.withUsername('ada')
      .password('{noop}hunter2')
      .roles(roles)
      .disabled(!enabled)
      .accountLocked(true)
      .build();
  return UsernamePasswordAuthenticationToken.authenticated(user, 'hunter2', [
    ...user.authorities,
    ...AuthorityUtils.createAuthorityList(authorities),
  ])..details = details;
}

/// Evaluates [expression] for [authentication] with the arguments [args].
Object? evaluate(
  String expression, {
  Authentication? authentication,
  MethodSecurityExpressionHandler? handler,
  List<Object?> args = const [],
  Object? target,
  Object? returnObject,
  Object? filterObject,
}) {
  handler ??= MethodSecurityExpressionHandler();
  final root = handler.createRoot(() => authentication, target: target)
    ..returnObject = returnObject
    ..filterObject = filterObject;
  final context = handler.createEvaluationContext(root, _signature, args);
  // Not handler.evaluate: that one accepts only booleans.
  return handler.parse(expression).getValue(context);
}

bool allowed(
  String expression, {
  Authentication? authentication,
  MethodSecurityExpressionHandler? handler,
  List<Object?> args = const [],
}) {
  handler ??= MethodSecurityExpressionHandler();
  final root = handler.createRoot(() => authentication);
  return handler.evaluate(
    expression,
    handler.createEvaluationContext(root, _signature, args),
  );
}

void main() {
  group('roles and authorities', () {
    test('hasAuthority needs exactly that authority, not a role of that '
        'name', () {
      final user = ada(roles: ['ADMIN'], authorities: ['orders:write']);
      expect(
        allowed("hasAuthority('orders:write')", authentication: user),
        isTrue,
      );
      expect(
        allowed("hasAuthority('orders:read')", authentication: user),
        isFalse,
      );
      expect(allowed("hasAuthority('ADMIN')", authentication: user), isFalse);
      expect(
        allowed("hasAuthority('ROLE_ADMIN')", authentication: user),
        isTrue,
      );
    });

    test('hasAnyAuthority takes several names, or a list', () {
      final user = ada(authorities: ['b']);
      expect(
        allowed("hasAnyAuthority('a', 'b')", authentication: user),
        isTrue,
      );
      expect(
        allowed("hasAnyAuthority('a', 'c')", authentication: user),
        isFalse,
      );
      expect(
        allowed("hasAnyAuthority({'a', 'b'})", authentication: user),
        isTrue,
      );
      expect(allowed('hasAnyAuthority({})', authentication: user), isFalse);
    });

    test('hasRole adds the prefix once', () {
      final user = ada(roles: ['USER']);
      expect(allowed("hasRole('USER')", authentication: user), isTrue);
      expect(allowed("hasRole('ROLE_USER')", authentication: user), isTrue);
      expect(allowed("hasRole('ADMIN')", authentication: user), isFalse);
      expect(
        allowed("hasAnyRole('ADMIN', 'USER')", authentication: user),
        isTrue,
      );
      expect(
        allowed("hasAnyRole({'ADMIN', 'ROOT'})", authentication: user),
        isFalse,
      );
    });

    test('the role prefix is configurable, also to none', () {
      final custom = MethodSecurityExpressionHandler(defaultRolePrefix: 'APP_');
      final none = MethodSecurityExpressionHandler(defaultRolePrefix: '');
      final appUser = ada(authorities: ['APP_ADMIN']);
      final plain = ada(authorities: ['ADMIN']);
      expect(
        allowed("hasRole('ADMIN')", authentication: appUser, handler: custom),
        isTrue,
      );
      expect(
        allowed("hasRole('ADMIN')", authentication: plain, handler: custom),
        isFalse,
      );
      expect(
        allowed("hasRole('ADMIN')", authentication: plain, handler: none),
        isTrue,
      );
    });

    test('the role hierarchy applies to roles and authorities', () {
      final handler = MethodSecurityExpressionHandler(
        roleHierarchy: RoleHierarchyImpl.fromHierarchy(
          'ROLE_ADMIN > ROLE_USER',
        ),
      );
      final admin = ada(roles: ['ADMIN']);
      expect(
        allowed("hasRole('USER')", authentication: admin, handler: handler),
        isTrue,
      );
      expect(
        allowed(
          "hasAuthority('ROLE_USER')",
          authentication: admin,
          handler: handler,
        ),
        isTrue,
      );
      expect(allowed("hasRole('USER')", authentication: admin), isFalse);
    });

    test('nobody logged in holds nothing', () {
      expect(allowed("hasRole('USER')"), isFalse);
      expect(allowed("hasAuthority('a')"), isFalse);
      expect(allowed('isAuthenticated()'), isFalse);
      expect(allowed('isAnonymous()'), isFalse);
      expect(allowed("hasPermission(#order, 'cancel')", args: ['x']), isFalse);
    });

    test('the root answers the same without SpEL', () {
      final root = MethodSecurityExpressionRoot(
        () => ada(roles: ['USER'], authorities: ['read']),
      );
      expect(root.hasAuthority('read'), isTrue);
      expect(root.hasAuthority('write'), isFalse);
      expect(root.hasAnyAuthority(['write', 'read']), isTrue);
      expect(root.hasAnyAuthority([]), isFalse);
      expect(root.hasRole('USER'), isTrue);
      expect(root.hasRole('ADMIN'), isFalse);
      expect(root.hasAnyRole(['ADMIN', 'USER']), isTrue);
      expect(root.isAuthenticated(), isTrue);
      expect(root.isAnonymous(), isFalse);
      expect(root.isFullyAuthenticated(), isTrue);
      expect(root.isRememberMe(), isFalse);
    });

    test('names must be strings or lists of them', () {
      expect(
        () => allowed('hasRole(5)', authentication: ada()),
        throwsArgumentError,
      );
      expect(
        () => allowed('hasAuthority(null)', authentication: ada()),
        throwsArgumentError,
      );
    });

    test('permitAll and denyAll, as functions and as words', () {
      expect(allowed('permitAll'), isTrue);
      expect(allowed('permitAll()'), isTrue);
      expect(allowed('denyAll'), isFalse);
      expect(allowed('denyAll()'), isFalse);
    });
  });

  group('how the login is described', () {
    final anonymous = AnonymousAuthenticationToken(
      'key',
      'anonymousUser',
      AuthorityUtils.createAuthorityList(['ROLE_ANONYMOUS']),
    );
    final handler = MethodSecurityExpressionHandler(
      trustResolver: const _RememberMeAware(),
    );

    test('isAuthenticated: logged in and not anonymous', () {
      expect(allowed('isAuthenticated()', authentication: ada()), isTrue);
      expect(allowed('isAuthenticated()', authentication: anonymous), isFalse);
      expect(
        allowed(
          'isAuthenticated()',
          authentication: UsernamePasswordAuthenticationToken.unauthenticated(
            'ada',
            'x',
          ),
        ),
        isFalse,
      );
    });

    test('isAnonymous', () {
      expect(allowed('isAnonymous()', authentication: anonymous), isTrue);
      expect(allowed('isAnonymous()', authentication: ada()), isFalse);
    });

    test('isFullyAuthenticated: a login that was not remembered', () {
      expect(allowed('isFullyAuthenticated()', authentication: ada()), isTrue);
      expect(
        allowed('isFullyAuthenticated()', authentication: anonymous),
        isFalse,
      );
      final remembered = TestingAuthenticationToken('remembered', null);
      expect(
        allowed(
          'isFullyAuthenticated()',
          authentication: remembered,
          handler: handler,
        ),
        isFalse,
      );
      expect(
        allowed(
          'isFullyAuthenticated()',
          authentication: ada(),
          handler: handler,
        ),
        isTrue,
      );
    });

    test('isRememberMe asks the trust resolver (never true by default)', () {
      final remembered = TestingAuthenticationToken('remembered', null);
      expect(allowed('isRememberMe()', authentication: remembered), isFalse);
      expect(
        allowed('isRememberMe()', authentication: remembered, handler: handler),
        isTrue,
      );
      expect(
        allowed('isRememberMe()', authentication: ada(), handler: handler),
        isFalse,
      );
    });
  });

  group('hasPermission', () {
    late RecordingPermissions permissions;
    late MethodSecurityExpressionHandler handler;

    setUp(() {
      permissions = RecordingPermissions();
      handler = MethodSecurityExpressionHandler(
        permissionEvaluator: permissions,
      );
    });

    test('(object, permission) asks about the object', () {
      expect(
        allowed(
          "hasPermission(#order, 'cancel')",
          authentication: ada(),
          handler: handler,
          args: ['order-1'],
        ),
        isTrue,
      );
      expect(permissions.asked, [
        ['object', 'ada', 'order-1', 'cancel'],
      ]);
    });

    test('(id, type, permission) asks about an id of a type', () {
      expect(
        allowed(
          "hasPermission(42, 'Order', 'cancel')",
          authentication: ada(),
          handler: handler,
        ),
        isTrue,
      );
      expect(permissions.asked, [
        ['id', 'ada', 42, 'Order', 'cancel'],
      ]);
    });

    test("the evaluator's no is a no", () {
      handler = MethodSecurityExpressionHandler(
        permissionEvaluator: RecordingPermissions(answer: false),
      );
      expect(
        allowed(
          "hasPermission(1, 'Order', 'cancel')",
          authentication: ada(),
          handler: handler,
        ),
        isFalse,
      );
    });

    test('other numbers of arguments fail instead of guessing', () {
      for (final call in [
        'hasPermission()',
        "hasPermission('x')",
        'hasPermission(1, 2, 3, 4)',
        // The type of (id, type, permission) must be text.
        'hasPermission(1, 2, 3)',
      ]) {
        expect(
          () => allowed(call, authentication: ada(), handler: handler),
          throwsArgumentError,
          reason: call,
        );
      }
      expect(permissions.asked, isEmpty);
    });

    test('a permission may be null-free but the target may be null', () {
      expect(
        allowed(
          "hasPermission(null, 'cancel')",
          authentication: ada(),
          handler: handler,
        ),
        isTrue,
      );
      expect(permissions.asked.single, ['object', 'ada', null, 'cancel']);
    });

    test('without a PermissionEvaluator everything is denied', () {
      expect(
        allowed(
          "hasPermission(#order, 'cancel')",
          authentication: ada(),
          args: ['x'],
        ),
        isFalse,
      );
      expect(
        allowed("hasPermission(1, 'Order', 'cancel')", authentication: ada()),
        isFalse,
      );
      const deny = DenyAllPermissionEvaluator();
      expect(deny.hasPermission(ada(), 'x', 'read'), isFalse);
      expect(deny.hasPermissionById(ada(), 1, 'Order', 'read'), isFalse);
    });
  });

  group('what an expression can read', () {
    final user = ada(
      roles: ['USER'],
      authorities: ['orders:write'],
      details: 'from 10.0.0.1',
    );

    test('the authentication', () {
      expect(evaluate('authentication.name', authentication: user), 'ada');
      expect(
        evaluate('authentication.details', authentication: user),
        'from 10.0.0.1',
      );
      expect(
        evaluate('authentication.authenticated', authentication: user),
        isTrue,
      );
      expect(
        evaluate('authentication.isAuthenticated', authentication: user),
        isTrue,
      );
      expect(
        evaluate('authentication.principal.username', authentication: user),
        'ada',
      );
      expect(
        evaluate('authentication.authorities.size()', authentication: user),
        2,
      );
      expect(
        evaluate(
          'authentication.authorities[0].authority',
          authentication: user,
        ),
        'ROLE_USER',
      );
    });

    test('the principal, shortcut and path', () {
      expect(evaluate('principal.username', authentication: user), 'ada');
      // The user's own authorities (the token also holds orders:write).
      expect(evaluate('principal.authorities.size()', authentication: user), 1);
    });

    test("the user's flags", () {
      final disabled = ada(enabled: false);
      expect(evaluate('principal.enabled', authentication: disabled), isFalse);
      expect(evaluate('principal.isEnabled', authentication: user), isTrue);
      expect(
        evaluate('principal.accountNonExpired', authentication: user),
        isTrue,
      );
      expect(
        evaluate('principal.accountNonLocked', authentication: user),
        isFalse,
      );
      expect(
        evaluate('principal.credentialsNonExpired', authentication: user),
        isTrue,
      );
    });

    test('without an authentication: no principal', () {
      expect(evaluate('principal'), isNull);
      expect(evaluate('authentication'), isNull);
    });

    test('this, the argument names and p0 / a0', () {
      final bean = Object();
      expect(evaluate('this', target: bean), same(bean));
      expect(evaluate('#order', args: ['o', 'r']), 'o');
      expect(evaluate('#reason', args: ['o', 'r']), 'r');
      expect(evaluate('#p1', args: ['o', 'r']), 'r');
      expect(evaluate('#a0', args: ['o', 'r']), 'o');
      // More arguments than names (a signature without them): by index.
      expect(evaluate('#p2', args: ['o', 'r', 'extra']), 'extra');
    });

    test('returnObject and filterObject', () {
      expect(evaluate('returnObject', returnObject: 'result'), 'result');
      expect(evaluate('filterObject', filterObject: 'element'), 'element');
    });

    test('nothing else of the root', () {
      expect(
        () => evaluate('trustResolver', authentication: user),
        throwsA(anything),
      );
      expect(
        () => evaluate('permissionEvaluator', authentication: user),
        throwsA(anything),
      );
    });

    test('an unknown property of the authentication or user is an error', () {
      for (final path in [
        'authentication.nothing',
        'principal.nothing',
        'authentication.authorities[0].nothing',
      ]) {
        expect(
          () => evaluate(path, authentication: user),
          throwsA(anything),
          reason: path,
        );
      }
    });
  });

  group('passwords and credentials are not readable', () {
    final user = ada(roles: ['USER']);

    for (final path in [
      'authentication.credentials',
      'principal.password',
      'authentication.principal.password',
      'authentication.principal.credentials',
    ]) {
      test('$path fails, in a condition too', () {
        expect(() => evaluate(path, authentication: user), throwsA(anything));
        // A rule that tests a password guess must fail closed, not answer.
        expect(
          () => allowed("$path == 'hunter2'", authentication: user),
          throwsArgumentError,
        );
      });
    }

    test('the accessor refuses by name for users, tokens and the root', () {
      final context = MethodSecurityExpressionHandler().createEvaluationContext(
        MethodSecurityExpressionRoot(() => user),
        _signature,
        const [],
      );
      final accessor = context.propertyAccessors.firstWhere(
        (a) => '${a.runtimeType}' == '_SecurityPropertyAccessor',
      );
      final principal = user.principal! as User;

      expect(accessor.canRead(context, principal, 'username'), isTrue);
      expect(accessor.canRead(context, principal, 'password'), isFalse);
      expect(accessor.canRead(context, user, 'credentials'), isFalse);
      expect(accessor.canRead(context, user, 'principal'), isTrue);
      expect(accessor.canRead(context, 'a string', 'length'), isFalse);
      expect(
        accessor.canRead(context, SimpleGrantedAuthority('A'), 'authority'),
        isTrue,
      );
      expect(
        accessor.canRead(context, SimpleGrantedAuthority('A'), 'other'),
        isFalse,
      );
    });
  });

  group('assignments are refused', () {
    final user = ada(roles: ['USER'], details: 'original');

    test('of properties of the authentication and the user', () {
      for (final assignment in [
        "authentication.details = 'changed'",
        "principal.username = 'root'",
        'authentication.authenticated = false',
        'principal.enabled = false',
      ]) {
        expect(
          () => evaluate(assignment, authentication: user),
          throwsA(anything),
          reason: assignment,
        );
      }
      expect(user.details, 'original');
      expect((user.principal! as User).username, 'ada');
      expect(user.isAuthenticated, isTrue);
    });

    test('through an expression that must give a boolean', () {
      expect(
        () => allowed(
          "(authentication.details = 'x') == 'x'",
          authentication: user,
        ),
        throwsArgumentError,
      );
      expect(user.details, 'original');
    });

    test('the accessor says so when asked to write', () {
      final context = MethodSecurityExpressionHandler().createEvaluationContext(
        MethodSecurityExpressionRoot(() => user),
        _signature,
        const [],
      );
      final accessor = context.propertyAccessors.firstWhere(
        (a) => '${a.runtimeType}' == '_SecurityPropertyAccessor',
      );

      expect(accessor.canWrite(context, user, 'details'), isFalse);
      expect(
        () => accessor.write(context, user, 'details', 'changed'),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('details'),
          ),
        ),
      );
      expect(user.details, 'original');
    });
  });

  group('a broken expression fails closed', () {
    test('a value that is not a boolean', () {
      expect(
        () => allowed("'yes'", authentication: ada()),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('must be a boolean'),
          ),
        ),
      );
      expect(() => allowed('null', authentication: ada()), throwsArgumentError);
      expect(() => allowed('1', authentication: ada()), throwsArgumentError);
    });

    test('a syntax error or an unknown function', () {
      expect(
        () => allowed('hasRole(', authentication: ada()),
        throwsArgumentError,
      );
      expect(
        () => allowed('noSuchFunction()', authentication: ada()),
        throwsArgumentError,
      );
    });

    test('the failure names the expression, not the credentials', () {
      try {
        allowed('principal.password == null', authentication: ada());
        fail('must throw');
      } on ArgumentError catch (e) {
        expect(e.message, contains('principal.password == null'));
        expect('${e.message}', isNot(contains('hunter2')));
      }
    });

    test('an AuthenticationException thrown by a function stays what it is '
        '(a 401 must not turn into a 500)', () {
      final handler = MethodSecurityExpressionHandler(
        customizers: [
          _Customizer((context) => context.addMethodResolver(_BoomFunction())),
        ],
      );
      expect(
        () => allowed('boom()', authentication: ada(), handler: handler),
        throwsA(isA<LockedException>()),
      );
    });

    test('any other failure inside, also in a property, denies the call '
        'as an error', () {
      final handler = MethodSecurityExpressionHandler(
        customizers: [
          _Customizer((context) => context.addPropertyAccessor(_Boom())),
        ],
      );
      expect(
        () => allowed('boom', authentication: ada(), handler: handler),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains("Failed to evaluate expression 'boom'"),
          ),
        ),
      );
    });

    test('parsed expressions are cached', () {
      final handler = MethodSecurityExpressionHandler();
      expect(identical(handler.parse('true'), handler.parse('true')), isTrue);
      expect(identical(handler.parse('true'), handler.parse('false')), isFalse);
    });
  });

  group('customizers', () {
    test('add variables, functions and accessors to every context', () {
      final handler = MethodSecurityExpressionHandler(
        customizers: [
          _Customizer((context) => context.setVariable('tenant', 'acme')),
          _Customizer((context) => context.addPropertyAccessor(_Tenant())),
        ],
      );
      expect(
        allowed("#tenant == 'acme'", authentication: ada(), handler: handler),
        isTrue,
      );
      expect(
        allowed(
          "authentication.principal.tenant == 'acme'",
          authentication: ada(),
          handler: handler,
        ),
        isTrue,
      );
      // A second context starts clean: the customizers run per context.
      expect(evaluate('#tenant', handler: handler), 'acme');
    });

    test('are applied after the arguments, so they can read them', () {
      final seen = <Object?>[];
      final handler = MethodSecurityExpressionHandler(
        customizers: [
          _Customizer((context) => seen.add(context.lookupVariable('order'))),
        ],
      );
      allowed('true', handler: handler, args: ['order-7']);
      expect(seen, ['order-7']);
    });

    test('the list given is copied', () {
      final given = <SecurityExpressionContextCustomizer>[];
      final handler = MethodSecurityExpressionHandler(customizers: given);
      given.add(_Customizer((context) => context.setVariable('late', 1)));
      expect(handler.customizers, isEmpty);
      expect(
        () => handler.customizers.add(_Customizer((_) {})),
        throwsUnsupportedError,
      );
    });
  });

  group('the beans of the application', () {
    ApplicationContextRunner runner() => const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springSecurityCoreAutoConfiguration)
        .withPropertyValues(['logging.level.root=warn']);

    test('the handler has the defaults without any bean of its own', () async {
      await runner().runAsync((started) async {
        final handler = started.context
            .getBean<MethodSecurityExpressionHandler>();
        expect(handler.defaultRolePrefix, 'ROLE_');
        expect(handler.permissionEvaluator, isA<DenyAllPermissionEvaluator>());
        expect(handler.roleHierarchy, isA<NullRoleHierarchy>());
        expect(handler.customizers, isEmpty);
      });
    });

    test('GrantedAuthorityDefaults changes the role prefix', () async {
      await runner()
          .withBean<GrantedAuthorityDefaults>(
            () => const GrantedAuthorityDefaults('APP_'),
          )
          .runAsync((started) async {
            final handler = started.context
                .getBean<MethodSecurityExpressionHandler>();
            expect(handler.defaultRolePrefix, 'APP_');
            expect(
              allowed(
                "hasRole('ADMIN')",
                authentication: ada(authorities: ['APP_ADMIN']),
                handler: handler,
              ),
              isTrue,
            );
          });
      expect(const GrantedAuthorityDefaults('').rolePrefix, isEmpty);
    });

    test('a PermissionEvaluator, a RoleHierarchy and customizers are '
        'picked up', () async {
      final permissions = RecordingPermissions();
      await runner()
          .withBean<PermissionEvaluator>(() => permissions)
          .withBean<RoleHierarchy>(
            () => RoleHierarchyImpl.fromHierarchy('ROLE_ADMIN > ROLE_USER'),
          )
          .withBean<SecurityExpressionContextCustomizer>(
            () =>
                _Customizer((context) => context.setVariable('tenant', 'acme')),
          )
          .runAsync((started) async {
            final handler = started.context
                .getBean<MethodSecurityExpressionHandler>();
            final admin = ada(roles: ['ADMIN']);
            expect(
              allowed(
                "hasRole('USER')",
                authentication: admin,
                handler: handler,
              ),
              isTrue,
            );
            expect(
              allowed(
                "hasPermission(1, 'Order', 'read')",
                authentication: admin,
                handler: handler,
              ),
              isTrue,
            );
            expect(permissions.asked, hasLength(1));
            expect(evaluate('#tenant', handler: handler), 'acme');
          });
    });
  });
}

final class _Customizer implements SecurityExpressionContextCustomizer {
  _Customizer(this._customize);

  final void Function(StandardEvaluationContext context) _customize;

  @override
  void customize(StandardEvaluationContext context) => _customize(context);
}

/// A function `boom()` that fails like a login would.
final class _BoomFunction implements MethodResolver {
  @override
  MethodExecutor? resolve(
    EvaluationContext context,
    Object target,
    String name,
    List<Object?> arguments,
  ) => name == 'boom' ? (_, _, _) => throw LockedException() : null;
}

/// A property `boom` of the root that fails.
final class _Boom implements PropertyAccessor {
  @override
  bool canRead(EvaluationContext context, Object target, String name) =>
      name == 'boom';

  @override
  Object? read(EvaluationContext context, Object target, String name) =>
      throw LockedException();

  @override
  bool canWrite(EvaluationContext context, Object target, String name) => false;

  @override
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  ) {}
}

/// `tenant` of a user.
final class _Tenant implements PropertyAccessor {
  @override
  bool canRead(EvaluationContext context, Object target, String name) =>
      target is User && name == 'tenant';

  @override
  Object? read(EvaluationContext context, Object target, String name) => 'acme';

  @override
  bool canWrite(EvaluationContext context, Object target, String name) => false;

  @override
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  ) {}
}
