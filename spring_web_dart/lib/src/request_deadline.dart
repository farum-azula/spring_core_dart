import 'dart:async';

/// A time limit for the work of one request, carried along with it: code
/// that runs under a deadline (a controller, a service it calls, a Feign
/// client) can ask how much time is left and stop when there is none.
///
/// A deadline is a total: it counts from the moment [run] starts and does
/// not care how many calls, retries or waits fit in it. Use it where a
/// caller waits for an answer and you want the work behind that answer to
/// give up when the caller has stopped waiting. The web starter runs every
/// request under one when `server.request-timeout` is set, and the Feign
/// starter ends a call when it passes (`call-timeout` is the limit of one
/// call, and the deadline of the enclosing request limits it further), so
/// a call made while a request is handled never outlives the request.
///
/// The deadline is found through the `Zone` of the code, like a
/// transaction, so it follows `await`s without being passed around:
/// [current] is the deadline of the code that runs now, or `null` outside
/// any. Nesting never extends it: [run] inside another deadline gets the
/// earlier of the two ends, so an inner step cannot take more time than
/// the outer one has left.
///
/// ```dart
/// // The whole checkout answers within 2 s, whatever the steps do.
/// final order = await RequestDeadline.run(
///   const Duration(seconds: 2),
///   () async {
///     final stock = await warehouse.reserve(basket); // a Feign client
///     RequestDeadline.current?.check(); // nothing left: stop here
///     return payments.charge(basket, stock);
///   },
/// );
/// ```
///
/// The deadline does not interrupt code: a step that never looks at it
/// keeps running. [check] and the clients that read it (Feign) are where
/// it takes effect. It works on every platform, the browser included.
///
/// Spring (Java) has no counterpart: its timeouts are per call (a read
/// timeout, a transaction timeout), and no limit follows a request through
/// the calls it makes. This is an extension of Spring for Dart.
final class RequestDeadline {
  RequestDeadline._(this._budget);

  static final Object _key = Object();

  final Duration _budget;
  final Stopwatch _clock = Stopwatch()..start();
  bool _released = false;

  /// The deadline of the code that runs now, or `null` when it runs under
  /// none (or the deadline was [release]d).
  static RequestDeadline? get current {
    final deadline = Zone.current[_key];
    return deadline is RequestDeadline && !deadline._released ? deadline : null;
  }

  /// Runs [body] under a deadline of [budget] from now, and returns what
  /// it returns. Under a deadline already, the new one ends at the earlier
  /// of the two, never later. A zero or negative [budget] is a deadline
  /// that has passed.
  ///
  /// When [body] is asynchronous, the deadline covers what it starts: the
  /// code after its `await`s, the callbacks of its timers and streams.
  ///
  /// ```dart
  /// // Catalog and prices must both come within 800 ms.
  /// final (books, prices) = await RequestDeadline.run(
  ///   const Duration(milliseconds: 800),
  ///   () => (catalog.list(), pricing.list()).wait,
  /// );
  /// ```
  static T run<T>(Duration budget, T Function() body) {
    var effective = budget.isNegative ? Duration.zero : budget;
    final outer = current;
    if (outer != null && outer.remaining < effective) {
      effective = outer.remaining;
    }
    return runZoned(body, zoneValues: {_key: RequestDeadline._(effective)});
  }

  /// Runs [body] under a deadline that ends at [instant]; as [run] with
  /// the time until then. An [instant] in the past is a deadline that has
  /// passed.
  ///
  /// ```dart
  /// // The caller said it gives up at this time (a request header).
  /// await RequestDeadline.runUntil(callerDeadline, () => process(job));
  /// ```
  static T runUntil<T>(DateTime instant, T Function() body) =>
      run(instant.difference(DateTime.now()), body);

  /// The length of time this deadline was given (after the earlier end of
  /// an enclosing deadline was taken into account).
  Duration get budget => _budget;

  /// How much time is left; [Duration.zero] when it has passed, never
  /// negative.
  Duration get remaining {
    final left = _budget - _clock.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether the time has passed. Always `false` once the deadline was
  /// [release]d.
  bool get isExpired => !_released && remaining == Duration.zero;

  /// Whether the deadline was ended by [release]: it no longer limits
  /// anything.
  bool get isReleased => _released;

  /// Throws a [RequestDeadlineExceededException] when the time has passed,
  /// else returns. Call it between the steps of long work to stop it when
  /// nobody is waiting for the result any more.
  ///
  /// ```dart
  /// for (final book in books) {
  ///   RequestDeadline.current?.check();
  ///   await index.add(book);
  /// }
  /// ```
  void check() {
    if (isExpired) {
      throw RequestDeadlineExceededException(_budget);
    }
  }

  /// Ends the deadline: from now on [current] is `null` where it was this
  /// deadline, and [isExpired] is `false`; deadlines created inside it
  /// before keep their own end.
  ///
  /// For servers and frameworks, not for application code: the web starter
  /// calls it when a response becomes a stream (server-sent events, a
  /// streamed download), whose life is not the time of one request, so
  /// that what the stream does afterwards is not cut at the request's
  /// deadline.
  void release() => _released = true;

  @override
  String toString() {
    if (_released) {
      return 'RequestDeadline[released]';
    }
    return 'RequestDeadline[${remaining.inMilliseconds} of '
        '${_budget.inMilliseconds} ms left]';
  }
}

/// Thrown by [RequestDeadline.check] when the deadline has passed.
///
/// It means the work was stopped on purpose, because nobody waits for its
/// result any more. In a web request that has a deadline, an unhandled one
/// is answered with a 503 (like any error that ends the request after its
/// deadline); catch it to clean up, or to answer in another way.
///
/// Spring (Java) has no counterpart, as it has no request deadline.
class RequestDeadlineExceededException implements Exception {
  /// The failure of a deadline of [budget].
  RequestDeadlineExceededException(this.budget);

  /// The time the deadline that passed was given.
  final Duration budget;

  /// What happened, for people and logs.
  String get message =>
      'The request deadline of ${budget.inMilliseconds} ms has passed';

  @override
  String toString() => 'RequestDeadlineExceededException: $message';
}
