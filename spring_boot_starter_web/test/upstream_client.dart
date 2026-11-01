// A Feign client as an application writes it, with the code the generator
// writes for it, so the tests need no code generation: the service the
// controllers of request_timeout_test.dart call.
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

@FeignClient('upstream', url: '')
abstract interface class UpstreamClient {
  @GetMapping('/work')
  Future<String> work();
}

// ---- generated ----

class UpstreamClientImpl implements UpstreamClient {
  UpstreamClientImpl(this._handler, this._metadata);

  static UpstreamClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<UpstreamClient>(
      typeName: 'UpstreamClient',
      annotations: const [FeignClient('upstream', url: '')],
      methods: [
        ProxyMethod(
          'work',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/work')],
          call: (target, arguments) => (target as UpstreamClient).work(),
        ),
      ],
    );
    return UpstreamClientImpl(
      InterfaceProxies.handlerFor(r, metadata),
      metadata,
    );
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<UpstreamClient> _metadata;

  @override
  Future<String> work() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[0], const []));
}

/// The client bean, as the generator registers it.
final upstreamModule = BeanModule('upstream', [
  BeanDefinition<UpstreamClient>(
    name: 'upstreamClient',
    primary: true,
    create: UpstreamClientImpl.$create,
  ),
]);
