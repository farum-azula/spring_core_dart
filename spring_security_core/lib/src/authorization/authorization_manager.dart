import 'dart:async';

import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/authority.dart';
import 'package:spring_security_core/src/core/exceptions.dart';

/// The answer of an access check: granted or not.
///
/// An [AuthorizationManager] returns one. Implement it only to carry more
/// facts about a decision; otherwise return an [AuthorizationDecision].
///
/// Spring (Java): `AuthorizationResult`.
abstract interface class AuthorizationResult {
  /// `true` lets the request or call through; `false` denies it.
  bool get isGranted;
}

/// The usual [AuthorizationResult]: a plain yes or no.
///
/// ```dart
/// return AuthorizationDecision(order.owner == user.name);
/// ```
///
/// Spring (Java): `AuthorizationDecision`.
class AuthorizationDecision implements AuthorizationResult {
  /// Grants when [isGranted] is `true`, denies otherwise.
  const AuthorizationDecision(this.isGranted);

  /// The shared "granted" decision.
  static const granted = AuthorizationDecision(true);

  /// The shared "denied" decision.
  static const denied = AuthorizationDecision(false);

  @override
  final bool isGranted;

  @override
  // The text names the actual class, subclasses included, like Java's
  // getClass().getName().
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType [granted=$isGranted]';
}

/// An [AuthorizationDecision] of a role or authority check that also says
/// which authorities would have granted access, for logs and error pages.
///
/// [AuthorityAuthorizationManager] returns it.
///
/// Spring (Java): `AuthorityAuthorizationDecision`.
class AuthorityAuthorizationDecision extends AuthorizationDecision {
  /// A decision, granted or not, of a check for [authorities].
  const AuthorityAuthorizationDecision(super.isGranted, this.authorities);

  /// The authority names the check looked for, such as `ROLE_ADMIN`; any
  /// one of them grants access.
  final List<String> authorities;

  @override
  String toString() =>
      // The text names the actual class, subclasses included, like Java's
      // getClass().getName().
      // ignore: no_runtimetype_tostring
      '$runtimeType [granted=$isGranted, authorities=$authorities]';
}

/// The [AccessDeniedException] thrown when an access check says no; it
/// carries the [result] that denied.
///
/// Method security and the web starter's request rules throw it. A web
/// request that fails with it is answered 403, or asked to log in (401 or
/// a redirect) when the user is anonymous. Catch [AccessDeniedException]
/// rather than this class unless you need the [result].
///
/// Spring (Java): `AuthorizationDeniedException`.
class AuthorizationDeniedException extends AccessDeniedException {
  /// A denial with a log [message] and the [result] that denied.
  AuthorizationDeniedException(super.message, this.result);

  /// The decision that denied; [AuthorizationDecision.denied] when the
  /// check abstained.
  final AuthorizationResult result;
}

/// An access check: given the current user and the thing being accessed,
/// of type [T], it decides whether access is granted.
///
/// Every rule of the web starter is one: `hasRole('ADMIN')`,
/// `authenticated()` and `permitAll()` in `authorizeHttpRequests` build
/// the managers of this file, with `RequestAuthorizationContext` as [T].
/// Write your own when a rule cannot be said with roles, for example "only
/// the user named in the path", and pass it to `access(...)`.
///
/// ```dart
/// // Only the user named in the path may use /users/{name}/**.
/// final class SameUser
///     implements AuthorizationManager<RequestAuthorizationContext> {
///   const SameUser();
///
///   @override
///   AuthorizationResult authorize(
///     Authentication? Function() authentication,
///     RequestAuthorizationContext context,
///   ) {
///     final user = authentication();
///     // Anonymous users have a name too ('anonymousUser'): check first.
///     return AuthorizationDecision(
///       const AuthenticationTrustResolverImpl().isAuthenticated(user) &&
///           user!.name == context.variables['name'],
///     );
///   }
/// }
///
/// // In the SecurityFilterChain bean:
/// http.authorizeHttpRequests((auth) => auth
///     .requestMatchers('/users/{name}/**').access(const SameUser())
///     .anyRequest().authenticated());
/// ```
///
/// Spring (Java):
/// ```java
/// http.authorizeHttpRequests(auth -> auth
///     .requestMatchers("/users/{name}/**").access((authentication, context) ->
///         new AuthorizationDecision(
///             authentication.get().getName()
///                 .equals(context.getVariables().get("name"))))
///     .anyRequest().authenticated());
/// ```
abstract interface class AuthorizationManager<T> {
  /// Decides whether the current user may access [object].
  ///
  /// [authentication] returns the current user. Call it only when the
  /// decision needs the user, so rules like `permitAll()` cost nothing.
  /// When there is no authentication at all, the web starter's filter and
  /// method security make it throw an
  /// `AuthenticationCredentialsNotFoundException`, which asks the client to
  /// log in.
  ///
  /// Return `null` to abstain. The caller treats an abstention like a
  /// denial (fail closed), except inside [AuthorizationManagers]
  /// combinations.
  FutureOr<AuthorizationResult?> authorize(
    Authentication? Function() authentication,
    T object,
  );
}

