import 'dart:async';

import 'package:spring_security_core/src/core/authentication.dart';
import 'package:spring_security_core/src/core/authority.dart';
import 'package:spring_security_core/src/core/exceptions.dart';

/// The outcome of an authorization check, like Spring's
/// `AuthorizationResult`.
abstract interface class AuthorizationResult {
  /// Whether access is granted.
  bool get isGranted;
}

/// A plain yes or no, like Spring's `AuthorizationDecision`.
class AuthorizationDecision implements AuthorizationResult {
  /// A decision.
  const AuthorizationDecision(this.isGranted);

  /// Granted.
  static const granted = AuthorizationDecision(true);

  /// Denied.
  static const denied = AuthorizationDecision(false);

  @override
  final bool isGranted;

  @override
  // The text names the actual class, subclasses included, like Java's
  // getClass().getName().
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType [granted=$isGranted]';
}

/// A decision about authorities, saying which were asked for, like
/// Spring's `AuthorityAuthorizationDecision`.
class AuthorityAuthorizationDecision extends AuthorizationDecision {
  /// A decision for [authorities].
  const AuthorityAuthorizationDecision(super.isGranted, this.authorities);

  /// The authorities that would grant access.
  final List<String> authorities;

  @override
  String toString() =>
      // The text names the actual class, subclasses included, like Java's
      // getClass().getName().
      // ignore: no_runtimetype_tostring
      '$runtimeType [granted=$isGranted, authorities=$authorities]';
}

/// Access was denied by an [AuthorizationManager], like Spring's
/// `AuthorizationDeniedException`; a 403 (or a login challenge for an
/// anonymous request).
class AuthorizationDeniedException extends AccessDeniedException {
  /// Denied with [result].
  AuthorizationDeniedException(super.message, this.result);

  /// The result that denied.
  final AuthorizationResult result;
}

/// Decides whether the current user may access an object of type [T] (a
/// request, a method call), like Spring's `AuthorizationManager`.
///
/// ```dart
/// final class OwnerAuthorizationManager
///     implements AuthorizationManager<MethodInvocation> {
///   @override
///   AuthorizationResult? authorize(authentication, invocation) =>
///       AuthorizationDecision(
///           (invocation.arguments.first as Order).owner ==
///               authentication()?.name);
/// }
/// ```
abstract interface class AuthorizationManager<T> {
  /// The decision for [object]; `null` abstains. [authentication] reads the
  /// current authentication (`null` when there is none) only if needed.
  FutureOr<AuthorizationResult?> authorize(
    Authentication? Function() authentication,
    T object,
  );
}

/// Calls [manager] and throws [AuthorizationDeniedException] unless it
/// granted (an abstention denies: fail closed), like Spring's
/// `AuthorizationManager.verify`.
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

/// Tells anonymous and full logins apart, like Spring's
/// `AuthenticationTrustResolver`.
abstract interface class AuthenticationTrustResolver {
  /// Whether [authentication] is anonymous.
  bool isAnonymous(Authentication? authentication);

  /// Whether [authentication] comes from a remember-me cookie.
  bool isRememberMe(Authentication? authentication);

  /// Whether [authentication] is authenticated and not anonymous.
  bool isAuthenticated(Authentication? authentication);

  /// Whether [authentication] is authenticated, not anonymous and not
  /// remembered.
  bool isFullyAuthenticated(Authentication? authentication);
}

