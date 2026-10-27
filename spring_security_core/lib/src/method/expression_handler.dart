import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/authorization/authorization_manager.dart';
import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/authority.dart';
import 'package:spring_security_core/src/core/exceptions.dart';
import 'package:spring_security_core/src/userdetails/user_details.dart';

/// Decides `hasPermission(...)` in security expressions, like Spring's
/// `PermissionEvaluator`.
///
/// ```dart
/// @Component()
/// class OrderPermissions implements PermissionEvaluator {
///   @override
///   bool hasPermission(Authentication authentication, Object? target,
///       Object permission) =>
///       target is Order && target.owner == authentication.name;
///
///   @override
///   bool hasPermissionById(Authentication authentication, Object? targetId,
///       String targetType, Object permission) => false;
/// }
/// ```
abstract interface class PermissionEvaluator {
  /// `hasPermission(#order, 'cancel')`.
  bool hasPermission(
    Authentication authentication,
    Object? targetDomainObject,
    Object permission,
  );

  /// `hasPermission(#id, 'Order', 'cancel')`.
  bool hasPermissionById(
    Authentication authentication,
    Object? targetId,
    String targetType,
    Object permission,
  );
}

/// Denies every `hasPermission`, like Spring's `DenyAllPermissionEvaluator`
/// (the default until the application declares a [PermissionEvaluator]).
final class DenyAllPermissionEvaluator implements PermissionEvaluator {
  /// The evaluator.
  const DenyAllPermissionEvaluator();

  @override
  bool hasPermission(
    Authentication authentication,
    Object? targetDomainObject,
    Object permission,
  ) => false;

  @override
  bool hasPermissionById(
    Authentication authentication,
    Object? targetId,
    String targetType,
    Object permission,
  ) => false;
}

/// Changes the evaluation context of security expressions: add property
/// accessors for the application's principal types, variables, functions.
/// Every bean of this type is applied.
///
/// ```dart
/// @Component()
/// class AccountExpressions implements SecurityExpressionContextCustomizer {
///   @override
///   void customize(StandardEvaluationContext context) =>
///       context.addPropertyAccessor(FunctionPropertyAccessor<Account>(
///           getters: {'tenant': (a) => a.tenant}));
/// }
/// ```
abstract interface class SecurityExpressionContextCustomizer {
  /// Adjusts [context].
  void customize(StandardEvaluationContext context);
}

/// The root object of security expressions, like Spring's
/// `MethodSecurityExpressionRoot`: `hasRole`, `principal`, ...
final class MethodSecurityExpressionRoot {
  /// The root for [authentication] (read when first needed).
  MethodSecurityExpressionRoot(
    this._authentication, {
    this.trustResolver = const AuthenticationTrustResolverImpl(),
    this.roleHierarchy = const NullRoleHierarchy(),
    this.permissionEvaluator = const DenyAllPermissionEvaluator(),
    this.defaultRolePrefix = 'ROLE_',
    this.target,
  });

  final Authentication? Function() _authentication;

  /// Tells anonymous from authenticated.
  final AuthenticationTrustResolver trustResolver;

  /// Expands roles.
  final RoleHierarchy roleHierarchy;

  /// Answers `hasPermission`.
  final PermissionEvaluator permissionEvaluator;

  /// Added to roles without it.
  final String defaultRolePrefix;

  /// The bean the method belongs to (`this`).
  final Object? target;

  /// The returned value (`@PostAuthorize`).
  Object? returnObject;

  /// The element being filtered (`@PreFilter`, `@PostFilter`).
  Object? filterObject;

  Set<String>? _authorities;

  /// The current authentication (`null` when there is none).
  Authentication? get authentication => _authentication();

  /// The principal of [authentication].
  Object? get principal => authentication?.principal;

  Set<String> get _held => _authorities ??= AuthorityUtils.authorityListToSet(
    roleHierarchy.getReachableGrantedAuthorities(
      authentication?.authorities ?? const [],
    ),
  );

  /// Whether the user has [authority].
  bool hasAuthority(String authority) => _held.contains(authority);

  /// Whether the user has one of [authorities].
  bool hasAnyAuthority(List<String> authorities) =>
      authorities.any(_held.contains);

  /// Whether the user has [role] (the prefix is added when missing).
  bool hasRole(String role) => hasAnyRole([role]);

