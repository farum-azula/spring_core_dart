import 'dart:async';

import 'package:spring_web_dart/spring_web_dart.dart';

/// An open stream of server-sent events to one client, which code
/// anywhere in the application can send events to.
///
/// Server-sent events (`text/event-stream`) keep a response open and push
/// events to a browser's `EventSource` as they happen. When the events
/// come from one stream known at request time, return an `EventStream`
/// or a `Stream` instead. Use an emitter when they come from elsewhere,
/// later: a controller method creates and returns it, the application
/// keeps it (usually in a bean), and a service or an event listener calls
/// [send] when something happens. Events sent before the response is
/// ready are buffered. The data of an event is written as JSON (a
/// `String` as it is).
///
/// The emitter ends when it is [complete]d, when it times out, when a
/// send fails, or when the client goes away; then [onCompletion] runs, the
/// place to forget the emitter.
///
/// ```dart
/// // Each subscriber gets the orders as they are placed.
/// @GetMapping('/notifications')
/// SseEmitter subscribe() {
///   final emitter = SseEmitter(timeout: const Duration(minutes: 30));
///   notifications.add(emitter);
///   emitter.onCompletion(() => notifications.remove(emitter));
///   return emitter;
/// }
///
/// // Elsewhere, when an order is placed:
/// for (final emitter in notifications) {
///   emitter.send(ServerSentEvent(order, event: 'order', id: order.id));
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// SseEmitter emitter = new SseEmitter(1_800_000L);
/// emitter.send(SseEmitter.event().id(order.id()).name("order").data(order));
/// ```
class SseEmitter {
  /// An emitter that ends after [timeout], counted from when the response
  /// starts; without one, after `spring.mvc.async.request-timeout`, or
  /// never when that is not set.
  SseEmitter({this.timeout});

  /// How long the stream stays open; `null` for the configured default.
  final Duration? timeout;

  final _buffer = <ServerSentEvent<Object?>>[];
  final _onCompletion = <void Function()>[];
  final _onTimeout = <void Function()>[];
  final _onError = <void Function(Object error)>[];
  SseEmitterHandler? _handler;
  var _complete = false;
  Object? _failure;
  Timer? _timer;

  /// Whether the emitter has ended: completed, timed out, failed, or the
  /// client went away. Sending then throws a [StateError].
  bool get isComplete => _complete;

  /// Sends [data] as one event, or buffers it until the response is
  /// ready. Pass a [ServerSentEvent] to set its `id`, `event` name,
  /// `retry` or `comment`; any other value becomes the event's data.
  ///
  /// Throws a [StateError] once the emitter has ended. When the write
  /// fails (the client went away), the emitter ends, the [onError] and
  /// [onCompletion] callbacks run, and the error is rethrown.
  Future<void> send(Object? data) async {
    if (_complete) {
      throw StateError('The SseEmitter has already completed');
    }
    final event = data is ServerSentEvent<Object?>
        ? data
        : ServerSentEvent<Object?>(data);
    final handler = _handler;
    if (handler == null) {
      _buffer.add(event);
      return;
    }
    try {
      await handler.send(event);
    } on Object catch (error) {
      _fail(error);
      rethrow;
    }
  }

  /// Ends the stream normally, once the events sent so far are written;
  /// [onCompletion] callbacks run. Does nothing when it has ended already.
  void complete() {
    if (_complete) {
      return;
    }
    _complete = true;
    _timer?.cancel();
    final handler = _handler;
    if (handler != null) {
      unawaited(handler.complete());
      _notifyCompletion();
    }
  }

  /// Ends the stream because of [error]: the error is logged, [onError]
  /// and [onCompletion] callbacks run, and the response ends like with
  /// [complete]. The client only sees the stream close: the response
  /// started with status 200 when the handler returned the emitter.
  void completeWithError(Object error) {
    if (_complete) {
      return;
    }
    _failure = error;
    _complete = true;
    _timer?.cancel();
    final handler = _handler;
    if (handler != null) {
      unawaited(handler.completeWithError(error));
      _notifyError(error);
      _notifyCompletion();
    }
  }

  /// Registers [callback] to run once when the emitter ends, whatever
  /// the reason; use it to forget the emitter.
  void onCompletion(void Function() callback) => _onCompletion.add(callback);

  /// Registers [callback] to run when the emitter times out, before it
  /// completes.
  void onTimeout(void Function() callback) => _onTimeout.add(callback);

  /// Registers [callback] to run with the error when a send fails or
  /// [completeWithError] is called.
  void onError(void Function(Object error) callback) => _onError.add(callback);

  /// Connects the emitter to the response: the buffered events are
  /// written, then every [send] goes straight to [handler], and the
  /// timeout starts ([defaultTimeout] when [timeout] is `null`). Called
  /// by the web starter when the response starts; applications do not
  /// call it.
  Future<void> initialize(
    SseEmitterHandler handler, {
    Duration? defaultTimeout,
  }) async {
    _handler = handler;
    final buffered = [..._buffer];
    _buffer.clear();
    for (final event in buffered) {
      await handler.send(event);
    }
    if (_complete) {
      if (_failure case final failure?) {
        await handler.completeWithError(failure);
        _notifyError(failure);
      } else {
        await handler.complete();
      }
      _notifyCompletion();
      return;
    }
    final limit = timeout ?? defaultTimeout;
    if (limit != null && limit > Duration.zero) {
      _timer = Timer(limit, () {
        if (_complete) {
          return;
        }
        for (final callback in [..._onTimeout]) {
          callback();
        }
        complete();
      });
    }
    unawaited(
      handler.done.then((_) {
        if (!_complete) {
          _complete = true;
          _timer?.cancel();
          _notifyCompletion();
        }
      }),
    );
  }

  void _fail(Object error) {
    if (_complete) {
      return;
    }
    _complete = true;
    _timer?.cancel();
    _notifyError(error);
    _notifyCompletion();
  }

  void _notifyError(Object error) {
    for (final callback in [..._onError]) {
      callback(error);
    }
  }

  var _notified = false;

  void _notifyCompletion() {
    if (_notified) {
      return;
    }
    _notified = true;
    for (final callback in [..._onCompletion]) {
      callback();
    }
  }
}

/// The response an [SseEmitter] writes to once it is connected.
///
/// The web starter implements it over the event stream response; a test
/// can implement it to see what an emitter sends. Applications use the
/// emitter, not this.
abstract interface class SseEmitterHandler {
  /// Writes [event] to the stream; throws when the client went away.
  Future<void> send(ServerSentEvent<Object?> event);

  /// Ends the response once what was written is out.
  Future<void> complete();

  /// Ends the response because of [error].
  Future<void> completeWithError(Object error);

  /// Completes when the response has ended, also when the client went
  /// away.
  Future<void> get done;
}
