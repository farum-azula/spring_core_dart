import 'package:spring_core_dart/src/aop/proxy.dart';
import 'package:spring_core_dart/src/context/annotations.dart';
import 'package:spring_core_dart/src/context/event/application_event.dart';
import 'package:spring_core_dart/src/context/event/application_listener.dart';

/// The declared result type [R] of an `@EventListener` method (the element
/// type of an `Iterable` result), so that its results are published as
/// `R`.
///
/// A listener's non-null result is published as a new event. Published as
/// `R` instead of `Object`, it reaches the `PayloadApplicationEvent<R>`
/// listeners, as in Spring (which uses the result's runtime class). The
/// generator writes it; you only need it in a hand-written
/// [EventListenerMethod].
///
/// ```dart
/// EventListenerMethod.of<Shipping, OrderPlaced>(
///   'Shipping.onPlaced',
///   (bean, event) => bean.onPlaced(event), // returns OrderShipped
///   resultType: const EventResultType<OrderShipped>(),
/// );
/// ```
final class EventResultType<R extends Object> {
  /// Describes the result type [R].
  const EventResultType();

  /// Publishes [result] through [publisher], typed as [R] when it is one
  /// (as its static type otherwise).
  void publish(ApplicationEventPublisher publisher, Object result) =>
      result is R
      ? publisher.publishEvent<R>(result)
      : publisher.publishEvent(result);
}

/// One `@EventListener` method of a bean class [T], described by generated
/// code: which events it takes, its condition, its order and how to call
/// it.
///
/// Dart has no reflection to find and call annotated methods at runtime,
/// so the generator writes one of these per method into
/// `BeanDefinition.eventListeners`. The context wraps each in a listener
/// that looks the bean up when an event arrives. Applications never see
/// it; write one only for a hand-written bean definition.
///
/// ```dart
/// // A hand-written definition whose onPlaced method listens to big
/// // orders only.
/// BeanDefinition<Shipping>(
///   name: 'shipping',
///   types: const [Shipping],
///   create: (_) => Shipping(),
///   eventListeners: [
///     EventListenerMethod.of<Shipping, OrderPlaced>(
///       'Shipping.onPlaced',
///       (bean, event) => bean.onPlaced(event),
///       condition: (event) => event.total >= 100,
///     ),
///   ],
/// );
/// ```
///
/// Spring (Java) builds the equivalent `ApplicationListenerMethodAdapter`
/// reflectively from:
/// ```java
/// @EventListener(condition = "#event.total >= 100")
/// void onPlaced(OrderPlaced event) { ... }
/// ```
final class EventListenerMethod<T extends Object> {
  /// Creates a listener method from raw callbacks: `supports` decides on
  /// the event type, `shouldHandle` on the condition (called right before
  /// `invoke`, inside the multicaster's error handling), `invoke` calls
  /// the method on the bean; [async] is the method's `@Async`. [of],
  /// [EventListenerMethod.matching] and [forPayload] build these callbacks
  /// for the usual cases.
  EventListenerMethod({
    required this.id,
    required this._supports,
    required this._invoke,
    this._shouldHandle,
    this.order,
    this.async,
    this.resultType,
  });

  /// A listener for several event types: [accepts] decides on the event or
  /// its payload; [condition] (a `bool Function(E)`) is applied to the
  /// accepted object.
  ///
  /// The generator uses it for `@EventListener(classes: [A, B])`:
  ///
  /// ```dart
  /// EventListenerMethod<Shipping>.matching(
  ///   id: 'Shipping.onContext',
  ///   accepts: (e) => e is ContextRefreshedEvent || e is ContextClosedEvent,
  ///   invoke: (bean, event) => bean.onContext(),
  /// );
  /// ```
  EventListenerMethod.matching({
    required this.id,
    required bool Function(Object candidate) accepts,
    required this._invoke,
    this.order,
    this.async,
    this.resultType,
    Function? condition,
  }) : _supports = ((event) => _matched(event, accepts) != null),
       // `condition` is untyped (it comes from the annotation), so it is
       // called dynamically.
       _shouldHandle = condition == null
           ? null
           : ((event) =>
                 Function.apply(condition, [_matched(event, accepts)!.value]) ==
                 true);

  /// A listener for events (or published objects) of type [E], the
  /// method's parameter type; [condition] filters the matched event or
  /// object. The generator uses it for most `@EventListener` methods.
  static EventListenerMethod<T> of<T extends Object, E>(
    String id,
    Object? Function(T bean, E event) handler, {
    int? order,
    bool Function(E event)? condition,
    Async? async,
    EventResultType<Object>? resultType,
  }) => EventListenerMethod<T>(
    id: id,
    order: order,
    async: async,
    resultType: resultType,
    supports: (event) => unwrap<E>(event) != null,
    shouldHandle: condition == null
        ? null
        : (event) => condition(unwrap<E>(event)!.value),
    invoke: (bean, event) => handler(bean, unwrap<E>(event)!.value),
  );

