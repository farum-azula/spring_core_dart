import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_oauth2_client/src/properties/oauth2_client_properties.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration_repository.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registrations.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/common_oauth2_provider.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.security.oauth2.client.registration');

/// Turns [OAuth2ClientProperties] into registrations, as Spring Boot
/// does.
///
/// For each registration, the provider is the `provider` property, else
/// the registration id. With the provider's `issuer-uri`, the endpoints
/// come from its metadata ([ClientRegistrations.fromIssuerLocation]);
/// else a common provider (google, github, facebook, okta) gives them;
/// else the provider's properties must. The provider's properties then
/// override what came before, and the registration's own properties come
/// last.
///
/// Differences from Spring Boot: a registration with an `issuer-uri` is
/// resolved at its first use, not at startup, so an app starts without
/// the network (the result is a [ClientRegistrationSupplier] per id); and
/// an `authorization_code` registration without a client secret and
/// without `client-authentication-method` uses `none` (a public client)
/// even when its common provider says `client_secret_basic`; the
/// registration's `dpop` property (not in Spring Boot) sets
/// [ClientRegistration.dpop].
///
/// A registration whose issuer, authorization, token, JWK Set, user-info
/// or redirect URI is plain `http://` on a host other than a loopback one
/// (`localhost`, `127.0.0.1`, `[::1]`) is logged as a warning once, when
/// it is built, and still works (a local test provider is fine). An app
/// trusts an ID token because TLS brought it from the provider; over
/// `http://` anyone on the way can read the tokens or change them. Not in
/// Spring Boot.
///
/// Spring Boot (Java): `OAuth2ClientPropertiesMapper`.
final class OAuth2ClientPropertiesMapper {
  /// A mapper of [properties]; discovery uses [transport] (the
  /// `httpTransport` bean in an application).
  OAuth2ClientPropertiesMapper(this.properties, {this.transport});

  /// The properties mapped.
  final OAuth2ClientProperties properties;

  /// The transport of issuer discovery; a new platform transport when
  /// `null`.
  final HttpTransport? transport;

  // The registrations already warned about (a supplier that failed is
  // called again; the warning stays one).
  final Set<String> _warned = {};

  /// A supplier per registration id. Registrations without an issuer are
  /// built now, so a missing endpoint fails the start; those with one are
  /// checked as far as possible now and built at first use.
  ///
  /// Throws a [StateError] for a missing client id or an unknown
  /// provider, an [ArgumentError] for an incomplete registration or a
  /// `dpop` other than `auto`, `true` and `false` or a `response-mode`
  /// other than `query` and `form_post`.
  Map<String, ClientRegistrationSupplier> asClientRegistrations() {
    properties.validate();
    return {
      for (final MapEntry(key: id, :value) in properties.registration.entries)
        id: _supplier(id, _clean(value)),
    };
  }

