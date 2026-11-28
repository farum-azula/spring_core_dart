import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client_manager.dart';
import 'package:spring_boot_starter_oauth2_client/src/web/oauth2_client_http_request_interceptor.dart';
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

/// Adds an [OAuth2ClientHttpRequestInterceptor] to the `RestClient` of
/// every HTTP service group, so the interfaces marked
/// `@ClientRegistrationId` send their registration's token. Declare it as
/// a bean (a `RestClientHttpServiceGroupConfigurer`).
///
/// The starter already adds the interceptor to every builder it makes,
/// the groups' included (`spring.security.oauth2.client.restclient.enabled`,
/// on by default); this is for an application that turns that off and
/// wants it on its groups alone, or a manager of its own. A builder that
/// already has an [OAuth2ClientHttpRequestInterceptor] gets no second.
///
/// ```dart
/// @Bean()
/// OAuth2RestClientHttpServiceGroupConfigurer oauth2Groups(
///   OAuth2AuthorizedClientManager manager,
/// ) => OAuth2RestClientHttpServiceGroupConfigurer.from(manager);
/// ```
///
/// Spring Security 7 (Java):
/// `OAuth2RestClientHttpServiceGroupConfigurer.from(manager)`.
final class OAuth2RestClientHttpServiceGroupConfigurer
    implements RestClientHttpServiceGroupConfigurer {
  /// The configurer that adds [interceptor].
  const OAuth2RestClientHttpServiceGroupConfigurer(this.interceptor);

  /// The configurer of an interceptor on [manager].
  factory OAuth2RestClientHttpServiceGroupConfigurer.from(
    OAuth2AuthorizedClientManager manager,
  ) => OAuth2RestClientHttpServiceGroupConfigurer(
    OAuth2ClientHttpRequestInterceptor(manager),
  );

  /// The interceptor added to every group.
  final OAuth2ClientHttpRequestInterceptor interceptor;

  @override
  void configureGroups(HttpServiceGroupBuilders groups) => groups.forEachClient(
    (_, builder) => addInterceptor(builder, interceptor),
  );

  /// Adds [interceptor] to [builder] unless it has an OAuth2 interceptor
  /// already.
  static void addInterceptor(
    RestClientBuilder builder,
    OAuth2ClientHttpRequestInterceptor interceptor,
  ) => builder.requestInterceptors((interceptors) {
    if (!interceptors.any(
      (existing) => existing is OAuth2ClientHttpRequestInterceptor,
    )) {
      interceptors.add(interceptor);
    }
  });
}