/// The default [AuthenticationTrustResolver], like Spring's
/// `AuthenticationTrustResolverImpl`.
final class AuthenticationTrustResolverImpl
    implements AuthenticationTrustResolver {
  /// The resolver.
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

/// Which roles imply which, like Spring's `RoleHierarchy`.
abstract interface class RoleHierarchy {
  /// [authorities] with those they imply added.
  List<GrantedAuthority> getReachableGrantedAuthorities(
    Iterable<GrantedAuthority> authorities,
  );
}

/// No hierarchy: each role is only itself, like Spring's
/// `NullRoleHierarchy`.
final class NullRoleHierarchy implements RoleHierarchy {
  /// The empty hierarchy.
  const NullRoleHierarchy();

  @override
  List<GrantedAuthority> getReachableGrantedAuthorities(
    Iterable<GrantedAuthority> authorities,
  ) => List.of(authorities);
}

/// A hierarchy from lines like `ROLE_ADMIN > ROLE_STAFF`, like Spring's
/// `RoleHierarchyImpl`: an admin also has the staff's authorities (and
/// those staff imply, transitively).
///
/// ```dart
/// final hierarchy = RoleHierarchyImpl.fromHierarchy('''
///   ROLE_ADMIN > ROLE_STAFF
///   ROLE_STAFF > ROLE_USER
/// ''');
/// ```
final class RoleHierarchyImpl implements RoleHierarchy {
  RoleHierarchyImpl._(this._reachable);

  /// Parses [hierarchy]: one `A > B` (or `A > B > C`) per line.
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

/// Grants when the authentication has one of [authorities], like Spring's
/// `AuthorityAuthorizationManager`; never for a missing or unauthenticated
/// one.
final class AuthorityAuthorizationManager<T>
    implements AuthorizationManager<T> {
  AuthorityAuthorizationManager._(
    this.authorities, {
    this.roleHierarchy = const NullRoleHierarchy(),
  });

  /// Grants with the role [role] (`hasRole('ADMIN')` → `ROLE_ADMIN`).
  factory AuthorityAuthorizationManager.hasRole(
    String role, {
    String rolePrefix = 'ROLE_',
    RoleHierarchy roleHierarchy = const NullRoleHierarchy(),
  }) => AuthorityAuthorizationManager.hasAnyRole(
    [role],
    rolePrefix: rolePrefix,
    roleHierarchy: roleHierarchy,
  );

  /// Grants with any of [roles].
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

  /// Grants with the authority [authority].
  factory AuthorityAuthorizationManager.hasAuthority(
    String authority, {
    RoleHierarchy roleHierarchy = const NullRoleHierarchy(),
  }) => AuthorityAuthorizationManager._([
    authority,
  ], roleHierarchy: roleHierarchy);

  /// Grants with any of [authorities].
  factory AuthorityAuthorizationManager.hasAnyAuthority(
    List<String> authorities, {
    RoleHierarchy roleHierarchy = const NullRoleHierarchy(),
  }) => AuthorityAuthorizationManager._(
    List.unmodifiable(authorities),
    roleHierarchy: roleHierarchy,
  );

  /// The authorities that grant.
  final List<String> authorities;

  /// Expands the user's roles.
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

/// Grants by how the request is authenticated, like Spring's
/// `AuthenticatedAuthorizationManager`.
final class AuthenticatedAuthorizationManager<T>
    implements AuthorizationManager<T> {
  const AuthenticatedAuthorizationManager._(this._kind, this._resolver);

  /// Any authenticated, non-anonymous request.
  const AuthenticatedAuthorizationManager.authenticated({
    AuthenticationTrustResolver resolver =
        const AuthenticationTrustResolverImpl(),
  }) : this._(_Kind.authenticated, resolver);

  /// A full login (not remembered).
  const AuthenticatedAuthorizationManager.fullyAuthenticated({
    AuthenticationTrustResolver resolver =
        const AuthenticationTrustResolverImpl(),
  }) : this._(_Kind.fully, resolver);

  /// Only anonymous requests.
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

/// The same answer for everything: `permitAll()` / `denyAll()`, like
/// Spring's `SingleResultAuthorizationManager`.
final class SingleResultAuthorizationManager<T>
    implements AuthorizationManager<T> {
  /// Always [result].
  const SingleResultAuthorizationManager(this.result);

  /// Always granted.
  const SingleResultAuthorizationManager.permitAll()
    : result = AuthorizationDecision.granted;

  /// Always denied.
  const SingleResultAuthorizationManager.denyAll()
    : result = AuthorizationDecision.denied;

  /// The answer.
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

/// Combinations of managers, like Spring's `AuthorizationManagers`.
abstract final class AuthorizationManagers {
  /// Granted when any of [managers] grants; denied when one denies and
  /// none grants; abstains (so the caller denies) when all abstain.
  static AuthorizationManager<T> anyOf<T>(
    List<AuthorizationManager<T>> managers,
  ) => _Combined(managers, any: true);

  /// Granted when all of [managers] grant (abstentions ignored, at least
  /// one must grant).
  static AuthorizationManager<T> allOf<T>(
    List<AuthorizationManager<T>> managers,
  ) => _Combined(managers, any: false);

  /// The opposite of [manager] (an abstention stays one).
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
