@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io' as io;

import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

// A RestClient built without a transport calls only the host of its base
// URL: every other address is denied, and the message says how to allow
// it.
void main() {
  late io.HttpServer server;
  late int port;

  setUpAll(() async {
    server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      request.response.write('ok');
      await request.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  Matcher deniedFor(String host) => throwsA(
    isA<ResourceAccessException>().having(
      (e) => e.cause,
      'cause',
      isA<FilteredHostException>()
          .having((e) => e.host, 'host', host)
          .having(
            (e) => e.message,
            'message',
            allOf(
              contains('AllowedAddresses'),
              contains('spring.http.clients.allowed-addresses'),
            ),
          ),
    ),
  );

  test("the base URL's host is allowed by hand", () async {
    final rest = RestClient.create('http://127.0.0.1:$port');
    expect(await rest.get().uri('/x').retrieve().body<String>(), 'ok');
  });

  test('another host of the same client is denied', () async {
    final rest = RestClient.create('http://127.0.0.1:$port');
    await expectLater(
      rest.get().uri('http://169.254.169.254/latest').retrieve().body<String>(),
      deniedFor('169.254.169.254'),
    );
    await expectLater(
      rest.get().uri('https://evil.example/').retrieve().body<String>(),
      deniedFor('evil.example'),
    );
  });

  test('without a base URL every address is denied, loopback too', () async {
    final rest = RestClient.create();
    await expectLater(
      rest.get().uri('http://127.0.0.1:$port/x').retrieve().body<String>(),
      deniedFor('127.0.0.1'),
    );
    await expectLater(
      RestClient.builder()
          .build()
          .get()
          .uri('http://localhost:$port/x')
          .retrieve()
          .body<String>(),
      deniedFor('localhost'),
    );
  });

  test(
    "the base URL's variables are filled before its host is taken",
    () async {
      final rest = RestClient.builder()
          .baseUrl('http://{host}:$port')
          .defaultUriVariables({'host': '127.0.0.1'})
          .build();
      expect(await rest.get().uri('/x').retrieve().body<String>(), 'ok');
    },
  );

  test('a transport given by hand is used as it is', () async {
    final rest = RestClient.builder()
        .transport(
          platformHttpTransport(
            allowedAddresses: AllowedAddresses(['127.0.0.1']),
          ),
        )
        .build();
    expect(
      await rest
          .get()
          .uri('http://127.0.0.1:$port/x')
          .retrieve()
          .body<String>(),
      'ok',
    );
  });
}
