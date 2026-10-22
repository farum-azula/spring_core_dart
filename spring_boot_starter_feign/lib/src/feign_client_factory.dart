import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_feign/src/feign_client.dart';
import 'package:spring_boot_starter_feign/src/feign_client_config.dart';
import 'package:spring_boot_starter_feign/src/feign_exception.dart';
import 'package:spring_boot_starter_feign/src/feign_invocation_handler.dart';
import 'package:spring_boot_starter_feign/src/request_template.dart';
import 'package:spring_boot_starter_feign/src/retryer.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Creates the handlers of `@FeignClient` interfaces (the bean
/// `feignClientFactory` of the starter), with the application's
/// [ObjectMapper], [HttpTransport], [RequestInterceptor]s, [ErrorDecoder]
/// and [Retryer] beans.
///
/// Spring (Java): `FeignClientFactoryBean` with the beans of the client's
/// `FeignContext`.
final class FeignClientFactory
    implements InvocationHandlerFactory, BeanFactoryAware {
  /// A factory using these collaborators.
  FeignClientFactory({
    required this.environment,
    required this.mapper,
    required this.transport,
    this.interceptors = const [],
    this.errorDecoder = const DefaultErrorDecoder(),
    this.retryer = Retryer.never,
  });

  /// Configuration and placeholders.
  final Environment environment;

  /// JSON bodies.
  final ObjectMapper mapper;

  /// Sends the requests.
  final HttpTransport transport;

  /// Applied to every request.
  final List<RequestInterceptor> interceptors;

  /// Error responses → exceptions.
  final ErrorDecoder errorDecoder;

  /// Retries.
  final Retryer retryer;

  BeanFactory? _beanFactory;

  @override
  void setBeanFactory(BeanFactory beanFactory) => _beanFactory = beanFactory;

  @override
  bool supports(InterfaceMetadata<Object> metadata) =>
      metadata.annotation<FeignClient>() != null;

  @override
  InvocationHandler create(InterfaceMetadata<Object> metadata) {
    final client = metadata.annotation<FeignClient>()!;
    final fallbackType = client.fallback;
    Object? fallbackBean;
    return FeignInvocationHandler(
      metadata: metadata,
      client: client,
      config: FeignClientConfig.of(environment, client.name),
      environment: environment,
      mapper: mapper,
      transport: transport,
      interceptors: interceptors,
      errorDecoder: errorDecoder,
      retryer: retryer,
      fallback: fallbackType == null
          ? null
          : () => fallbackBean ??= _fallback(fallbackType, metadata),
    );
  }

  Object _fallback(Type type, InterfaceMetadata<Object> metadata) {
    final factory = _beanFactory;
    if (factory is! ListableBeanFactory) {
      throw StateError('No bean factory to look up the fallback $type');
    }
    final names = factory.getBeanNamesForType(type);
    if (names.isEmpty) {
      throw StateError(
        'The fallback $type of ${metadata.typeName} is not a bean: annotate '
        'it with @Component()',
      );
    }
    final bean = factory.getBeanByName(names.first);
    if (!metadata.isImplementedBy(bean)) {
      throw StateError(
        'The fallback $type must implement ${metadata.typeName}',
      );
    }
    return bean;
  }
}
