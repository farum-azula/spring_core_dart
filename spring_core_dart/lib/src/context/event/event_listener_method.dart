import 'package:spring_core_dart/src/aop/proxy.dart';
import 'package:spring_core_dart/src/context/annotations.dart';
import 'package:spring_core_dart/src/context/event/application_event.dart';

/// An `@EventListener` method of a bean of type [T], prepared by generated
/// code (no reflection).
///
/// The generator stores these in `BeanDefinition.eventListeners`; the
/// context wraps each in a listener that fetches the bean per event. Write
/// one by hand only for hand-made bean definitions.
///
/// ```dart
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
  /// the method on the bean; [async] is the method's `@Async`.
  EventListenerMethod({
    required this.id,
    required this._supports,
    required this._invoke,
    this._shouldHandle,
    this.order,
    this.async,
  });

  /// A listener for events (or payloads) of type [E]; [condition] filters
  /// the matched event or payload.
  static EventListenerMethod<T> of<T extends Object, E>(
    String id,
    Object? Function(T bean, E event) handler, {
    int? order,
    bool Function(E event)? condition,
    Async? async,
  }) => EventListenerMethod<T>(
    id: id,
    order: order,
    async: async,
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
  }) => EventListenerMethod<T>(
    id: id,
    order: order,
    async: async,
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
      payload: final P payload,
      :final timestamp,
    ) =>
      PayloadApplicationEvent<P>(source, payload, timestamp: timestamp),
    _ => null,
  };

  /// A listener for several event types: [accepts] decides on the event or
  /// its payload; [condition] (a `bool Function(E)`) is applied to the
  /// accepted object.
  ///
  /// Used for `@EventListener(classes: [A, B])`:
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
    Function? condition,
  }) : _supports = ((event) => _matched(event, accepts) != null),
       // `condition` is untyped (it comes from the annotation), so it is
       // called dynamically.
       _shouldHandle = condition == null
           ? null
           : ((event) =>
                 Function.apply(condition, [_matched(event, accepts)!.value]) ==
                 true);

  /// The accepted object: [event] itself or its payload; throws an
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
  /// does not handle it (boxed so that a `null` payload is
  /// distinguishable). Like Spring's `ApplicationListenerMethodAdapter`:
  /// when [E] is not an [ApplicationEvent] type (e.g. `Object`), the
  /// payload of a [PayloadApplicationEvent] that is an [E]; else [event]
  /// itself if it is an [E].
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

  /// `Class.method` by default.
  final String id;

  /// `@Order` of the method.
  final int? order;

  /// The method's `@Async` (`null` when it runs on the publishing call);
  /// see [Async].
  final Async? async;

  final bool Function(Object event) _supports;
  final bool Function(Object event)? _shouldHandle;
  final Object? Function(T bean, Object event) _invoke;

  /// Whether the method listens to [event]'s type (or its payload's), like
  /// Spring's `ApplicationListenerMethodAdapter.supportsEventType`; the
  /// condition is checked by [shouldHandle].
  bool supports(Object event) => _supports(event);

  /// Whether the condition accepts [event] (`true` without one), like
  /// Spring's `ApplicationListenerMethodAdapter.shouldHandle`; called for
  /// a [supports]ed event right before [invoke], so a failing condition
  /// reaches the multicaster's error handler like a failing listener.
  bool shouldHandle(Object event) => _shouldHandle?.call(event) ?? true;

  /// Calls the method; a non-null result is published by the caller.
  ///
  /// An AOP proxy that does not implement [T] is unwrapped to its target.
  Object? invoke(Object bean, Object event) =>
      _invoke((bean is T ? bean : AopUtils.getTarget(bean)) as T, event);

  @override
  String toString() => 'EventListenerMethod($id)';
}
