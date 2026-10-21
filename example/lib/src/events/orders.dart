// Events: payload events, ApplicationEvent subclasses, @EventListener
// (condition, @Order, classes, returned events), ApplicationListener.
//
// Spring (Java): ApplicationEventPublisher, @EventListener, ApplicationListener.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/tour_log.dart';

/// A plain object published as an event (wrapped in a payload event).
class OrderPlaced {
  const OrderPlaced(this.id, this.total);
  final int id;
  final double total;
}

/// A classic ApplicationEvent.
class OrderShipped extends ApplicationEvent {
  OrderShipped(super.source, this.id);
  final int id;
}

bool isBigOrder(OrderPlaced order) => order.total >= 100;

@Service()
class OrderService {
  OrderService(this.publisher);

  final ApplicationEventPublisher publisher;

  void place(int id, double total) =>
      publisher.publishEvent(OrderPlaced(id, total));
}

@Component()
class Shipping {
  /// The returned event is published in turn.
  @EventListener()
  @Order(2)
  OrderShipped onPlaced(OrderPlaced order) {
    tourLog.add('shipping: order ${order.id}');
    return OrderShipped(this, order.id);
  }

  /// Runs first (@Order(1)) and only for big orders.
  @EventListener(condition: isBigOrder)
  @Order(1)
  void onBigOrder(OrderPlaced order) =>
      tourLog.add('vip desk: big order ${order.id}');

  @EventListener(classes: [ContextRefreshedEvent, ContextClosedEvent])
  void onContext(ApplicationEvent event) =>
      tourLog.add('shipping: ${event.runtimeType}');
}

@Component()
class ShipmentNotifier implements ApplicationListener<OrderShipped> {
  @override
  void onApplicationEvent(OrderShipped event) =>
      tourLog.add('notifier: order ${event.id} shipped');
}
