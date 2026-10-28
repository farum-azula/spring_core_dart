import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_security_core/src/authorization/authorization_manager.dart';
import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/authority.dart';
import 'package:spring_security_core/src/core/exceptions.dart';
import 'package:spring_security_core/src/userdetails/user_details.dart';

/// The application's answer to `hasPermission(...)` in security
/// expressions: may this user do this to that object?
///
/// Roles say what a user may do in general; permissions are about one
/// object ("may Ada cancel order 42?"). Write the rule once in a bean of
/// this type and call it from any `@PreAuthorize` or `@PostAuthorize`.
/// Without such a bean every `hasPermission` is `false`
/// ([DenyAllPermissionEvaluator]).
///
/// ```dart
/// // @PreAuthorize("hasPermission(#order, 'cancel')")
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
///
/// Spring (Java): `PermissionEvaluator`, the same two methods.
abstract interface class PermissionEvaluator {
  /// Answers `hasPermission(#order, 'cancel')`: whether [authentication]
  /// may apply [permission] to [targetDomainObject], an object the method
  /// received or returned.
  bool hasPermission(
    Authentication authentication,
    Object? targetDomainObject,
    Object permission,
  );

  /// Answers `hasPermission(#id, 'Order', 'cancel')`: the same question
  /// when only the object's id ([targetId]) and type name ([targetType])
  /// are known, so the evaluator loads what it needs.
  bool hasPermissionById(
    Authentication authentication,
    Object? targetId,
    String targetType,
    Object permission,
  );
}

/// The [PermissionEvaluator] used until the application declares one: it
/// answers `false` to every `hasPermission`, so a forgotten evaluator
/// denies rather than allows.
///
/// Spring (Java): `DenyAllPermissionEvaluator`.
final class DenyAllPermissionEvaluator implements PermissionEvaluator {
  /// The stateless evaluator.
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

/// A hook that adjusts every evaluation context of security expressions,
/// to make more things readable in `@PreAuthorize` and its siblings.
///
/// Expressions can read the built-in security types and the classes of
/// the bean's package. Declare a bean of this type to add property
/// accessors for other classes (such as your principal type from another
/// package), variables or functions. Every bean of this type is applied,
/// to each call's context.
///
/// ```dart
/// // Lets expressions read `principal.tenant` on the Account principal.
/// // @PreAuthorize('#doc.tenant == principal.tenant')
/// @Component()
/// class AccountExpressions implements SecurityExpressionContextCustomizer {
///   @override
///   void customize(StandardEvaluationContext context) =>
///       context.addPropertyAccessor(FunctionPropertyAccessor<Account>(
///           getters: {'tenant': (a) => a.tenant}));
/// }
/// ```
///
/// Spring has no such interface: there you customize the
/// `MethodSecurityExpressionHandler` bean.
abstract interface class SecurityExpressionContextCustomizer {
  /// Adds accessors, variables or functions to [context], which is built
  /// for one call and already holds the arguments.
  void customize(StandardEvaluationContext context);
}

/// What a security expression reads its names from: `hasRole(...)`,
/// `principal`, `returnObject` and the rest are members of this object.
///
/// Method security creates one per call; applications do not. Its
/// methods describe what each function in an expression does.
///
/// Spring (Java): `MethodSecurityExpressionRoot`.
final class MethodSecurityExpressionRoot {
  /// A root for the user [authentication] returns, called only when an
  /// expression first needs the user.
  MethodSecurityExpressionRoot(
    this._authentication, {
    this.trustResolver = const AuthenticationTrustResolverImpl(),
    this.roleHierarchy = const NullRoleHierarchy(),
    this.permissionEvaluator = const DenyAllPermissionEvaluator(),
    this.defaultRolePrefix = 'ROLE_',
    this.target,
  });

  final Authentication? Function() _authentication;

  /// Tells anonymous users from real logins for `isAuthenticated()` and
  /// `isAnonymous()`.
  final AuthenticationTrustResolver trustResolver;

  /// Adds the authorities implied by the user's roles before
  /// `hasRole` and `hasAuthority` checks.
  final RoleHierarchy roleHierarchy;

  /// Answers `hasPermission(...)`.
  final PermissionEvaluator permissionEvaluator;

  /// The prefix `hasRole` adds to a role that does not start with it;
  /// `ROLE_` by default.
  final String defaultRolePrefix;

  /// The bean whose method is called; `this` in an expression.
  final Object? target;

  /// What the method returned, for `@PostAuthorize` (`returnObject`);
  /// `null` before the method has run.
  Object? returnObject;

  /// The element being tested by `@PreFilter` or `@PostFilter`
  /// (`filterObject`).
  Object? filterObject;

  Set<String>? _authorities;

  /// The current user (`authentication`); `null` when there is none.
  Authentication? get authentication => _authentication();

  /// The principal of [authentication] (`principal`), usually a
  /// `UserDetails`.
  Object? get principal => authentication?.principal;