  /// Whether the user has one of [roles].
  bool hasAnyRole(List<String> roles) => roles.any(
    (role) => _held.contains(
      defaultRolePrefix.isEmpty || role.startsWith(defaultRolePrefix)
          ? role
          : '$defaultRolePrefix$role',
    ),
  );

  /// Whether the request is authenticated and not anonymous.
  bool isAuthenticated() => trustResolver.isAuthenticated(authentication);

  /// Whether the user logged in fully (not remembered).
  bool isFullyAuthenticated() =>
      trustResolver.isFullyAuthenticated(authentication);

  /// Whether the request is anonymous.
  bool isAnonymous() => trustResolver.isAnonymous(authentication);

  /// Whether the user came back through remember-me.
  bool isRememberMe() => trustResolver.isRememberMe(authentication);

  /// `hasPermission(target, permission)` or
  /// `hasPermission(id, type, permission)`.
  bool hasPermission(List<Object?> arguments) {
    final authentication = this.authentication;
    if (authentication == null) {
      return false;
    }
    return switch (arguments) {
      [final target, final Object permission] =>
        permissionEvaluator.hasPermission(authentication, target, permission),
      [final id, final String type, final Object permission] =>
        permissionEvaluator.hasPermissionById(
          authentication,
          id,
          type,
          permission,
        ),
      _ => throw ArgumentError(
        'hasPermission takes (target, permission) or (id, type, permission)',
      ),
    };
  }
}

/// Builds the evaluation contexts of security expressions, like Spring's
/// `DefaultMethodSecurityExpressionHandler`.
final class MethodSecurityExpressionHandler {
  /// A handler; [introspector] reads the application's classes (the
  /// arguments), [beanFactory] resolves `@bean` references.
  MethodSecurityExpressionHandler({
    this.introspector,
    this.beanFactory,
    this.trustResolver = const AuthenticationTrustResolverImpl(),
    this.roleHierarchy = const NullRoleHierarchy(),
    this.permissionEvaluator = const DenyAllPermissionEvaluator(),
    this.defaultRolePrefix = 'ROLE_',
    List<SecurityExpressionContextCustomizer> customizers = const [],
  }) : customizers = List.unmodifiable(customizers);

  /// Reads the application's classes.
  final BeanIntrospector? introspector;

  /// Resolves `@bean` in expressions.
  final BeanFactory? beanFactory;

  /// Tells anonymous from authenticated.
  final AuthenticationTrustResolver trustResolver;

  /// Expands roles.
  final RoleHierarchy roleHierarchy;

  /// Answers `hasPermission`.
  final PermissionEvaluator permissionEvaluator;

  /// Added to roles without it.
  final String defaultRolePrefix;

  /// Applied to every context.
  final List<SecurityExpressionContextCustomizer> customizers;

  final _parser = SpelExpressionParser();
  final _expressions = <String, Expression>{};

  /// The parsed [text] (cached).
  Expression parse(String text) =>
      _expressions[text] ??= _parser.parseExpression(text);

  /// The root of a call by [authentication] on [target].
  MethodSecurityExpressionRoot createRoot(
    Authentication? Function() authentication, {
    Object? target,
  }) => MethodSecurityExpressionRoot(
    authentication,
    trustResolver: trustResolver,
    roleHierarchy: roleHierarchy,
    permissionEvaluator: permissionEvaluator,
    defaultRolePrefix: defaultRolePrefix,
    target: target,
  );

  /// A context for [root] with the arguments [args] of [signature].
  StandardEvaluationContext createEvaluationContext(
    MethodSecurityExpressionRoot root,
    MethodSignature signature,
    List<Object?> args,
  ) {
    final context = StandardEvaluationContext(root)
      ..addPropertyAccessor(const _SecurityPropertyAccessor())
      ..addMethodResolver(const _RootMethodResolver());
    if (introspector case final introspector?) {
      context
        ..addPropertyAccessor(IntrospectionPropertyAccessor(introspector))
        ..addMethodResolver(IntrospectionMethodResolver(introspector));
    }
    if (beanFactory case final factory?) {
      context.beanResolver = BeanFactoryResolver(factory);
    }
    for (var i = 0; i < args.length; i++) {
      context
        ..setVariable('p$i', args[i])
        ..setVariable('a$i', args[i]);
      if (i < signature.parameterNames.length) {
        context.setVariable(signature.parameterNames[i], args[i]);
      }
    }
    for (final customizer in customizers) {
      customizer.customize(context);
    }
    return context;
  }

