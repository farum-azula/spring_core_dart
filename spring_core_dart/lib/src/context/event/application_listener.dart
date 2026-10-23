import 'package:spring_core_dart/src/context/event/application_event.dart';
import 'package:spring_core_dart/src/context/event/event_listener_method.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// Publishes events, like Spring's `ApplicationEventPublisher`.
///
/// Objects that are not `ApplicationEvent`s are wrapped in a
/// `PayloadApplicationEvent`; listeners of the payload type receive the
/// payload itself. Every application context is a publisher and can be
/// injected as one.
///
/// ```dart
/// @Service()
/// class OrderService {
///   OrderService(this.publisher);
///   final ApplicationEventPublisher publisher;
///
///   void place(int id, int total) =>
///       publisher.publishEvent(OrderPlaced(id, total));
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class OrderService {
///   OrderService(ApplicationEventPublisher publisher) { ... }
///
///   void place(int id, int total) {
///     publisher.publishEvent(new OrderPlaced(id, total));
///   }
/// }
/// ```
abstract interface class ApplicationEventPublisher {
  /// Notifies all matching listeners of [event] (synchronously).
  void publishEvent(Object event);
}

/// A listener bean, like Spring's `ApplicationListener`.
///
/// The generator wires beans that implement it; for listeners added in
/// code use `ApplicationListenerAdapter.of`.
///
/// ```dart
/// @Component()
/// class ShipmentAudit implements ApplicationListener<OrderShipped> {
///   @override
///   void onApplicationEvent(OrderShipped event) => print(event.id);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class ShipmentAudit implements ApplicationListener<OrderShipped> {
///   public void onApplicationEvent(OrderShipped event) { ... }
/// }
/// ```
abstract interface class ApplicationListener<E extends Object> {
  /// Handles an event of type [E].
  void onApplicationEvent(E event);
}

/// A listener that decides at runtime which events it handles, like
/// Spring's `GenericApplicationListener`.
///
/// This is the form the multicaster works with; typed listeners and
/// `@EventListener` methods are adapted to it.
///
/// ```dart
/// class AuditAll implements GenericApplicationListener {
///   @override
///   bool supportsEvent(Object event) => event is! ContextRefreshedEvent;
///
///   @override
///   void onApplicationEvent(Object event) => print('audit: $event');
/// }
///
/// context.addApplicationListener(AuditAll());
/// ```
///
/// Spring (Java):
/// ```java
/// class AuditAll implements GenericApplicationListener {
///   public boolean supportsEventType(ResolvableType type) { ... }
///   public void onApplicationEvent(ApplicationEvent event) { ... }
/// }
/// ```
///
/// Unlike Spring the decision is made on the event instance, not on its
/// `ResolvableType`.
abstract interface class GenericApplicationListener {
  /// Whether [event] should be passed to [onApplicationEvent].
  bool supportsEvent(Object event);

  /// Handles an [event] that [supportsEvent] accepted.
  void onApplicationEvent(Object event);
}

/// A [GenericApplicationListener] deciding by the event's and source's
/// runtime types, with an order, like Spring's `SmartApplicationListener`.
///
/// Mix it in (`with SmartApplicationListener`) for the defaults: every
/// source type, lowest precedence. Beans and `registerSingleton` objects
/// of this type (as of any [GenericApplicationListener]) receive events.
///
/// ```dart
/// @Component()
/// class ContextAudit with SmartApplicationListener {
///   @override
///   bool supportsEventType(Type eventType) =>
///       eventType == ContextRefreshedEvent || eventType == ContextClosedEvent;
///
///   @override
///   void onApplicationEvent(Object event) => print(event);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class ContextAudit implements SmartApplicationListener {
///   public boolean supportsEventType(Class<? extends ApplicationEvent> t) {
///     return t == ContextRefreshedEvent.class || t == ContextClosedEvent.class;
///   }
///   public void onApplicationEvent(ApplicationEvent event) { ... }
/// }
/// ```
///
/// A payload is seen as its `PayloadApplicationEvent`; override
/// [supportsEvent] to decide on the instance instead.
abstract mixin class SmartApplicationListener
    implements GenericApplicationListener, Ordered {
  /// Whether events of the runtime type [eventType] are handled.
  bool supportsEventType(Type eventType);

  /// Whether events from sources of the runtime type [sourceType] are
  /// handled; `true` by default. Non-`ApplicationEvent` objects are their
  /// own source.
  bool supportsSourceType(Type sourceType) => true;

  @override
  bool supportsEvent(Object event) =>
      supportsEventType(event.runtimeType) &&
      supportsSourceType(
        (event is ApplicationEvent ? event.source : event).runtimeType,
      );

  @override
  int get order => Ordered.lowestPrecedence;
}

/// Adapts a function to [GenericApplicationListener] for events (or
/// payloads) of type [E].
///
/// ```dart
/// context.addApplicationListener(
///   ApplicationListenerAdapter.of<OrderPlaced>((o) => print(o.id), order: 1),
/// );
/// context.addApplicationListener(
///   ApplicationListenerAdapter.forListener(ShipmentAudit()),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// context.addApplicationListener(
///     ApplicationListener.forPayload((OrderPlaced o) -> ...));
/// context.addApplicationListener(new ShipmentAudit());
/// ```
final class ApplicationListenerAdapter<E>
    implements GenericApplicationListener, Ordered {
  ApplicationListenerAdapter._(this._handler, this.order);

  /// A listener for [E] events or payloads.
  static ApplicationListenerAdapter<E> of<E>(
    void Function(E event) handler, {
    int order = Ordered.lowestPrecedence,
  }) => ApplicationListenerAdapter<E>._(handler, order);

  /// Wraps an [ApplicationListener]; [order] defaults to the listener's
  /// own `Ordered.order` (lowest precedence when it is not [Ordered]).
  static ApplicationListenerAdapter<E> forListener<E extends Object>(
    ApplicationListener<E> listener, {
    int? order,
  }) => ApplicationListenerAdapter<E>._(
    listener.onApplicationEvent,
    order ?? OrderComparator.orderOf(listener),
  );

  final void Function(E event) _handler;

  /// Position among listeners; lower values run first.
  @override
  final int order;

  /// Whether [event] is an [E] or a payload event carrying an [E].
  @override
  bool supportsEvent(Object event) =>
      EventListenerMethod.unwrap<E>(event) != null;

  /// Calls the handler with the event or its payload.
  @override
  void onApplicationEvent(Object event) =>
      _handler(EventListenerMethod.unwrap<E>(event)!.value);
}

/// Handle returned when a listener is added; call [remove] to unsubscribe.
///
/// ```dart
/// final registration = context.addListener<String>(print);
/// registration.remove();
/// assert(registration.isRemoved);
/// ```
///
/// Spring (Java) has no handle; keep the listener and remove it:
/// ```java
/// context.removeApplicationListener(listener);
/// ```
final class ListenerRegistration {
  /// Creates a registration that runs the removal callback once.
  ListenerRegistration(this._remove);

  final void Function() _remove;
  bool _removed = false;

  /// Whether [remove] has been called.
  bool get isRemoved => _removed;

  /// Unsubscribes the listener; later calls do nothing.
  void remove() {
    if (!_removed) {
      _removed = true;
      _remove();
    }
  }
}
