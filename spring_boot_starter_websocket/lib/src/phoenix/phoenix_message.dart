import 'dart:async';

/// One message of the Phoenix Channels protocol, in either direction: an
/// [event] with a [payload] on a [topic], numbered by [ref] and tied to
/// one join of the topic by [joinRef].
///
/// Applications meet it on `PhoenixChannelSession.messages`, for the
/// events a server pushes or broadcasts; a `PhoenixSerializer` writes and
/// reads it as a text frame.
///
/// ```dart
/// // Every event of the room, whatever its name.
/// room.messages.listen((message) {
///   log.info('${message.event}: ${message.payload}');
/// });
/// ```
///
/// Phoenix (Elixir): `Phoenix.Socket.Message`, with the same fields.
final class PhoenixMessage {
  /// A message for [topic] with the name [event].
  const PhoenixMessage({
    required this.topic,
    required this.event,
    this.payload,
    this.ref,
    this.joinRef,
  });

  /// The channel the message belongs to, such as `room:42`; `phoenix`
  /// for the heartbeat.
  final String topic;

  /// The name of the event, such as `new_msg`; the protocol's own start
  /// with `phx_` (see [PhoenixEvents]).
  final String event;

  /// What the event carries, as decoded JSON: usually a map.
  final Object? payload;

  /// The number of a message that expects a reply, unique on its socket;
  /// the reply carries the same one. `null` for a broadcast.
  final String? ref;

  /// The [ref] of the join the message belongs to, so a message of an
  /// earlier join of the same topic can be told apart; `null` for a
  /// broadcast and for the heartbeat.
  final String? joinRef;

  @override
  String toString() =>
      'PhoenixMessage($topic $event, ref: $ref, joinRef: $joinRef, '
      '$payload)';
}

/// The names the Phoenix Channels protocol keeps for itself: the events
/// that join, leave and end a channel, the reply, and the heartbeat.
///
/// ```dart
/// // What a join looks like on the wire.
/// PhoenixMessage(topic: 'room:42', event: PhoenixEvents.join, ref: '1');
/// ```
///
/// Phoenix (JavaScript): `CHANNEL_EVENTS` of `phoenix.js`.
abstract final class PhoenixEvents {
  /// `phx_join`: the client joins a topic.
  static const join = 'phx_join';

  /// `phx_leave`: the client leaves a topic.
  static const leave = 'phx_leave';

  /// `phx_reply`: the server's answer to the message with the same `ref`.
  static const reply = 'phx_reply';

  /// `phx_close`: the server closed the channel.
  static const close = 'phx_close';

  /// `phx_error`: the channel crashed on the server; the client joins
  /// again.
  static const error = 'phx_error';

  /// `heartbeat`: sent on the [heartbeatTopic] to keep the connection
  /// open and to find a dead one.
  static const heartbeat = 'heartbeat';

  /// `phoenix`: the topic of the heartbeat.
  static const heartbeatTopic = 'phoenix';
}

/// The server's answer to a join or a push: a [status], `ok` or `error`,
/// and a [response].
///
/// ```dart
/// final reply = await room.push('new_msg', {'body': 'hi'});
/// log.info('stored as ${(reply.response! as Map)['id']}');
/// ```
///
/// Phoenix (Elixir): `{:reply, {:ok, response}, socket}` in a channel's
/// `handle_in`, a `Phoenix.Socket.Reply` on the wire.
final class PhoenixReply {
  /// A reply with [status] and [response].
  const PhoenixReply({required this.status, this.response});

  /// Reads the payload of a `phx_reply` message,
  /// `{"status": ..., "response": ...}`; a payload of another shape gives
  /// an `error` reply with the payload as its response.
  factory PhoenixReply.of(Object? payload) => switch (payload) {
    {'status': final String status} && final Map<Object?, Object?> reply =>
      PhoenixReply(status: status, response: reply['response']),
    _ => PhoenixReply(status: error, response: payload),
  };

  /// The status of a reply that succeeded.
  static const ok = 'ok';

  /// The status of a reply that failed.
  static const error = 'error';

  /// `ok` or `error`.
  final String status;

  /// What the server answered, as decoded JSON: usually a map, empty when
  /// there is nothing to say.
  final Object? response;

  /// Whether the [status] is `ok`.
  bool get isOk => status == ok;

  @override
  String toString() => 'PhoenixReply($status, $response)';
}

/// Thrown by `PhoenixChannelSession.join` when the topic could not be
/// joined: the server answered `error` (the [reply] says why, such as
/// `{"reason": "unauthorized"}`), no answer came in time ([isTimeout]),
/// or the channel was left or closed first.
///
/// The channel goes on trying, as a Phoenix client does, until it is
/// left.
///
/// ```dart
/// try {
///   await room.join();
/// } on PhoenixJoinException catch (error) {
///   log.warning('cannot join ${error.topic}: ${error.reply?.response}');
///   await room.leave(); // or keep it: it joins again by itself
/// }
/// ```
///
/// Phoenix (JavaScript): the `error` and `timeout` hooks of
/// `channel.join().receive(...)`.
class PhoenixJoinException implements Exception {
  /// A failed join of [topic], described by [message].
  PhoenixJoinException(
    this.topic,
    this.message, {
    this.reply,
    this.isTimeout = false,
    this.cause,
  });

  /// The topic that was not joined.
  final String topic;

  /// What went wrong, for people.
  final String message;

  /// The server's `error` reply, or `null` when there was none.
  final PhoenixReply? reply;

  /// Whether no reply came within the push timeout.
  final bool isTimeout;

  /// The error behind it, such as the one a join payload function threw.
  final Object? cause;

  @override
  String toString() => 'PhoenixJoinException: $topic: $message';
}

/// Thrown by `PhoenixChannelSession.push` when the server answered the
/// push with an `error` ([reply] holds its response), or when the channel
/// closed before the answer.
///
/// A push without any answer in time fails with a [TimeoutException]
/// instead.
///
/// ```dart
/// try {
///   await room.push('new_msg', {'body': ''});
/// } on PhoenixPushException catch (error) {
///   log.warning('rejected: ${error.reply?.response}');
/// }
/// ```
///
/// Phoenix (JavaScript): the `error` hook of
/// `channel.push(...).receive("error", ...)`.
class PhoenixPushException implements Exception {
  /// A failed push of [event] on [topic], described by [message].
  PhoenixPushException(this.topic, this.event, this.message, {this.reply});

  /// The topic of the push.
  final String topic;

  /// The event that was pushed.
  final String event;

  /// What went wrong, for people.
  final String message;

  /// The server's `error` reply, or `null` when the channel closed before
  /// one came.
  final PhoenixReply? reply;

  @override
  String toString() => 'PhoenixPushException: $topic $event: $message';
}
