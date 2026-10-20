import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/creation_log.dart';

/// A plain object published as an event (a payload).
class OrderPlaced {
  const OrderPlaced(this.id, this.total);

  final int id;
  final int total;
}

/// A classic application event.
class OrderShipped extends ApplicationEvent {
  OrderShipped(super.source, this.id);

  final int id;
}

bool isBigOrder(OrderPlaced order) => order.total >= 100;

@Service()
class OrderService {
  OrderService(this.publisher);

  final ApplicationEventPublisher publisher;

  void place(int id, int total) =>
      publisher.publishEvent(OrderPlaced(id, total));
}

@Component()
class Shipping {
  /// The returned event is published in turn.
  @EventListener()
  OrderShipped onPlaced(OrderPlaced order) {
    creationLog.add('shipping:${order.id}');
    return OrderShipped(this, order.id);
  }

  @EventListener(condition: isBigOrder)
  @Order(1)
  void onBigOrder(OrderPlaced order) => creationLog.add('big:${order.id}');

  @EventListener(classes: [ContextRefreshedEvent, ContextClosedEvent])
  void onContext() => creationLog.add('shipping:context');
}

/// Listener through the interface.
@Component()
class ShipmentAudit implements ApplicationListener<OrderShipped> {
  @override
  void onApplicationEvent(OrderShipped event) =>
      creationLog.add('audit:${event.id}');
}
