// What every supplier call gets (chapter 9): an API key and the
// application's name in headers (a RequestInterceptor), and retries of
// failed connections (a Retryer).
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// `neon.supplier.*`, from config/supplier.properties (imported) and its
/// dev variant; the key comes from the environment in prod.
@ConfigurationProperties('neon.supplier')
class SupplierProperties {
  String url = '';
  String apiKey = '';
}

@Configuration()
class SupplierClientConfig {
  @Bean()
  RequestInterceptor supplierHeaders(
    SupplierProperties supplier,
    @Value(r'${spring.application.name}') String application,
  ) => SupplierHeaders(application, supplier.apiKey);

  /// Up to 3 attempts when the connection fails or times out.
  @Bean()
  Retryer supplierRetryer() => const DefaultRetryer(maxAttempts: 3);
}

final class SupplierHeaders implements RequestInterceptor {
  SupplierHeaders(this.application, this.apiKey);

  final String application;
  final String apiKey;

  @override
  void apply(RequestTemplate template) {
    template.header('X-Client', application);
    if (template.clientName.startsWith('supplier')) {
      template.header('X-Api-Key', apiKey);
    }
  }
}
