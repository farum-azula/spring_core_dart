// The rules application on a real dart:io server, with raw request lines:
// what dart:io itself does to paths and headers before the security chain
// (normalizing `..`, reading `//host`), and that the answers on the wire
// carry the security headers once.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:test/test.dart';

import 'app/rules/rules.dart';
import 'support.dart';

/// Sends [requestLine] with [headers] and returns the status line and the
/// headers (lower-case names, all values).
Future<(int, Map<String, List<String>>)> raw(
  int port,
  String requestLine, [
  Map<String, String> headers = const {},
]) async {
  final socket = await Socket.connect('127.0.0.1', port);
  final headerLines = [
    for (final MapEntry(:key, :value) in headers.entries) '$key: $value\r\n',
  ].join();
  socket.add(
    latin1.encode(
      '$requestLine\r\nHost: localhost\r\nConnection: close\r\n'
      '$headerLines\r\n',
    ),
  );
  await socket.flush();
  final bytes = await socket.fold<List<int>>(
    [],
    (all, chunk) => all..addAll(chunk),
  );
  socket.destroy();
  final text = latin1.decode(bytes);
  final head = text.split('\r\n\r\n').first.split('\r\n');
  final status = int.parse(head.first.split(' ')[1]);
  final values = <String, List<String>>{};
  for (final line in head.skip(1)) {
    final colon = line.indexOf(':');
    (values[line.substring(0, colon).toLowerCase()] ??= []).add(
      line.substring(colon + 1).trim(),
    );
  }
  return (status, values);
}

void main() {
  Future<void> server(Future<void> Function(int port) body) =>
      securityRunner(rulesSecurityBeans, [
        'spring.test.web-environment=random-port',
        'server.address=127.0.0.1',
      ]).runAsync((started) async {
        final lifecycle = started.context
            .getBean<WebServerStartStopLifecycle>();
        final server = (await lifecycle.started)!;
        await body(server.port);
      });

  final admin = 'Basic ${base64.encode(utf8.encode('root:root-pw'))}';
  final user = 'Basic ${base64.encode(utf8.encode('ada:ada-pw'))}';

  test(
    'ambiguous request targets are refused with 400',
    () => server((port) async {
      for (final target in [
        '//admin/api/admin',
        '/api/admin;x=1',
        '/api%2Fadmin',
        '/api/admin%5c',
        '/api//admin',
        '/api/admin%00',
      ]) {
        final (status, _) = await raw(port, 'GET $target HTTP/1.1', {
          'Authorization': admin,
        });
        expect(status, 400, reason: target);
      }
    }),
  );

  test(
    r'dart:io normalizes `..` and `\`; the rules see the same path as the '
    'router',
    () => server((port) async {
      for (final target in [
        '/public/../api/admin',
        r'/public/..\api/admin',
        '/public/%2e%2e/api/admin',
      ]) {
        final (asUser, _) = await raw(port, 'GET $target HTTP/1.1', {
          'Authorization': user,
        });
        expect(asUser, 403, reason: target);
        final (anonymous, _) = await raw(port, 'GET $target HTTP/1.1');
        expect(anonymous, 401, reason: target);
      }
    }),
  );

  test(
    'security headers once each on the wire (dart:io defaults replaced)',
    () => server((port) async {
      final (status, headers) = await raw(port, 'GET /public/hello HTTP/1.1');
      expect(status, 200);
      expect(headers['x-frame-options'], ['DENY']);
      expect(headers['x-content-type-options'], ['nosniff']);
      expect(headers['x-xss-protection'], ['0']);
      // No version information (ASVS 14.3.3).
      expect(headers['server'], isNull);
      expect(headers['x-powered-by'], isNull);
    }),
  );

  test(
    'a Basic login and a 403 over the wire',
    () => server((port) async {
      expect(
        (await raw(port, 'GET /api/me HTTP/1.1', {'Authorization': user})).$1,
        200,
      );
      expect(
        (await raw(port, 'GET /api/admin HTTP/1.1', {
          'Authorization': user,
        })).$1,
        403,
      );
      final (status, headers) = await raw(port, 'GET /api/me HTTP/1.1');
      expect(status, 401);
      expect(headers['www-authenticate'], [
        'Basic realm="Realm", charset="UTF-8"',
      ]);
    }),
  );
}
