import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_feign/src/feign_client_config.dart';
import 'package:spring_boot_starter_feign/src/feign_client_factory.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _source = 'package:spring_boot_starter_feign#FeignAutoConfiguration';

/// The beans of the Feign starter, like Spring Cloud OpenFeign's
/// `FeignAutoConfiguration`:
///
/// - `httpTransport` — `platformHttpTransport()` (`dart:io` on the VM and
///   in Flutter, `fetch` on the web), when the application declares no
///   [HttpTransport]; connection timeout from
///   `spring.cloud.openfeign.client.config.default.connect-timeout`;
/// - `feignClientFactory` — creates the client implementations with the
///   `ObjectMapper`, the transport and the `RequestInterceptor`,
///   `ErrorDecoder` and `Retryer` beans (per client: see
///   `FeignClient.configuration`).
final feignAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<HttpTransport>(
    name: 'httpTransport',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'httpTransport',
    source: _source,
    conditions: const [
      ConditionGroup(_source, [ConditionalOnMissingBean(HttpTransport)]),
    ],
    create: (r) => platformHttpTransport(
      connectTimeout: FeignClientConfig.connectTimeout(
        r.dependency<Environment>(),
      ),
    ),
    destroyMethod: (transport) => transport.close(),
  ),
  BeanDefinition<FeignClientFactory>(
    name: 'feignClientFactory',
    source: _source,
    types: const [FeignClientFactory, InvocationHandlerFactory],
    // The RequestInterceptor, ErrorDecoder and Retryer beans are looked
    // up per client (see FeignClientFactory): those of a client's
    // `configuration:` classes belong to that client only.
    create: (r) => FeignClientFactory(
      environment: r.dependency<Environment>(),
      mapper:
          r.optionalDependency<ObjectMapper>() ??
          ObjectMapper(introspector: r.dependency<BeanIntrospector>()),
      transport: r.dependency<HttpTransport>(),
    ),
  ),
];
