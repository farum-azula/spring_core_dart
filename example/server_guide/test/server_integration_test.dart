// Chapter 12 (and 3-5) over real sockets: the server on a free port
// (webEnvironment: randomPort), called with dart:io's HttpClient and
// WebSocket as the Flutter app calls it — the login with the CSRF cookie,
// a session, server-sent events, the support chat, the firewall and the
// graceful shutdown.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/main.spring.dart';
import 'support/app.dart';

/// A client keeping cookies, as the app's cookie jar does.
final class Browser {
  Browser(this.port);

  final int port;
  final _client = HttpClient();
  final cookies = <String, String>{};

  Future<(int, String)> send(
    String method,
    String path, {
    String? form,
    Object? json,
  }) async {
    final request = await _client.openUrl(
      method,
      Uri.parse('http://localhost:$port$path'),
    );
    request.headers.set(
      'Cookie',
      [for (final MapEntry(:key, :value) in cookies.entries) '$key=$value']
          .join('; '),
    );
    final token = cookies['XSRF-TOKEN'];
    if (method != 'GET' && token != null) {
      request.headers.set('X-XSRF-TOKEN', token);
    }
    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(form);
    } else if (json != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(json));
    }
    final response = await request.close();
    for (final cookie in response.cookies) {
      cookie.value.isEmpty
          ? cookies.remove(cookie.name)
          : cookies[cookie.name] = cookie.value;
    }
    return (response.statusCode, await utf8.decodeStream(response));
  }

  void close() => _client.close(force: true);
}

/// The `text` of a chat message.
String? _text(Object? message) =>
    (jsonDecode(message! as String) as Map<String, Object?>)['text'] as String?;

void main() {
  final app = neonBooks(webEnvironment: WebEnvironment.randomPort);

  test('login with the CSRF cookie, a session, an order', () async {
    final browser = Browser(app.localServerPort);
    addTearDown(browser.close);
    expect((await browser.send('GET', '/api/books')).$1, 200);
    expect(browser.cookies, contains('XSRF-TOKEN'));
    final login = await browser.send(
      'POST',
      '/api/login',
      form: 'username=root&password=root-secret',
    );
    expect(login.$1, 204);
    expect(browser.cookies, contains('JSESSIONID'));
    final me = await browser.send('GET', '/api/me');
    expect(jsonDecode(me.$2), {
      'name': 'root',
      'roles': ['ADMIN', 'USER'],
      'authorities': ['ROLE_ADMIN', 'ROLE_USER'],
    });
    final basket = await browser.send(
      'PUT',
      '/api/basket/items/9780547928227',
      json: {'quantity': 2},
    );
    expect(basket.$1, 200);
    final order = await browser.send('POST', '/api/orders');
    expect(order.$1, 201);
    expect(jsonDecode(order.$2), containsPair('user', 'root'));
  });

  test('server-sent events over the socket', () async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      Uri.parse('http://localhost:${app.localServerPort}/api/stock/events'),
    );
    final response = await request.close();
    expect(response.headers.contentType?.mimeType, 'text/event-stream');
    final data = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((line) => line.startsWith('data:'));
    // The response is open: change the stock now.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    app.getBean<Catalog>().changeStock('9780441013593', 1);
    expect(
      jsonDecode((await data.timeout(const Duration(seconds: 5))).substring(5)),
      containsPair('isbn', '9780441013593'),
    );
  });

  test('the support chat with the session cookie of a login', () async {
    final browser = Browser(app.localServerPort);
    addTearDown(browser.close);
    await browser.send('GET', '/api/books');
    await browser.send(
      'POST',
      '/api/login',
      form: 'username=ada&password=ada-secret',
    );
    final socket = await WebSocket.connect(
      'ws://localhost:${app.localServerPort}/ws/support',
      headers: {'Cookie': 'JSESSIONID=${browser.cookies['JSESSIONID']}'},
    );
    final messages = StreamIterator(socket);
    expect(await messages.moveNext(), isTrue);
    expect(_text(messages.current), startsWith('Hi ada'));
    socket.add(jsonEncode({'text': 'opening hours?'}));
    expect(await messages.moveNext(), isTrue);
    expect(_text(messages.current), 'We are open from 9:00 to 21:00.');
    await socket.close();

    // Without the cookie the handshake is refused (401).
    await expectLater(
      WebSocket.connect('ws://localhost:${app.localServerPort}/ws/support'),
      throwsA(isA<WebSocketException>()),
    );
  });

  test('the firewall: a path starting with //', () async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.openUrl(
      'GET',
      Uri.parse('http://localhost:${app.localServerPort}//api/books'),
    );
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, 400);
  });

  test('graceful shutdown ends open event streams', () async {
    final context = await springApplication.runAsync(
      const [],
      properties: {
        'server.port': 0,
        'spring.main.banner-mode': 'off',
        'logging.console.enabled': false,
        'neon.stock.restock-initial-delay': '1h',
      },
    );
    // The server binds its socket after the start: then the port is
    // published as local.server.port.
    String? port;
    for (var i = 0; i < 100 && port == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      port = context.environment.getProperty('local.server.port');
    }
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(
      Uri.parse('http://localhost:$port/api/stock/events'),
    )).close();
    final ended = response.drain<void>();
    await context.closeAsync();
    await ended.timeout(const Duration(seconds: 10));
  });
}
