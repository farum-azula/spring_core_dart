import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// The [WebSocketTransport] for platforms with `dart:io` (the Dart VM,
/// Flutter on mobile and desktop), built on `dart:io`'s `WebSocket`.
///
/// `platformWebSocketTransport()` returns one on these platforms, so you
/// create it yourself only to pass an `HttpClient` for the handshakes: a
/// proxy, trusted certificates. Unlike the browser transport it sends
/// handshake headers, such as `Authorization`. A handshake that fails or
/// runs out of time throws a [WebSocketException].
///
/// ```dart
/// import 'package:spring_web_dart/io.dart';
///
/// // A token in a header, which a browser could not send.
/// final transport = IoWebSocketTransport();
/// final session = await transport.connect(
///   Uri.parse('wss://chat.neon.books/ws'),
///   headers: HttpHeaders({'Authorization': 'Bearer $token'}),
/// );
/// ```
///
/// Spring (Java): `StandardWebSocketClient`.
class IoWebSocketTransport implements WebSocketTransport {
  /// A transport whose handshakes go through `client`, an `HttpClient`
  /// with your proxy or TLS settings; without it `dart:io` uses a default
  /// client.
  IoWebSocketTransport({this._client});

  // The client for the handshakes (`null`: a default one).
  final io.HttpClient? _client;

  @override
  Future<WebSocketSession> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
  }) async {
    final handshake = io.WebSocket.connect(
      url.toString(),
      protocols: protocols.isEmpty ? null : protocols,
      headers: headers?.toMap(),
      customClient: _client,
    );
    try {
      final socket = timeout == null
          ? await handshake
          : await handshake.timeout(
              timeout,
              onTimeout: () {
                // Close the socket if the handshake completes late.
                unawaited(
                  handshake.then((s) => s.close(), onError: (Object _) {}),
                );
                throw TimeoutException('handshake', timeout);
              },
            );
      return IoWebSocketSession(socket, url);
    } on TimeoutException catch (error) {
      throw WebSocketException(
        'no handshake within ${timeout!.inMilliseconds} ms',
        url: url,
        cause: error,
        isTimeout: true,
      );
    } on Object catch (error) {
      if (error is WebSocketException) {
        rethrow;
      }
      throw WebSocketException(
        'cannot connect: $error',
        url: url,
        cause: error,
      );
    }
  }
}

/// A [WebSocketSession] over an open `dart:io` `WebSocket`, on either
/// side of the connection.
///
/// [IoWebSocketTransport] returns one for a client connection, and the
/// web starter's server returns one from
/// `ServerHttpRequest.upgradeToWebSocket` for an accepted connection.
/// Create one yourself only to wrap a `WebSocket` you opened with
/// `dart:io` directly.
///
/// A broken connection ends [messages] with a [WebSocketException].
/// [closeStatus] gives the code the other side sent; if this side closed
/// first and no answer has arrived yet, it gives the status passed to
/// [close].
final class IoWebSocketSession implements WebSocketSession {
  /// A session over the open `socket`, whose address is [uri].
  IoWebSocketSession(this._socket, this.uri);

  final io.WebSocket _socket;

  @override
  final Uri uri;

  @override
  late final Stream<Object> messages = _socket
      .map<Object>(
        (message) => switch (message) {
          final String text => text,
          final Uint8List bytes => bytes,
          final List<int> bytes => Uint8List.fromList(bytes),
          _ => '$message',
        },
      )
      .handleError(
        (Object error) => throw WebSocketException(
          'connection broke: $error',
          url: uri,
          cause: error,
        ),
        test: (error) => error is! WebSocketException,
      );

  @override
  String? get acceptedProtocol => _socket.protocol;

  @override
  bool get isOpen => _socket.readyState == io.WebSocket.open;

  @override
  void sendMessage(Object message) {
    if (_socket.readyState != io.WebSocket.open) {
      throw WebSocketException('the connection is closed', url: uri);
    }
    switch (message) {
      case String():
        _socket.add(message);
      case List<int>():
        _socket.add(message);
      default:
        throw ArgumentError.value(
          message,
          'message',
          'a String or a List<int>',
        );
    }
  }

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) {
    _local ??= status;
    return _socket.close(status.code, status.reason);
  }

  // What the client closed with (the server's answer may come later).
  CloseStatus? _local;

  @override
  CloseStatus? get closeStatus => switch (_socket.closeCode) {
    final code? => CloseStatus(code, switch (_socket.closeReason) {
      final reason? when reason.isNotEmpty => reason,
      _ => null,
    }),
    null => _local,
  };
}
