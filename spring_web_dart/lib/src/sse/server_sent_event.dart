/// One server-sent event (one chunk of a `text/event-stream` response):
/// the [data] plus the optional [id], [event] name, [retry] delay and
/// [comment]. [T] is the type of the data: `String` as sent, or a class
/// read from the JSON data.
///
/// Usually you do not write this type: a Feign method returns
/// `EventStream<OrderEvent>`, which is a `Stream<OrderEvent>`; the whole
/// events are there when you need them (`stream.events`).
///
/// ```dart
/// api.orders().events.listen((ServerSentEvent<OrderEvent> e) {
///   print('${e.id} ${e.event}: ${e.data.status}');
/// });
/// ```
///
/// Spring (Java): `ServerSentEvent<T>`.
/// ```java
/// Flux<ServerSentEvent<OrderEvent>> events = webClient.get().uri("/orders/events")
///     .retrieve().bodyToFlux(new ParameterizedTypeReference<>() {});
/// ```
final class ServerSentEvent<T> {
  /// An event carrying [data].
  const ServerSentEvent(
    this.data, {
    this.id,
    this.event,
    this.retry,
    this.comment,
  });

  /// The data (the `data:` lines, joined with newlines, then decoded).
  final T data;

  /// The `id:` of this event, if it has one. After a lost connection the
  /// last id is sent back in the `Last-Event-ID` header.
  final String? id;

  /// The `event:` name, e.g. `order-created` (`null`: the default
  /// `message`).
  final String? event;

  /// The `retry:` delay the server asks for before reconnecting.
  final Duration? retry;

  /// The `:` comment lines, joined with newlines.
  final String? comment;

  /// This event with other [data] (e.g. the decoded form of the text).
  ServerSentEvent<R> withData<R>(R data) => ServerSentEvent<R>(
    data,
    id: id,
    event: event,
    retry: retry,
    comment: comment,
  );

  /// This event in the `text/event-stream` format, ending with the blank
  /// line; [text] turns the data into text (default: `toString`).
  ///
  /// ```dart
  /// const ServerSentEvent('hello', id: '1').encode(); // 'id: 1\ndata: hello\n\n'
  /// ```
  String encode([String Function(T data)? text]) {
    final out = StringBuffer();
    void lines(String field, String value) {
      for (final line in value.split(RegExp('\r\n|\r|\n'))) {
        out.write(
          line.isEmpty ? '${field.isEmpty ? ':' : field}\n' : '$field: $line\n',
        );
      }
    }

    if (comment case final comment?) {
      lines('', comment);
    }
    if (id case final id?) {
      lines('id', id);
    }
    if (event case final event?) {
      lines('event', event);
    }
    if (retry case final retry?) {
      out.write('retry: ${retry.inMilliseconds}\n');
    }
    final value = data;
    if (value != null) {
      lines('data', text == null ? '$value' : text(value));
    }
    out.write('\n');
    return out.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is ServerSentEvent<Object?> &&
      other.data == data &&
      other.id == id &&
      other.event == event &&
      other.retry == retry &&
      other.comment == comment;

  @override
  int get hashCode => Object.hash(data, id, event, retry, comment);

  @override
  String toString() => [
    'ServerSentEvent(',
    [
      if (id != null) 'id: $id',
      if (event != null) 'event: $event',
      if (retry != null) 'retry: ${retry!.inMilliseconds} ms',
      if (comment != null) 'comment: $comment',
      'data: $data',
    ].join(', '),
    ')',
  ].join();
}