/// Asks [manager] about [object] and throws an
/// [AuthorizationDeniedException] unless it granted access.
///
/// An abstention (`null`) denies too: when nothing says yes, the answer is
/// no. Use it to enforce a manager in your own code.
///
/// Spring (Java): `AuthorizationManager.verify`.
Future<void> verifyAuthorization<T>(
  AuthorizationManager<T> manager,
  Authentication? Function() authentication,
  T object,
) async {
  final result = await manager.authorize(authentication, object);
  if (result == null || !result.isGranted) {
    throw AuthorizationDeniedException(
      'Access Denied',
      result ?? AuthorizationDecision.denied,
    );
  }
}

/// Tells what kind of login an [Authentication] is: anonymous,
/// "remember me", or a real one.
///
/// An anonymous user has an [Authentication] whose `isAuthenticated` flag
/// is `true`, so that flag alone cannot tell a logged-in user. Rules such
/// as `authenticated()` and `isAnonymous()` ask this resolver. Use
/// [AuthenticationTrustResolverImpl] in your own checks.
///
/// Spring (Java): `AuthenticationTrustResolver`.
abstract interface class AuthenticationTrustResolver {
  /// Whether [authentication] is an anonymous user, one who has not
  /// logged in.
  bool isAnonymous(Authentication? authentication);

  /// Whether [authentication] comes from a "remember me" cookie rather
  /// than a login in this session.
  bool isRememberMe(Authentication? authentication);

  /// Whether [authentication] is a real login: present, authenticated and
  /// not anonymous.
  bool isAuthenticated(Authentication? authentication);

  /// Whether [authentication] is a real login made in this session, not
  /// restored from a "remember me" cookie.
  bool isFullyAuthenticated(Authentication? authentication);
}

/// The standard [AuthenticationTrustResolver]: an
/// [AnonymousAuthenticationToken] is anonymous, everything else that is
/// authenticated is a real login.
///
/// There is no "remember me" login in these packages, so [isRememberMe]
/// is always `false` and [isFullyAuthenticated] equals [isAuthenticated].
///
/// Spring (Java): `AuthenticationTrustResolverImpl`.
final class AuthenticationTrustResolverImpl
    implements AuthenticationTrustResolver {
  /// The stateless resolver.
  const AuthenticationTrustResolverImpl();

  @override
  bool isAnonymous(Authentication? authentication) =>
      authentication is AnonymousAuthenticationToken;

  @override
  bool isRememberMe(Authentication? authentication) => false;

  @override
  bool isAuthenticated(Authentication? authentication) =>
      authentication != null &&
      authentication.isAuthenticated &&
      !isAnonymous(authentication);

  @override
  bool isFullyAuthenticated(Authentication? authentication) =>
      isAuthenticated(authentication) && !isRememberMe(authentication);
}

/// The rule that a role includes others, such as "an admin can do all a
/// staff member can".
///
/// Without one, a check for `ROLE_STAFF` fails for a user who only has
/// `ROLE_ADMIN`, so every rule would have to list both. Declare a
/// [RoleHierarchyImpl] bean and the role and authority checks (web rules,
/// `hasRole` in expressions, `@Secured`) use the expanded authorities.
///
/// Spring (Java): `RoleHierarchy`.
abstract interface class RoleHierarchy {
  /// [authorities] plus every authority they imply, directly or through
  /// other roles.
  List<GrantedAuthority> getReachableGrantedAuthorities(
    Iterable<GrantedAuthority> authorities,
  );
}

