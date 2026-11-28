import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/src/sse/event_stream.dart';

/// Keeps an [EventStream] an [EventStream] when a `@Retryable` method
/// that returns one is retried: the caller gets an `EventStream<T>` whose
/// listeners get the events of each call in turn, the whole events
/// (`id`, `event`, `retry`) included.
///
/// An [EventStream] read from a server reconnects by itself after a lost
/// connection; the retry comes after, when its own reconnects give up.
/// Each listener counts its retries, as each opens its own connection.
///
/// Register it as a bean (the web starters do) for the retries to find
/// it.
///
/// Spring (Java): a `Flux<ServerSentEvent<T>>` resubscribed by
/// `retryWhen`.
final class EventStreamRetryAdapter implements RetryStreamAdapter {
  /// The adapter.
  const EventStreamRetryAdapter();

  @override
  bool supports(Stream<Object?> stream) => stream is EventStream<Object?>;

  @override
  Stream<T> adapt<T>(StreamAttempts<T> attempts) => EventStream<T>(
    () => attempts.join((attempt) => (attempt as EventStream<T>).events),
  );
}
