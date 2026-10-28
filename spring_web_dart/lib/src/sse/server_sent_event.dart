/// One server-sent event, the unit of a `text/event-stream` response: its
/// [data], plus an optional [id], [event] name, [retry] delay and
/// [comment].
///
/// [T] is the type of the data: `String` as it travels, or a class that
/// is written to and read from JSON. The extra fields are what the
/// protocol adds to plain data. The [event] name lets one stream carry
/// several kinds of messages. The [id] lets a client resume after a lost
/// connection, since it sends the last id back in `Last-Event-ID`. The
/// [retry] delay tells the client how long to wait before reconnecting.
///
/// You need this type only when those fields matter. A client reading an
/// `EventStream<T>` gets the data directly and finds the whole events in
/// `EventStream.events`. A server writes the data of a plain `Stream<T>`
/// or `EventStream<T>` as events by itself; it emits a `ServerSentEvent`
/// (in a stream or through an `SseEmitter`) to set a name or an id.
///
/// ```dart
/// // Server: name each event so the client can tell the kinds apart, and
/// // give it an id so a reconnecting client can resume after it.
/// @GetMapping('/orders/events')
/// Stream<ServerSentEvent<Order>> events() => orders.changes.map(
///   (order) => ServerSentEvent(order, id: order.id, event: 'order-updated'),
/// );
///
/// // Client: a Feign method returning EventStream<Order>.
/// client.events().events.listen((ServerSentEvent<Order> e) {
///   print('${e.id} ${e.event}: ${e.data.status}');
/// });
/// ```
///
/// Spring (Java): `ServerSentEvent<T>`, built with a builder on the server
/// and read with `WebClient` on the client:
/// ```java
/// ServerSentEvent.builder(order).id(order.id()).event("order-updated")
///     .build();
///
/// Flux<ServerSentEvent<Order>> events = webClient.get()
///     .uri("/orders/events")
///     .retrieve()
///     .bodyToFlux(new ParameterizedTypeReference<>() {});
/// ```
final class ServerSentEvent<T> {
  /// An event carrying [data], with the other fields when given. A `null`
  /// field is left out when the event is written.
  const ServerSentEvent(
    this.data, {
    this.id,
    this.event,
    this.retry,
    this.comment,
  });

  /// The payload. On the wire it is the event's `data:` lines, joined with
  /// newlines; a client then decodes that text into [T].
  final T data;

  /// The event's `id:`, or `null` when it has none. After a lost
  /// connection a client sends the last id it saw back in the
  /// `Last-Event-ID` header, so the server can resume after it.
  final String? id;

  /// The `event:` name, such as `order-created`; `null` for an unnamed
  /// event, which the protocol calls `message`.
  final String? event;

  /// The `retry:` delay: how long the server asks clients to wait before
  /// reconnecting. Sent in whole milliseconds.
  final Duration? retry;

  /// The comment lines (lines starting with `:`), joined with newlines.
  /// Clients ignore them; servers send them as keep-alive heartbeats.
  final String? comment;

  /// This event with other [data] and the same id, name, retry and
  /// comment: for example the decoded object in place of the received
  /// text.
  ServerSentEvent<R> withData<R>(R data) => ServerSentEvent<R>(
    data,
    id: id,
    event: event,
    retry: retry,
    comment: comment,
  );

  /// This event in the `text/event-stream` format, ready to write to a
  /// response: comment, `id:`, `event:`, `retry:` and `data:` lines, then
  /// the blank line that ends the event.
  ///
  /// [text] turns the data into text (the web starter passes a JSON
  /// encoder); without it `toString` is used. A multi-line value becomes
  /// one line per line, and a `null` [data] gives no `data:` line.
  ///
  /// ```dart
  /// // 'id: 1\ndata: hello\n\n'
  /// const ServerSentEvent('hello', id: '1').encode();
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
