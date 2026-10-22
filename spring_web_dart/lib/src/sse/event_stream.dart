import 'dart:async';

import 'package:spring_web_dart/src/sse/server_sent_event.dart';

/// A stream of server-sent events that is a `Stream<T>` of their data:
/// listen to it or `await for` over it like any stream, and reach the
/// whole events ([ServerSentEvent] with `id`, `event`, `retry`) through
/// [events] when you need them. The short return type of Feign methods
/// that read `text/event-stream`.
///
/// It is cold: every listener opens its own connection, and cancelling the
/// subscription (or `break` in `await for`) closes it.
///
/// ```dart
/// @FeignClient('orders', url: r'${orders.url}')
/// abstract interface class OrdersClient {
///   @GetMapping('/orders/events')
///   EventStream<OrderEvent> events();
/// }
///
/// await for (final order in orders.events()) {
///   print(order.status);
/// }
///
/// orders.events().events.listen((e) => print('${e.id} ${e.event} ${e.data}'));
/// ```
///
/// For fallbacks and tests: `EventStream.of(stream)`,
/// `EventStream.fromIterable([...])`, `EventStream.fromEvents(...)`.
///
/// Spring (Java): there is no such type. Spring returns
/// `Flux<ServerSentEvent<OrderEvent>>` (or `Flux<OrderEvent>`) from
/// `WebClient` and `@HttpExchange` interfaces; OpenFeign cannot stream at
/// all. `EventStream<T>` folds the event wrapper into the stream so the
/// usual case stays short.
final class EventStream<T> extends Stream<T> {
  /// A stream whose listeners each get the events of a new [open] call.
  EventStream(Stream<ServerSentEvent<T>> Function() open) : _open = open;

  /// The events of [events] (listened to once).
  EventStream.fromEvents(Stream<ServerSentEvent<T>> events)
    : _open = (() => events);

  /// Events carrying the values of [data] (listened to once).
  EventStream.of(Stream<T> data)
    : _open = (() => data.map(ServerSentEvent<T>.new));

  /// Events carrying [values] (e.g. what a fallback returns).
  EventStream.fromIterable(Iterable<T> values)
    : _open = (() => Stream.fromIterable(values).map(ServerSentEvent<T>.new));

  /// No events.
  EventStream.empty() : _open = (() => const Stream.empty());

  final Stream<ServerSentEvent<T>> Function() _open;
  String? _lastEventId;

  /// The whole events (data with `id`, `event`, `retry`, `comment`); each
  /// listener opens its own connection.
  Stream<ServerSentEvent<T>> get events => _open().map((event) {
    if (event.id case final id?) {
      _lastEventId = id;
    }
    return event;
  });

  /// The id of the last event received through this object, if any.
  String? get lastEventId => _lastEventId;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => events
      .map((event) => event.data)
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
}
