import 'dart:async';

import 'package:spring_web_dart/spring_web_dart.dart';

/// The request that opens one connection of a `@WebSocketClient`, before
/// it is sent: its [url], [headers] and [protocols], which a
/// [WebSocketHandshakeInterceptor] may change.
///
/// A new one is made for every attempt, reconnections included, from the
/// client's URL, its `default-request-headers` and its protocols, so an
/// interceptor can add a fresh token each time. Applications only meet
/// it in an interceptor.
///
/// Browsers cannot send headers with a WebSocket handshake: in Flutter web
/// put tokens in the URL or a protocol instead (a header fails there with
/// a `WebSocketException`).
final class WebSocketHandshake {
  /// The handshake of the client [clientName] to [url]; the starter
  /// creates it.
  WebSocketHandshake({
    required this.clientName,
    required this.url,
    HttpHeaders? headers,
    List<String> protocols = const [],
  }) : headers = headers ?? HttpHeaders(),
       protocols = [...protocols];

  /// The name of the `@WebSocketClient` that connects, so one interceptor
  /// can treat clients differently.
  final String clientName;

  /// The address to connect to; replace it to change the server or the
  /// query, or use [queryParameter].
  Uri url;

  /// The headers sent with the handshake, starting with the configured
  /// `default-request-headers`. Not possible in browsers.
  final HttpHeaders headers;

  /// The subprotocols offered to the server (`Sec-WebSocket-Protocol`),
  /// starting with `@WebSocketClient(protocols:)`; a modifiable list.
  final List<String> protocols;

  /// Sets the query parameter [name] of [url] to [value], replacing any
  /// with that name, such as a token that works in browsers too.
  void queryParameter(String name, String value) {
    url = url.replace(
      queryParameters: {...url.queryParametersAll, name: value},
    );
  }

  @override
  String toString() => 'WebSocketHandshake($clientName, $url)';
}

/// A bean that changes the handshake of every `@WebSocketClient`
/// connection before it is sent, typically to add authentication.
///
/// Every bean implementing it is called, on each connection and
/// reconnection, so a token that expired in the meantime is replaced by a
/// fresh one. Check [WebSocketHandshake.clientName] when only some
/// clients need it. A failing interceptor fails that connection attempt.
///
/// ```dart
/// // The chat server wants the user's current token in the URL.
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
/// For an OAuth 2.0 access token, the OAuth2 client's
/// `OAuth2AccessTokenHeaders` writes the headers by the token's type:
/// `Authorization: Bearer <token>`, or for a DPoP-bound token
/// `Authorization: DPoP <token>` and a proof whose `htu` is the `http(s)`
/// form of the `ws(s)` URL (the handshake is an HTTP `GET` of it).
///
/// Spring (Java): `WebSocketHttpHeaders` passed to
/// `WebSocketClient.execute`, or a `StompSessionHandler` adding headers to
/// the `CONNECT` frame.
abstract interface class WebSocketHandshakeInterceptor {
  /// Changes [handshake] before it is sent; it may wait, for example
  /// for a token refresh.
  FutureOr<void> apply(WebSocketHandshake handshake);
}
