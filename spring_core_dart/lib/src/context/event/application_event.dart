/// An optional base class for application events: it records which object
/// raised the event and when.
///
/// An event is a message that one part of an application publishes and
/// any number of listeners receive. Extending this class is optional: any
/// object can be published, and the context then wraps it in a
/// [PayloadApplicationEvent]. Extend it when listeners need the [source]
/// and [timestamp]; a plain class (or a record) is enough otherwise. The
/// context's own events (`ContextRefreshedEvent`, ...) extend it.
///
/// ```dart
/// // Raised by the shipping service, with the order id.
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
  /// Creates an event raised by [source]; [timestamp] defaults to the
  /// current time.
  ApplicationEvent(this.source, {DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  /// The object that raised the event, usually the publishing bean (or
  /// the context, for the context's own events).
  final Object source;

  /// When the event was created (not when a listener receives it).
  final DateTime timestamp;

  @override
  String toString() => '$runtimeType[source=$source]';
}

/// The envelope the context puts around a published object that is not an
/// [ApplicationEvent], adding a source and a timestamp.
///
/// You rarely see it: when you publish `OrderPlaced(...)`, listeners of
/// `OrderPlaced` receive the object itself. The context creates the
/// envelope, typed with the static type of the published object. Listen to
/// `PayloadApplicationEvent<T>` only when you also want the [source] (the
/// context that published it) and the timestamp. An `@EventListener`
/// method (or `ApplicationListener`) of `PayloadApplicationEvent<T>`
/// matches on the payload's runtime type, as in Spring; a listener added
/// with `addListener` matches on the envelope's type argument.
///
/// ```dart
/// context.addListener<OrderPlaced>((order) => log.info(order.id));
/// context.publishEvent(OrderPlaced(1, 20)); // wrapped automatically
///
/// // Listeners of the wrapper see the source too:
/// context.addListener<PayloadApplicationEvent<OrderPlaced>>(
///   (event) => log.info('${event.payload} from ${event.source}'),
/// );
///
/// @EventListener()
/// void on(PayloadApplicationEvent<OrderPlaced> event) { ... }
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
  /// Wraps [payload], published by [source]; [timestamp] defaults to the
  /// current time. The context does this for you.
  PayloadApplicationEvent(super.source, this.payload, {super.timestamp});

  /// The object that was published.
  final T payload;

  @override
  String toString() => 'PayloadApplicationEvent[payload=$payload]';
}
