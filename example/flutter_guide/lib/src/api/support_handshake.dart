import 'package:neon_books_app/src/account/sso_properties.dart';
import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

/// Sends the session cookie with the support chat's handshake: the
/// handshake is an HTTP request that passes the server's security chain,
/// so the server knows who connects. Runs on every connection and
/// reconnection, so a new session (after a new login) is used. In a
/// browser the cookies go with the handshake by themselves (and headers
/// may not be set), so it is a bean everywhere but on the web.
///
/// After a Keycloak login of a native app (the `sso` profile) the server
/// knows the user by the access token, not by the session: the handshake
/// carries `Authorization: Bearer` too, a fresh token from the
/// [OAuth2AuthorizedClientManager] (a bean only where a registration is
/// configured).
@Component()
@Profile(['!web'])
class SupportHandshake implements WebSocketHandshakeInterceptor {
  SupportHandshake(this._cookies, this._sso, this._tokens);

  final CookieJar _cookies;
  final SsoProperties _sso;
  final OAuth2AuthorizedClientManager? _tokens;

  @override
  Future<void> apply(WebSocketHandshake handshake) async {
    if (handshake.clientName != 'support') {
      return;
    }
    if (_cookies.header case final cookies?) {
      handshake.headers.set(HttpHeaders.cookieHeader, cookies);
    }
    final user = SecurityContextHolder.getContext().authentication;
    if (_tokens case final tokens? when user is OAuth2AuthenticationToken) {
      final client = await tokens.authorize(
        OAuth2AuthorizeRequest.withClientRegistrationId(
          _sso.registrationId,
        ).principal(user).build(),
      );
      if (client?.accessToken.tokenValue case final token?) {
        handshake.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
    }
  }
}
