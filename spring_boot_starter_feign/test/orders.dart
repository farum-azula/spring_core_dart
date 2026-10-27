// Event stream clients as an application writes them, with the code the
// generator writes for them (see catalog.dart).
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

class OrderEvent {
  const OrderEvent({required this.id, required this.status});
  final int id;
  final String status;
}

@FeignClient('orders', url: 'http://orders.test')
abstract interface class OrdersClient {
  @GetMapping('/shops/{shop}/orders/events')
  EventStream<OrderEvent> events(@PathVariable() String shop);

  @GetMapping('/ticks')
  Stream<String> ticks();
}

@FeignClient('news', url: 'http://news.test', fallback: NewsFallback)
abstract interface class NewsClient {
  @GetMapping('/news')
  EventStream<String> news();
}

class NewsFallback implements NewsClient {
  @override
  EventStream<String> news() => EventStream.fromIterable(['offline']);
}

@FeignClient('badStream', url: 'http://bad.test')
abstract interface class BadStreamClient {
  @GetMapping('/later')
  Future<EventStream<String>> later();

  @GetMapping('/now')
  String now();
}

// ---- generated ----

final orderEventIntrospection = BeanIntrospection<OrderEvent>(
  properties: [
    BeanProperty<OrderEvent>(
      'id',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (e) => e.id,
    ),
    BeanProperty<OrderEvent>(
      'status',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (e) => e.status,
    ),
  ],
  constructor: BeanConstructor<OrderEvent>(
    parameters: const [
      BeanParameter(
        'id',
        type: ClassType<int>(),
        symbol: #id,
        isRequired: true,
      ),
      BeanParameter(
        'status',
        type: ClassType<String>(),
        symbol: #status,
        isRequired: true,
      ),
    ],
    create: (positional, named) =>
        Function.apply(OrderEvent.new, positional, named) as OrderEvent,
  ),
);

class OrdersClientImpl implements OrdersClient {
  OrdersClientImpl(this._handler, this._metadata);

  static OrdersClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<OrdersClient>(
      typeName: 'OrdersClient',
      annotations: const [FeignClient('orders', url: 'http://orders.test')],
      methods: [
        ProxyMethod(
          'events',
          parameters: const [
            BeanParameter(
              'shop',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [PathVariable()],
            ),
          ],
          returnType: const GenericType<EventStream<OrderEvent>>([
            ClassType<OrderEvent>(),
          ]),
          annotations: const [GetMapping('/shops/{shop}/orders/events')],
          call: (target, arguments) =>
              (target as OrdersClient).events(arguments[0]! as String),
        ),
        ProxyMethod(
          'ticks',
          returnType: const GenericType<Stream<String>>([ClassType<String>()]),
          annotations: const [GetMapping('/ticks')],
          call: (target, arguments) => (target as OrdersClient).ticks(),
        ),
      ],
    );
    return OrdersClientImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<OrdersClient> _metadata;

  @override
  EventStream<OrderEvent> events(String shop) =>
      _handler.invoke(_metadata.methods[0], [shop])! as EventStream<OrderEvent>;

  @override
  Stream<String> ticks() =>
      _handler.invoke(_metadata.methods[1], const [])! as Stream<String>;
}

class NewsClientImpl implements NewsClient {
  NewsClientImpl(this._handler, this._metadata);

  static NewsClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<NewsClient>(
      typeName: 'NewsClient',
      annotations: const [
        FeignClient('news', url: 'http://news.test', fallback: NewsFallback),
      ],
      methods: [
        ProxyMethod(
          'news',
          returnType: const GenericType<EventStream<String>>([
            ClassType<String>(),
          ]),
          annotations: const [GetMapping('/news')],
          call: (target, arguments) => (target as NewsClient).news(),
        ),
      ],
    );
    return NewsClientImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<NewsClient> _metadata;

  @override
  EventStream<String> news() =>
      _handler.invoke(_metadata.methods[0], const [])! as EventStream<String>;
}

class BadStreamClientImpl implements BadStreamClient {
  BadStreamClientImpl(this._handler, this._metadata);

  static BadStreamClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<BadStreamClient>(
      typeName: 'BadStreamClient',
      annotations: const [FeignClient('badStream', url: 'http://bad.test')],
      methods: [
        ProxyMethod(
          'later',
          returnType: const GenericType<EventStream<String>>([
            ClassType<String>(),
          ]),
          isFuture: true,
          annotations: const [GetMapping('/later')],
          call: (target, arguments) => (target as BadStreamClient).later(),
        ),
        ProxyMethod(
          'now',
          returnType: const ClassType<String>(),
          annotations: const [GetMapping('/now')],
          call: (target, arguments) => (target as BadStreamClient).now(),
        ),
      ],
    );
    return BadStreamClientImpl(
      InterfaceProxies.handlerFor(r, metadata),
      metadata,
    );
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<BadStreamClient> _metadata;

  @override
  Future<EventStream<String>> later() => retypeFuture<EventStream<String>>(
    _handler.invoke(_metadata.methods[0], const []),
  );

  @override
  String now() => _handler.invoke(_metadata.methods[1], const [])! as String;
}

/// The event stream clients and the fallback bean.
final ordersModule = BeanModule(
  'orders',
  [
    BeanDefinition<OrdersClient>(
      name: 'ordersClient',
      primary: true,
      create: OrdersClientImpl.$create,
    ),
    BeanDefinition<NewsClient>(
      name: 'newsClient',
      primary: true,
      create: NewsClientImpl.$create,
    ),
    BeanDefinition<NewsFallback>(
      name: 'newsFallback',
      types: const [NewsFallback, NewsClient],
      create: (_) => NewsFallback(),
    ),
  ],
  introspections: [orderEventIntrospection],
);

/// A module with invalid event stream methods.
final badStreamModule = BeanModule('badStream', [
  BeanDefinition<BadStreamClient>(
    name: 'badStreamClient',
    primary: true,
    create: BadStreamClientImpl.$create,
  ),
]);
