import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The `spring.feign.oauth2.*` properties: Feign clients that send the
/// access token of an OAuth2 client registration.
@ConfigurationProperties('spring.feign.oauth2')
class FeignOAuth2Properties {
  /// Whether Feign clients send the access token of an OAuth2 client
  /// registration.
  bool enabled = false;

  /// The registration whose token Feign clients send; without it the Feign
  /// client's name is the registration id.
  String? clientRegistrationId;
}
