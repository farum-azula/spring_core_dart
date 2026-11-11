import 'dart:convert';

import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_message.dart';

/// The wire format of a Phoenix socket: how a [PhoenixMessage] becomes a
/// text frame and back.
///
/// The server speaks the version the client names in the `vsn` query
/// parameter of the handshake. The starter has the two JSON formats of
/// Phoenix, [PhoenixSerializerV2] (the default) and [PhoenixSerializerV1];
/// a bean implementing this interface adds another, picked by its [vsn]
/// (`spring.websocket.client.config.<name>.phoenix.vsn`).
///
/// ```dart
/// const serializer = PhoenixSerializerV2();
/// serializer.encode(
///   const PhoenixMessage(topic: 'room:42', event: 'new_msg', ref: '3'),
/// ); // [null,"3","room:42","new_msg",null]
/// ```
///
/// Phoenix (Elixir): `Phoenix.Socket.Serializer`; in `phoenix.js` the
/// `encode` and `decode` options of the socket.
abstract interface class PhoenixSerializer {
  /// The version it implements, such as `2.0.0`: sent as the `vsn` query
  /// parameter.
  String get vsn;

  /// Writes [message] as a text frame. Throws when the payload is not
  /// JSON (a `JsonUnsupportedObjectError`).
  String encode(PhoenixMessage message);

  /// Reads the text [frame]. Throws a [FormatException] when it is not a
  /// message of this format; the socket skips such a frame.
  PhoenixMessage decode(String frame);
}

/// The first JSON format of Phoenix (`vsn=1.0.0`): each message is an
/// object, `{"topic", "event", "payload", "ref", "join_ref"}`.
///
/// Servers answer it without a `join_ref`, so a message of an earlier
/// join of a topic is recognised by its `ref` only.
///
/// ```dart
/// const PhoenixSerializerV1().encode(
///   const PhoenixMessage(topic: 'room:42', event: 'phx_join', ref: '1'),
/// ); // {"topic":"room:42","event":"phx_join","payload":null,"ref":"1",...}
/// ```
///
/// Phoenix (Elixir): `Phoenix.Socket.V1.JSONSerializer`.
final class PhoenixSerializerV1 implements PhoenixSerializer {
  /// The format of `vsn=1.0.0`.
  const PhoenixSerializerV1();

  @override
  String get vsn => '1.0.0';

  @override
  String encode(PhoenixMessage message) => jsonEncode({
    'topic': message.topic,
    'event': message.event,
    'payload': message.payload,
    'ref': message.ref,
    'join_ref': message.joinRef,
  });

  @override
  PhoenixMessage decode(String frame) => switch (jsonDecode(frame)) {
    {'topic': final String topic, 'event': final String event} && final json =>
      PhoenixMessage(
        topic: topic,
        event: event,
        payload: json['payload'],
        ref: _ref(json['ref']),
        joinRef: _ref(json['join_ref']),
      ),
    _ => throw FormatException('not a Phoenix message (vsn $vsn)', frame),
  };
}

/// The second JSON format of Phoenix (`vsn=2.0.0`), the default: each
/// message is an array, `[join_ref, ref, topic, event, payload]`.
///
/// Only its text frames are supported; a binary frame (Phoenix's binary
/// payloads) is skipped by the socket.
///
/// ```dart
/// const PhoenixSerializerV2().decode(
///   '["1","1","room:42","phx_reply",{"status":"ok","response":{}}]',
/// ); // a reply to the join "1" of room:42
/// ```
///
/// Phoenix (Elixir): `Phoenix.Socket.V2.JSONSerializer`.
final class PhoenixSerializerV2 implements PhoenixSerializer {
  /// The format of `vsn=2.0.0`.
  const PhoenixSerializerV2();

  @override
  String get vsn => '2.0.0';

  @override
  String encode(PhoenixMessage message) => jsonEncode([
    message.joinRef,
    message.ref,
    message.topic,
    message.event,
    message.payload,
  ]);

  @override
  PhoenixMessage decode(String frame) => switch (jsonDecode(frame)) {
    [
      final joinRef,
      final ref,
      final String topic,
      final String event,
      final payload,
    ] =>
      PhoenixMessage(
        topic: topic,
        event: event,
        payload: payload,
        ref: _ref(ref),
        joinRef: _ref(joinRef),
      ),
    _ => throw FormatException('not a Phoenix message (vsn $vsn)', frame),
  };
}

// Refs are strings on the wire; a server that counts them as numbers is
// read too.
String? _ref(Object? value) => value == null ? null : '$value';
