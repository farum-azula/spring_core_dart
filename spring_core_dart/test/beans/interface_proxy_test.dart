import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

@InterfaceProxy()
class Remote {
  const Remote(this.name);
  final String name;
}

abstract interface class Greeter {
  Future<String> greet(String name, {String greeting = 'Hello'});
  int count();
}

// What the generator writes for Greeter.
class _GreeterImpl implements Greeter {
  _GreeterImpl(this._handler, this._metadata);

  static _GreeterImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<Greeter>(
      typeName: 'Greeter',
      annotations: const [Remote('greetings')],
      methods: [
        ProxyMethod(
          'greet',
          parameters: const [
            BeanParameter('name', type: ClassType<String>(), isRequired: true),
            BeanParameter(
              'greeting',
              type: ClassType<String>(),
              symbol: #greeting,
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          call: (target, arguments) => (target as Greeter).greet(
            arguments[0]! as String,
            greeting: arguments[1]! as String,
          ),
        ),
        ProxyMethod(
          'count',
          returnType: const ClassType<int>(),
          call: (target, arguments) => (target as Greeter).count(),
        ),
      ],
    );
    return _GreeterImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<Greeter> _metadata;

  @override
  Future<String> greet(String name, {String greeting = 'Hello'}) =>
      retypeFuture<String>(
        _handler.invoke(_metadata.methods[0], [name, greeting]),
      );

  @override
  int count() => _handler.invoke(_metadata.methods[1], const [])! as int;
}

class LocalGreeter implements Greeter {
  @override
  Future<String> greet(String name, {String greeting = 'Hello'}) async =>
      '$greeting, $name (local)';

  @override
  int count() => 0;
}

final class RemoteHandlers implements InvocationHandlerFactory {
  final calls = <String>[];

  @override
  bool supports(InterfaceMetadata<Object> metadata) =>
      metadata.annotation<Remote>() != null;

  @override
  InvocationHandler create(InterfaceMetadata<Object> metadata) =>
      _Handler(metadata, calls);
}

final class _Handler implements InvocationHandler {
  _Handler(this.metadata, this.calls);
  final InterfaceMetadata<Object> metadata;
  final List<String> calls;

  @override
  Object? invoke(ProxyMethod method, List<Object?> arguments) {
    calls.add('${metadata.annotation<Remote>()!.name}.${method.name}');
    return switch (method.name) {
      'greet' => Future.value('${arguments[1]}, ${arguments[0]}'),
      _ => calls.length,
    };
  }
}

void main() {
  final greeter = BeanDefinition<Greeter>(
    name: 'greeter',
    create: _GreeterImpl.$create,
  );

  test(
    'a generated implementation gets its handler from a factory bean',
    () async {
      final handlers = RemoteHandlers();
      final context = AnnotationConfigApplicationContext([
        BeanModule('app', [
          greeter,
          BeanDefinition<RemoteHandlers>(
            name: 'remoteHandlers',
            types: const [RemoteHandlers, InvocationHandlerFactory],
            create: (_) => handlers,
          ),
        ]),
      ])..refresh();
      final bean = context.getBean<Greeter>();
      expect(await bean.greet('Ada'), 'Hello, Ada');
      expect(await bean.greet('Ada', greeting: 'Hi'), 'Hi, Ada');
      expect(bean.count(), 3);
      expect(handlers.calls, [
        'greetings.greet',
        'greetings.greet',
        'greetings.count',
      ]);
      context.close();
    },
  );

  test(
    'ProxyMethod.callOn calls the same method on another implementation',
    () async {
      final handlers = RemoteHandlers();
      final context = AnnotationConfigApplicationContext([
        BeanModule('app', [
          greeter,
          BeanDefinition<RemoteHandlers>(
            name: 'remoteHandlers',
            types: const [RemoteHandlers, InvocationHandlerFactory],
            create: (_) => handlers,
          ),
        ]),
      ])..refresh();
      final proxy = context.getBean<Greeter>() as _GreeterImpl;
      final greet = proxy._metadata.methods.first;
      expect(
        await (greet.callOn(LocalGreeter(), ['Ada', 'Hey'])! as Future<String>),
        'Hey, Ada (local)',
      );
      context.close();
    },
  );

  test('a missing factory names the interface and its annotation', () {
    final context = AnnotationConfigApplicationContext([
      BeanModule('app', [greeter]),
    ]);
    expect(
      context.refresh,
      throwsA(
        predicate(
          (Object error) => '$error'.contains(
            'No InvocationHandlerFactory bean supports Greeter',
          ),
        ),
      ),
    );
  });
}
