import 'dart:async';

import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client.dart';
import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client_manager.dart';
import 'package:spring_boot_starter_oauth2_client/src/client/oauth2_access_token_headers.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/tokens.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_key.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_nonces.dart';
import 'package:spring_boot_starter_oauth2_client/src/web/client_attributes.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.security.oauth2.client.web.client');

/// A `RestClient` interceptor that sends the OAuth 2.0 access token of a
/// registration with a call: `Authorization: Bearer <token>`, or for a
/// DPoP-bound token `Authorization: DPoP <token>` and a fresh proof for
/// that request.
///
/// The registration is the request attribute
/// [ClientAttributes.clientRegistrationIdAttributeName] (set by
/// `@ClientRegistrationId` on an HTTP service interface or method, or by
/// `.attributes(ClientAttributes.clientRegistrationId('partner'))` on a
/// call), else [defaultClientRegistrationId]. A call with neither is sent
/// as it is: the interceptor can sit on every client and add tokens only
/// where they are asked for. The principal is the security context's
/// authentication, else `anonymousUser` (the principal of
/// client-credentials tokens).
///
/// The token comes from the [OAuth2AuthorizedClientManager] at each call,
/// so it is refreshed when it expires within a minute, and two calls at
/// once share one refresh. When the manager has no client (and needs no
/// login) the call is sent without a token; a registration that does not
/// exist, a login that is needed (`ClientAuthorizationRequiredException`)
/// or a refused refresh fail the call before it is sent.
///
/// After the answer:
///
/// - a `DPoP-Nonce` header (on any answer) goes into the next proof for
///   that server;
/// - a `401` with `WWW-Authenticate: DPoP error="use_dpop_nonce"` is sent
///   once more, with a proof that carries the new nonce (RFC 9449 §9: the
///   server refused the request before handling it); a streamed body that
///   cannot be sent again (`StreamingBody.isRepeatable`) is not, and the
///   `401` is the answer;
/// - another `401` marks the token expired when it is still the stored
///   one ([authorizedClientService]), so the next call refreshes it (or
///   gets a new client-credentials token); the call itself is not
///   repeated.
///
/// ```dart
/// final rest = RestClient.builder()
///     .baseUrl('https://api.partner.example')
///     .requestInterceptor(OAuth2ClientHttpRequestInterceptor(manager))
///     .build();
/// final orders = await rest.get()
///     .uri('/orders')
///     .attributes(ClientAttributes.clientRegistrationId('partner'))
///     .retrieve()
///     .body<String>();
/// ```
///
/// In an application the starter adds it to every `RestClientBuilder` it
/// makes (`spring.security.oauth2.client.restclient.enabled`), or to the
/// HTTP service groups of `OAuth2RestClientHttpServiceGroupConfigurer`.
///
/// It never reads the body (a `StreamingClientHttpRequestInterceptor`), so
/// an upload streamed by the client passes it as a stream rather than
/// being read whole into memory first.
///
/// Spring Security 7 (Java): `OAuth2ClientHttpRequestInterceptor`
/// (`org.springframework.security.oauth2.client.web.client`), with
/// `RequestAttributeClientRegistrationIdResolver` and
/// `SecurityContextHolderPrincipalResolver`; the default registration,
/// DPoP and the expired mark on a `401` (Spring removes the client) are
/// additions, and so is the streamed body (Spring's interceptors get the
/// body as bytes).
final class OAuth2ClientHttpRequestInterceptor
    implements StreamingClientHttpRequestInterceptor {
  /// An interceptor taking tokens from [authorizedClientManager]; calls
  /// without the registration attribute use [defaultClientRegistrationId]
  /// (none by default); [authorizedClientService] (where the manager
  /// keeps the clients) lets a `401` mark a token expired; [dPoPKey] signs
  /// the proofs of DPoP-bound tokens; `clock` gives the proofs' time (the
  /// current time by default).
  OAuth2ClientHttpRequestInterceptor(
    this.authorizedClientManager, {
    String? defaultClientRegistrationId,
    this.authorizedClientService,
    SecurityContextHolderStrategy? securityContextHolderStrategy,
    this.dPoPKey,
    this._clock,
  }) : defaultClientRegistrationId =
           defaultClientRegistrationId == null ||
               defaultClientRegistrationId.trim().isEmpty
           ? null
           : defaultClientRegistrationId.trim(),
       _strategy =
           securityContextHolderStrategy ??
           SecurityContextHolder.getContextHolderStrategy();

  /// Where tokens come from.
  final OAuth2AuthorizedClientManager authorizedClientManager;

  /// Where the clients are kept, for the expired mark after a `401`;
  /// `null` to never mark.
  final OAuth2AuthorizedClientService? authorizedClientService;

  /// The registration of a call without the registration attribute, or
  /// `null` to send such a call without a token.
  final String? defaultClientRegistrationId;

  /// The key of the DPoP proofs, or `null` when the tokens are `Bearer`.
  final DPoPKey? dPoPKey;

  final SecurityContextHolderStrategy _strategy;
  final DateTime Function()? _clock;
  final DPoPNonces _nonces = DPoPNonces();
  Future<void> _pending = Future.value();

  /// The registration of [request]: its attribute, else the default.
  String? clientRegistrationIdOf(HttpRequest request) =>
      ClientAttributes.resolveClientRegistrationId(request.attributes) ??
      defaultClientRegistrationId;

  @override
  Future<HttpResponse> intercept(
    HttpRequest request,
    List<int>? body,
    ClientHttpRequestExecution execution,
  ) async {
    final registrationId = clientRegistrationIdOf(request);
    if (registrationId == null) {
      return await execution.execute(request, body);
    }
    await _pending;
    final principal =
        _strategy.getContext().authentication ?? anonymousAuthentication;
    final client = await authorizedClientManager.authorize(
      OAuth2AuthorizeRequest.withClientRegistrationId(
        registrationId,
      ).principal(principal).build(),
    );
    final token = client?.accessToken;
    if (token == null) {
      return await execution.execute(request, body);
    }
    final sent = await _authorized(request, token);
    final response = await execution.execute(sent, body);
    final nonce = _nonces.remember(request.url, response.headers);
    if (response.statusCode != 401) {
      return response;
    }
    if (token.tokenType == TokenType.dpop && wantsNonce(response.headers)) {
      // A stream read once cannot be sent with the new nonce.
      if (nonce == null || !(request.streamingBody?.isRepeatable ?? true)) {
        return response;
      }
      _log.debug('The resource server asked for a DPoP nonce; sending again');
      final again = await execution.execute(
        await _authorized(request, token),
        body,
      );
      _nonces.remember(request.url, again.headers);
      if (again.statusCode != 401 || wantsNonce(again.headers)) {
        return again;
      }
      await _expire(registrationId, principal, token.tokenValue);
      return again;
    }
    await _expire(registrationId, principal, token.tokenValue);
    return response;
  }

  // [request] with the headers of [token] (a fresh proof for a DPoP one),
  // replacing any: a copy, so a request sent again has its own.
  Future<HttpRequest> _authorized(
    HttpRequest request,
    OAuth2AccessToken token,
  ) async {
    final headers =
        await OAuth2AccessTokenHeaders(dPoPKey: dPoPKey, clock: _clock).of(
          token,
          method: request.method.value,
          url: request.url,
          nonce: _nonces.of(request.url),
        );
    final authorized = request.headers.copy()
      ..remove(HttpHeaders.authorizationHeader)
      ..remove(dPoPHeader);
    headers.forEach(authorized.set);
    return request.withHeaders(authorized);
  }

  // Marks [tokenValue] expired when it is still the stored token of
  // [registrationId] and [principal]; the next call waits for it.
  Future<void> _expire(
    String registrationId,
    Authentication principal,
    String tokenValue,
  ) {
    final service = authorizedClientService;
    if (service == null) {
      return Future.value();
    }
    final done = _pending.then((_) async {
      final client = await service.loadAuthorizedClient(
        registrationId,
        principal.name,
      );
      if (client == null || client.accessToken.tokenValue != tokenValue) {
        return; // already replaced
      }
      _log.debug(
        "Access token of registration '$registrationId' rejected; it will "
        'be renewed at the next call',
      );
      final access = client.accessToken;
      await service.saveAuthorizedClient(
        OAuth2AuthorizedClient(
          client.clientRegistration,
          client.principalName,
          OAuth2AccessToken(
            access.tokenType,
            access.tokenValue,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            scopes: access.scopes,
          ),
          refreshToken: client.refreshToken,
          idToken: client.idToken,
        ),
        principal,
      );
    });
    _pending = done.then<void>((_) {}, onError: (Object _) {});
    return done.then<void>(
      (_) {},
      onError: (Object error) {
        _log.debug('Could not mark the rejected token expired: $error');
      },
    );
  }

  @override
  String toString() =>
      'OAuth2ClientHttpRequestInterceptor [default registration='
      '${defaultClientRegistrationId ?? 'none'}, '
      'dPoP=${dPoPKey?.algorithm ?? 'none'}]';
}
