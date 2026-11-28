// What every supplier call gets (chapter 9): the `supplier` group of HTTP
// services (its base URL and timeouts in spring.http.serviceclient.supplier.*),
// and an API key and the application's name in headers (an interceptor on
// the group's RestClient).
import 'package:neon_books_server/src/supplier/supplier_clients.dart';
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

/// `neon.supplier.*`, from config/supplier.properties (imported) and its
/// dev variant; the key comes from the environment in prod.
@ConfigurationProperties('neon.supplier')
class SupplierProperties {
  String url = '';
  String apiKey = '';
}

@Configuration()
@ImportHttpServices(
  group: 'supplier',
  types: [SupplierOffers, SupplierDeliveries],
)
class SupplierClientConfig {
  /// The headers on every call of the `supplier` group, after its
  /// properties are applied.
  @Bean()
  RestClientHttpServiceGroupConfigurer supplierHeaders(
    SupplierProperties supplier,
    @Value(r'${spring.application.name}') String application,
  ) => RestClientHttpServiceGroupConfigurer.of(
    (groups) => groups
        .filterByName(['supplier'])
        .forEachClient(
          (group, builder) => builder.requestInterceptor(
            SupplierHeaders(application, supplier.apiKey),
          ),
        ),
  );
}

/// The application's name and the API key (masked in the request log, as
/// every `X-Api-Key`).
final class SupplierHeaders implements ClientHttpRequestInterceptor {
  SupplierHeaders(this.application, this.apiKey);

  final String application;
  final String apiKey;

  @override
  Future<HttpResponse> intercept(
    HttpRequest request,
    List<int>? body,
    ClientHttpRequestExecution execution,
  ) {
    request.headers
      ..set('X-Client', application)
      ..set('X-Api-Key', apiKey);
    return execution.execute(request, body);
  }
}