  /// Evaluates [text] to a `bool`; anything else is an error (a broken
  /// expression must never let a call through).
  bool evaluate(String text, StandardEvaluationContext context) {
    final Object? value;
    try {
      value = parse(text).getValue(context);
    } on AuthenticationException {
      rethrow;
    } on Object catch (e) {
      throw ArgumentError("Failed to evaluate expression '$text': $e");
    }
    if (value is! bool) {
      throw ArgumentError(
        "Expression '$text' must be a boolean, it gave ${value.runtimeType}",
      );
    }
    return value;
  }
}

// The root's methods: hasRole(...), hasPermission(...), ...
final class _RootMethodResolver implements MethodResolver {
  const _RootMethodResolver();

  static List<String> _strings(List<Object?> args) => [
    for (final arg in args)
      if (arg is String)
        arg
      else if (arg is Iterable)
        ...arg.map((a) => '$a')
      else
        throw ArgumentError('Expected role or authority names, got $arg'),
  ];

  @override
  MethodExecutor? resolve(
    EvaluationContext context,
    Object target,
    String name,
    List<Object?> arguments,
  ) {
    if (target is! MethodSecurityExpressionRoot) {
      return null;
    }
    return switch (name) {
      'hasRole' => (
        _,
        t,
        args,
      ) => (t as MethodSecurityExpressionRoot).hasAnyRole(_strings(args)),
      'hasAnyRole' => (
        _,
        t,
        args,
      ) => (t as MethodSecurityExpressionRoot).hasAnyRole(_strings(args)),
      'hasAuthority' => (
        _,
        t,
        args,
      ) => (t as MethodSecurityExpressionRoot).hasAnyAuthority(_strings(args)),
      'hasAnyAuthority' => (
        _,
        t,
        args,
      ) => (t as MethodSecurityExpressionRoot).hasAnyAuthority(_strings(args)),
      'isAuthenticated' => (
        _,
        t,
        _,
      ) => (t as MethodSecurityExpressionRoot).isAuthenticated(),
      'isFullyAuthenticated' => (
        _,
        t,
        _,
      ) => (t as MethodSecurityExpressionRoot).isFullyAuthenticated(),
      'isAnonymous' => (
        _,
        t,
        _,
      ) => (t as MethodSecurityExpressionRoot).isAnonymous(),
      'isRememberMe' => (
        _,
        t,
        _,
      ) => (t as MethodSecurityExpressionRoot).isRememberMe(),
      'permitAll' => (_, _, _) => true,
      'denyAll' => (_, _, _) => false,
      'hasPermission' => (
        _,
        t,
        args,
      ) => (t as MethodSecurityExpressionRoot).hasPermission(args),
      _ => null,
    };
  }
}

// Properties of the root, of authentications, users and authorities.
// Passwords and credentials are not readable from expressions.
final class _SecurityPropertyAccessor implements PropertyAccessor {
  const _SecurityPropertyAccessor();

  static final _missing = Object();

  static Object? _read(Object target, String name) => switch (target) {
    MethodSecurityExpressionRoot() => switch (name) {
      'principal' => target.principal,
      'authentication' => target.authentication,
      'returnObject' => target.returnObject,
      'filterObject' => target.filterObject,
      'this' => target.target,
      'permitAll' => true,
      'denyAll' => false,
      _ => _missing,
    },
    Authentication() => switch (name) {
      'name' => target.name,
      'principal' => target.principal,
      'authorities' => target.authorities,
      'details' => target.details,
      'authenticated' || 'isAuthenticated' => target.isAuthenticated,
      _ => _missing,
    },
    UserDetails() => switch (name) {
      'username' => target.username,
      'authorities' => target.authorities,
      'enabled' || 'isEnabled' => target.isEnabled,
      'accountNonExpired' => target.isAccountNonExpired,
      'accountNonLocked' => target.isAccountNonLocked,
      'credentialsNonExpired' => target.isCredentialsNonExpired,
      _ => _missing,
    },
    GrantedAuthority() => name == 'authority' ? target.authority : _missing,
    _ => _missing,
  };

  @override
  bool canRead(EvaluationContext context, Object target, String name) =>
      !identical(_read(target, name), _missing);

  @override
  Object? read(EvaluationContext context, Object target, String name) =>
      _read(target, name);

  @override
  bool canWrite(EvaluationContext context, Object target, String name) => false;

  @override
  void write(
    EvaluationContext context,
    Object target,
    String name,
    Object? newValue,
  ) => throw UnsupportedError('Security expressions cannot assign $name');
}
