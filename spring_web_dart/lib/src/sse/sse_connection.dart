import 'dart:async';

import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/streamed_http_response.dart';
import 'package:spring_web_dart/src/http_status.dart';
import 'package:spring_web_dart/src/sse/server_sent_event.dart';
import 'package:spring_web_dart/src/sse/sse_decoder.dart';

/// The reconnection rules of an event stream: whether, after how long and
/// how many times it connects again when its connection ends or breaks.
///
/// An event stream is meant to last, but connections drop: a proxy times
/// out, the phone changes networks, the server restarts. A browser's
/// `EventSource` reconnects by itself, and so does
/// [connectServerSentEvents], following these rules. It waits [delay], or
/// the delay the server sent in a `retry:` field, and sends the last event
/// id in `Last-Event-ID` so the server can resume.
///
/// Feign clients build one from their configuration (the
/// `event-stream.reconnect`, `event-stream.reconnect-delay` and
/// `event-stream.max-attempts` keys), so applications set properties
/// rather than create it. You write one when you call
/// [connectServerSentEvents] yourself.
///
/// ```dart
/// // Retry quickly, but give up after five connections in a row that
/// // bring no event.
/// const SseReconnect(delay: Duration(seconds: 1), maxAttempts: 5);
///
/// // A one-shot stream: it ends with its first connection.
/// SseReconnect.never;
/// ```
///
/// Spring (Java): no built-in reconnection; the usual way is
/// `Flux.retryWhen(Retry.fixedDelay(...))` on a `WebClient` stream.
final class SseReconnect {
  /// Rules that reconnect when [enabled] (the default), after [delay]
  /// (3 seconds by default). [maxAttempts] limits the connections in a row
  /// that bring no event (`null`, the default: no limit). [retryIf] picks
  /// the errors worth another try; by default only an
  /// [HttpTransportException], that is a network failure or a timeout.
  const SseReconnect({
    this.enabled = true,
    this.delay = const Duration(seconds: 3),
    this.maxAttempts,
    this.retryIf = _isTransportError,
  });

  /// Rules that never reconnect: the stream ends when its first connection
  /// ends, and fails with its error.
  static const never = SseReconnect(enabled: false);

  /// Whether to reconnect at all. When `false` the other fields do not
  /// matter.
  final bool enabled;

  /// The wait before connecting again. Once the server has sent a
  /// `retry:` field, its value is used instead.
  final Duration delay;

  /// How many connections in a row may end without bringing an event
  /// before the stream gives up and ends (with the last error, if there
  /// was one). The first connection counts, and any event with data
  /// starts the count again. `null` for no limit.
  final int? maxAttempts;

  /// Decides whether a failure is worth another try. An error it rejects
  /// ends the stream with that error, such as a `4xx` that `connect`
  /// turned into an exception. A connection that simply ends is always
  /// retried.
  final bool Function(Object error) retryIf;

  static bool _isTransportError(Object error) =>
      error is HttpTransportException;
}

