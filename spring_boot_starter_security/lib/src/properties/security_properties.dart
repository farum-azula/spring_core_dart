import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_security/src/jwt/bearer.dart';
import 'package:spring_boot_starter_security/src/jwt/jose.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// The `spring.security.*` properties the starter reads: the default user,
/// the place of the security filter, the sessions, the cookie key and the
/// JWT resource server.
///
/// Set them in `application.properties` (or YAML, or the environment).
/// Applications rarely use this class; the auto-configuration reads it.
/// The values as the starter uses them (trimmed, with defaults) are the
/// getters of [SecurityPropertiesValues].
///
/// The `spring.security.session.*` properties (not in Spring Boot, where
/// `maximumSessions` is set in code only) apply to the chains that keep
/// logins in sessions (form login, `oauth2Login()`); `stateless` chains,
/// bearer tokens and HTTP Basic make no sessions. A chain's own
/// `sessionManagement((s) => s.maximumSessions(...))` wins.
///
/// ```properties
/// # A development user instead of the generated password.
/// spring.security.user.name=admin
/// spring.security.user.password=change-me
/// spring.security.user.roles=ADMIN
///
/// # Or an API that accepts the identity provider's tokens.
/// spring.security.oauth2.resourceserver.jwt.issuer-uri=https://login.example.com
/// spring.security.oauth2.resourceserver.jwt.audiences=orders-api
/// ```
///
/// With `issuer-uri` or `jwk-set-uri` set, every request needs a valid
/// bearer token and there is no default user. With `jwk-set-uri`, the
/// issuer (when also set) and the audiences are checked too; with
/// `issuer-uri` alone, the keys come from the issuer's metadata and
/// `jws-algorithms` is not used.
///
/// Spring (Java): Spring Boot's `SecurityProperties` and
/// `OAuth2ResourceServerProperties`, with the same names.
@ConfigurationProperties('spring.security')
class SecurityProperties {
  /// The default user, made when the application has no user store.
  SecurityUserProperties user = SecurityUserProperties();

  /// The security filter among the web filters.
  SecurityFilterProperties filter = SecurityFilterProperties();

  /// The sessions of the chains that keep logins in sessions.
  SecuritySessionProperties session = SecuritySessionProperties();

  /// The signing of the cookies kept instead of a session before a login.
  SecurityCookieProperties cookie = SecurityCookieProperties();

  /// OAuth2 settings of the application as a resource server.
  SecurityOAuth2Properties oauth2 = SecurityOAuth2Properties();
}

/// The `spring.security.user.*` properties.
@Introspected()
class SecurityUserProperties {
  /// The name of the default user.
  String name = 'user';

  /// The password of the default user; without it a random one is
  /// generated and logged (for development only).
  String? password;

  /// The roles of the default user, without the `ROLE_` prefix.
  List<String> roles = [];
}

/// The `spring.security.filter.*` properties.
@Introspected()
class SecurityFilterProperties {
  /// The place of the security filter among the web filters.
  int order = -100;
}

/// The `spring.security.session.*` properties.
@Introspected()
class SecuritySessionProperties {
  /// The most sessions per user of the chains with sessions; `-1` for no
  /// limit. `0` and values below `-1` fail the start.
  int maximumSessions = 10;

  /// Whether a login over the session limit is refused instead of ending
  /// the oldest session.
  bool maxSessionsPreventsLogin = false;
}

/// The `spring.security.cookie.*` properties.
@Introspected()
class SecurityCookieProperties {
  /// The key that signs the security cookies (at least 32 characters; the
  /// same on every instance behind a proxy); a random key of the process
  /// when unset (set it to keep cookies valid across restarts and
  /// servers).
  String? secret;
}

/// The `spring.security.oauth2.*` properties of the resource server.
@Introspected()
class SecurityOAuth2Properties {
  /// The application as an OAuth2 resource server.
  SecurityResourceServerProperties resourceserver =
      SecurityResourceServerProperties();
}

/// The `spring.security.oauth2.resourceserver.*` properties.
@Introspected()
class SecurityResourceServerProperties {
  /// Bearer tokens that are JSON Web Tokens.
  SecurityJwtProperties jwt = SecurityJwtProperties();
}

/// The `spring.security.oauth2.resourceserver.jwt.*` properties.
@Introspected()
class SecurityJwtProperties {
  /// The issuer of the accepted bearer tokens; the keys come from its
  /// metadata.
  String? issuerUri;

  /// The address of the keys that sign the accepted bearer tokens.
  String? jwkSetUri;

