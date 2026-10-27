import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// A [WebSocketTransport] on `dart:io`'s `WebSocket`: the VM, Flutter
/// mobile and desktop. Sends handshake headers (e.g. `Authorization`).
///
/// ```dart
/// import 'package:spring_web_dart/io.dart';
///
/// final transport = IoWebSocketTransport();
/// final session = await transport.connect(
///   Uri.parse('wss://chat.neon.books/ws'),
///   headers: HttpHeaders({'Authorization': 'Bearer $token'}),
/// );
/// ```
///
/// Spring (Java): `StandardWebSocketClient`.
class IoWebSocketTransport implements WebSocketTransport {
  /// A transport; `client` is used for the handshakes (proxy, TLS
  /// settings).
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

/// A [WebSocketSession] over `dart:io`'s `WebSocket`: what
/// [IoWebSocketTransport] connects, and what the web starter's server
/// accepts (`ServerHttpRequest.upgradeToWebSocket`).
final class IoWebSocketSession implements WebSocketSession {
  /// The session of the open `socket`, connected to [uri].
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
