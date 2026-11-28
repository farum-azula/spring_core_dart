import 'package:spring_web_dart/spring_web_dart.dart';

/// The request attributes the OAuth2 client reads on a `RestClient` call:
/// which registration's token `OAuth2ClientHttpRequestInterceptor` sends.
///
/// ```dart
/// final orders = await rest.get()
///     .uri('/orders')
///     .attributes(ClientAttributes.clientRegistrationId('partner'))
///     .retrieve()
///     .body<String>();
/// ```
///
/// On an HTTP service interface, `@ClientRegistrationId('partner')` sets
/// the same attribute.
///
/// Spring Security (Java): `ClientAttributes`
/// (`org.springframework.security.oauth2.client.web.client`).
abstract final class ClientAttributes {
  /// The name of the attribute that holds the registration id.
  static const String clientRegistrationIdAttributeName =
      'ClientRegistration.clientRegistrationId';

  /// Sets the registration id [clientRegistrationId] in the attributes it
  /// is given: the argument of `RequestHeadersSpec.attributes`.
  static void Function(Map<String, Object?> attributes) clientRegistrationId(
    String clientRegistrationId,
  ) =>
      (attributes) =>
          attributes[clientRegistrationIdAttributeName] = clientRegistrationId;

  /// The registration id in [attributes], or `null` when there is none (or
  /// it is blank).
  static String? resolveClientRegistrationId(Map<String, Object?> attributes) =>
      switch (attributes[clientRegistrationIdAttributeName]) {
        final String id when id.trim().isNotEmpty => id.trim(),
        _ => null,
      };
}

/// Names the OAuth2 registration whose access token the calls of an HTTP
/// service interface (on the interface) or of one method carry: the
/// generated call sets [ClientAttributes.clientRegistrationIdAttributeName]
/// to [registrationId], and `OAuth2ClientHttpRequestInterceptor` sends that
/// registration's token.
///
/// ```dart
/// @HttpExchange('/orders')
/// @ClientRegistrationId('partner')
/// abstract interface class OrderService {
///   @GetExchange()
///   Future<List<Order>> all();
/// }
/// ```
///
/// Spring Security (Java): `@ClientRegistrationId`
/// (`org.springframework.security.oauth2.client.annotation`).
class ClientRegistrationId extends HttpRequestAttribute {
  /// The registration [registrationId].
  const ClientRegistrationId(this.registrationId)
    : super(ClientAttributes.clientRegistrationIdAttributeName, registrationId);

  /// The registration's id (`spring.security.oauth2.client.registration.<id>`).
  final String registrationId;
}
