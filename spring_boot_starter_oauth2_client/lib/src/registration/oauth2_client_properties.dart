// The documentation has Markdown table rows, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration_repository.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registrations.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/common_oauth2_provider.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _registrationPrefix = 'spring.security.oauth2.client.registration';
const _providerPrefix = 'spring.security.oauth2.client.provider';

/// The `spring.security.oauth2.client.registration.<id>.*` properties of
/// one registration.
///
/// | Property | Meaning |
/// |---|---|
/// | `provider` | the provider id when it differs from the registration id |
/// | `client-id` | required |
/// | `client-secret` | none for an app |
/// | `client-authentication-method` | `client_secret_basic`, `client_secret_post`, `none` |
/// | `authorization-grant-type` | `authorization_code`, `client_credentials` |
/// | `redirect-uri` | a template, such as `neonbooks:/oauth2/callback` |
/// | `scope` | a comma list or a YAML list |
/// | `client-name` | shown to users |
///
/// Spring Boot (Java): `OAuth2ClientProperties.Registration`.
final class OAuth2ClientRegistrationProperties {
  /// The properties of one registration, as read.
  const OAuth2ClientRegistrationProperties({
    this.provider,
    this.clientId,
    this.clientSecret,
    this.clientAuthenticationMethod,
    this.authorizationGrantType,
    this.redirectUri,
    this.scope,
    this.clientName,
  });

  /// `provider`.
  final String? provider;

  /// `client-id`.
  final String? clientId;

  /// `client-secret`; a credential, never log it.
  final String? clientSecret;

  /// `client-authentication-method`.
  final String? clientAuthenticationMethod;

  /// `authorization-grant-type`.
  final String? authorizationGrantType;

  /// `redirect-uri`.
  final String? redirectUri;

  /// `scope`; `null` when not set.
  final Set<String>? scope;

  /// `client-name`.
  final String? clientName;
}

/// The `spring.security.oauth2.client.provider.<id>.*` properties of one
/// provider.
///
/// | Property | Meaning |
/// |---|---|
/// | `issuer-uri` | the endpoints come from the provider's metadata |
/// | `authorization-uri` | the login page |
/// | `token-uri` | the token endpoint |
/// | `user-info-uri` | the user-info endpoint |
/// | `user-info-authentication-method` | `header` (default), `form`, `query` |
/// | `user-name-attribute` | the attribute naming the user |
/// | `jwk-set-uri` | the provider's keys |
///
/// Spring Boot (Java): `OAuth2ClientProperties.Provider`.
final class OAuth2ClientProviderProperties {
  /// The properties of one provider, as read.
  const OAuth2ClientProviderProperties({
    this.authorizationUri,
    this.tokenUri,
    this.userInfoUri,
    this.userInfoAuthenticationMethod,
    this.userNameAttribute,
    this.jwkSetUri,
    this.issuerUri,
  });

  /// `authorization-uri`.
  final String? authorizationUri;

  /// `token-uri`.
  final String? tokenUri;

  /// `user-info-uri`.
  final String? userInfoUri;

  /// `user-info-authentication-method`.
  final String? userInfoAuthenticationMethod;

  /// `user-name-attribute`.
  final String? userNameAttribute;

  /// `jwk-set-uri`.
  final String? jwkSetUri;

  /// `issuer-uri`.
  final String? issuerUri;
}

/// The `spring.security.oauth2.client.*` properties: the registrations
/// and the providers, by id.
///
/// The starter reads them to build the `ClientRegistrationRepository`;
/// applications set them and rarely use this class.
///
/// ```properties
/// spring.security.oauth2.client.registration.keycloak.client-id=neon-app
/// spring.security.oauth2.client.registration.keycloak.scope=openid,profile,email
/// spring.security.oauth2.client.registration.keycloak.redirect-uri=neonbooks:/oauth2/callback
/// spring.security.oauth2.client.provider.keycloak.issuer-uri=https://sso.example.com/realms/neon
/// ```
///
/// Spring Boot (Java): `OAuth2ClientProperties`, with the same names.
final class OAuth2ClientProperties {
  /// The properties [registration] and [provider], by id.
  const OAuth2ClientProperties({
    this.registration = const {},
    this.provider = const {},
  });

