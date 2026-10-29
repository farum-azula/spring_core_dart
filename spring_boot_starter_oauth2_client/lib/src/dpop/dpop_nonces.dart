import 'dart:convert';

import 'package:spring_boot_starter_oauth2_client/src/core/oauth2_error.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/access_token_response.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The header a server sends its DPoP nonce in (RFC 9449 §8, §9).
const dPoPNonceHeader = 'DPoP-Nonce';

/// The header a DPoP proof is sent in (RFC 9449 §4.1).
const dPoPHeader = 'DPoP';

/// The last DPoP nonce each server (scheme, host and port) sent, to put
/// into the next proof for it (RFC 9449 §8 and §9). Internal: the token
/// response clients, the user services and the Feign interceptor keep
/// one each.
final class DPoPNonces {
  final Map<String, String> _byOrigin = {};
  static const _remembered = 64;
  static const _maxLength = 1024;

  /// The nonce last received from the server of [url], or `null`.
  String? of(Uri url) => _byOrigin[_origin(url)];

  /// Remembers the `DPoP-Nonce` of [headers] for the server of [url];
  /// returns it, or `null` when there is none or it is not a valid nonce
  /// (RFC 9449 §8.1: `1*NQCHAR`).
  String? remember(Uri url, HttpHeaders headers) {
    final nonce = headers[dPoPNonceHeader]?.trim();
    if (nonce == null || !_valid(nonce)) {
      return null;
    }
    final origin = _origin(url);
    _byOrigin
      ..remove(origin)
      ..[origin] = nonce;
    while (_byOrigin.length > _remembered) {
      _byOrigin.remove(_byOrigin.keys.first);
    }
    return nonce;
  }

  static String _origin(Uri url) =>
      '${url.scheme.toLowerCase()}://${url.host.toLowerCase()}:${url.port}';

  // NQCHAR = %x21 / %x23-5B / %x5D-7E
  static bool _valid(String nonce) =>
      nonce.isNotEmpty &&
      nonce.length <= _maxLength &&
      nonce.codeUnits.every(
        (c) =>
            c == 0x21 || (c >= 0x23 && c <= 0x5b) || (c >= 0x5d && c <= 0x7e),
      );
}

/// Whether the token endpoint's [response] asks for a DPoP nonce: a 400
/// (or 401) with the OAuth 2.0 error `use_dpop_nonce` (RFC 9449 §8).
bool tokenEndpointWantsNonce(HttpResponse response) {
  if (response.statusCode != 400 && response.statusCode != 401) {
    return false;
  }
  if (response.bodyBytes.length > 64 * 1024) {
    return false;
  }
  try {
    final error = oauth2ErrorOf(jsonDecode(utf8.decode(response.bodyBytes)));
    return error?.errorCode == OAuth2ErrorCodes.useDPoPNonce;
  } on FormatException {
    return false;
  }
}

/// Whether the resource server's [response] asks for a DPoP nonce: a 401
/// with `WWW-Authenticate: DPoP error="use_dpop_nonce"` (RFC 9449 §9).
bool resourceServerWantsNonce(HttpResponse response) =>
    response.statusCode == 401 && wantsNonce(response.headers);

/// Whether a `WWW-Authenticate` header of [headers] is a DPoP challenge
/// with the error `use_dpop_nonce`.
bool wantsNonce(HttpHeaders headers) => headers
    .getAll(HttpHeaders.wwwAuthenticateHeader)
    .any(
      (challenge) =>
          RegExp(r'^\s*DPoP\b', caseSensitive: false).hasMatch(challenge) &&
          RegExp(
            r'''\berror\s*=\s*"?use_dpop_nonce"?''',
          ).hasMatch(challenge),
    );