  Set<String> get _held => _authorities ??= AuthorityUtils.authorityListToSet(
    roleHierarchy.getReachableGrantedAuthorities(
      authentication?.authorities ?? const [],
    ),
  );

  /// Whether the user has [authority], written in full
  /// (`SCOPE_read`), after the role hierarchy expanded the user's
  /// authorities.
  bool hasAuthority(String authority) => _held.contains(authority);

  /// Whether the user has one of [authorities], written in full.
  bool hasAnyAuthority(List<String> authorities) =>
      authorities.any(_held.contains);

  /// Whether the user has [role]: `hasRole('ADMIN')` looks for
  /// `ROLE_ADMIN`; a role that already starts with the prefix is used as
  /// written.
  bool hasRole(String role) => hasAnyRole([role]);

  /// Whether the user has one of [roles], each with the prefix added
  /// when missing.
  bool hasAnyRole(List<String> roles) => roles.any(
    (role) => _held.contains(
      defaultRolePrefix.isEmpty || role.startsWith(defaultRolePrefix)
          ? role
          : '$defaultRolePrefix$role',
    ),
  );

  /// Whether the user really logged in (not anonymous).
  bool isAuthenticated() => trustResolver.isAuthenticated(authentication);

  /// Whether the user logged in during this session (not "remember me");
  /// here the same as [isAuthenticated].
  bool isFullyAuthenticated() =>
      trustResolver.isFullyAuthenticated(authentication);

  /// Whether the user is anonymous (has not logged in).
  bool isAnonymous() => trustResolver.isAnonymous(authentication);

  /// Whether the user came back through a "remember me" cookie; always
  /// `false` with the default resolver.
  bool isRememberMe() => trustResolver.isRememberMe(authentication);

  /// `hasPermission(target, permission)` or
  /// `hasPermission(id, type, permission)`, answered by the
  /// [permissionEvaluator]; `false` without a user.
  ///
  /// Throws an [ArgumentError] for any other list of [arguments].
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

/// The engine behind method security: it parses the expressions of the
/// security annotations and evaluates them for each call.
///
/// The auto-configuration builds it from the optional `RoleHierarchy`,
/// `PermissionEvaluator`, `GrantedAuthorityDefaults` and
/// [SecurityExpressionContextCustomizer] beans, so applications change
/// its behaviour by declaring those. Declare your own bean of this type
/// only to replace all of it.
///
/// Spring (Java): `DefaultMethodSecurityExpressionHandler`.
final class MethodSecurityExpressionHandler {
  /// A handler. [introspector] makes the application's classes (the
  /// arguments) readable in expressions, and [beanFactory] resolves
  /// `@bean` references; without them, those parts of an expression fail.
  MethodSecurityExpressionHandler({
    this.introspector,
    this.beanFactory,
    this.trustResolver = const AuthenticationTrustResolverImpl(),
    this.roleHierarchy = const NullRoleHierarchy(),
    this.permissionEvaluator = const DenyAllPermissionEvaluator(),
    this.defaultRolePrefix = 'ROLE_',
    List<SecurityExpressionContextCustomizer> customizers = const [],
  }) : customizers = List.unmodifiable(customizers);

  /// Makes the application's classes readable in expressions; `null`
  /// leaves only the security types readable.
  final BeanIntrospector? introspector;

  /// Resolves `@bean` references in expressions; `null` makes them
  /// fail.
  final BeanFactory? beanFactory;

  /// Tells anonymous users from real logins.
  final AuthenticationTrustResolver trustResolver;

  /// Adds the authorities implied by the user's roles.
  final RoleHierarchy roleHierarchy;

  /// Answers `hasPermission(...)`.
  final PermissionEvaluator permissionEvaluator;

  /// The prefix `hasRole` adds; `ROLE_` by default.
  final String defaultRolePrefix;

  /// Run on every evaluation context, in order.
  final List<SecurityExpressionContextCustomizer> customizers;

  final _parser = SpelExpressionParser();
  final _expressions = <String, Expression>{};

  /// The parsed expression [text], cached after the first call.
  ///
  /// Throws when [text] is not valid SpEL; startup calls it for every
  /// annotation so a broken expression stops the application.
  Expression parse(String text) =>
      _expressions[text] ??= _parser.parseExpression(text);

  /// A new root object for one call on [target]; [authentication] is
  /// called only when an expression needs the user.
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

  /// A new evaluation context for [root] in which the arguments [args] of
  /// [signature] are variables: by name (`#order`) and by position (`#p0`,
  /// `#a0`). The customizers have run on it.
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

  /// Evaluates the expression [text] in [context] and returns its `bool`.
  ///
  /// A broken expression must never let a call through: any error while
  /// evaluating, or a result that is not a `bool`, throws an
  /// [ArgumentError] naming the expression. An [AuthenticationException]
  /// (no user at all) is thrown as it is.
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
