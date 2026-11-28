import 'dart:async';

/// Makes the stream a retried `@Retryable` method returns: a stream of the
/// type of the first call's (an `EventStream` stays an `EventStream`),
/// whose events are those of each call in turn ([StreamAttempts.join]).
///
/// The core knows `Stream`; a library with a stream type of its own adds
/// an adapter for it as a bean (`spring_web_dart`'s
/// `EventStreamRetryAdapter`). The first adapter that [supports] the
/// first call's stream makes it; a plain stream needs none.
///
/// ```dart
/// final class TickerRetryAdapter implements RetryStreamAdapter {
///   const TickerRetryAdapter();
///
///   @override
///   bool supports(Stream<Object?> stream) => stream is Ticker;
///
///   @override
///   Stream<T> adapt<T>(StreamAttempts<T> attempts) =>
///       Ticker<T>(attempts.join((attempt) => attempt));
/// }
/// ```
///
/// Spring (Java) resubscribes a `Flux` (`retryWhen`); Dart's stream types
/// have no common way to start again, so each type says how.
abstract interface class RetryStreamAdapter {
  /// Whether this adapter makes the retried stream of [stream], the first
  /// call's.
  bool supports(Stream<Object?> stream);

  /// The stream handed to the caller: of the first call's type, with the
  /// events of every call [attempts] makes.
  Stream<T> adapt<T>(StreamAttempts<T> attempts);
}

/// The calls of a retried stream method: the stream of the first one,
/// and the events of all of them in one stream ([join]).
///
/// A [RetryStreamAdapter] gets it; the retries are those of the method's
/// `@Retryable`.
abstract interface class StreamAttempts<T> {
  /// The stream the first call returned.
  Stream<T> get first;

  /// The events of each call in turn: listening listens to what
  /// [eventsOf] makes of [first]; on an error the policy allows to retry,
  /// it is cancelled and, after the pause, the method is called again and
  /// what [eventsOf] makes of the new stream is listened to; it ends when
  /// one ends, or with the last error when the retries give up. Each
  /// listen counts its own retries.
  Stream<E> join<E>(Stream<E> Function(Stream<T> attempt) eventsOf);
}

/// A plain `Stream`'s adapter: the events of every call, broadcast when
/// the first call's stream is.
final class PlainStreamRetryAdapter implements RetryStreamAdapter {
  /// The adapter.
  const PlainStreamRetryAdapter();

  @override
  bool supports(Stream<Object?> stream) => true;

  @override
  Stream<T> adapt<T>(StreamAttempts<T> attempts) {
    final joined = attempts.join((attempt) => attempt);
    return attempts.first.isBroadcast ? joined.asBroadcastStream() : joined;
  }
}

/// The retries of one listen of a retried stream, as the interceptor
/// decides them: framework code.
abstract interface class StreamRetryRun {
  /// The pause before the next call after [error], or `null` to end the
  /// stream with it.
  Duration? failed(Object error, StackTrace stackTrace);

  /// A new call starts.
  void retrying();

  /// The stream ended without an error.
  void done();
}

/// The [StreamAttempts] of the interceptor: `next` calls the method again,
/// and each listen starts a [StreamRetryRun] that decides its retries.
final class RetriedStreamAttempts<T> implements StreamAttempts<T> {
  /// The calls of a method whose first call returned [first].
  RetriedStreamAttempts(
    this.first, {
    required this._next,
    required this._start,
  });

  @override
  final Stream<T> first;

  final Stream<T> Function() _next;
  final StreamRetryRun Function() _start;

  @override
  Stream<E> join<E>(Stream<E> Function(Stream<T> attempt) eventsOf) {
    late final StreamController<E> controller;
    StreamSubscription<E>? subscription;
    Timer? timer;
    var paused = false;
    final run = _start();

    void listenTo(Stream<T> attempt) {
      subscription = eventsOf(attempt).listen(
        controller.add,
        onError: (Object error, StackTrace stackTrace) {
          final pause = run.failed(error, stackTrace);
          final failed = subscription;
          subscription = null;
          unawaited(failed?.cancel());
          if (pause == null) {
            controller.addError(error, stackTrace);
            unawaited(controller.close());
            return;
          }
          timer = Timer(pause, () {
            timer = null;
            run.retrying();
            Stream<T> next;
            try {
              next = _next();
            } on Object catch (error, stackTrace) {
              next = Stream<T>.error(error, stackTrace);
            }
            listenTo(next);
            if (paused) {
              subscription?.pause();
            }
          });
        },
        onDone: () {
          run.done();
          unawaited(controller.close());
        },
      );
    }

    controller = StreamController<E>(
      onListen: () => listenTo(first),
      onPause: () {
        paused = true;
        subscription?.pause();
      },
      onResume: () {
        paused = false;
        subscription?.resume();
      },
      onCancel: () {
        timer?.cancel();
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
