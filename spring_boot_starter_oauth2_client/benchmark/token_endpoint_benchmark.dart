// What moving the starter's own calls onto RestClient costs: a
// client_credentials token request (the form, HTTP Basic, the answer read
// into an OAuth2AccessTokenResponse) and a JWK Set fetch (a GET, the
// status and size checked, the JSON decoded), each as the starter sent it
// before on the bare HttpTransport and as it sends it now with a
// RestClient on the same transport. The transport answers at once, so only
// the clients' own work is measured. Not part of the tests; run with
//   dart run benchmark/token_endpoint_benchmark.dart
//   dart compile exe benchmark/token_endpoint_benchmark.dart -o /tmp/tb && /tmp/tb
//
// November 2026, Apple M5, AOT, microseconds per call (medians of 5 runs
// of 100 000 calls), bare / RestClient:
//   token request (client_credentials): 2.61 / 4.00 (+1.40)
//   JWK Set fetch:                       1.05 / 1.88 (+0.83)
// The difference is the RestClient's request spec (the headers copied into
// the request, the body converter) and its async layers. A real call is a
// TLS round trip of milliseconds, once per token lifetime (minutes) or JWK
// cache period (five minutes): nothing a frame or a request feels.

import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_oauth2_client/src/core/parameter_names.dart';
import 'package:spring_boot_starter_oauth2_client/src/dpop/dpop_nonces.dart';
import 'package:spring_boot_starter_oauth2_client/src/endpoint/token_response_clients.dart'
    show clientAuthentication;

final class _Instant implements HttpTransport {
  _Instant(this._answers);

  final Map<String, List<int>> _answers;
  final _headers = HttpHeaders({'Content-Type': 'application/json'});

  @override
  Future<HttpResponse> send(HttpRequest request) async => HttpResponse(
    200,
    headers: _headers,
    body: _answers[request.url.path]!,
    request: request,
  );

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) =>
      throw UnsupportedError('not measured');

  @override
  void close() {}
}

Future<double> _perCall(Future<void> Function() call, int count) async {
  final watch = Stopwatch()..start();
  for (var i = 0; i < count; i++) {
    await call();
  }
  return watch.elapsedMicroseconds / count;
}

Future<double> _median(Future<void> Function() call, int count) async {
  await _perCall(call, count ~/ 4);
  final runs = [for (var r = 0; r < 5; r++) await _perCall(call, count)]
    ..sort();
  return runs[2];
}

Future<void> main(List<String> args) async {
  final count = args.isEmpty ? 100000 : int.parse(args.first);
  final transport = _Instant({
    '/token': utf8.encode(
      jsonEncode({
        'access_token': 'cc-token',
        'token_type': 'Bearer',
        'expires_in': 300,
        'scope': 'orders.read',
      }),
    ),
    '/certs': utf8.encode(
      jsonEncode({
        'keys': [
          {'kty': 'RSA', 'kid': 'k1', 'n': 'AQAB' * 86, 'e': 'AQAB'},
        ],
      }),
    ),
  });
  final registration = ClientRegistration.withRegistrationId('partner')
      .clientId('shop')
      .clientSecret('demo-secret')
      .authorizationGrantType(AuthorizationGrantType.clientCredentials)
      .scope(['orders.read'])
      .tokenUri('https://sso.neon.books/token')
      .build();
  final grant = OAuth2ClientCredentialsGrantRequest(registration);
  final jwkUrl = Uri.parse('https://sso.neon.books/certs');

  final tokens = DefaultClientCredentialsTokenResponseClient(transport);
  Future<void> restToken() => tokens.getTokenResponse(grant);

  // The token request as the starter sent it before (0.10.0): the same
  // steps as getTokenResponse (without DPoP), the request sent on the bare
  // transport.
  final nonces = DPoPNonces();
  Future<String?> noSecret() async => null;
  Future<void> bareToken() async {
    final url = Uri.parse(registration.providerDetails.tokenUri!);
    final form = <String, String>{...tokens.grantParameters(grant)};
    final secret = await noSecret();
    Future<HttpResponse> send(String? nonce) async {
      final headers = HttpHeaders({
        HttpHeaders.acceptHeader: '${MediaType.applicationJson};charset=UTF-8',
        HttpHeaders.contentTypeHeader:
            '${MediaType.applicationFormUrlencoded};charset=UTF-8',
      });
      final body = {
        ...form,
        ...clientAuthentication(registration, headers, clientSecret: secret),
      };
      return await transport.send(
        HttpRequest(
          method: HttpMethod.post,
          url: url,
          headers: headers,
          body: utf8.encode(formUrlEncodeAll(body)),
          followRedirects: false,
        ),
      );
    }

    final response = await send(nonces.of(url));
    final answer = OAuth2AccessTokenResponse.fromHttpResponse(
      response,
      requestedScopes: tokens.requestedScopes(grant),
      now: DateTime.now(),
    );
    if (answer.accessToken.tokenType == TokenType.dpop) {
      throw StateError('not measured');
    }
  }

  // The JWK Set fetch before, and now.
  void read(HttpResponse response) {
    if (response.statusCode != 200 || response.bodyBytes.length > 512 * 1024) {
      throw StateError('${response.statusCode}');
    }
    jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<void> bareJwk() async => read(
    await transport.send(
      HttpRequest(
        method: HttpMethod.get,
        url: jwkUrl,
        headers: HttpHeaders({
          HttpHeaders.acceptHeader:
              'application/json, application/jwk-set+json',
        }),
        followRedirects: false,
      ),
    ),
  );

  final rest = RestClient.builder()
      .transport(transport)
      .followRedirects(false)
      .build();
  Future<void> restJwk() async => read(
    await rest
        .get()
        .uri(jwkUrl)
        .accept('application/json, application/jwk-set+json')
        .exchange((_, answer) => answer.response),
  );

  for (final (name, bare, client) in [
    ('token request (client_credentials)', bareToken, restToken),
    ('JWK Set fetch', bareJwk, restJwk),
  ]) {
    final before = await _median(bare, count);
    final after = await _median(client, count);
    final difference = (after - before).toStringAsFixed(2);
    stdout.writeln(
      '$name: ${before.toStringAsFixed(2)} / ${after.toStringAsFixed(2)} '
      '(${after >= before ? '+' : ''}$difference) us per call',
    );
  }
}
