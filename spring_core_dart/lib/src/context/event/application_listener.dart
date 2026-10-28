import 'package:spring_core_dart/src/context/event/application_event.dart';
import 'package:spring_core_dart/src/context/event/event_listener_method.dart';
import 'package:spring_core_dart/src/core/order.dart';

/// Sends an event to every listener interested in it.
///
/// Inject it into a bean that wants to tell the rest of the application
/// that something happened (an order placed, a user signed in) without
/// calling the interested beans itself. Listeners are `@EventListener`
/// methods and listener beans; the publisher does not know them. Every
/// application context is a publisher, and the context registers itself
/// as the bean injected for this type.
///
/// Any object can be an event. One that is not an `ApplicationEvent` is
/// wrapped in a `PayloadApplicationEvent<T>` of its static type `T`, and
/// listeners of `T` receive the object itself.
///
/// ```dart
/// // The service announces each order; shipping and mailing listen.
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
  /// Delivers [event] to every listener that accepts it. By default the
  /// listeners run before this call returns, and a listener error reaches
  /// the caller; with an asynchronous multicaster they run later. An
  /// [event] that is not an `ApplicationEvent` is wrapped in a
  /// `PayloadApplicationEvent<T>`.
  void publishEvent<T extends Object>(T event);
}

/// A bean that listens to one type of event by implementing an interface.
///
/// It does the same as an `@EventListener` method, which is shorter and
/// can live in any bean; implement this interface when a class exists only
/// to listen, or when code ported from Java does. The generator wires
/// beans that implement it (the bean is fetched for each event, so a lazy
/// listener is created by its first event). For a listener object that is
/// not a bean, wrap it with `ApplicationListenerAdapter.forListener`.
///
/// ```dart
/// // Every shipment is written to the audit log.
/// @Component()
/// @Log()
/// class ShipmentAudit implements ApplicationListener<OrderShipped> {
///   @override
///   void onApplicationEvent(OrderShipped event) =>
///       log.info('shipped ${event.id}');
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
  /// Called for each published event of type [E] (or each published
  /// object of type [E]).
  void onApplicationEvent(E event);
}

/// A listener that receives any event and decides at runtime, per event,
/// whether to handle it.
///
/// This is the form the event multicaster works with: `@EventListener`
/// methods, [ApplicationListener] beans and [ApplicationListenerAdapter]s
/// are all adapted to it. Implement it yourself for a listener whose
/// choice is not one type, for example everything except one event. A
/// singleton bean that implements it is registered as a listener when
/// created; an object can also be added with
/// `ConfigurableApplicationContext.addApplicationListener`.
///
/// ```dart
/// // Audits every event except the refresh.
/// class AuditAll implements GenericApplicationListener {
///   @override
///   bool supportsEvent(Object event) => event is! ContextRefreshedEvent;
///
///   @override
///   void onApplicationEvent(Object event) => log.info('audit: $event');
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
  /// Whether [event] should be passed to [onApplicationEvent]; asked for
  /// every published event. A published object that is not an
  /// `ApplicationEvent` arrives here as its `PayloadApplicationEvent`.
  bool supportsEvent(Object event);

  /// Handles an [event] that [supportsEvent] accepted.
  ///
  /// An error thrown here goes to the multicaster's error handler, or to
  /// the publisher when there is none.
  void onApplicationEvent(Object event);
}

/// A [GenericApplicationListener] that decides by the runtime types of the
/// event and its source, and has an order among the listeners.
///
/// Use it for a listener of several event types, or of events from one
/// kind of source. Mix it in (`with SmartApplicationListener`) for the
/// defaults: every source type, lowest precedence (runs last). Beans and
/// `registerSingleton` objects of this type, as of any
/// [GenericApplicationListener], receive events.
///
/// ```dart
/// // Logs the refresh and the close of the context.
/// @Component()
/// @Log()
/// class ContextAudit with SmartApplicationListener {
///   @override
///   bool supportsEventType(Type eventType) =>
///       eventType == ContextRefreshedEvent || eventType == ContextClosedEvent;
///
///   @override
///   void onApplicationEvent(Object event) => log.info(event);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class ContextAudit implements SmartApplicationListener {
///   public boolean supportsEventType(Class<? extends ApplicationEvent> t) {
///     return t == ContextRefreshedEvent.class
///         || t == ContextClosedEvent.class;
///   }
///   public void onApplicationEvent(ApplicationEvent event) { ... }
/// }
/// ```
///
/// A payload is seen as its `PayloadApplicationEvent`; override
/// [supportsEvent] to decide on the instance instead.
abstract mixin class SmartApplicationListener
    implements GenericApplicationListener, Ordered {
  /// Whether events of the runtime type [eventType] are handled. It is the
  /// event's exact runtime type (a published object that is not an
  /// `ApplicationEvent` comes as its `PayloadApplicationEvent`), so a test
  /// with `==` does not accept subclasses.
  bool supportsEventType(Type eventType);

  /// Whether events from sources of the runtime type [sourceType] are
  /// handled; `true` by default. For a published object that is not an
  /// `ApplicationEvent`, the source is its `PayloadApplicationEvent`'s
  /// source, the context.
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

/// A [GenericApplicationListener] made from a function or an
/// [ApplicationListener], for events (or published objects) of type [E].
///
/// Use it to add a listener in code with
/// `ConfigurableApplicationContext.addApplicationListener`, for example
/// from a test or a widget; `ApplicationContext.addListener` creates one
/// for you.
///
/// ```dart
/// context.addApplicationListener(
///   ApplicationListenerAdapter.of<OrderPlaced>(
///     (o) => log.info(o.id),
///     order: 1,
///   ),
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

  /// A listener that calls [handler] with each event (or published
  /// object) of type [E]; a lower [order] runs first.
  static ApplicationListenerAdapter<E> of<E>(
    void Function(E event) handler, {
    int order = Ordered.lowestPrecedence,
  }) => ApplicationListenerAdapter<E>._(handler, order);

  /// Wraps an [ApplicationListener] object that is not a bean; [order]
  /// defaults to the listener's own `Ordered.order` (lowest precedence
  /// when it is not [Ordered]).
  static ApplicationListenerAdapter<E> forListener<E extends Object>(
    ApplicationListener<E> listener, {
    int? order,
  }) => ApplicationListenerAdapter<E>._(
    listener.onApplicationEvent,
    order ?? OrderComparator.orderOf(listener),
  );

  final void Function(E event) _handler;

  /// The position among listeners; lower values run first.
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

/// What `ApplicationContext.addListener` returns: call [remove] to stop
/// the listener.
///
/// Keep it where the listening ends, for example in a Flutter widget's
/// `dispose`.
///
/// ```dart
/// final registration = context.addListener<String>(log.info);
/// registration.remove();
/// assert(registration.isRemoved);
/// ```
///
/// Spring (Java) has no handle; keep the listener and remove it:
/// ```java
/// context.removeApplicationListener(listener);
/// ```
final class ListenerRegistration {
  /// Creates a registration that runs the removal function at most once.
  ListenerRegistration(this._remove);

  final void Function() _remove;
  bool _removed = false;

  /// Whether [remove] has been called.
  bool get isRemoved => _removed;

  /// Stops the listener; later calls do nothing.
  void remove() {
    if (!_removed) {
      _removed = true;
      _remove();
    }
  }
}
