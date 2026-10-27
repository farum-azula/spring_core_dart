import 'package:spring_boot_dart/spring_boot_dart.dart' show Principal;
import 'package:spring_security_core/src/core/authority.dart';
import 'package:spring_security_core/src/userdetails/user_details.dart';

/// Who made a request (or is logged in) and what they may do, like
/// Spring's `Authentication`: before authentication a request for it
/// (the username and the password typed), after it the authenticated
/// user with their [authorities].
///
/// It is a [Principal], so a controller taking `Principal` gets it.
///
/// ```dart
/// final authentication = SecurityContextHolder.getContext().authentication;
/// if (authentication != null && authentication.isAuthenticated) {
///   print('${authentication.name}: ${authentication.authorities}');
/// }
/// ```
abstract interface class Authentication implements Principal {
  /// What the principal may do (`ROLE_ADMIN`, `SCOPE_read`, ...).
  List<GrantedAuthority> get authorities;

  /// What proves the identity (a password), usually erased once
  /// authenticated.
  Object? get credentials;

  /// More about the request (the client's address, a session id).
  Object? get details;

  /// The identity: a username before authentication, a [UserDetails] (or
  /// a token's claims) after it.
  Object? get principal;

  /// Whether this is trusted as authenticated.
  bool get isAuthenticated;

  /// Marks it as not authenticated; tokens refuse `true` (create an
  /// authenticated token instead), like Spring's `setAuthenticated`.
  set isAuthenticated(bool value);
}

/// An object holding a secret it can forget, like Spring's
/// `CredentialsContainer`: `ProviderManager` erases the password of an
/// authenticated user so it does not stay in memory.
abstract interface class CredentialsContainer {
  /// Forgets the secret.
  void eraseCredentials();
}

/// The common part of the tokens, like Spring's
/// `AbstractAuthenticationToken`: authorities, details, the authenticated
/// flag and the [name] taken from the principal.
abstract class AbstractAuthenticationToken
    implements Authentication, CredentialsContainer {
  /// A token with [authorities] (copied, unmodifiable).
  AbstractAuthenticationToken([
    Iterable<GrantedAuthority> authorities = const [],
  ]) : authorities = List.unmodifiable(authorities);

  @override
  final List<GrantedAuthority> authorities;

  @override
  Object? details;

  bool _authenticated = false;

  @override
  bool get isAuthenticated => _authenticated;

  @override
  set isAuthenticated(bool value) => _authenticated = value;

  /// The username of a [UserDetails] principal, the name of a [Principal],
  /// otherwise the principal as text (`''` without one).
  @override
  String get name => switch (principal) {
    final UserDetails user => user.username,
    final Authentication authentication => authentication.name,
    final Principal principal => principal.name,
    null => '',
    final other => '$other',
  };

  @override
  void eraseCredentials() {
    for (final part in [credentials, principal, details]) {
      if (part is CredentialsContainer) {
        part.eraseCredentials();
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AbstractAuthenticationToken &&
      other.runtimeType == runtimeType &&
      other.principal == principal &&
      other.credentials == credentials &&
      other.details == details &&
      other.isAuthenticated == isAuthenticated &&
      _sameAuthorities(other.authorities, authorities);

  @override
  int get hashCode => Object.hash(
    runtimeType,
    principal,
    credentials,
    details,
    isAuthenticated,
    Object.hashAll(authorities),
  );

  /// Never the credentials: a token may end up in a log.
  @override
  String toString() =>
      '$runtimeType [Principal=$name, Credentials=[PROTECTED], '
      'Authenticated=$isAuthenticated, Details=$details, '
      'Granted Authorities=$authorities]';

  static bool _sameAuthorities(
    List<GrantedAuthority> a,
    List<GrantedAuthority> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// A username and a password, like Spring's
/// `UsernamePasswordAuthenticationToken`:
/// [UsernamePasswordAuthenticationToken.unauthenticated] is the login
/// request, [UsernamePasswordAuthenticationToken.authenticated] what a
/// provider returns for it.
///
/// ```dart
/// final result = await authenticationManager.authenticate(
///   UsernamePasswordAuthenticationToken.unauthenticated('ada', 'secret'),
/// );
/// ```
class UsernamePasswordAuthenticationToken extends AbstractAuthenticationToken {
  /// A login request: not authenticated, no authorities.
  UsernamePasswordAuthenticationToken.unauthenticated(
    this.principal,
    this._credentials,
  ) : super();

  /// An authenticated user with [authorities].
  UsernamePasswordAuthenticationToken.authenticated(
    this.principal,
    this._credentials,
    Iterable<GrantedAuthority> authorities,
  ) : super(authorities) {
    super.isAuthenticated = true;
  }

  @override
  final Object? principal;

  Object? _credentials;

  @override
  Object? get credentials => _credentials;

  /// Only `false`: an authenticated token comes from
  /// [UsernamePasswordAuthenticationToken.authenticated].
  @override
  set isAuthenticated(bool value) {
    if (value) {
      throw ArgumentError(
        'Cannot set this token to trusted - use '
        'UsernamePasswordAuthenticationToken.authenticated instead',
      );
    }
    super.isAuthenticated = false;
  }

  @override
  void eraseCredentials() {
    super.eraseCredentials();
    _credentials = null;
  }
}

/// A request without credentials, like Spring's
/// `AnonymousAuthenticationToken`: lets rules tell "not logged in"
/// (`isAnonymous()`) from "no security context". It counts as
/// authenticated, but `isAuthenticated()` in expressions is `false` for it.
class AnonymousAuthenticationToken extends AbstractAuthenticationToken {
  /// An anonymous principal (usually `'anonymousUser'`) with [authorities]
  /// (usually `ROLE_ANONYMOUS`); [key] identifies who created it.
  AnonymousAuthenticationToken(
    String key,
    this.principal,
    Iterable<GrantedAuthority> authorities,
  ) : keyHash = key.hashCode,
      super(authorities) {
    if (key.isEmpty) {
      throw ArgumentError('An anonymous token needs a non-empty key');
    }
    if (authorities.isEmpty) {
      throw ArgumentError('An anonymous token needs authorities');
    }
    super.isAuthenticated = true;
  }

  /// The hash of the key it was created with.
  final int keyHash;

  @override
  final Object principal;

  @override
  Object? get credentials => '';
}

/// A token for tests, like Spring's `TestingAuthenticationToken`:
/// authenticated, with the roles or authorities given.
///
/// ```dart
/// SecurityContextHolder.getContext().authentication =
///     TestingAuthenticationToken('ada', 'secret', ['ROLE_ADMIN']);
/// ```
class TestingAuthenticationToken extends AbstractAuthenticationToken {
  /// [principal] with [authorities] (authority names), authenticated.
  TestingAuthenticationToken(
    this.principal,
    this.credentials, [
    List<String> authorities = const [],
  ]) : super(AuthorityUtils.createAuthorityList(authorities)) {
    super.isAuthenticated = true;
  }

  @override
  final Object? principal;

  @override
  final Object? credentials;
}
