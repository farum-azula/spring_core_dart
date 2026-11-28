@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io' as io;

import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

// IoHttpTransport with AllowedAddresses against a server on loopback:
// the resolved address is the one checked and the one connected to, and
// every redirect is checked again.
void main() {
  late io.HttpServer server;
  late int port;

  setUpAll(() async {
    server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/metadata':
          response
            ..statusCode = 302
            ..headers.set('Location', 'http://169.254.169.254/latest');
        case '/by-name':
          response
            ..statusCode = 302
            ..headers.set('Location', 'http://localhost:$port/ok');
        case '/ok':
          response.write('ok ${request.headers.host}');
      }
      await response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  Future<HttpResponse> get(HttpTransport transport, String url) =>
      transport.send(HttpRequest(method: HttpMethod.get, url: Uri.parse(url)));

  test('loopback is denied until it is on the list', () async {
    final closed = IoHttpTransport(
      allowedAddresses: AllowedAddresses(['api.neon.books']),
    );
    addTearDown(closed.close);
    await expectLater(
      get(closed, 'http://127.0.0.1:$port/ok'),
      throwsA(isA<FilteredHostException>()),
    );
    final open = IoHttpTransport(
      allowedAddresses: AllowedAddresses(['127.0.0.1']),
    );
    addTearDown(open.close);
    expect(
      (await get(open, 'http://127.0.0.1:$port/ok')).bodyText,
      startsWith('ok'),
    );
  });

  test('a name that resolves to loopback is denied (DNS rebinding)', () async {
    final transport = IoHttpTransport(
      allowedAddresses: AllowedAddresses(['api.neon.books']),
      lookup: (host) async => [io.InternetAddress.loopbackIPv4],
    );
    addTearDown(transport.close);
    await expectLater(
      get(transport, 'http://api.neon.books:$port/ok'),
      throwsA(
        isA<FilteredHostException>().having(
          (e) => e.reason,
          'reason',
          contains('it resolves to 127.0.0.1 (loopback)'),
        ),
      ),
    );
  });

  test('the address checked is the address connected to', () async {
    var lookups = 0;
    final transport = IoHttpTransport(
      allowedAddresses: AllowedAddresses(['books.internal', '127.0.0.1']),
      // A resolver only the transport knows: HttpClient alone could not
      // find the name at all.
      lookup: (host) async {
        lookups++;
        return [io.InternetAddress.loopbackIPv4];
      },
    );
    addTearDown(transport.close);
    final response = await get(transport, 'http://books.internal:$port/ok');
    expect(response.bodyText, 'ok books.internal');
    expect(lookups, 1);
  });

  test('localhost on the list may resolve to loopback', () async {
    final transport = IoHttpTransport(
      allowedAddresses: AllowedAddresses(['localhost']),
      lookup: (host) async => [io.InternetAddress.loopbackIPv4],
    );
    addTearDown(transport.close);
    expect(
      (await get(transport, 'http://localhost:$port/ok')).bodyText,
      'ok localhost',
    );
  });

  // localhost is ::1 first on many systems, and a server on IPv4 alone
  // refuses it: the next allowed address is tried, as Socket.connect does.
  test('the allowed addresses are tried in order until one connects', () async {
    final transport = IoHttpTransport(
      allowedAddresses: AllowedAddresses(['localhost']),
      lookup: (host) async => [
        io.InternetAddress.loopbackIPv6,
        io.InternetAddress.loopbackIPv4,
      ],
    );
    addTearDown(transport.close);
    expect(
      (await get(transport, 'http://localhost:$port/ok')).bodyText,
      'ok localhost',
    );
  });

  test('a redirect to a denied address is not followed', () async {
    final transport = IoHttpTransport(
      allowedAddresses: AllowedAddresses(['127.0.0.1']),
    );
    addTearDown(transport.close);
    await expectLater(
      get(transport, 'http://127.0.0.1:$port/metadata'),
      throwsA(
        isA<FilteredHostException>()
            .having((e) => e.host, 'host', '169.254.169.254')
            .having((e) => e.reason, 'reason', contains('cloud metadata')),
      ),
    );
    await expectLater(
      get(transport, 'http://127.0.0.1:$port/by-name'),
      throwsA(
        isA<FilteredHostException>().having((e) => e.host, 'host', 'localhost'),
      ),
    );
  });

  test(
    'through RestClient a denied call is a ResourceAccessException',
    () async {
      final transport = IoHttpTransport(
        allowedAddresses: AllowedAddresses.none(
          remedy: 'add it to spring.http.clients.allowed-addresses',
        ),
      );
      addTearDown(transport.close);
      final rest = RestClient.builder().transport(transport).build();
      await expectLater(
        rest.get().uri('http://127.0.0.1:$port/ok').retrieve().body<String>(),
        throwsA(
          isA<ResourceAccessException>()
              .having((e) => e.isRetryable, 'retryable', isFalse)
              .having(
                (e) => e.message,
                'message',
                contains('spring.http.clients.allowed-addresses'),
              ),
        ),
      );
    },
  );

  test('a connect timeout per request', () async {
    final transport = IoHttpTransport(
      allowedAddresses: AllowedAddresses(['slow.test']),
      lookup: (host) => Future.delayed(
        const Duration(seconds: 2),
        () => [io.InternetAddress('93.184.215.14')],
      ),
    );
    addTearDown(transport.close);
    await expectLater(
      transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('http://slow.test/'),
          connectTimeout: const Duration(milliseconds: 50),
        ),
      ),
      throwsA(
        isA<HttpTransportException>()
            .having((e) => e.isTimeout, 'timeout', isTrue)
            .having((e) => e.message, 'message', contains('connect timeout')),
      ),
    );
  });
}