/// The [RoleHierarchy] used when the application declares none: every
/// role is only itself.
///
/// Spring (Java): `NullRoleHierarchy`.
final class NullRoleHierarchy implements RoleHierarchy {
  /// The hierarchy that adds nothing.
  const NullRoleHierarchy();

  @override
  List<GrantedAuthority> getReachableGrantedAuthorities(
    Iterable<GrantedAuthority> authorities,
  ) => List.of(authorities);
}

/// A [RoleHierarchy] written as text, one rule per line:
/// `ROLE_ADMIN > ROLE_STAFF` means an admin also has every authority of
/// staff.
///
/// The rules chain: with `ROLE_ADMIN > ROLE_STAFF` and
/// `ROLE_STAFF > ROLE_USER`, an admin is also a user. Declare it as a bean
/// to make it apply everywhere.
///
/// ```dart
/// @Bean()
/// RoleHierarchy roleHierarchy() => RoleHierarchyImpl.fromHierarchy('''
///   ROLE_ADMIN > ROLE_STAFF
///   ROLE_STAFF > ROLE_USER
/// ''');
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// static RoleHierarchy roleHierarchy() {
///   return RoleHierarchyImpl.fromHierarchy("""
///       ROLE_ADMIN > ROLE_STAFF
///       ROLE_STAFF > ROLE_USER
///       """);
/// }
/// ```
final class RoleHierarchyImpl implements RoleHierarchy {
  RoleHierarchyImpl._(this._reachable);

  /// Parses [hierarchy]: one `A > B` or `A > B > C` rule per line, with
  /// full authority names (`ROLE_ADMIN`, not `ADMIN`); blank lines are
  /// skipped.
  ///
  /// Throws an [ArgumentError] for a line that is not such a rule and for
  /// a cycle (`A > B` and `B > A`).
  factory RoleHierarchyImpl.fromHierarchy(String hierarchy) {
    final direct = <String, Set<String>>{};
    for (final raw in hierarchy.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      final roles = [for (final role in line.split('>')) role.trim()];
      if (roles.length < 2 || roles.any((role) => role.isEmpty)) {
        throw ArgumentError('Invalid role hierarchy line: $line');
      }
      for (var i = 0; i + 1 < roles.length; i++) {
        (direct[roles[i]] ??= {}).add(roles[i + 1]);
      }
    }
    final reachable = <String, Set<String>>{};
    for (final role in direct.keys) {
      final seen = <String>{};
      final pending = [...direct[role]!];
      while (pending.isNotEmpty) {
        final next = pending.removeLast();
        if (next == role) {
          throw ArgumentError('Cycle in the role hierarchy at $role');
        }
        if (seen.add(next)) {
          pending.addAll(direct[next] ?? const {});
        }
      }
      reachable[role] = seen;
    }
    return RoleHierarchyImpl._(reachable);
  }

  final Map<String, Set<String>> _reachable;

  @override
  List<GrantedAuthority> getReachableGrantedAuthorities(
    Iterable<GrantedAuthority> authorities,
  ) {
    final result = <String?, GrantedAuthority>{};
    for (final authority in authorities) {
      result[authority.authority] = authority;
      final name = authority.authority;
      if (name == null) {
        continue;
      }
      for (final implied in _reachable[name] ?? const <String>{}) {
        result.putIfAbsent(implied, () => SimpleGrantedAuthority(implied));
      }
    }
    return result.values.toList();
  }
}