  /// Reads the properties of [environment].
  factory OAuth2ClientProperties.of(Environment environment) {
    String? text(String key) {
      final value = environment.getProperty(key)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final binder = environment is ConfigurableEnvironment
        ? Binder.get(environment)
        : null;
    Set<String>? scopes(String key) {
      final List<String>? values;
      if (binder != null) {
        values = binder
            .bind(key, const ListType<String>(ClassType<String>()))
            .map<List<String>?>((values) => values)
            .orElse(null);
      } else {
        values = environment.getProperty(key)?.split(',');
      }
      if (values == null) {
        return null;
      }
      return {
        for (final value in values)
          if (value.trim().isNotEmpty) value.trim(),
      };
    }

    final registrations = {
      for (final id in _ids(environment, binder, _registrationPrefix))
        id: OAuth2ClientRegistrationProperties(
          provider: text('$_registrationPrefix.$id.provider'),
          clientId: text('$_registrationPrefix.$id.client-id'),
          clientSecret: text('$_registrationPrefix.$id.client-secret'),
          clientAuthenticationMethod: text(
            '$_registrationPrefix.$id.client-authentication-method',
          ),
          authorizationGrantType: text(
            '$_registrationPrefix.$id.authorization-grant-type',
          ),
          redirectUri: text('$_registrationPrefix.$id.redirect-uri'),
          scope: scopes('$_registrationPrefix.$id.scope'),
          clientName: text('$_registrationPrefix.$id.client-name'),
        ),
    };
    final providers = {
      for (final id in _ids(environment, binder, _providerPrefix))
        id: OAuth2ClientProviderProperties(
          authorizationUri: text('$_providerPrefix.$id.authorization-uri'),
          tokenUri: text('$_providerPrefix.$id.token-uri'),
          userInfoUri: text('$_providerPrefix.$id.user-info-uri'),
          userInfoAuthenticationMethod: text(
            '$_providerPrefix.$id.user-info-authentication-method',
          ),
          userNameAttribute: text('$_providerPrefix.$id.user-name-attribute'),
          jwkSetUri: text('$_providerPrefix.$id.jwk-set-uri'),
          issuerUri: text('$_providerPrefix.$id.issuer-uri'),
        ),
    };
    return OAuth2ClientProperties(
      registration: registrations,
      provider: providers,
    );
  }

  /// Whether [environment] has at least one registration property: the
  /// condition of the starter's repository.
  static bool hasRegistrations(Environment environment) => _ids(
    environment,
    environment is ConfigurableEnvironment ? Binder.get(environment) : null,
    _registrationPrefix,
  ).isNotEmpty;

  // The ids under [prefix]: the first element of every property name
  // below it (relaxed names, YAML lists and environment variables
  // included).
  static Set<String> _ids(
    Environment environment,
    Binder? binder,
    String prefix,
  ) {
    if (binder == null) {
      return const {};
    }
    final entries = binder
        .bind(
          prefix,
          const MapType<String, String>(
            ClassType<String>(),
            ClassType<String>(),
          ),
        )
        .orElse(const {});
    return {
      for (final key in entries.keys)
        if (key.split('.').first.trim().isNotEmpty) key.split('.').first,
    };
  }

  /// The registrations, by id.
  final Map<String, OAuth2ClientRegistrationProperties> registration;

  /// The providers, by id.
  final Map<String, OAuth2ClientProviderProperties> provider;

  /// Checks that every registration has a client id.
  ///
  /// Throws a [StateError] (`Client id of registration 'x' must not be
  /// empty.`) otherwise.
  void validate() {
    for (final MapEntry(key: id, :value) in registration.entries) {
      if (value.clientId == null || value.clientId!.isEmpty) {
        throw StateError("Client id of registration '$id' must not be empty.");
      }
    }
  }
}

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
/// even when its common provider says `client_secret_basic`.
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

  /// A supplier per registration id. Registrations without an issuer are
  /// built now, so a missing endpoint fails the start; those with one are
  /// checked as far as possible now and built at first use.
  ///
  /// Throws a [StateError] for a missing client id or an unknown
  /// provider, an [ArgumentError] for an incomplete registration.
  Map<String, ClientRegistrationSupplier> asClientRegistrations() {
    properties.validate();
    return {
      for (final MapEntry(key: id, :value) in properties.registration.entries)
        id: _supplier(id, value),
    };
  }

  ClientRegistrationSupplier _supplier(
    String registrationId,
    OAuth2ClientRegistrationProperties registration,
  ) {
    final providerId = registration.provider ?? registrationId;
    final provider = properties.provider[providerId];
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

  static ClientRegistration _build(
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
    return builder.build();
  }
}
