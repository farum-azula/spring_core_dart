import 'dart:async';

import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client.dart';
import 'package:spring_boot_starter_oauth2_client/src/client/authorized_client_manager.dart';
import 'package:spring_boot_starter_oauth2_client/src/client/oauth2_access_token_headers.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/tokens.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_key.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_nonces.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.oauth2.client.feign');

/// A Feign [RequestInterceptor] that sends the OAuth 2.0 access token of
/// the current user (or of the client, for client credentials) with every
/// call: `Authorization: Bearer <token>`, or for a DPoP-bound token
/// `Authorization: DPoP <token>` and a fresh proof.
///
/// With it, the Feign clients of an app call the API as the logged-in
/// user, and a server's clients call other services with its own
/// client-credentials token, without any code in the clients. The token
/// comes from the [OAuth2AuthorizedClientManager] at each call, so it is
/// refreshed when it expires within a minute. The registration is
/// [clientRegistrationId], else the Feign client's name; the principal is
/// the security context's authentication, else `anonymousUser` (the
/// principal of client-credentials tokens).
///
/// Switch it on with Spring Cloud OpenFeign's properties:
///
/// ```properties
/// spring.cloud.openfeign.oauth2.enabled=true
/// spring.cloud.openfeign.oauth2.client-registration-id=keycloak
/// ```
///
/// A call made while nobody is logged in (an `authorization_code`
/// registration) fails with a `ClientAuthorizationRequiredException`; a
/// client that calls public endpoints too declares its own interceptor
/// in its `configuration` instead.
///
/// When the API answers 401 although the token looked valid (revoked,
/// the provider's keys rotated), the [OAuth2AccessTokenErrorDecoder]
/// marks it expired, so the next call refreshes it. The failed call is
/// not repeated: Feign's interceptors cannot see responses, and its
/// `ErrorDecoder` and `Retryer` belong to the application.
///
/// A DPoP-bound token ([TokenType.dpop], when the registration uses
/// DPoP) is sent with a `DPoP` proof signed by [dPoPKey] for this request:
/// its method, its URL without query and fragment, and the hash of the
/// token (`ath`). When the API asks for a nonce (`DPoP-Nonce`), the error
/// decoder hands it over ([rememberDPoPNonce]) and the next proof for that
/// server carries it; the call that got the `use_dpop_nonce` answer is not
/// repeated, for the reason above. Nonces sent in successful answers are
/// not seen (Feign shows them to no hook).
///
/// Spring Cloud OpenFeign (Java): `OAuth2AccessTokenInterceptor`, with
/// the same properties and the same choice of registration; DPoP is an
/// addition (Spring sends Bearer tokens only).
class OAuth2AccessTokenInterceptor implements RequestInterceptor {
  /// An interceptor taking tokens from [authorizedClientManager];
  /// [authorizedClientService] (where the manager keeps the clients) lets
  /// [invalidate] mark a rejected token expired; [dPoPKey] signs the
  /// proofs of DPoP-bound tokens; `clock` gives the proofs' time (the
  /// current time by default).
  OAuth2AccessTokenInterceptor(
    this.authorizedClientManager, {
    String? clientRegistrationId,
    this.authorizedClientService,
    SecurityContextHolderStrategy? securityContextHolderStrategy,
    this.dPoPKey,
    this._clock,
  }) : clientRegistrationId =
           clientRegistrationId == null || clientRegistrationId.trim().isEmpty
           ? null
           : clientRegistrationId.trim(),
       _strategy =
           securityContextHolderStrategy ??
           SecurityContextHolder.getContextHolderStrategy();

  /// Where tokens come from.
  final OAuth2AuthorizedClientManager authorizedClientManager;

  /// Where the clients are kept, for [invalidate]; `null` to never
  /// invalidate.
  final OAuth2AuthorizedClientService? authorizedClientService;

  /// The registration of every call, or `null` for the Feign client's
  /// name.
  final String? clientRegistrationId;

  /// The key of the DPoP proofs, or `null` when the tokens are `Bearer`.
  final DPoPKey? dPoPKey;

  final SecurityContextHolderStrategy _strategy;
  final DateTime Function()? _clock;
  final DPoPNonces _nonces = DPoPNonces();

  // The tokens sent lately, with whose they are, for invalidate().
  final Map<String, (String, Authentication)> _sent = {};
  static const _remembered = 32;
  Future<void> _pending = Future.value();

