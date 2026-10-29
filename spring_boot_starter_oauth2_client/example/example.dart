// A service that calls a partner's API with its own access token (the
// client_credentials grant): the starter gets the token from the
// provider's token endpoint, keeps it while it is valid, and the Feign
// interceptor sends it with every call. The generator writes
// example.spring.dart (`dart run build_runner build`).
//
//   dart run example/example.dart
//
// A local server stands in for the partner's identity provider and API,
// so the example runs without anything else.

import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

import 'example.spring.dart';

/// The partner's API. The starter's interceptor adds
/// `Authorization: Bearer <token>` to every call
/// (`spring.cloud.openfeign.oauth2.enabled=true`).
@FeignClient('orders', url: r'${partner.url}')
abstract interface class OrdersClient {
  @GetMapping('/orders')
  Future<List<Object?>> orders();
}

/// Calls the API twice and asks the authorized client manager for the
/// token, then logs what happened; `@Log` gives it the `log` getter. The
/// token itself is a credential: it is never logged.
@Component()
@Log(topic: 'example')
class OrdersTour implements CommandLineRunner {
  OrdersTour(this.orders, this.authorizedClients);

  final OrdersClient orders;
  final OAuth2AuthorizedClientManager authorizedClients;

  @override
  Future<void> run(List<String> args) async {
    final first = await orders.orders();
    final second = await orders.orders();
    final client = await authorizedClients.authorize(
      OAuth2AuthorizeRequest.withClientRegistrationId(
        'partner',
      ).principal(anonymousAuthentication).build(),
    );
    log
      ..info('orders: $first') // [A-1, A-2]
      ..info('again: ${second.length} orders') // 2 orders
      ..info('token requests: $_tokenRequests') // 1: the token is reused
      ..info('scopes: ${client?.accessToken.scopes}') // {orders.read}
      ..info('principal: ${client?.principalName}'); // anonymousUser
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final partner = await _partner();
  final base = 'http://127.0.0.1:${partner.port}';
  const registration = 'spring.security.oauth2.client.registration.partner';
  final context = await springApplication.runAsync(
    args,
    properties: {
      '$registration.client-id': 'shop',
      '$registration.client-secret': 'demo-secret',
      '$registration.authorization-grant-type': 'client_credentials',
      '$registration.scope': 'orders.read',
      'spring.security.oauth2.client.provider.partner.token-uri':
          '$base/oauth2/token',
      'spring.cloud.openfeign.oauth2.enabled': 'true',
      'spring.cloud.openfeign.oauth2.client-registration-id': 'partner',
      'partner.url': base,
    },
  );

  await context.closeAsync();
  await partner.close(force: true);
}

var _tokenRequests = 0;

/// The partner's token endpoint and API on 127.0.0.1: tokens for the
/// client `shop` (HTTP Basic, as `client_secret_basic`), orders for a
/// valid token.
Future<io.HttpServer> _partner() async {
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  final tokens = <String>{};
  final client = base64Encode(utf8.encode('shop:demo-secret'));
  server.listen((request) async {
    final response = request.response;
    void json(Object body) => response
      ..headers.contentType = io.ContentType.json
      ..write(jsonEncode(body));
    final authorization = request.headers.value(
      io.HttpHeaders.authorizationHeader,
    );
    switch (request.uri.path) {
      case '/oauth2/token':
        _tokenRequests++;
        final form = Uri.splitQueryString(await utf8.decodeStream(request));
        if (authorization != 'Basic $client' ||
            form['grant_type'] != 'client_credentials') {
          response.statusCode = io.HttpStatus.unauthorized;
          json({'error': 'invalid_client'});
          break;
        }
        final access = 'access-${tokens.length + 1}';
        tokens.add(access);
        json({
          'access_token': access,
          'token_type': 'Bearer',
          'expires_in': 300,
          'scope': form['scope'],
        });
      case '/orders':
        if (!tokens.contains(authorization?.replaceFirst('Bearer ', ''))) {
          response.statusCode = io.HttpStatus.unauthorized;
          break;
        }
        json(['A-1', 'A-2']);
      default:
        response.statusCode = io.HttpStatus.notFound;
    }
    await response.close();
  });
  return server;
}
