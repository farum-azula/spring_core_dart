import 'package:spring_boot_starter_oauth2_client/src/oidc/claims.dart';
import 'package:spring_boot_starter_oauth2_client/src/oidc/oidc_id_token.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// A user logged in through an OAuth 2.0 provider: what the provider said
/// about them ([attributes]), what they may do ([authorities]), and their
/// [name].
///
/// The login puts it in the [OAuth2AuthenticationToken] of the security
/// context; with OpenID Connect it is an [OidcUser]. Read it to show who
/// is logged in:
///
/// ```dart
/// final user = login.user!;
/// log.info('Hello ${user.getAttribute<String>('name') ?? user.name}');
/// ```
///
/// Spring (Java): `OAuth2User` (an `OAuth2AuthenticatedPrincipal`).
abstract interface class OAuth2User implements Principal {
  /// The provider's attributes of the user (the user-info answer, or the
  /// ID token's claims and the user info); cannot be modified.
  Map<String, Object?> get attributes;

  /// What the user may do: `OAUTH2_USER` or `OIDC_USER`, `SCOPE_<scope>`
  /// for each scope, plus what a `GrantedAuthoritiesMapper` added.
  List<GrantedAuthority> get authorities;

  /// The user's name in the application: the value of the registration's
  /// user name attribute (`sub`, `login`, `email`, ...).
  @override
  String get name;

  /// The attribute [name] when it is a [T], else `null`.
  T? getAttribute<T>(String name);
}

/// The [OAuth2User] the user services build.
///
/// Spring (Java): `DefaultOAuth2User`.
class DefaultOAuth2User implements OAuth2User {
  /// A user with [authorities] and [attributes], named by the attribute
  /// [nameAttributeKey].
  ///
  /// Throws an [ArgumentError] when [attributes] is empty or has no
  /// non-null [nameAttributeKey].
  DefaultOAuth2User(
    Iterable<GrantedAuthority> authorities,
    Map<String, Object?> attributes,
    this.nameAttributeKey,
  ) : authorities = List.unmodifiable(_unique(authorities)),
      attributes = Map.unmodifiable(attributes) {
    if (attributes.isEmpty) {
      throw ArgumentError('attributes cannot be empty');
    }
    if (nameAttributeKey.isEmpty) {
      throw ArgumentError('nameAttributeKey cannot be empty');
    }
    if (attributes[nameAttributeKey] == null) {
      throw ArgumentError(
        "Missing attribute '$nameAttributeKey' in attributes",
      );
    }
  }

  /// The attribute that names the user.
  final String nameAttributeKey;

  @override
  final List<GrantedAuthority> authorities;

  @override
  final Map<String, Object?> attributes;

  @override
  String get name => '${attributes[nameAttributeKey]}';

