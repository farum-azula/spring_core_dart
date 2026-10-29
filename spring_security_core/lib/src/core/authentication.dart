import 'package:spring_boot_dart/spring_boot_dart.dart' show Principal;
import 'package:spring_security_core/src/core/authority.dart';
import 'package:spring_security_core/src/userdetails/user_details.dart';

/// Who is calling and what they may do: the user's identity, their
/// [authorities] and whether they are authenticated.
///
/// The same type has two lives. Before a login it is the login request: a
/// username and the password the user typed, not yet trusted. An
/// `AuthenticationManager` checks it and returns a new one for the
/// authenticated user, with the user's [authorities] and their password
/// erased. That second one is stored in the `SecurityContext`, where every
/// access check (`@PreAuthorize`, the web rules) reads it.
///
/// Application code usually only reads it: to know who is logged in, to
/// write an audit entry, or to filter data by owner. It is a [Principal],
/// so with `spring_boot_starter_security` a controller parameter of type
/// `Principal` (or `Authentication`) receives the current one.
///
/// ```dart
/// // Record who changed the price.
/// final authentication = SecurityContextHolder.getContext().authentication;
/// if (authentication != null && authentication.isAuthenticated) {
///   audit.record('price changed', by: authentication.name);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// Authentication authentication =
///     SecurityContextHolder.getContext().getAuthentication();
/// if (authentication != null && authentication.isAuthenticated()) {
///   audit.record("price changed", authentication.getName());
/// }
/// ```
abstract interface class Authentication implements Principal {
  /// The permissions of the user, such as `ROLE_ADMIN` or `SCOPE_read`.
  ///
  /// Empty for a login request that has not been checked yet.
  List<GrantedAuthority> get authorities;

  /// The secret that proves the identity, usually the typed password.
  ///
  /// `ProviderManager` erases it (sets it to `null`) once the login
  /// succeeded, so it does not stay in memory.
  Object? get credentials;

  /// Extra facts about the login, such as the client's address and
  /// session id; `null` when nobody set them.
  ///
  /// The web starter fills it for form, basic and bearer-token logins.
  Object? get details;

  /// The identity: the typed username in a login request; after the login,
  /// usually the [UserDetails] of the user (a `Jwt` for a bearer token).
  Object? get principal;

  /// Whether this object can be trusted as a checked identity.
  ///
  /// `false` for a login request, `true` for what an
  /// `AuthenticationManager` returned. Anonymous users are `true` too: use
  /// `AuthenticationTrustResolver.isAuthenticated` to tell a real login
  /// from an anonymous one.
  bool get isAuthenticated;

  /// Marks it as no longer trusted, for example when an application
  /// revokes a login.
  ///
  /// [UsernamePasswordAuthenticationToken] throws an [ArgumentError] for
  /// `true`: a trusted token must come from its `authenticated`
  /// constructor, so that only code that really checked the password
  /// creates one.
  set isAuthenticated(bool value);
}

/// An object that holds a secret, such as a password, and can forget it.
///
/// After a successful login `ProviderManager` calls [eraseCredentials] on
/// the result, so the typed password and the stored hash do not stay in
/// memory for the rest of the session. Implement it on your own
/// `Authentication` or `UserDetails` classes when they carry secrets.
///
/// Spring (Java): `CredentialsContainer`.
abstract interface class CredentialsContainer {
  /// Sets the secret to `null`; the object stays usable otherwise.
  void eraseCredentials();
}

