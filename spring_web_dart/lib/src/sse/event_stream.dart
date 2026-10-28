import 'dart:async';

import 'package:spring_web_dart/src/sse/server_sent_event.dart';

/// A stream of server-sent events (`text/event-stream`) that reads as a
/// plain `Stream<T>` of their data, with the whole events still reachable
/// through [events].
///
/// Server-sent events are how a server pushes a series of messages over
/// one long HTTP response: notifications, progress, live prices. Each
/// event carries data plus an optional id, name and retry delay, but most
/// code only wants the data. This type gives the data directly: listen
/// to it or `await for` over it like any stream. When the id or the event
/// name matters, [events] gives each [ServerSentEvent] whole.
///
/// It is used in two places:
///
/// - As the return type of a Feign client method, which then opens the
///   connection, reads each event's data as `T` (JSON for a class) and
///   reconnects after a lost connection.
/// - As the return type of a `@RestController` method, whose events the
///   web starter writes as a `text/event-stream` response.
///
/// It is cold: nothing happens until someone listens, every listener opens
/// its own connection, and cancelling the subscription (or `break` in
/// `await for`) closes that connection.
///
/// ```dart
/// @FeignClient('orders', url: r'${orders.url}')
/// abstract interface class OrdersClient {
///   @GetMapping('/orders/events')
///   EventStream<OrderEvent> events();
/// }
///
/// // Only the data: each event's JSON read as an OrderEvent.
/// await for (final order in orders.events()) {
///   log.info(order.status);
/// }
///
/// // The whole events, when the event name tells the kinds apart.
/// orders.events().events.listen(
///   (e) => log.info('${e.id} ${e.event} ${e.data}'),
/// );
/// ```
///
/// Spring (Java): there is no such type. Spring returns
/// `Flux<ServerSentEvent<OrderEvent>>` (or `Flux<OrderEvent>`) from
/// `WebClient` and `@HttpExchange` interfaces; OpenFeign cannot stream at
/// all. `EventStream<T>` folds the event wrapper into the stream so the
/// usual case stays short.
final class EventStream<T> extends Stream<T> {
  /// A stream whose every listener gets the events of a new [open] call.
  /// [open] usually opens a connection, so each listener has its own.
  EventStream(Stream<ServerSentEvent<T>> Function() open) : _open = open;

  /// A stream of the events of [events], which already exist. Unlike the
  /// default constructor, a second listener gets no new connection: it
  /// listens to [events] again, which fails for a single-subscription
  /// stream.
  EventStream.fromEvents(Stream<ServerSentEvent<T>> events)
    : _open = (() => events);

  /// Events carrying the values of [data], with no id or name. For a
  /// controller method that already has a `Stream<T>`, or a test. As with
  /// [EventStream.fromEvents], [data] is listened to again by each
  /// listener.
  EventStream.of(Stream<T> data)
    : _open = (() => data.map(ServerSentEvent<T>.new));

  /// Events carrying [values], with no id or name; every listener gets
  /// them all. For a Feign fallback or a test.
  EventStream.fromIterable(Iterable<T> values)
    : _open = (() => Stream.fromIterable(values).map(ServerSentEvent<T>.new));

  /// A stream that ends at once, without events. For a fallback that has
  /// nothing to say.
  EventStream.empty() : _open = (() => const Stream.empty());

  final Stream<ServerSentEvent<T>> Function() _open;
  String? _lastEventId;

  /// The whole events: the data with its `id`, `event` name, `retry` delay
  /// and `comment`. Each listener opens its own connection, as with the
  /// stream itself. Reading through it also updates [lastEventId].
  Stream<ServerSentEvent<T>> get events => _open().map((event) {
    if (event.id case final id?) {
      _lastEventId = id;
    }
    return event;
  });

  /// The id of the last event that carried one, received by any listener
  /// of this object; `null` before that. A Feign client already sends it
  /// back by itself when it reconnects.
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