/// Reads server-sent events from an HTTP endpoint as one stream that
/// survives lost connections: when a connection ends or breaks, it opens
/// a new one and goes on.
///
/// This is the client side of an event stream, the job a browser's
/// `EventSource` does. Feign clients use it for methods that return an
/// `EventStream<T>`, so applications rarely call it. Call it to read an
/// event stream with a bare [HttpTransport].
///
/// [connect] opens one connection. It gets the id of the last event
/// received (`null` the first time) to send as `Last-Event-ID`, and
/// returns the response with its headers. It throws if the server
/// refused; the error is then retried or not as [reconnect] decides.
/// A non-2xx status is not checked here, so [connect] must throw for it.
///
/// Then:
///
/// - A `204 No Content` response ends the stream: the server's way to say
///   "stop", as for `EventSource`.
/// - A connection that ends, or fails with an error [reconnect] accepts,
///   is opened again after the delay, up to the limit of [reconnect].
/// - Blocks without `data:` (heartbeat comments, a lone `retry:`) update
///   the last id and the delay but are not emitted.
/// - [onReconnect] is told about every retry, with the error (or `null`
///   for a connection that ended), the delay and the attempt number, for
///   example to log it.
///
/// Nothing happens until the stream is listened to; cancelling the
/// subscription closes the connection and stops reconnecting.
///
/// ```dart
/// // `transport` is the application's `HttpTransport` bean.
/// Stream<ServerSentEvent<String>> orderEvents() =>
///     connectServerSentEvents((lastEventId) async {
///       final response = await transport.stream(HttpRequest(
///         method: HttpMethod.get,
///         url: Uri.parse('https://api.neon.books/orders/events'),
///         headers: HttpHeaders({
///           'Accept': MediaType.textEventStream,
///           // Resume after the last event seen before the drop.
///           if (lastEventId != null) 'Last-Event-ID': lastEventId,
///         }),
///       ));
///       if (!response.isSuccess) {
///         // Not a network failure: the stream ends with this error.
///         throw StateError((await response.read()).bodyText);
///       }
///       return response;
///     });
///
/// // Each listener of `orders` opens its own connection.
/// final orders = EventStream<String>(orderEvents);
/// ```
///
/// Spring (Java): no single call.
/// `WebClient.get().retrieve().bodyToFlux(ServerSentEvent.class)` reads
/// the events, and `retryWhen` on the `Flux` reconnects.
Stream<ServerSentEvent<String>> connectServerSentEvents(
  Future<StreamedHttpResponse> Function(String? lastEventId) connect, {
  SseReconnect reconnect = const SseReconnect(),
  void Function(Object? error, Duration delay, int attempt)? onReconnect,
}) {
  late final StreamController<ServerSentEvent<String>> out;
  StreamSubscription<ServerSentEvent<String?>>? current;
  Timer? timer;
  var cancelled = false;
  String? lastEventId;
  var delay = reconnect.delay;
  var attempts = 0;

  void finish([Object? error, StackTrace? stackTrace]) {
    if (cancelled || out.isClosed) {
      return;
    }
    if (error != null) {
      out.addError(error, stackTrace);
    }
    unawaited(out.close());
  }

  late void Function() open;

  // The connection ended ([error] == null) or failed: try again or stop.
  void retry([Object? error, StackTrace? stackTrace]) {
    if (cancelled) {
      return;
    }
    attempts++;
    final max = reconnect.maxAttempts;
    final again =
        reconnect.enabled &&
        (error == null || reconnect.retryIf(error)) &&
        (max == null || attempts < max);
    if (!again) {
      finish(error, stackTrace);
      return;
    }
    onReconnect?.call(error, delay, attempts);
    timer = Timer(delay, open);
  }

  open = () async {
    if (cancelled) {
      return;
    }
    final StreamedHttpResponse response;
    try {
      response = await connect(lastEventId);
    } on Object catch (error, stackTrace) {
      retry(error, stackTrace);
      return;
    }
    if (cancelled) {
      unawaited(response.discard());
      return;
    }
    if (response.statusCode == HttpStatus.noContent) {
      unawaited(response.discard());
      finish();
      return;
    }
    // Kept in `current`, which onCancel cancels.
    // ignore: cancel_subscriptions
    final subscription = current = response.body
        .transform(const SseDecoder())
        .listen(
          (event) {
            if (event.id case final id?) {
              lastEventId = id;
            }
            if (event.retry case final retry?) {
              delay = retry;
            }
            if (event.data case final data?) {
              attempts = 0;
              out.add(event.withData<String>(data));
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            current = null;
            retry(error, stackTrace);
          },
          onDone: () {
            current = null;
            retry();
          },
          cancelOnError: true,
        );
    if (out.isPaused) {
      subscription.pause();
    }
  };

  out = StreamController<ServerSentEvent<String>>(
    onListen: open,
    onPause: () => current?.pause(),
    onResume: () => current?.resume(),
    onCancel: () async {
      cancelled = true;
      timer?.cancel();
      await current?.cancel();
    },
  );
  return out.stream;
}