  @override
  T? getAttribute<T>(String name) => switch (attributes[name]) {
    final T value => value,
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is DefaultOAuth2User &&
      other.runtimeType == runtimeType &&
      other.name == name &&
      _sameAuthorities(other.authorities, authorities);

  @override
  int get hashCode => Object.hash(runtimeType, name);

  @override
  String toString() =>
      // The text names the actual class, subclasses included, as Java's
      // getClass().getSimpleName() does.
      // ignore: no_runtimetype_tostring
      '$runtimeType [Name: [$name], Granted Authorities: $authorities]';

  static List<GrantedAuthority> _unique(Iterable<GrantedAuthority> all) {
    final seen = <String?>{};
    return [
      for (final authority in all)
        if (seen.add(authority.authority)) authority,
    ];
  }

  static bool _sameAuthorities(
    List<GrantedAuthority> a,
    List<GrantedAuthority> b,
  ) =>
      a.length == b.length &&
      a.map((x) => x.authority).toSet().containsAll(b.map((x) => x.authority));
}

/// A user logged in with OpenID Connect: an [OAuth2User] with the ID
/// token, and the user info when it was loaded.
///
/// Its [claims] are the ID token's and the user info's (the ID token's
/// win), readable with the standard getters:
///
/// ```dart
/// final user = login.user as OidcUser;
/// log.info('${user.fullName} <${user.email}>, ${user.idToken.issuer}');
/// ```
///
/// Spring (Java): `OidcUser`.
abstract interface class OidcUser
    implements OAuth2User, ClaimAccessor, IdTokenClaimAccessor {
  /// The ID token of the login.
  OidcIdToken get idToken;

  /// The answer of the user-info endpoint, or `null` when it was not
  /// asked.
  OidcUserInfo? get userInfo;
}

/// The [OidcUser] the OIDC user service builds.
///
/// Spring (Java): `DefaultOidcUser`.
class DefaultOidcUser extends DefaultOAuth2User
    with ClaimAccessor, StandardClaimAccessor, IdTokenClaimAccessor
    implements OidcUser {
  /// A user with [authorities], [idToken] and optional [userInfo], named
  /// by the claim [nameAttributeKey] (`sub` by default).
  DefaultOidcUser(
    Iterable<GrantedAuthority> authorities,
    this.idToken, {
    this.userInfo,
    String nameAttributeKey = IdTokenClaimNames.sub,
  }) : super(
         authorities,
         {...?userInfo?.claims, ...idToken.claims},
         nameAttributeKey,
       );

  @override
  final OidcIdToken idToken;

  @override
  final OidcUserInfo? userInfo;

  @override
  Map<String, Object?> get claims => attributes;
}

/// The authority every user of an OAuth 2.0 login has: `OAUTH2_USER`,
/// with the user's attributes.
///
/// Spring (Java): `OAuth2UserAuthority`.
class OAuth2UserAuthority implements GrantedAuthority {
  /// The authority [authority] (`OAUTH2_USER` by default) of a user with
  /// [attributes], named by [userNameAttributeName].
  OAuth2UserAuthority(
    Map<String, Object?> attributes, {
    this.authority = 'OAUTH2_USER',
    this.userNameAttributeName,
  }) : attributes = Map.unmodifiable(attributes);

  @override
  final String authority;

  /// The user's attributes.
  final Map<String, Object?> attributes;

  /// The attribute that names the user, or `null`.
  final String? userNameAttributeName;

  @override
  bool operator ==(Object other) =>
      other is OAuth2UserAuthority && other.authority == authority;

  @override
  int get hashCode => authority.hashCode;

  @override
  String toString() => authority;
}

/// The authority every user of an OpenID Connect login has: `OIDC_USER`,
/// with the ID token and the user info.
///
/// Spring (Java): `OidcUserAuthority`.
class OidcUserAuthority extends OAuth2UserAuthority {
  /// The authority [authority] (`OIDC_USER` by default) of the user of
  /// [idToken] and [userInfo].
  OidcUserAuthority(
    this.idToken, {
    this.userInfo,
    super.authority = 'OIDC_USER',
    super.userNameAttributeName,
  }) : super({...?userInfo?.claims, ...idToken.claims});

  /// The ID token.
  final OidcIdToken idToken;

  /// The user info, or `null`.
  final OidcUserInfo? userInfo;
}

/// Who is logged in through an OAuth 2.0 or OpenID Connect provider, as
/// the security context holds it.
///
/// The app login puts one in the `SecurityContextHolder`; anything that
/// asks who is logged in (`@PreAuthorize`, the Feign interceptor, your
/// code) finds it there. [principal] is the [OAuth2User] (an [OidcUser]
/// with OpenID Connect), [authorizedClientRegistrationId] the provider
/// used.
///
/// ```dart
/// final authentication = SecurityContextHolder.getContext().authentication;
/// if (authentication is OAuth2AuthenticationToken) {
///   log.info('${authentication.name} via '
///       '${authentication.authorizedClientRegistrationId}');
/// }
/// ```
///
/// Spring (Java): `OAuth2AuthenticationToken`.
class OAuth2AuthenticationToken extends AbstractAuthenticationToken {
  /// An authenticated token of [principal], with [authorities] (usually
  /// the user's, mapped), from the registration
  /// [authorizedClientRegistrationId].
  OAuth2AuthenticationToken(
    this.principal,
    Iterable<GrantedAuthority> authorities,
    this.authorizedClientRegistrationId,
  ) : super(authorities) {
    if (authorizedClientRegistrationId.isEmpty) {
      throw ArgumentError('authorizedClientRegistrationId cannot be empty');
    }
    super.isAuthenticated = true;
  }

  @override
  final OAuth2User principal;

  /// The registration the user logged in with, such as `keycloak`.
  final String authorizedClientRegistrationId;

  /// Always empty: the tokens are in the authorized client, not here.
  @override
  Object? get credentials => '';

  @override
  String get name => principal.name;
}
