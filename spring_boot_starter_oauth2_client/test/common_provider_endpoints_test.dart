// The generator's spa Content Security Policy lets the browser fetch from
// the common providers' endpoints. The generator does not depend on this
// package, so it keeps a copy of them; this test (here, as this package
// already has the generator as a dev dependency) keeps the copy equal to
// CommonOAuth2Provider.
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart';
import 'package:test/test.dart';

void main() {
  test("the generator's copy of the common providers' endpoints is "
      'CommonOAuth2Provider', () {
    final endpoints = {
      for (final provider in CommonOAuth2Provider.values)
        provider.name: () {
          if (provider == CommonOAuth2Provider.okta) {
            // No endpoints of its own: they come from its issuer.
            return const <String, String>{};
          }
          final details = provider
              .getBuilder(provider.name)
              .clientId('id')
              .build()
              .providerDetails;
          return {
            'tokenuri': ?details.tokenUri,
            'jwkseturi': ?details.jwkSetUri,
            'userinfouri': ?details.userInfoEndpoint.uri,
          };
        }(),
    };
    expect(WebDevServerSettings.commonProviderEndpoints, endpoints);
  });
}
