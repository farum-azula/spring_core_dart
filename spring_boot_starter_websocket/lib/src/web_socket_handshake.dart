import 'dart:async';

import 'package:spring_web_dart/spring_web_dart.dart';

/// The handshake of one connection attempt of a `@WebSocketClient`, open
/// to [WebSocketHandshakeInterceptor]s: change the [url] (e.g. add a
/// token as a query parameter), [headers] or [protocols].
///
/// Browsers cannot send headers with a WebSocket handshake: in Flutter web
/// put tokens in the URL or a protocol instead (a header fails there).
final class WebSocketHandshake {
  /// The handshake of client [clientName] to [url].
  WebSocketHandshake({
    required this.clientName,
    required this.url,
    HttpHeaders? headers,
    List<String> protocols = const [],
  }) : headers = headers ?? HttpHeaders(),
       protocols = [...protocols];

  /// The `@WebSocketClient` name.
  final String clientName;

  /// The address to connect to.
  Uri url;

  /// The handshake headers.
  final HttpHeaders headers;

  /// The subprotocols offered.
  final List<String> protocols;

  /// Adds the query parameter [name] (replacing one with that name).
  void queryParameter(String name, String value) {
    url = url.replace(
      queryParameters: {...url.queryParametersAll, name: value},
    );
  }

  @override
  String toString() => 'WebSocketHandshake($clientName, $url)';
}

/// Changes every handshake of the `@WebSocketClient`s before it is sent,
/// on each connection and reconnection (so a fresh token is used). Declare
/// it as a bean.
///
/// ```dart
/// @Component()
/// class ChatAuth implements WebSocketHandshakeInterceptor {
///   ChatAuth(this.tokens);
///   final TokenStore tokens;
///
///   @override
///   Future<void> apply(WebSocketHandshake handshake) async {
///     if (handshake.clientName == 'chat') {
///       handshake.queryParameter('token', await tokens.current());
///     }
///   }
/// }
/// ```
///
/// Spring (Java): `WebSocketHttpHeaders` passed to
/// `WebSocketClient.execute`, or a `StompSessionHandler` adding headers to
/// the `CONNECT` frame.
abstract interface class WebSocketHandshakeInterceptor {
  /// Changes [handshake].
  FutureOr<void> apply(WebSocketHandshake handshake);
}
