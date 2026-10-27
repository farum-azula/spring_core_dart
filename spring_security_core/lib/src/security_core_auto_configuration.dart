import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/authentication/authentication_manager.dart';
import 'package:spring_security_core/src/authentication/events.dart';
import 'package:spring_security_core/src/authorization/authorization_manager.dart';
import 'package:spring_security_core/src/crypto/password_encoder.dart';
import 'package:spring_security_core/src/method/expression_handler.dart';
import 'package:spring_security_core/src/method/method_security_interceptor.dart';
import 'package:spring_security_core/src/userdetails/user_details_service.dart';

const _source = 'package:spring_security_core#SecurityCoreAutoConfiguration';

/// Where the method security advisor sits among the advisors: before
/// every other one (Spring's `AuthorizationInterceptorsOrder.FIRST` +
/// 100), so `@Cacheable`, `@Validated` and the application's aspects run
/// only for an authorized call — a cached result is never returned to
/// someone who may not call the method.
const int methodSecurityAdvisorOrder = Ordered.highestPrecedence + 100;

/// The prefix `hasRole` adds, like Spring's `GrantedAuthorityDefaults`:
/// declare a bean to change `ROLE_`.
///
/// ```dart
/// @Bean()
/// GrantedAuthorityDefaults authorityDefaults() =>
///     const GrantedAuthorityDefaults('');
/// ```
final class GrantedAuthorityDefaults {
  /// Roles get [rolePrefix].
  const GrantedAuthorityDefaults(this.rolePrefix);

  /// The prefix.
  final String rolePrefix;
}

// The application has users or providers of its own to authenticate with.
final class _OnAuthenticationSources implements Condition {
  const _OnAuthenticationSources();

  @override
  bool matches(ConditionContext context) =>
      context.beanFactory.getBeanNamesForType(UserDetailsService).isNotEmpty ||
      context.beanFactory
          .getBeanNamesForType(AuthenticationProvider)
          .isNotEmpty;
}

/// The beans of `spring_security_core`, like the parts of Spring
/// Security's `@EnableMethodSecurity` and `AuthenticationConfiguration`:
///
/// - **method security** — the interceptor behind `@PreAuthorize`,
///   `@PostAuthorize`, `@Secured`, `@PreFilter` and `@PostFilter`, its
///   advisor, and a check at startup that every expression parses and
///   every bean with such annotations is proxied. Spring needs
///   `@EnableMethodSecurity`; here the dependency is enough, so an
///   annotation is never silently ignored. Optional beans:
///   `RoleHierarchy`, `PermissionEvaluator`, `GrantedAuthorityDefaults`,
///   `SecurityExpressionContextCustomizer`s;
/// - **authentication events** — an `AuthenticationEventPublisher`
///   publishing `AuthenticationSuccessEvent` and the failure events;
/// - **an `AuthenticationManager`** — when the application declares a
///   `UserDetailsService` or `AuthenticationProvider`s and no manager:
///   its providers, or a `DaoAuthenticationProvider` over the user
///   service with the `PasswordEncoder` bean (the delegating encoder
///   without one), upgrading hashes through a
///   `UserDetailsPasswordService` bean.
final securityCoreAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<MethodSecurityExpressionHandler>(
    name: 'methodSecurityExpressionHandler',
    factoryMethodName: 'methodSecurityExpressionHandler',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.methodSecurityExpressionHandler', [
        ConditionalOnMissingBean(MethodSecurityExpressionHandler),
      ]),
    ],
    create: (r) => MethodSecurityExpressionHandler(
      introspector: r.optionalDependency<BeanIntrospector>(),
      beanFactory: r.dependency<BeanFactory>(),
      roleHierarchy:
          r.optionalDependency<RoleHierarchy>() ?? const NullRoleHierarchy(),
      permissionEvaluator:
          r.optionalDependency<PermissionEvaluator>() ??
          const DenyAllPermissionEvaluator(),
      defaultRolePrefix:
          r.optionalDependency<GrantedAuthorityDefaults>()?.rolePrefix ??
          'ROLE_',
      customizers:
          r.optionalDependencyList<SecurityExpressionContextCustomizer>() ??
          const [],
    ),
  ),
  BeanDefinition<MethodSecurityInterceptor>(
    name: 'methodSecurityInterceptor',
    types: const [MethodSecurityInterceptor, MethodInterceptor],
    source: _source,
    create: (r) => MethodSecurityInterceptor(
      r.dependency<MethodSecurityExpressionHandler>(),
    ),
  ),
  BeanDefinition<MethodSecurityValidator>(
    name: 'methodSecurityValidator',
    types: const [
      MethodSecurityValidator,
      BeanPostProcessor,
      BeanFactoryAware,
      Ordered,
    ],
    source: _source,
    create: (r) {
      final factory = r.dependency<BeanFactory>();
      return MethodSecurityValidator(
        () => factory.getBean<MethodSecurityInterceptor>(),
      );
    },
  ),
  BeanDefinition<DefaultPointcutAdvisor>(
    name: 'methodSecurityAdvisor',
    types: const [DefaultPointcutAdvisor, PointcutAdvisor, Advisor, Ordered],
    source: _source,
    create: (r) => DefaultPointcutAdvisor(
      const MethodSecurityPointcut(),
      r.dependency<MethodSecurityInterceptor>(),
      order: methodSecurityAdvisorOrder,
    ),
  ),
  BeanDefinition<AuthenticationEventPublisher>(
    name: 'authenticationEventPublisher',
    factoryMethodName: 'authenticationEventPublisher',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.authenticationEventPublisher', [
        ConditionalOnMissingBean(AuthenticationEventPublisher),
      ]),
    ],
    create: (r) => DefaultAuthenticationEventPublisher(
      r.dependency<ApplicationEventPublisher>(),
    ),
  ),
  BeanDefinition<AuthenticationManager>(
    name: 'authenticationManager',
    factoryMethodName: 'authenticationManager',
    source: _source,
    conditions: const [
      ConditionGroup('$_source.authenticationManager', [
        ConditionalOnMissingBean(AuthenticationManager),
        _OnAuthenticationSources(),
      ]),
    ],
    create: (r) {
      final providers =
          r.optionalDependencyList<AuthenticationProvider>() ?? const [];
      final List<AuthenticationProvider> all;
      if (providers.isNotEmpty) {
        all = providers;
      } else {
        final users = r.dependency<UserDetailsService>();
        all = [
          DaoAuthenticationProvider(
            users,
            passwordEncoder: r.optionalDependency<PasswordEncoder>(),
            userDetailsPasswordService:
                r.optionalDependency<UserDetailsPasswordService>() ??
                (users is UserDetailsPasswordService
                    ? users as UserDetailsPasswordService
                    : null),
          ),
        ];
      }
      return ProviderManager(
        all,
        eventPublisher: r.dependency<AuthenticationEventPublisher>(),
      );
    },
  ),
];