/// A base class for [Authentication] implementations: it stores the
/// authorities, the details and the authenticated flag, and derives
/// [name] from the principal.
///
/// Extend it when a new login method needs its own token type, for example
/// an API key token; then you only add the principal and the credentials.
/// Its [toString] never shows the credentials, and [eraseCredentials]
/// passes the call on to a principal, credentials or details that hold
/// secrets of their own.
///
/// ```dart
/// // A token for requests signed with an API key.
/// class ApiKeyAuthenticationToken extends AbstractAuthenticationToken {
///   ApiKeyAuthenticationToken(this.principal, this.credentials,
///       [super.authorities]);
///
///   @override
///   final Object? principal;
///
///   @override
///   final Object? credentials;
/// }
/// ```
///
/// Spring (Java): `AbstractAuthenticationToken`.
abstract class AbstractAuthenticationToken
    implements Authentication, CredentialsContainer {
  /// A token, not yet authenticated, with a copy of [authorities] that
  /// cannot be modified.
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

  /// The user's name, taken from the principal: the username of a
  /// [UserDetails], the name of an [Authentication] or a [Principal],
  /// otherwise the principal's `toString()`; `''` when the principal is
  /// `null`.
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

  /// A description for logs: the name, the authorities and the flags, with
  /// the credentials replaced by `[PROTECTED]`.
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

/// A login with a username and a password, both before and after it is
/// checked.
///
/// Build one with [UsernamePasswordAuthenticationToken.unauthenticated]
/// from what the user typed and pass it to an `AuthenticationManager`. The
/// manager answers with one built by
/// [UsernamePasswordAuthenticationToken.authenticated], holding the
/// user's `UserDetails` and authorities, or throws an
/// `AuthenticationException`. The web starter does this for form and
/// basic logins; an application does it itself in a Flutter app or a JSON
/// login endpoint.
///
/// ```dart
/// // A Flutter login screen checks the typed password and keeps the user
/// // logged in for the whole app.
/// final result = await authenticationManager.authenticate(
///   UsernamePasswordAuthenticationToken.unauthenticated(name, password),
/// );
/// SecurityContextHolder.setContext(SecurityContextImpl(result));
/// ```
///
/// Spring (Java):
/// ```java
/// Authentication result = authenticationManager.authenticate(
///     UsernamePasswordAuthenticationToken.unauthenticated(name, password));
/// SecurityContextHolder.getContext().setAuthentication(result);
/// ```
class UsernamePasswordAuthenticationToken extends AbstractAuthenticationToken {
  /// A login request to check: [principal] is usually the typed username
  /// and the credentials the typed password. It is not authenticated and
  /// has no authorities.
  UsernamePasswordAuthenticationToken.unauthenticated(
    this.principal,
    this._credentials,
  ) : super();

  /// A checked login: [principal] is usually the user's `UserDetails`,
  /// with the user's [authorities].
  ///
  /// Only code that has verified the credentials should call it: every
  /// access check trusts the result.
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

  /// Accepts only `false`; `true` throws an [ArgumentError], because a
  /// trusted token must come from
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

/// The identity given to a caller who has not logged in.
///
/// With it, a rule can tell "not logged in" (`isAnonymous()`, the web
/// rule `anonymous()`) from "no security context at all", which fails
/// every check. The web starter gives one to every request that carries no
/// login, named `anonymousUser` with the authority `ROLE_ANONYMOUS`.
/// Applications rarely create one; tests do it through
/// `withAnonymousUser`.
///
/// Its [isAuthenticated] flag is `true`, so a check for an authority such
/// as `hasRole('ANONYMOUS')` can grant it. `isAuthenticated()` in an
/// expression and `AuthenticationTrustResolver.isAuthenticated` are
/// `false` for it, and a web request denied to it is asked to log in
/// rather than answered 403.
///
/// Spring (Java): `AnonymousAuthenticationToken`, the same constructor.
class AnonymousAuthenticationToken extends AbstractAuthenticationToken {
  /// An anonymous [principal] (usually `'anonymousUser'`) with
  /// [authorities] (usually `ROLE_ANONYMOUS`), already authenticated.
  ///
  /// [key] names the code that created the token; only its hash is kept.
  /// Throws an [ArgumentError] when [key] or [authorities] is empty.
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

  /// The `hashCode` of the key the token was created with, so code can
  /// check that a token comes from the filter it expects.
  final int keyHash;

  @override
  final Object principal;

  @override
  Object? get credentials => '';
}

/// A login that another system has already checked: the application
/// only learns who the user is and what they may do, and checks no
/// password itself.
///
/// It exists for setups where the authentication happens elsewhere: a
/// proxy or single sign-on gateway in front of a server that passes the
/// user in a header, or a Flutter web app whose own server logged the
/// user in (`ServerOAuth2LoginService` of
/// `spring_boot_starter_flutter_security` builds one from the server's
/// answer when the login was not an OAuth 2.0 one). Use
/// [PreAuthenticatedAuthenticationToken.authenticated] only with what that
/// trusted system said, never with input a client may forge.
///
/// ```dart
/// // The app's server says who holds the session cookie.
/// final user = PreAuthenticatedAuthenticationToken.authenticated(
///   'ada',
///   null,
///   AuthorityUtils.createAuthorityList(['ROLE_USER']),
/// );
/// SecurityContextHolder.setContext(SecurityContextImpl(user));
/// ```
///
/// Spring (Java): `PreAuthenticatedAuthenticationToken` of
/// `spring-security-web`, the same two constructors:
/// ```java
/// var user = new PreAuthenticatedAuthenticationToken("ada", null,
///     AuthorityUtils.createAuthorityList("ROLE_USER"));
/// ```
class PreAuthenticatedAuthenticationToken extends AbstractAuthenticationToken {
  /// A request to look the user up: [principal] as the other system named
  /// them, with its [credentials] (often `null`); not authenticated, no
  /// authorities.
  PreAuthenticatedAuthenticationToken(this.principal, this._credentials)
    : super();

  /// A login the other system checked: [principal] with [authorities].
  PreAuthenticatedAuthenticationToken.authenticated(
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

  @override
  void eraseCredentials() {
    super.eraseCredentials();
    _credentials = null;
  }
}

/// An already authenticated token with the authorities you name, for
/// tests and for code that runs as a fixed identity.
///
/// No password is checked: whatever you pass is trusted. Never build one
/// from input a client sent. In tests, `withMockUser` from
/// `package:spring_security_core/testing.dart` is often shorter.
///
/// ```dart
/// // A test of an admin-only service method.
/// await SecurityContextHolder.runWithContext(
///   () => orders.cancel(order),
///   SecurityContextImpl(
///     TestingAuthenticationToken('ada', null, ['ROLE_ADMIN']),
///   ),
/// );
/// ```
///
/// Spring (Java): `new TestingAuthenticationToken("ada", null,
/// "ROLE_ADMIN")`.
class TestingAuthenticationToken extends AbstractAuthenticationToken {
  /// An authenticated token for [principal] with [credentials] and the
  /// authorities named in [authorities] (used as given: write
  /// `ROLE_ADMIN`, not `ADMIN`).
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
