import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/config/web_socket_properties.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_serializer.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_socket.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client_config.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_handshake.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_url.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The bean that makes the [PhoenixSocket]s of the application, one per
/// client name and address, and closes them when the application stops.
///
/// The starter registers it as `phoenixSocketFactory`. The
/// `@PhoenixChannel` interfaces take their sockets from it, and so does a
/// library that speaks the Phoenix Channels protocol in code. A socket
/// gets the settings of its name
/// (`spring.websocket.client.config.<name>.*`, with `phoenix.*` for the
/// heartbeat, the push timeout and the `vsn`), the application's
/// [WebSocketTransport] and its [WebSocketHandshakeInterceptor] beans.
///
/// ```dart
/// @Service()
/// class Presence {
///   Presence(PhoenixSocketFactory sockets)
///     : _lobby = sockets.socket('chat').channel('lobby');
///
///   final PhoenixChannelSession _lobby;
///
///   Stream<Object?> watch() {
///     _lobby.join().ignore();
///     return _lobby.on('presence_diff');
///   }
/// }
/// ```
///
/// Phoenix (JavaScript): `new Socket(endPoint, opts)`; there is no
/// registry of sockets there.
final class PhoenixSocketFactory implements DisposableBean {
  /// A factory reading the client settings from [properties], with the
  /// given [transport] and [interceptors]. [serializers] come before the
  /// two formats of the starter, so one of them may replace a `vsn`.
  PhoenixSocketFactory({
    required this.environment,
    required this.properties,
    required this.transport,
    this.interceptors = const [],
    List<PhoenixSerializer> serializers = const [],
  }) : serializers = List.unmodifiable([
         ...serializers,
         const PhoenixSerializerV2(),
         const PhoenixSerializerV1(),
       ]);

  /// Where the `${...}` of a configured URL are resolved.
  final Environment environment;

  /// The bound `spring.websocket.client.*` properties.
  final WebSocketProperties properties;

  /// Opens the connections: `dart:io` or the browser, or a mock in tests.
  final WebSocketTransport transport;

  /// Called on every handshake of every socket, in this order, after the
  /// socket added its `vsn` and parameters.
  final List<WebSocketHandshakeInterceptor> interceptors;

  /// The wire formats a socket may speak, picked by their `vsn`: the
  /// application's [PhoenixSerializer] beans, then [PhoenixSerializerV2]
  /// and [PhoenixSerializerV1].
  final List<PhoenixSerializer> serializers;

  final _sockets = <String, PhoenixSocket>{};

  /// The settings of the client [name], from
  /// `spring.websocket.client.config.<name>.*`.
  WebSocketClientConfig configOf(String name) =>
      WebSocketClientConfig.of(properties, name);

  /// The wire format of the version [vsn], or `null` when there is
  /// none.
  PhoenixSerializer? serializerOf(String vsn) =>
      serializers.where((serializer) => serializer.vsn == vsn).firstOrNull;

  /// The socket of the client [name] for [url], made on the first call
  /// and shared by the later ones with the same name and address.
  ///
  /// Without [url] the address is the configured
  /// `spring.websocket.client.config.<name>.url`. [vsn] wins over the
  /// configured `phoenix.vsn`. [parameters] gives the extra query
  /// parameters of every handshake; those of the call that made the
  /// socket are kept.
  ///
  /// Throws a [StateError] when there is no address, when it does not
  /// start with `ws://` or `wss://`, when no [PhoenixSerializer] has the
  /// `vsn`, or when the socket exists with another `vsn`.
  PhoenixSocket socket(
    String name, {
    Uri? url,
    String? vsn,
    PhoenixParameters? parameters,
  }) {
    final config = configOf(name);
    final problems = <String>[];
    final address =
        url ??
        resolveClientUrl(
          environment,
          config.url,
          problems,
          missing:
              'no URL: pass one or set '
              'spring.websocket.client.config.$name.url',
        );
    final version = vsn ?? config.phoenix.vsn;
    final serializer = serializerOf(version);
    if (serializer == null) {
      final known = {for (final serializer in serializers) serializer.vsn};
      problems.add(
        'no PhoenixSerializer for vsn "$version" (known: ${known.join(', ')})',
      );
    }
    if (address == null || serializer == null) {
      throw StateError(
        'Invalid Phoenix socket $name: ${problems.join('; ')}',
      );
    }
    final existing = _sockets['$name $address'];
    if (existing == null) {
      return _sockets['$name $address'] = PhoenixSocket(
        name: name,
        url: address,
        config: config,
        transport: transport,
        serializer: serializer,
        parameters: parameters,
        interceptors: interceptors,
      );
    }
    if (existing.serializer.vsn != version) {
      throw StateError(
        'Invalid Phoenix socket $name: it speaks vsn '
        '${existing.serializer.vsn} already, not $version (one connection '
        'has one wire format)',
      );
    }
    return existing;
  }

  /// Closes every socket when the application stops; later use of one
  /// fails with a [StateError]. With open connections it returns a future
  /// that completes once they are closed, which `closeAsync()` awaits.
  @override
  FutureOr<void> destroy() {
    final sockets = [..._sockets.values];
    _sockets.clear();
    final closing = <Future<void>>[];
    for (final socket in sockets) {
      if (socket.isConnected) {
        closing.add(socket.dispose());
      } else {
        // Nothing to wait for: no connection to close.
        unawaited(socket.dispose());
      }
    }
    if (closing.isNotEmpty) {
      return Future.wait(closing).then((_) {});
    }
  }
}
