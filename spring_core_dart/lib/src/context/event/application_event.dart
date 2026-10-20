/// Base class of application events, like Spring's `ApplicationEvent`.
///
/// Extending it is optional: any object can be published and is then
/// wrapped in a [PayloadApplicationEvent].
///
/// ```dart
/// class OrderShipped extends ApplicationEvent {
///   OrderShipped(super.source, this.id);
///   final int id;
/// }
///
/// context.publishEvent(OrderShipped(this, 42));
/// ```
///
/// Spring (Java):
/// ```java
/// class OrderShipped extends ApplicationEvent {
///   OrderShipped(Object source, int id) { super(source); this.id = id; }
///   final int id;
/// }
///
/// context.publishEvent(new OrderShipped(this, 42));
/// ```
abstract class ApplicationEvent {
  /// Creates an event raised by [source]; [timestamp] defaults to now.
  ApplicationEvent(this.source, {DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  /// The object the event originated from.
  final Object source;

  /// When the event was created.
  final DateTime timestamp;

  @override
  String toString() => '$runtimeType[source=$source]';
}

/// Wraps an arbitrary published object, like Spring's
/// `PayloadApplicationEvent`. Listeners for the payload type receive the
/// payload itself.
///
/// The context creates it for you; listen to the payload type directly.
///
/// ```dart
/// context.addListener<OrderPlaced>((order) => print(order.id));
/// context.publishEvent(OrderPlaced(1, 20)); // wrapped automatically
///
/// // Listeners of the wrapper see the source too:
/// context.addListener<PayloadApplicationEvent<Object>>(
///   (event) => print('${event.payload} from ${event.source}'),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// context.publishEvent(new OrderPlaced(1, 20));
///
/// @EventListener
/// void on(PayloadApplicationEvent<OrderPlaced> event) { ... }
/// ```
class PayloadApplicationEvent<T extends Object> extends ApplicationEvent {
  /// Creates an event carrying [payload], published by [source].
  PayloadApplicationEvent(super.source, this.payload);

  /// The published object.
  final T payload;

  @override
  String toString() => 'PayloadApplicationEvent[payload=$payload]';
}
