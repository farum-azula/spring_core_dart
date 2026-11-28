import 'package:spring_boot_starter_oauth2_client/src/properties/oauth2_client_properties.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/client_registration.dart';
import 'package:spring_boot_starter_oauth2_client/src/registration/common_oauth2_provider.dart';
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

const _log = SpringLog('spring.security.oauth2.client.registration');

/// The hosts of the providers' endpoints the application configured by
/// hand: every `spring.security.oauth2.client.provider.<id>.*-uri`
/// (`issuer-uri`, `authorization-uri`, `token-uri`, `user-info-uri`,
/// `jwk-set-uri`) and the built-in endpoints of the known providers its
/// registrations name (`google`, `github`, `facebook`, `apple`). The
/// RestClient starter's transport allows them, as it allows a group's
/// base URL.
///
/// The endpoints a discovery document names on another host than its
/// issuer (Google's token endpoint on `oauth2.googleapis.com`, Microsoft
/// Entra ID's user info on `graph.microsoft.com`) join the list when the
/// document is read and its issuer checked ([allowDiscovered]): by host
/// name only, so they open public addresses only. An endpoint the
/// document names by an address literal or a `localhost` name still goes
/// on `spring.http.clients.allowed-addresses` by hand.
final class OAuth2ProviderAllowedAddresses
    implements AllowedAddressesContributor {
  /// The endpoints of [properties].
  const OAuth2ProviderAllowedAddresses(this.properties);

  /// The OAuth2 client's properties.
  final OAuth2ClientProperties properties;

  @override
  Iterable<String> allowedAddresses() {
    final hosts = <String>{};
    void add(String? uri) {
      final host = Uri.tryParse(uri?.trim() ?? '')?.host ?? '';
      if (host.isNotEmpty) {
        hosts.add(host);
      }
    }

    for (final provider in properties.provider.values) {
      add(provider.issuerUri);
      add(provider.authorizationUri);
      add(provider.tokenUri);
      add(provider.userInfoUri);
      add(provider.jwkSetUri);
    }
    for (final MapEntry(key: id, :value) in properties.registration.entries) {
      final common = CommonOAuth2Provider.of(value.provider ?? id);
      if (common == null) {
        continue;
      }
      final details = common
          .getBuilder(id)
          .clientId(id)
          .build()
          .providerDetails;
      add(details.issuerUri);
      add(details.authorizationUri);
      add(details.tokenUri);
      add(details.userInfoEndpoint.uri);
      add(details.jwkSetUri);
    }
    return hosts;
  }

  /// Adds to [allowed] the hosts of [endpoints] (URLs a discovery document
  /// named, after its issuer was checked), by host name only
  /// ([AllowedAddresses.allowHostName]). An endpoint named by an address
  /// literal or a `localhost` name is left out and logged: it needs an
  /// entry of `spring.http.clients.allowed-addresses`.
  ///
  /// The OAuth2 client calls it for the token, JWK Set, user-info and
  /// revocation endpoints of a registration it discovered
  /// ([endpointsOf]), the security starter's resource server for the
  /// `jwks_uri` of its issuer.
  static void allowDiscovered(
    AllowedAddresses allowed,
    Iterable<String?> endpoints,
  ) {
    for (final endpoint in endpoints) {
      final url = Uri.tryParse(endpoint?.trim() ?? '');
      if (url == null || url.host.isEmpty) {
        continue;
      }
      try {
        allowed.checkUrl(url);
        continue; // allowed already
      } on FilteredHostException {
        // not yet
      }
      final host = url.host;
      if (allowed.allowHostName(host)) {
        _log.debug(
          () => 'Allowing $host, an endpoint host of the discovery document',
        );
      } else {
        _log.debug(
          () =>
              'Not allowing $host of the discovery document by itself (an '
              'address or a localhost name): add it to '
              'spring.http.clients.allowed-addresses',
        );
      }
    }
  }

  /// The endpoints of [registration] the client calls over the transport:
  /// the token, JWK Set, user-info and revocation endpoints.
  static List<String?> endpointsOf(ClientRegistration registration) {
    final provider = registration.providerDetails;
    return [
      provider.tokenUri,
      provider.jwkSetUri,
      provider.userInfoEndpoint.uri,
      provider.revocationEndpoint,
    ];
  }
}
