import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The `spring.security.oauth2.client.restclient.*` properties: the access
/// token on `RestClient` calls and HTTP service interfaces.
@ConfigurationProperties('spring.security.oauth2.client.restclient')
class OAuth2RestClientProperties {
  /// Whether every `RestClientBuilder` of the RestClient starter (the
  /// injected builders and the HTTP service groups') gets the
  /// `OAuth2ClientHttpRequestInterceptor`. It sends a token only on the
  /// calls that name a registration (`@ClientRegistrationId`, the
  /// request attribute) or with [clientRegistrationId].
  bool enabled = true;

  /// The registration whose token calls that name none send. None by
  /// default: every call to any host would carry this token, so set it
  /// only when the application calls nothing else.
  String? clientRegistrationId;
}
