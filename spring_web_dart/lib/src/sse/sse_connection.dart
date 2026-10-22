import 'dart:async';

import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/streamed_http_response.dart';
import 'package:spring_web_dart/src/http_status.dart';
import 'package:spring_web_dart/src/sse/server_sent_event.dart';
import 'package:spring_web_dart/src/sse/sse_decoder.dart';

/// When an event stream connects again after its connection ended or
/// broke, like the browser's `EventSource`: after [delay] (or the server's
/// `retry:`), sending the last event id in `Last-Event-ID`.
///
/// ```dart
/// const SseReconnect(delay: Duration(seconds: 1), maxAttempts: 5)
/// SseReconnect.never
/// ```
///
/// Spring (Java): no built-in reconnection; `Flux.retryWhen(Retry.fixedDelay(...))`.
final class SseReconnect {
  /// Reconnects after [delay]; [maxAttempts] limits the connections in a
  /// row that bring no event (`null`: no limit); [retryIf] picks the
  /// errors worth another try (default: [HttpTransportException]).
  const SseReconnect({
    this.enabled = true,
    this.delay = const Duration(seconds: 3),
    this.maxAttempts,
    this.retryIf = _isTransportError,
  });

  /// Never reconnects: the stream ends with its connection.
  static const never = SseReconnect(enabled: false);

  /// Whether to reconnect at all.
  final bool enabled;

  /// The wait before connecting again (until the server sends `retry:`).
  final Duration delay;

  /// The connections in a row without an event before giving up.
  final int? maxAttempts;

  /// Whether a failure is worth another try (others end the stream with
  /// the error).
  final bool Function(Object error) retryIf;

  static bool _isTransportError(Object error) =>
      error is HttpTransportException;
}

/// The events of an endless `text/event-stream` connection: [connect]
/// opens it (getting the last event id, `null` the first time) and returns
/// the response, or throws to fail. A `204 No Content` response ends the
/// stream (the server's way to say "stop", as for `EventSource`); a
/// response or connection that ends is opened again as [reconnect] says.
/// Blocks without `data:` (heartbeats, a lone `retry:`) update the id and
/// delay but are not emitted. [onReconnect] is told about every retry
/// (e.g. to log it).
///
/// Starts connecting when listened to; cancelling the subscription closes
/// the connection.
///
/// ```dart
/// final events = connectServerSentEvents((lastEventId) async {
///   final response = await transport.stream(HttpRequest(
///     method: HttpMethod.get,
///     url: Uri.parse('https://api.neon.books/orders/events'),
///     headers: HttpHeaders({
///       'Accept': MediaType.textEventStream,
///       if (lastEventId != null) 'Last-Event-ID': lastEventId,
///     }),
///   ));
///   if (!response.isSuccess) {
///     throw StateError((await response.read()).bodyText);
///   }
///   return response;
/// });
/// final orders = EventStream<String>(() => events);
/// ```
///
/// Spring (Java): `WebClient.get().retrieve().bodyToFlux(ServerSentEvent.class)`
/// with `retryWhen`.
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
