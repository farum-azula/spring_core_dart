// The fake OpenID Connect provider of the oauth2Login() comparison
// (differential_test.dart): a real HTTP server on 127.0.0.1, because the
// Spring reference discovers it at startup and fetches its tokens and keys
// over the network. Both applications use the same instance. Discovery,
// the token endpoint (client_secret_basic, the redirect URI, PKCE when the
// authorization request had a challenge, one use per code), user info, the
// JWK Set; the user's approval is [HttpOidcProvider.approve], called by
// the test with the authorization URL the application redirected to. Its
// ID tokens are signed with the test RSA key; tests change its fields to
// make it misbehave.
//
// HTTP/1.1 by hand on a socket: Java's HTTP client offers an upgrade to
// HTTP/2 (`Upgrade: h2c`) with its POSTs, and dart:io's server hands such
// a request over without its body.
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

import 'app/jwt/keys.dart';

const differentialClientId = 'neon-web';
const differentialClientSecret = 'web-secret';

final class _Grant {
  _Grant(this.challenge, this.redirectUri, this.nonce, this.scope);
  final String? challenge;
  final String redirectUri;
  final String? nonce;
  final String scope;
}

/// A request as the provider reads it.
final class _Request {
  _Request(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

/// An answer: a status and a JSON body (none when `null`).
typedef _Answer = (int status, Object? json);

final class HttpOidcProvider {
  HttpOidcProvider._(this._server);

  /// A provider listening on a free port of 127.0.0.1.
  static Future<HttpOidcProvider> start() async {
    final provider = HttpOidcProvider._(
      await io.ServerSocket.bind(io.InternetAddress.loopbackIPv4, 0),
    );
    provider._server.listen(provider._serve);
    return provider;
  }

  final io.ServerSocket _server;

  /// `http://127.0.0.1:<port>` (a loopback issuer: no plain-http warning).
  String get issuer => 'http://127.0.0.1:${_server.port}';

  // What the provider answers; tests change them (reset() restores).
  String? audience;
  String? forcedNonce;
  String? issParameter;

  final Map<String, _Grant> _codes = {};
  final Set<String> _accessTokens = {};
  int _sequence = 0;

  void reset() {
    audience = null;
    forcedNonce = null;
    issParameter = null;
  }

  Future<void> close() => _server.close();

  Map<String, Object?> metadata() => {
    'issuer': issuer,
    'authorization_endpoint': '$issuer/authorize',
    'token_endpoint': '$issuer/token',
    'userinfo_endpoint': '$issuer/userinfo',
    'jwks_uri': '$issuer/jwks',
    'end_session_endpoint': '$issuer/logout',
    'response_types_supported': ['code'],
    'subject_types_supported': ['public'],
    'id_token_signing_alg_values_supported': ['RS256'],
    'scopes_supported': ['openid', 'profile'],
    'token_endpoint_auth_methods_supported': ['client_secret_basic'],
    'grant_types_supported': ['authorization_code'],
    'code_challenge_methods_supported': ['S256'],
    // As Keycloak: the redirect back carries `iss` (RFC 9207).
    'authorization_response_iss_parameter_supported': true,
  };

  /// The user approved [authorizationUri]: a code bound to its redirect
  /// URI, nonce and PKCE challenge, and the redirect back to the
  /// application (with `state` and `iss`).
  Uri approve(Uri authorizationUri) {
    final query = authorizationUri.queryParameters;
    final code = 'code-${++_sequence}';
    _codes[code] = _Grant(
      query['code_challenge'],
      query['redirect_uri']!,
      query['nonce'],
      query['scope'] ?? '',
    );
    return Uri.parse(query['redirect_uri']!).replace(
      queryParameters: {
        'code': code,
        'state': ?query['state'],
        'iss': issParameter ?? issuer,
      },
    );
  }

  // One request per connection: read it, answer, close.
  Future<void> _serve(io.Socket socket) async {
    final bytes = <int>[];
    _Request? request;
    try {
      await for (final chunk in socket) {
        bytes.addAll(chunk);
        request = _parse(bytes);
        if (request != null) {
          break;
        }
      }
      final (status, json) = request == null ? (400, null) : _answer(request);
      final body = json == null ? const <int>[] : utf8.encode(jsonEncode(json));
      socket
        ..add(
          latin1.encode(
            'HTTP/1.1 $status ${status == 200 ? 'OK' : 'Error'}\r\n'
            'Content-Type: application/json\r\n'
            'Content-Length: ${body.length}\r\n'
            'Connection: close\r\n\r\n',
          ),
        )
        ..add(body);
      await socket.flush();
    } on Object {
      // The client went away.
    } finally {
      socket.destroy();
    }
  }

  // The request once its head and its Content-Length bytes are in.
  static _Request? _parse(List<int> bytes) {
    final text = latin1.decode(bytes);
    final end = text.indexOf('\r\n\r\n');
    if (end < 0) {
      return null;
    }
    final lines = text.substring(0, end).split('\r\n');
    final headers = <String, String>{
      for (final line in lines.skip(1))
        if (line.indexOf(':') case final colon when colon > 0)
          line.substring(0, colon).trim().toLowerCase(): line
              .substring(colon + 1)
              .trim(),
    };
    final length = int.tryParse(headers['content-length'] ?? '') ?? 0;
    if (bytes.length < end + 4 + length) {
      return null;
    }
    final [method, target, ...] = lines.first.split(' ');
    return _Request(
      method,
      Uri.parse(target),
      headers,
      utf8.decode(bytes.sublist(end + 4, end + 4 + length)),
    );
  }

  _Answer _answer(_Request request) {
    switch ((request.method, request.uri.path)) {
      case ('GET', '/.well-known/openid-configuration'):
        return (200, metadata());
      case ('GET', '/jwks'):
        return (
          200,
          {
            'keys': [testKeys.rsa.jwk],
          },
        );
      case ('POST', '/token'):
        return _token(request, Uri.splitQueryString(request.body));
      case ('GET', '/userinfo'):
        final header = request.headers['authorization'] ?? '';
        if (!_accessTokens.contains(header.replaceFirst('Bearer ', ''))) {
          return (401, null);
        }
        return (
          200,
          {
            'sub': 'user-1',
            'name': 'Ada Lovelace',
            'preferred_username': 'ada',
          },
        );
      default:
        return (404, null);
    }
  }

  _Answer _token(_Request request, Map<String, String> form) {
    const credentials = '$differentialClientId:$differentialClientSecret';
    final expected = 'Basic ${base64.encode(utf8.encode(credentials))}';
    if (request.headers['authorization'] != expected) {
      return (401, {'error': 'invalid_client'});
    }
    final grant = _codes.remove(form['code']);
    final verifier = form['code_verifier'];
    if (form['grant_type'] != 'authorization_code' ||
        grant == null ||
        form['redirect_uri'] != grant.redirectUri ||
        (grant.challenge != null &&
            (verifier == null ||
                sha256Base64Url(verifier) != grant.challenge))) {
      return (400, {'error': 'invalid_grant'});
    }
    final access = 'access-${++_sequence}';
    _accessTokens.add(access);
    final now = TokenFactory.now();
    return (
      200,
      {
        'access_token': access,
        'token_type': 'Bearer',
        'expires_in': 300,
        'scope': grant.scope,
        'id_token': testKeys.token(
          claims: {
            'iss': issuer,
            'sub': 'user-1',
            'aud': audience ?? differentialClientId,
            'iat': now,
            'exp': now + 300,
            'nonce': ?(forcedNonce ?? grant.nonce),
            'name': 'Ada Lovelace',
            'preferred_username': 'ada',
          },
        ),
      },
    );
  }
}