/// An [AuthorizationManager] that grants access when the user has one of
/// the given [authorities], after the [roleHierarchy] expanded the user's
/// own.
///
/// It is behind `hasRole`, `hasAnyRole`, `hasAuthority` and
/// `hasAnyAuthority` of the web rules, and behind `@Secured`. It denies
/// when there is no authentication or its `isAuthenticated` flag is
/// `false`. An anonymous user has that flag set, so a rule for
/// `ROLE_ANONYMOUS` grants them.
///
/// ```dart
/// // A rule built by hand, for code that composes managers.
/// final admins = AuthorityAuthorizationManager<RequestAuthorizationContext>
///     .hasRole('ADMIN');
/// ```
///
/// Spring (Java): `AuthorityAuthorizationManager.hasRole("ADMIN")`.
final class AuthorityAuthorizationManager<T>
    implements AuthorizationManager<T> {
  AuthorityAuthorizationManager._(
    this.authorities, {
    this.roleHierarchy = const NullRoleHierarchy(),
  });

  /// Grants users with the role [role]: `hasRole('ADMIN')` looks for
  /// `ROLE_ADMIN`.
  ///
  /// Throws an [ArgumentError] when [role] already starts with
  /// [rolePrefix]; use [AuthorityAuthorizationManager.hasAuthority] for
  /// full names.
  factory AuthorityAuthorizationManager.hasRole(
    String role, {
    String rolePrefix = 'ROLE_',
    RoleHierarchy roleHierarchy = const NullRoleHierarchy(),
  }) => AuthorityAuthorizationManager.hasAnyRole(
    [role],
    rolePrefix: rolePrefix,
    roleHierarchy: roleHierarchy,
  );

  /// Grants users with any of [roles], each with [rolePrefix] added.
  ///
  /// Throws an [ArgumentError] when a role already starts with
  /// [rolePrefix].
  factory AuthorityAuthorizationManager.hasAnyRole(
    List<String> roles, {
    String rolePrefix = 'ROLE_',
    RoleHierarchy roleHierarchy = const NullRoleHierarchy(),
  }) {
    for (final role in roles) {
      if (rolePrefix.isNotEmpty && role.startsWith(rolePrefix)) {
        throw ArgumentError(
          '$role should not start with $rolePrefix since $rolePrefix is '
          'automatically prepended when using hasAnyRole. Consider using '
          'hasAnyAuthority instead.',
        );
      }
    }
    return AuthorityAuthorizationManager._([
      for (final role in roles) '$rolePrefix$role',
    ], roleHierarchy: roleHierarchy);
  }

  /// Grants users with [authority], used as written (no prefix added).
  factory AuthorityAuthorizationManager.hasAuthority(
    String authority, {
    RoleHierarchy roleHierarchy = const NullRoleHierarchy(),
  }) => AuthorityAuthorizationManager._([
    authority,
  ], roleHierarchy: roleHierarchy);

  /// Grants users with any of [authorities], used as written.
  factory AuthorityAuthorizationManager.hasAnyAuthority(
    List<String> authorities, {
    RoleHierarchy roleHierarchy = const NullRoleHierarchy(),
  }) => AuthorityAuthorizationManager._(
    List.unmodifiable(authorities),
    roleHierarchy: roleHierarchy,
  );

  /// The full authority names, any one of which grants access.
  final List<String> authorities;

  /// Adds the authorities implied by the user's roles before the check.
  final RoleHierarchy roleHierarchy;

  @override
  AuthorizationResult authorize(
    Authentication? Function() authentication,
    T object,
  ) {
    final current = authentication();
    final granted =
        current != null &&
        current.isAuthenticated &&
        _has(current, authorities);
    return AuthorityAuthorizationDecision(granted, authorities);
  }

  bool _has(Authentication authentication, List<String> wanted) {
    final held = AuthorityUtils.authorityListToSet(
      roleHierarchy.getReachableGrantedAuthorities(authentication.authorities),
    );
    return wanted.any(held.contains);
  }

  @override
  String toString() =>
      'AuthorityAuthorizationManager[authorities=$authorities]';
}

/// An [AuthorizationManager] that grants by the kind of login, not by
/// authorities: any real login, a full login, or only anonymous users.
///
/// It is behind the web rules `authenticated()`, `fullyAuthenticated()`
/// and `anonymous()`.
///
/// Spring (Java): `AuthenticatedAuthorizationManager`.
final class AuthenticatedAuthorizationManager<T>
    implements AuthorizationManager<T> {
  const AuthenticatedAuthorizationManager._(this._kind, this._resolver);

  /// Grants any real login; denies anonymous users and requests with no
  /// authentication.
  const AuthenticatedAuthorizationManager.authenticated({
    AuthenticationTrustResolver resolver =
        const AuthenticationTrustResolverImpl(),
  }) : this._(_Kind.authenticated, resolver);

  /// Grants a real login made in this session (not "remember me"); here
  /// the same as [AuthenticatedAuthorizationManager.authenticated].
  const AuthenticatedAuthorizationManager.fullyAuthenticated({
    AuthenticationTrustResolver resolver =
        const AuthenticationTrustResolverImpl(),
  }) : this._(_Kind.fully, resolver);

  /// Grants only anonymous users, for pages such as a login or sign-up
  /// form that logged-in users should not see.
  const AuthenticatedAuthorizationManager.anonymous({
    AuthenticationTrustResolver resolver =
        const AuthenticationTrustResolverImpl(),
  }) : this._(_Kind.anonymous, resolver);

  final _Kind _kind;
  final AuthenticationTrustResolver _resolver;

  @override
  AuthorizationResult authorize(
    Authentication? Function() authentication,
    T object,
  ) {
    final current = authentication();
    return AuthorizationDecision(switch (_kind) {
      _Kind.authenticated => _resolver.isAuthenticated(current),
      _Kind.fully => _resolver.isFullyAuthenticated(current),
      _Kind.anonymous => _resolver.isAnonymous(current),
    });
  }

  @override
  String toString() => 'AuthenticatedAuthorizationManager[${_kind.name}]';
}

