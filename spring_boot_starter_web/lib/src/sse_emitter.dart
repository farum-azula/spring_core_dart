import 'dart:async';

import 'package:spring_web_dart/spring_web_dart.dart';

/// Server-sent events pushed from anywhere, like Spring MVC's `SseEmitter`.
/// A handler returns it; events sent before the response is ready are
/// buffered. The data of an event is written as JSON (a `String` as is).
///
/// Keep emitters in a bean to send to them later; remove them in
/// [onCompletion] (the client went away, the emitter timed out or was
/// completed).
///
/// ```dart
/// @GetMapping('/notifications')
/// SseEmitter subscribe() {
///   final emitter = SseEmitter(timeout: const Duration(minutes: 30));
///   notifications.add(emitter);
///   emitter.onCompletion(() => notifications.remove(emitter));
///   return emitter;
/// }
///
/// // Elsewhere:
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
  /// An emitter ending after [timeout] (by default
  /// `spring.mvc.async.request-timeout`, else never).
  SseEmitter({this.timeout});

  /// How long the stream stays open; `null` for the default.
  final Duration? timeout;

  final _buffer = <ServerSentEvent<Object?>>[];
  final _onCompletion = <void Function()>[];
  final _onTimeout = <void Function()>[];
  final _onError = <void Function(Object error)>[];
  SseEmitterHandler? _handler;
  var _complete = false;
  Object? _failure;
  Timer? _timer;

  /// Whether the emitter ended (completed, timed out, failed, or the client
  /// went away). Sending then throws a [StateError].
  bool get isComplete => _complete;

  /// Sends [data] as an event (a [ServerSentEvent] keeps its `id`,
  /// `event`, `retry` and `comment`).
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

  /// Ends the stream normally.
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

  /// Ends the stream because of [error] (answered as an error when nothing
  /// was sent yet).
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

  /// Called when the emitter ends, whatever the reason.
  void onCompletion(void Function() callback) => _onCompletion.add(callback);

  /// Called when the emitter times out (before it completes).
  void onTimeout(void Function() callback) => _onTimeout.add(callback);

  /// Called when sending fails or [completeWithError] is called.
  void onError(void Function(Object error) callback) => _onError.add(callback);

  /// Connects the emitter to the response: buffered events are sent, then
  /// every [send]. Called by the web starter; [defaultTimeout] applies
  /// when [timeout] is `null`.
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

/// Where an [SseEmitter] writes; implemented by the web starter.
abstract interface class SseEmitterHandler {
  /// Writes [event].
  Future<void> send(ServerSentEvent<Object?> event);

  /// Ends the response.
  Future<void> complete();

  /// Ends the response after [error].
  Future<void> completeWithError(Object error);

  /// Completes when the response ended (the client went away).
  Future<void> get done;
}