  // Blank is unset, and values are trimmed, as property values were read
  // before they were bound.
  static String? _text(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static OAuth2ClientRegistrationProperties _clean(
    OAuth2ClientRegistrationProperties registration,
  ) => OAuth2ClientRegistrationProperties(
    provider: _text(registration.provider),
    clientId: _text(registration.clientId),
    clientSecret: _text(registration.clientSecret),
    clientAuthenticationMethod: _text(registration.clientAuthenticationMethod),
    authorizationGrantType: _text(registration.authorizationGrantType),
    redirectUri: _text(registration.redirectUri),
    scope: registration.scope == null
        ? null
        : {
            for (final value in registration.scope!)
              if (value.trim().isNotEmpty) value.trim(),
          },
    clientName: _text(registration.clientName),
    dpop: _text(registration.dpop),
    responseMode: _text(registration.responseMode),
    nativeSignIn: _text(registration.nativeSignIn),
  );

  static OAuth2ClientProviderProperties _cleanProvider(
    OAuth2ClientProviderProperties provider,
  ) => OAuth2ClientProviderProperties(
    authorizationUri: _text(provider.authorizationUri),
    tokenUri: _text(provider.tokenUri),
    userInfoUri: _text(provider.userInfoUri),
    userInfoAuthenticationMethod: _text(provider.userInfoAuthenticationMethod),
    userNameAttribute: _text(provider.userNameAttribute),
    jwkSetUri: _text(provider.jwkSetUri),
    issuerUri: _text(provider.issuerUri),
  );

  ClientRegistrationSupplier _supplier(
    String registrationId,
    OAuth2ClientRegistrationProperties registration,
  ) {
    if (registration.dpop case final dpop?) {
      DPoPMode.parse(dpop); // fails at startup, not at the first use
    }
    if (registration.responseMode case final mode?) {
      ResponseMode.parse(mode);
    }
    final providerId = registration.provider ?? registrationId;
    final provider = switch (properties.provider[providerId]) {
      final bound? => _cleanProvider(bound),
      null => null,
    };
    final issuer = provider?.issuerUri;
    if (provider != null && issuer != null) {
      return () async {
        final builder = await ClientRegistrations.fromIssuerLocation(
          issuer,
          transport: transport,
        );
        builder.registrationId(registrationId);
        return _build(_applyProvider(builder, provider), registration);
      };
    }
    final common = CommonOAuth2Provider.of(providerId);
    if (common == null && provider == null) {
      throw StateError(
        registration.provider != null
            ? "Unknown provider ID '${registration.provider}'"
            : "Provider ID must be specified for client registration '"
                  "$registrationId'",
      );
    }
    var builder =
        common?.getBuilder(registrationId) ??
        ClientRegistration.withRegistrationId(registrationId);
    if (provider != null) {
      builder = _applyProvider(builder, provider);
    }
    final built = _build(builder, registration);
    return () async => built;
  }

  static ClientRegistrationBuilder _applyProvider(
    ClientRegistrationBuilder builder,
    OAuth2ClientProviderProperties provider,
  ) {
    if (provider.authorizationUri case final uri?) {
      builder.authorizationUri(uri);
    }
    if (provider.tokenUri case final uri?) {
      builder.tokenUri(uri);
    }
    if (provider.userInfoUri case final uri?) {
      builder.userInfoUri(uri);
    }
    if (provider.userInfoAuthenticationMethod case final method?) {
      builder.userInfoAuthenticationMethod(AuthenticationMethod(method));
    }
    if (provider.jwkSetUri case final uri?) {
      builder.jwkSetUri(uri);
    }
    if (provider.userNameAttribute case final name?) {
      builder.userNameAttributeName(name);
    }
    return builder;
  }

  ClientRegistration _build(
    ClientRegistrationBuilder builder,
    OAuth2ClientRegistrationProperties registration,
  ) {
    final built = _builtFrom(builder, registration);
    _warnAboutPlainHttp(built);
    return built;
  }

  void _warnAboutPlainHttp(ClientRegistration registration) {
    final provider = registration.providerDetails;
    final insecure = [
      for (final (name, uri) in [
        ('issuer-uri', provider.issuerUri),
        ('authorization-uri', provider.authorizationUri),
        ('token-uri', provider.tokenUri),
        ('jwk-set-uri', provider.jwkSetUri),
        ('user-info-uri', provider.userInfoEndpoint.uri),
        ('redirect-uri', registration.redirectUri),
      ])
        if (_isPlainHttpOutsideLoopback(uri)) '$name $uri',
    ];
    if (insecure.isEmpty || !_warned.add(registration.registrationId)) {
      return;
    }
    _log.warning(
      "Client registration '${registration.registrationId}' uses http:// "
      'outside a loopback host (${insecure.join(', ')}): tokens and ID '
      'tokens can be read or changed on the way; use https://',
    );
  }

  static ClientRegistration _builtFrom(
    ClientRegistrationBuilder builder,
    OAuth2ClientRegistrationProperties registration,
  ) {
    builder
      ..clientId(registration.clientId!)
      ..clientSecret(registration.clientSecret);
    if (registration.clientAuthenticationMethod case final method?) {
      builder.clientAuthenticationMethod(ClientAuthenticationMethod(method));
    } else if (registration.clientSecret == null) {
      // A public client (an app): nothing to send but the client id. The
      // builder picks `none` for authorization_code, basic otherwise.
      builder.clientAuthenticationMethod(null);
    }
    if (registration.authorizationGrantType case final grant?) {
      builder.authorizationGrantType(AuthorizationGrantType(grant));
    }
    if (registration.redirectUri case final uri?) {
      builder.redirectUri(uri);
    }
    if (registration.scope case final scope?) {
      builder.scope(scope);
    }
    if (registration.clientName case final name?) {
      builder.clientName(name);
    }
    if (registration.dpop case final dpop?) {
      builder.dpop(DPoPMode.parse(dpop));
    }
    if (registration.responseMode case final mode?) {
      builder.responseMode(ResponseMode.parse(mode));
    }
    return builder.build();
  }
}

// Whether [uri] is a plain `http://` URL on a host other than a loopback
// one (`localhost`, `127.0.0.1`, `[::1]`): what the mapper warns about.
// Templates (`{baseUrl}/...`), custom schemes and `https` are not.
bool _isPlainHttpOutsideLoopback(String? uri) {
  if (uri == null) {
    return false;
  }
  final parsed = Uri.tryParse(uri.trim());
  if (parsed == null || parsed.scheme.toLowerCase() != 'http') {
    return false;
  }
  final host = parsed.host.toLowerCase();
  return host != 'localhost' && host != '127.0.0.1' && host != '::1';
}