enum _Kind { authenticated, fully, anonymous }

/// An [AuthorizationManager] that gives the same answer every time,
/// without looking at the user.
///
/// It is behind the web rules `permitAll()` and `denyAll()`.
///
/// Spring (Java): `SingleResultAuthorizationManager`.
final class SingleResultAuthorizationManager<T>
    implements AuthorizationManager<T> {
  /// A manager that always answers [result].
  const SingleResultAuthorizationManager(this.result);

  /// Grants everyone, logged in or not.
  const SingleResultAuthorizationManager.permitAll()
    : result = AuthorizationDecision.granted;

  /// Denies everyone, even logged-in users.
  const SingleResultAuthorizationManager.denyAll()
    : result = AuthorizationDecision.denied;

  /// The answer given every time.
  final AuthorizationResult result;

  @override
  AuthorizationResult authorize(
    Authentication? Function() authentication,
    T object,
  ) => result;

  @override
  String toString() =>
      'SingleResultAuthorizationManager[granted=${result.isGranted}]';
}

/// Builds one [AuthorizationManager] out of several: either, both, or the
/// opposite.
///
/// ```dart
/// // Admins, or the user named in the path.
/// final rule = AuthorizationManagers.anyOf<RequestAuthorizationContext>([
///   AuthorityAuthorizationManager.hasRole('ADMIN'),
///   const SameUser(),
/// ]);
/// ```
///
/// Spring (Java): `AuthorizationManagers`.
abstract final class AuthorizationManagers {
  /// A manager that asks [managers] in order and grants as soon as one
  /// grants.
  ///
  /// It denies when at least one denied and none granted, and abstains
  /// (so the caller denies) when all abstain.
  static AuthorizationManager<T> anyOf<T>(
    List<AuthorizationManager<T>> managers,
  ) => _Combined(managers, any: true);

  /// A manager that asks [managers] in order and denies as soon as one
  /// denies.
  ///
  /// Abstentions are skipped. It grants when at least one granted and none
  /// denied, and abstains (so the caller denies) when all abstain.
  static AuthorizationManager<T> allOf<T>(
    List<AuthorizationManager<T>> managers,
  ) => _Combined(managers, any: false);

  /// A manager answering the opposite of [manager]; an abstention stays an
  /// abstention, so the caller still denies.
  static AuthorizationManager<T> not<T>(AuthorizationManager<T> manager) =>
      _Not(manager);
}

final class _Combined<T> implements AuthorizationManager<T> {
  _Combined(List<AuthorizationManager<T>> managers, {required this.any})
    : managers = List.unmodifiable(managers);

  final List<AuthorizationManager<T>> managers;
  final bool any;

  @override
  Future<AuthorizationResult?> authorize(
    Authentication? Function() authentication,
    T object,
  ) async {
    var decided = false;
    for (final manager in managers) {
      final result = await manager.authorize(authentication, object);
      if (result == null) {
        continue;
      }
      decided = true;
      if (any && result.isGranted) {
        return AuthorizationDecision.granted;
      }
      if (!any && !result.isGranted) {
        return AuthorizationDecision.denied;
      }
    }
    if (!decided) {
      return null;
    }
    return any ? AuthorizationDecision.denied : AuthorizationDecision.granted;
  }
}

final class _Not<T> implements AuthorizationManager<T> {
  _Not(this.manager);

  final AuthorizationManager<T> manager;

  @override
  Future<AuthorizationResult?> authorize(
    Authentication? Function() authentication,
    T object,
  ) async {
    final result = await manager.authorize(authentication, object);
    return result == null ? null : AuthorizationDecision(!result.isGranted);
  }
}
