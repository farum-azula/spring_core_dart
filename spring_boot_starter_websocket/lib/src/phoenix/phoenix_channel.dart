import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Marks an abstract class as a channel of a Phoenix server (a Phoenix
/// application, or a service that speaks its protocol): the application
/// gets a bean that implements it over a shared socket.
///
/// Phoenix Channels put many topics on one WebSocket connection: a client
/// joins a topic, receives the events the server sends on it and pushes
/// its own, each with a reply. Instead of handling that by hand you
/// declare it: methods marked [OnEvent] give the events of one name as a
/// typed `Stream`, methods marked [Push] send one and return the reply,
/// and an optional `Future<void> leave()` leaves the topic. Any other
/// method fails the start. The generator writes the implementation (no
/// reflection); payloads are read and written as JSON through the
/// `ObjectMapper`. The bean is named after the class (`room`).
///
/// ```dart
/// @PhoenixChannel('chat', topic: 'room:{id}', url: r'${chat.url}')
/// abstract interface class Room {
///   @OnEvent('new_msg')
///   Stream<ChatMessage> messages(String id);
///
///   @Push('new_msg')
///   Future<Ack> send(String id, ChatMessage message);
///
///   Future<void> leave(String id);
/// }
///
/// @Service()
/// class Chat {
///   Chat(this.room); // the generated bean
///   final Room room;
///
///   // Listening joins room:42; it stays joined while we listen.
///   void open() => room.messages('42').listen(show);
///
///   Future<Ack> say(String text) =>
///       room.send('42', ChatMessage(from: 'me', text: text));
/// }
/// ```
///
/// The `{id}` of the [topic] is filled from the parameter named `id` of
/// each method, so one interface serves every room; each topic is one
/// channel, joined on its first listener or push and left when its last
/// listener cancels or `leave` is called. Interfaces with the same [name]
/// and address share one connection, kept and reconnected like a
/// `@WebSocketClient`'s; after a reconnection every topic is joined
/// again and the streams go on. What a join sends comes from a parameter
/// marked [JoinPayload] and from the [PhoenixJoinInterceptor] beans.
///
/// Phoenix (JavaScript):
/// ```js
/// let socket = new Socket("/socket"); socket.connect()
/// let room = socket.channel("room:42")
/// room.on("new_msg", show)
/// room.join()
/// room.push("new_msg", {body: "hi"}).receive("ok", ack => ...)
/// ```
///
/// Differs from Spring: Spring has no Phoenix client; like
/// `@WebSocketClient` it follows the `@FeignClient` style, an injectable
/// interface with typed streams.
@InterfaceProxy(primary: true)
class PhoenixChannel {
  /// A channel of the client [name], joining [topic] on the socket at
  /// [url] (or at the configured `url`).
  const PhoenixChannel(this.name, {required this.topic, this.url, this.vsn});

  /// The name of the client: its properties are
  /// `spring.websocket.client.config.<name>.*`, a
  /// `WebSocketHandshakeInterceptor` sees it as
  /// `WebSocketHandshake.clientName` and a [PhoenixJoinInterceptor] as
  /// [PhoenixJoin.clientName]. Interfaces with the same name and address
  /// share a connection.
  final String name;

  /// The topic to join, such as `lobby` or `room:{id}`. A `{name}` is
  /// replaced by the parameter of that name of the method called, so
  /// every method has one; `${...}` placeholders are resolved from the
  /// `Environment` once, at startup.
  final String topic;

  /// The address of the socket's WebSocket endpoint, `/websocket`
  /// included, such as `wss://chat.neon.books/socket/websocket`; `${...}`
  /// placeholders are resolved, as in `r'${chat.url}'`. When given, it
  /// wins over the configured `url`; without both, the start fails.
  final String? url;

  /// The version of the wire format, `2.0.0` or `1.0.0`; when given, it
  /// wins over the configured `phoenix.vsn` (`2.0.0` by default).
  final String? vsn;
}

/// Marks the method of a [PhoenixChannel] that gives the events named
/// [event] of the topic as a stream.
///
/// The method returns `Stream<T>` and takes the topic's parameters (and
/// an optional [JoinPayload]). `T` decides what the stream gives: a
/// payload that already is a `T` (a `String`, a `Map<String, Object?>`)
/// as it is, any other type the payload read as JSON. A payload that
/// cannot be read is an error event (a `MessageConversionException`) and
/// the stream goes on. Every call gives a new stream. Listening joins the
/// topic; when the last listener of a topic cancels, it is left.
///
/// ```dart
/// // In a @PhoenixChannel: each new_msg of the room as a ChatMessage.
/// @OnEvent('new_msg')
/// Stream<ChatMessage> messages(String id);
/// ```
///
/// Phoenix (JavaScript): `channel.on("new_msg", callback)`.
class OnEvent {
  /// Marks the method that gives the events named [event].
  const OnEvent(this.event);

  /// The name of the event, such as `new_msg` or `presence_diff`.
  final String event;
}

/// Marks a method of a [PhoenixChannel] that pushes the event named
/// [event] to the server and returns its reply.
///
/// The method returns a `Future` and takes the topic's parameters and at
/// most one more, the payload: written as JSON (a `String` and a `Map` as
/// they are); without one, `{}` is sent. A `Future<T>` completes with the
/// response of the reply read as `T`; a `Future<void>` waits for the
/// reply and ignores its response. The push joins the topic first when
/// needed. It fails with a `PhoenixPushException` when the server answers
/// `error`, with a `TimeoutException` when no reply comes within
/// `phoenix.push-timeout`, and with a `PhoenixJoinException` when the
/// topic cannot be joined.
///
/// ```dart
/// // In a @PhoenixChannel: the reply's response read as an Ack.
/// @Push('new_msg')
/// Future<Ack> send(String id, ChatMessage message);
///
/// // An event the server does not answer ({:noreply, socket}).
/// @Push('typing', reply: false)
/// Future<void> typing(String id);
/// ```
///
/// Phoenix (JavaScript):
/// `channel.push("new_msg", payload).receive("ok", ack => ...)`.
class Push {
  /// Marks the method that pushes the event named [event].
  const Push(this.event, {this.reply = true});

  /// The name of the event, such as `new_msg`.
  final String event;

  /// Whether the server answers the event. With `false`, for a
  /// `Future<void>` method only, the future completes once the event is
  /// sent, and nothing is awaited.
  final bool reply;
}

/// Marks the parameter of a [PhoenixChannel] method that carries what the
/// join of the topic sends, for a server whose `join/3` reads parameters.
///
/// Any method may have one. It is used when the call joins the topic
/// (the first listener or push), and kept for the joins after a
/// reconnection; a call on a topic that is joined already ignores it. The
/// value is written as JSON and must be an object (a `Map`, or a class);
/// `null` adds nothing. The [PhoenixJoinInterceptor] beans see it and may
/// add to it.
///
/// ```dart
/// // In a @PhoenixChannel: join room:42 from its 100th message on.
/// @OnEvent('new_msg')
/// Stream<ChatMessage> messages(String id, @JoinPayload() RoomJoin join);
/// ```
///
/// Phoenix (JavaScript): the `params` of `socket.channel(topic, params)`.
class JoinPayload {
  /// Marks the parameter that carries the join payload.
  const JoinPayload();
}

/// One join of a topic by a [PhoenixChannel] interface, before it is
/// sent: its [payload], which a [PhoenixJoinInterceptor] may change.
///
/// A new one is made for every join, the ones after a reconnection
/// included, starting from the [JoinPayload] argument, so an interceptor
/// can add a fresh token each time. Applications only meet it in an
/// interceptor.
final class PhoenixJoin {
  /// The join of [topic] by the client [clientName]; the starter creates
  /// it.
  PhoenixJoin({
    required this.clientName,
    required this.topic,
    Map<String, Object?>? payload,
  }) : payload = {...?payload};

  /// The name of the `@PhoenixChannel` that joins, so one interceptor can
  /// treat clients differently.
  final String clientName;

  /// The topic that is joined, its parameters filled in, such as
  /// `room:42`.
  final String topic;

  /// What the join sends, as JSON; a modifiable map.
  final Map<String, Object?> payload;

  @override
  String toString() => 'PhoenixJoin($clientName, $topic)';
}

/// A bean that changes the join payload of every [PhoenixChannel] topic
/// before it is sent, typically to add authentication.
///
/// Every bean implementing it is called, on each join and each join
/// again after a reconnection, so a token that expired in the meantime is
/// replaced by a fresh one. Check [PhoenixJoin.clientName] or
/// [PhoenixJoin.topic] when only some need it. A failing interceptor
/// fails that join, which is tried again.
///
/// ```dart
/// // The rooms want the user's current token when joined.
/// @Component()
/// class RoomAuth implements PhoenixJoinInterceptor {
///   RoomAuth(this.tokens);
///   final TokenStore tokens;
///
///   @override
///   Future<void> apply(PhoenixJoin join) async {
///     if (join.topic.startsWith('room:')) {
///       join.payload['token'] = await tokens.current();
///     }
///   }
/// }
/// ```
///
/// Phoenix (JavaScript): a function as the `params` of
/// `socket.channel(topic, () => ({token}))`.
abstract interface class PhoenixJoinInterceptor {
  /// Changes [join] before it is sent; it may wait, for example for a
  /// token refresh.
  FutureOr<void> apply(PhoenixJoin join);
}