  /// The signature algorithms accepted with `jwk-set-uri`. Default:
  /// `RS256`.
  @PropertyValues([
    'RS256',
    'RS384',
    'RS512',
    'PS256',
    'PS384',
    'PS512',
    'ES256',
    'ES384',
    'ES512',
    'HS256',
    'HS384',
    'HS512',
  ])
  List<String> jwsAlgorithms = [];

  /// The audiences a bearer token must have one of; no audience check when
  /// empty.
  List<String> audiences = [];

  /// Put before each authority read from the token.
  String authorityPrefix = 'SCOPE_';

  /// The claim whose values are the user's authorities; without it the
  /// `scope` claim, else `scp`.
  String? authoritiesClaimName;

  /// The character that splits a text claim into authorities.
  String authoritiesClaimDelimiter = ' ';

  /// The claim that names the user of a bearer token.
  String principalClaimName = 'sub';
}

/// The values of [SecurityProperties] as the starter uses them: text
/// trimmed, blank as unset, defaults filled in, and checked.
extension SecurityPropertiesValues on SecurityProperties {
  SecurityJwtProperties get _jwt => oauth2.resourceserver.jwt;

  /// `spring.security.user.name`: the default user's name, `user` when
  /// blank.
  String get userName => _text(user.name) ?? 'user';

  /// `spring.security.user.password`: the default user's password, or
  /// `null` when unset (a random one is then generated and logged).
  String? get userPassword => _text(user.password);

  /// `spring.security.user.roles`: the default user's roles, without
  /// `ROLE_`; none when unset.
  List<String> get userRoles => _texts(user.roles);

  /// `spring.security.filter.order`: the place of the security filter
  /// among the web filters, `-100` by default.
  int get filterOrder => filter.order;

  /// `spring.security.session.maximum-sessions`: the most sessions per
  /// user of the chains with sessions, 10 by default, `-1` for no limit.
  ///
  /// Throws an [ArgumentError] for `0` or a value below `-1`.
  int get maximumSessions {
    final value = session.maximumSessions;
    if (value == 0 || value < -1) {
      throw ArgumentError(
        'spring.security.session.maximum-sessions must be -1 or positive: '
        '$value',
      );
    }
    return value;
  }

  /// `spring.security.session.max-sessions-prevents-login`: whether a
  /// login above [maximumSessions] is refused instead of ending the
  /// user's least recently used session; `false` by default.
  bool get maxSessionsPreventsLogin => session.maxSessionsPreventsLogin;

  /// `spring.security.oauth2.resourceserver.jwt.issuer-uri`: the identity
  /// provider whose tokens are accepted, or `null`.
  String? get issuerUri => _text(_jwt.issuerUri);

  /// `spring.security.oauth2.resourceserver.jwt.jwk-set-uri`: the URL of
  /// the provider's public keys, or `null`.
  String? get jwkSetUri => _text(_jwt.jwkSetUri);

  /// `spring.security.oauth2.resourceserver.jwt.jws-algorithms`: the
  /// signature algorithms accepted with `jwk-set-uri`, `RS256` when unset.
  ///
  /// Throws an [ArgumentError] for an unknown name.
  Set<JwsAlgorithm> get jwsAlgorithms {
    final names = _texts(_jwt.jwsAlgorithms);
    if (names.isEmpty) {
      return const {JwsAlgorithm.rs256};
    }
    return {
      for (final name in names)
        JwsAlgorithm.from(name) ??
            (throw ArgumentError(
              'spring.security.oauth2.resourceserver.jwt.jws-algorithms: '
              'unknown $name',
            )),
    };
  }

  /// `spring.security.oauth2.resourceserver.jwt.audiences`: tokens must
  /// name one of them in `aud`; no audience check when empty.
  List<String> get audiences => _texts(_jwt.audiences);

  /// Whether `issuer-uri` or `jwk-set-uri` is set, which makes the
  /// application a JWT resource server.
  bool get hasResourceServer => issuerUri != null || jwkSetUri != null;

  /// A [JwtAuthenticationConverter] following `authority-prefix`
  /// (`SCOPE_`, may be empty), `authorities-claim-name`,
  /// `authorities-claim-delimiter` (a space) and `principal-claim-name`
  /// (`sub`).
  JwtAuthenticationConverter get jwtAuthenticationConverter =>
      JwtAuthenticationConverter(
        authoritiesConverter: JwtGrantedAuthoritiesConverter(
          authorityPrefix: _jwt.authorityPrefix,
          authoritiesClaimName: _text(_jwt.authoritiesClaimName),
          authoritiesClaimDelimiter: _jwt.authoritiesClaimDelimiter,
        ),
        principalClaimName: _text(_jwt.principalClaimName) ?? 'sub',
      );
}

String? _text(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

List<String> _texts(List<String> values) => [
  for (final value in values)
    if (value.trim().isNotEmpty) value.trim(),
];
