import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/authentication/authentication_manager.dart';
import 'package:spring_security_core/src/authentication/events.dart';
import 'package:spring_security_core/src/authorization/authorization_manager.dart';
import 'package:spring_security_core/src/crypto/password_encoder.dart';
import 'package:spring_security_core/src/method/expression_handler.dart';
import 'package:spring_security_core/src/method/method_security_interceptor.dart';
import 'package:spring_security_core/src/userdetails/user_details_service.dart';

const _source = 'package:spring_security_core#SecurityCoreAutoConfiguration';

/// The position of method security among the advice wrapped around a bean
/// method: before every other advice.
///
/// So `@Cacheable`, `@Validated` and the application's own aspects run
/// only for an authorized call, and a cached result is never returned to
/// someone who may not call the method. An aspect that must run before
/// the security check needs a lower order than this value.
///
/// Spring (Java): `AuthorizationInterceptorsOrder.FIRST` + 100.
const int methodSecurityAdvisorOrder = Ordered.highestPrecedence + 100;

/// Changes the prefix that role checks add, `ROLE_` by default.
///
/// `hasRole('ADMIN')` looks for the authority `ROLE_ADMIN`. When your
/// authorities are named differently, for example plain `ADMIN` from an
/// external directory, declare a bean of this type: method security
/// expressions and the web starter's `hasRole` rules then use your prefix.
///
/// ```dart
/// // Roles are stored without a prefix: hasRole('ADMIN') finds 'ADMIN'.
/// @Bean()
/// GrantedAuthorityDefaults authorityDefaults() =>
///     const GrantedAuthorityDefaults('');
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// static GrantedAuthorityDefaults authorityDefaults() {
///   return new GrantedAuthorityDefaults("");
/// }
/// ```
final class GrantedAuthorityDefaults {
  /// Role checks add [rolePrefix] to role names.
  const GrantedAuthorityDefaults(this.rolePrefix);

  /// The prefix added to role names; `''` adds none.
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

/// The beans this package adds to every application that depends on it;
/// they switch method security and password logins on without any setup.
///
/// - **Method security**: the interceptor behind `@PreAuthorize`,
///   `@PostAuthorize`, `@Secured`, `@PreFilter` and `@PostFilter`, its
///   advisor, and a startup check that every expression parses and every
///   bean with such annotations is proxied. The application can add a
///   `RoleHierarchy`, a `PermissionEvaluator`, `GrantedAuthorityDefaults`
///   and `SecurityExpressionContextCustomizer`s as beans, or replace the
///   `MethodSecurityExpressionHandler`.
/// - **Authentication events**: an `AuthenticationEventPublisher` that
///   publishes `AuthenticationSuccessEvent` and the failure events as
///   application events, unless the application declares its own.
/// - **An `AuthenticationManager`**, when the application declares a
///   `UserDetailsService` or `AuthenticationProvider`s and no manager.
///   With providers, a `ProviderManager` over all of them. Otherwise a
///   `DaoAuthenticationProvider` over the user service, with the
///   `PasswordEncoder` bean (the delegating encoder without one), storing
///   upgraded hashes through a `UserDetailsPasswordService` bean or the
///   user service itself when it is one.
///
/// Spring (Java): parts of `@EnableMethodSecurity` and
/// `AuthenticationConfiguration`. Spring needs `@EnableMethodSecurity`;
/// here the dependency is enough, so an annotation is never silently
/// ignored.
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