  /// A listener of `PayloadApplicationEvent<P>`, matching on the runtime
  /// type of the payload like Spring's `ResolvableType` matching: a
  /// payload published as `PayloadApplicationEvent<Object>` (an object of
  /// static type `Object`, a listener's result) is handed over as a
  /// `PayloadApplicationEvent<P>` with the same source and timestamp.
  /// [condition] filters the event.
  ///
  /// The generator uses it for `@EventListener` methods (and
  /// `ApplicationListener`s) of a `PayloadApplicationEvent<P>`:
  ///
  /// ```dart
  /// EventListenerMethod.forPayload<Audit, OrderPlaced>(
  ///   'Audit.on',
  ///   (bean, event) => bean.on(event),
  /// );
  /// ```
  static EventListenerMethod<T> forPayload<T extends Object, P extends Object>(
    String id,
    Object? Function(T bean, PayloadApplicationEvent<P> event) handler, {
    int? order,
    bool Function(PayloadApplicationEvent<P> event)? condition,
    Async? async,
    EventResultType<Object>? resultType,
  }) => EventListenerMethod<T>(
    id: id,
    order: order,
    async: async,
    resultType: resultType,
    supports: (event) => _payloadEvent<P>(event) != null,
    shouldHandle: condition == null
        ? null
        : (event) => condition(_payloadEvent<P>(event)!),
    invoke: (bean, event) => handler(bean, _payloadEvent<P>(event)!),
  );

  static PayloadApplicationEvent<P>? _payloadEvent<P extends Object>(
    Object event,
  ) => switch (event) {
    final PayloadApplicationEvent<P> typed => typed,
    PayloadApplicationEvent(
      :final source,
      :final P payload,
      :final timestamp,
    ) =>
      PayloadApplicationEvent<P>(source, payload, timestamp: timestamp),
    _ => null,
  };

  /// The object [accepts] takes from [event]: the payload of a
  /// `PayloadApplicationEvent` first, else [event] itself. Throws an
  /// `ArgumentError` if neither is accepted.
  static Object match(Object event, bool Function(Object candidate) accepts) =>
      _matched(event, accepts)?.value ??
      (throw ArgumentError.value(event, 'event', 'Event is not accepted'));

  static ({Object value})? _matched(
    Object event,
    bool Function(Object candidate) accepts,
  ) {
    // The payload first, like unwrap: a payload is never an
    // ApplicationEvent, so only a non-event type can have accepted it.
    if (event is PayloadApplicationEvent &&
        event.payload is! ApplicationEvent &&
        accepts(event.payload)) {
      return (value: event.payload);
    }
    if (accepts(event)) {
      return (value: event);
    }
    return null;
  }

  /// The value a listener of [E] receives for [event], or `null` when it
  /// does not handle it; the record keeps a `null` payload apart from "not
  /// handled".
  ///
  /// When [E] is not an [ApplicationEvent] type (`Object`, say) and
  /// [event] is a [PayloadApplicationEvent] whose payload is an [E], the
  /// listener gets the payload; otherwise it gets [event] itself if it is
  /// an [E]. Spring's `ApplicationListenerMethodAdapter` decides the same.
  static ({E value})? unwrap<E>(Object event) {
    if (event is PayloadApplicationEvent && <E>[] is! List<ApplicationEvent>) {
      if (event.payload case final E payload) {
        return (value: payload);
      }
    }
    if (event is E) {
      return (value: event as E);
    }
    return null;
  }

  /// The listener's id, shown in logs and errors: `@EventListener(id:)`,
  /// or `Class.method` by default.
  final String id;

  /// The method's `@Order`; `null` without one, which counts as the lowest
  /// precedence (the listener runs last).
  final int? order;

  /// The method's `@Async` (`null` when it runs on the publishing call);
  /// see [Async].
  final Async? async;

  /// The declared result type; results are published as it (as `Object`
  /// without it).
  final EventResultType<Object>? resultType;

  final bool Function(Object event) _supports;
  final bool Function(Object event)? _shouldHandle;
  final Object? Function(T bean, Object event) _invoke;

  /// Whether the method listens to [event]'s type (or its payload's); the
  /// condition is checked separately by [shouldHandle] (Spring's
  /// `ApplicationListenerMethodAdapter.supportsEventType`).
  bool supports(Object event) => _supports(event);

  /// Whether the condition accepts [event] (`true` without one). Called
  /// for a [supports]ed event right before [invoke], so a failing
  /// condition reaches the multicaster's error handler like a failing
  /// listener (Spring's `ApplicationListenerMethodAdapter.shouldHandle`).
  bool shouldHandle(Object event) => _shouldHandle?.call(event) ?? true;

  /// Calls the method on [bean] with [event] (or its payload) and returns
  /// the method's result; the caller publishes a non-null result.
  ///
  /// An AOP proxy that does not implement [T] is unwrapped to its target.
  Object? invoke(Object bean, Object event) =>
      _invoke((bean is T ? bean : AopUtils.getTarget(bean)) as T, event);

  @override
  String toString() => 'EventListenerMethod($id)';
}
