// Clients with per-client configuration classes, written as an
// application writes them, with the code the generator writes for them.
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

@FeignClient(
  'inventory',
  url: 'http://inventory.test',
  configuration: [InventoryFeignConfig],
)
abstract interface class InventoryClient {
  @GetMapping('/ping')
  Future<String> ping();
}

@FeignClient('plain', url: 'plain.test')
abstract interface class PlainClient {
  @GetMapping('/ping')
  Future<String> ping();

  @GetMapping('/items?type=a%20b&flag')
  Future<String> items(@RequestParam('page') int page);
}

@FeignClient('fromProperty', url: '')
abstract interface class PropertyUrlClient {
  @GetMapping('/ping')
  Future<String> ping();
}

/// Only for `InventoryClient` (`@FeignClient(configuration:)`).
@Configuration()
class InventoryFeignConfig {
  @Bean()
  RequestInterceptor inventoryAuth() =>
      BasicAuthRequestInterceptor('stock', 'pässword');

  @Bean()
  Retryer inventoryRetryer() =>
      const DefaultRetryer(period: Duration(milliseconds: 1), maxAttempts: 2);

  @Bean()
  ErrorDecoder inventoryErrors() => const InventoryErrorDecoder();
}

final class InventoryErrorDecoder implements ErrorDecoder {
  const InventoryErrorDecoder();

  @override
  Exception decode(String methodKey, HttpResponse response) =>
      InventoryException(response.statusCode);
}

final class InventoryException implements Exception {
  InventoryException(this.status);
  final int status;
}

final class TraceInterceptor implements RequestInterceptor {
  @override
  void apply(RequestTemplate template) =>
      template.header('X-Trace', template.clientName);
}

final class AuditInterceptor implements RequestInterceptor {
  @override
  void apply(RequestTemplate template) => template.header('X-Audit', 'yes');
}

final class FastRetryer extends DefaultRetryer {
  const FastRetryer()
    : super(period: const Duration(milliseconds: 1), maxAttempts: 3);
}

// ---- generated ----

class InventoryClientImpl implements InventoryClient {
  InventoryClientImpl(this._handler, this._metadata);

  static InventoryClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<InventoryClient>(
      typeName: 'InventoryClient',
      annotations: _inventoryAnnotations,
      methods: [
        ProxyMethod(
          'ping',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/ping')],
          call: (target, arguments) => (target as InventoryClient).ping(),
        ),
      ],
    );
    return InventoryClientImpl(
      InterfaceProxies.handlerFor(r, metadata),
      metadata,
    );
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<InventoryClient> _metadata;

  @override
  Future<String> ping() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[0], const []));
}

const _inventoryAnnotations = [
  FeignClient(
    'inventory',
    url: 'http://inventory.test',
    configuration: [InventoryFeignConfig],
  ),
];

class PlainClientImpl implements PlainClient {
  PlainClientImpl(this._handler, this._metadata);

  static PlainClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<PlainClient>(
      typeName: 'PlainClient',
      annotations: const [FeignClient('plain', url: 'plain.test')],
      methods: [
        ProxyMethod(
          'ping',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/ping')],
          call: (target, arguments) => (target as PlainClient).ping(),
        ),
        ProxyMethod(
          'items',
          parameters: const [
            BeanParameter(
              'page',
              type: ClassType<int>(),
              isRequired: true,
              annotations: [RequestParam('page')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/items?type=a%20b&flag')],
          call: (target, arguments) =>
              (target as PlainClient).items(arguments[0]! as int),
        ),
      ],
    );
    return PlainClientImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<PlainClient> _metadata;

  @override
  Future<String> ping() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[0], const []));

  @override
  Future<String> items(int page) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[1], [page]));
}

class PropertyUrlClientImpl implements PropertyUrlClient {
  PropertyUrlClientImpl(this._handler, this._metadata);

  static PropertyUrlClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<PropertyUrlClient>(
      typeName: 'PropertyUrlClient',
      annotations: const [FeignClient('fromProperty', url: '')],
      methods: [
        ProxyMethod(
          'ping',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/ping')],
          call: (target, arguments) => (target as PropertyUrlClient).ping(),
        ),
      ],
    );
    return PropertyUrlClientImpl(
      InterfaceProxies.handlerFor(r, metadata),
      metadata,
    );
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<PropertyUrlClient> _metadata;

  @override
  Future<String> ping() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[0], const []));
}

const _configSource =
    'package:test/client_configuration.dart#'
    'InventoryFeignConfig';

/// The clients and the configuration class, as the generator registers
/// them (client definitions carry their annotations).
final clientConfigurationModule = BeanModule('clientConfiguration', [
  BeanDefinition<InventoryClient>(
    name: 'inventoryClient',
    primary: true,
    create: InventoryClientImpl.$create,
    annotations: _inventoryAnnotations,
  ),
  BeanDefinition<PlainClient>(
    name: 'plainClient',
    primary: true,
    create: PlainClientImpl.$create,
    annotations: const [FeignClient('plain', url: 'plain.test')],
  ),
  BeanDefinition<InventoryFeignConfig>(
    name: 'inventoryFeignConfig',
    source: _configSource,
    create: (_) => InventoryFeignConfig(),
    annotations: const [Configuration()],
  ),
  BeanDefinition<RequestInterceptor>(
    name: 'inventoryAuth',
    source: '$_configSource.inventoryAuth',
    factoryBeanName: 'inventoryFeignConfig',
    factoryMethodName: 'inventoryAuth',
    create: (r) => r.dependency<InventoryFeignConfig>().inventoryAuth(),
  ),
  BeanDefinition<Retryer>(
    name: 'inventoryRetryer',
    source: '$_configSource.inventoryRetryer',
    factoryBeanName: 'inventoryFeignConfig',
    factoryMethodName: 'inventoryRetryer',
    create: (r) => r.dependency<InventoryFeignConfig>().inventoryRetryer(),
  ),
  // A static @Bean method: no factoryBeanName, known by its source.
  BeanDefinition<ErrorDecoder>(
    name: 'inventoryErrors',
    source: '$_configSource.inventoryErrors',
    create: (r) => r.dependency<InventoryFeignConfig>().inventoryErrors(),
  ),
]);

final propertyUrlModule = BeanModule('propertyUrl', [
  BeanDefinition<PropertyUrlClient>(
    name: 'propertyUrlClient',
    primary: true,
    create: PropertyUrlClientImpl.$create,
  ),
]);