  @override
  Future<void> apply(RequestTemplate template) async {
    await _pending;
    final registrationId = clientRegistrationId ?? template.clientName;
    final principal =
        _strategy.getContext().authentication ?? anonymousAuthentication;
    final client = await authorizedClientManager.authorize(
      OAuth2AuthorizeRequest.withClientRegistrationId(
        registrationId,
      ).principal(principal).build(),
    );
    final token = client?.accessToken;
    if (token == null) {
      throw StateError('OAuth2 token has not been successfully acquired.');
    }
    _remember(token.tokenValue, registrationId, principal);
    template
      ..removeHeader(HttpHeaders.authorizationHeader)
      ..removeHeader(dPoPHeader);
    final headers =
        await OAuth2AccessTokenHeaders(
          dPoPKey: dPoPKey,
          clock: _clock,
        ).of(
          token,
          method: template.method.value,
          url: template.url,
          nonce: _nonces.of(template.url),
        );
    headers.forEach(template.header);
  }

  /// Remembers the `DPoP-Nonce` [response] carries (if any) for its
  /// server, for the next proof sent there.
  ///
  /// The [OAuth2AccessTokenErrorDecoder] calls it for every error answer;
  /// call it yourself with answers it does not see (a successful answer
  /// of a method that returns the raw `HttpResponse`).
  void rememberDPoPNonce(HttpResponse response) {
    final url = response.request?.url;
    if (url != null) {
      _nonces.remember(url, response.headers);
    }
  }

  void _remember(String token, String registrationId, Authentication who) {
    _sent
      ..remove(token)
      ..[token] = (registrationId, who);
    while (_sent.length > _remembered) {
      _sent.remove(_sent.keys.first);
    }
  }

  /// Marks the access token [tokenValue] expired when this interceptor
  /// sent it and it is still the stored one, so the next call refreshes
  /// it (or gets a new client-credentials token). Does nothing otherwise.
  ///
  /// The next [apply] waits for it.
  Future<void> invalidate(String tokenValue) {
    final sent = _sent.remove(tokenValue);
    final service = authorizedClientService;
    if (sent == null || service == null) {
      return Future.value();
    }
    final (registrationId, principal) = sent;
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
    return done;
  }
}

/// A Feign [ErrorDecoder] that reports a `401 Unauthorized` answer to a
/// call carrying a token of the [OAuth2AccessTokenInterceptor], so the
/// token is renewed at the next call, then decodes the error with
/// [delegate] as usual.
///
/// It also hands every `DPoP-Nonce` of an error answer to the
/// interceptor, for the next DPoP proof; a 401 that only asks for a nonce
/// (`WWW-Authenticate: DPoP error="use_dpop_nonce"`) leaves the token
/// alone.
///
/// The starter declares it with the interceptor when the application has
/// no `ErrorDecoder` bean. An application with its own decoder wraps it:
///
/// ```dart
/// @Bean()
/// ErrorDecoder errorDecoder(OAuth2AccessTokenInterceptor tokens) =>
///     OAuth2AccessTokenErrorDecoder(MyErrorDecoder(), tokens);
/// ```
///
/// Spring has no such decoder (Spring Cloud OpenFeign does nothing on a
/// 401; Spring Security's `OAuth2AuthorizationFailureHandler` removes the
/// client of a WebClient call instead).
class OAuth2AccessTokenErrorDecoder implements ErrorDecoder {
  /// A decoder reporting to [interceptor] and decoding with [delegate].
  OAuth2AccessTokenErrorDecoder(this.delegate, this.interceptor);

  /// Decodes every error.
  final ErrorDecoder delegate;

  /// Receives the rejected tokens.
  final OAuth2AccessTokenInterceptor interceptor;

  @override
  Exception decode(String methodKey, HttpResponse response) {
    interceptor.rememberDPoPNonce(response);
    if (response.statusCode == 401) {
      final header = response.request?.headers[HttpHeaders.authorizationHeader];
      final token = switch (header) {
        final value? when value.startsWith('Bearer ') => value.substring(7),
        final value?
            when value.startsWith('DPoP ') &&
                !wantsNonce(
                  response.headers,
                ) =>
          value.substring(5),
        _ => null,
      };
      if (token != null) {
        unawaited(
          interceptor
              .invalidate(token)
              .then<void>((_) {}, onError: (Object _) {}),
        );
      }
    }
    return delegate.decode(methodKey, response);
  }
}
