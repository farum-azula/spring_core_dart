import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

/// Sends the session cookie with the support chat's handshake: the
/// handshake is an HTTP request that passes the server's security chain,
/// so the server knows who connects. Runs on every connection and
/// reconnection, so a new session (after a new login) is used. In a
/// browser the cookies go with the handshake by themselves (and headers
/// may not be set), so it is a bean everywhere but on the web.
@Component()
@Profile(['!web'])
class SupportHandshake implements WebSocketHandshakeInterceptor {
  SupportHandshake(this._cookies);

  final CookieJar _cookies;

  @override
  void apply(WebSocketHandshake handshake) {
    if (handshake.clientName == 'support') {
      if (_cookies.header case final cookies?) {
        handshake.headers.set(HttpHeaders.cookieHeader, cookies);
      }
    }
  }
}
