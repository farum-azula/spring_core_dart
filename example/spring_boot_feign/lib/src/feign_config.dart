// Beans the Feign starter picks up: every RequestInterceptor changes every
// request; a Retryer retries connection errors and timeouts.
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

@Configuration()
class FeignConfig {
  /// Every request says who is calling.
  @Bean()
  RequestInterceptor clientName(
    @Value(r'${spring.application.name}') String application,
  ) => _Header('X-Client', application);

  /// Up to 3 attempts when the network hiccups.
  @Bean()
  Retryer retryer() => const DefaultRetryer(maxAttempts: 3);
}

final class _Header implements RequestInterceptor {
  _Header(this.name, this.value);

  final String name;
  final String value;

  @override
  void apply(RequestTemplate template) => template.header(name, value);
}
