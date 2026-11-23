// IoHttpTransport follows redirects itself: a hop to another origin drops
// the headers that carry a credential, https never goes down to http.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

void main() {
  late io.HttpServer other;
  late io.HttpServer api;
  final seen = <String, String>{};

  setUp(() async {
    seen.clear();
    other = await io.HttpServer.bind('127.0.0.1', 0)
      ..listen((request) {
        request.headers.forEach((name, values) => seen[name] = values.join());
        unawaited(
          (request.response..write('other')).close(),
        );
      });
    api = await io.HttpServer.bind('127.0.0.1', 0)
      ..listen((request) {
        final target = switch (request.uri.path) {
          '/away' => 'http://localhost:${other.port}/collect',
          '/same' => '/here',
          _ => null,
        };
        if (target == null) {
          request.headers.forEach((name, values) => seen[name] = values.join());
          unawaited((request.response..write('here')).close());
          return;
        }
        request.response
          ..statusCode = 302
          ..headers.set('Location', target);
        unawaited(request.response.close());
      });
  });

  tearDown(() async {
    await other.close(force: true);
    await api.close(force: true);
  });

  HttpRequest request(String path) => HttpRequest(
    method: HttpMethod.get,
    url: Uri.parse('http://127.0.0.1:${api.port}$path'),
    headers: HttpHeaders({
      'Authorization': 'Bearer SECRET',
      'X-Api-Key': 'SECRET',
      'DPoP': 'PROOF',
      'X-Tenant': 'SECRET',
      'Accept': 'text/plain',
    }),
    sensitiveHeaders: const {'x-tenant'},
  );

  test('another origin gets no credential (FE-1)', () async {
    final transport = IoHttpTransport();
    addTearDown(transport.close);
    final response = await transport.send(request('/away'));
    expect(response.bodyText, 'other');
    expect(seen.keys, isNot(contains('authorization')));
    expect(seen.keys, isNot(contains('x-api-key')));
    expect(seen.keys, isNot(contains('dpop')));
    expect(seen.keys, isNot(contains('x-tenant')));
    expect(seen['accept'], 'text/plain');
  });

  test('the same origin keeps them', () async {
    final transport = IoHttpTransport();
    addTearDown(transport.close);
    final response = await transport.send(request('/same'));
    expect(response.bodyText, 'here');
    expect(seen['authorization'], 'Bearer SECRET');
    expect(seen['x-tenant'], 'SECRET');
  });

  test('without followRedirects the 3xx is the answer', () async {
    final transport = IoHttpTransport();
    addTearDown(transport.close);
    final response = await transport.send(
      HttpRequest(
        method: HttpMethod.get,
        url: Uri.parse('http://127.0.0.1:${api.port}/away'),
        followRedirects: false,
      ),
    );
    expect(response.statusCode, 302);
    expect(seen, isEmpty);
  });

  test('the shared rule of credential names (LG-1)', () {
    for (final header in ['Authorization', 'DPoP', 'Cookie', 'X-Api-Key']) {
      expect(HttpSecrets.isSensitiveHeader(header), isTrue, reason: header);
    }
    expect(HttpSecrets.isSensitiveHeader('Accept'), isFalse);
    for (final parameter in [
      'code',
      'state',
      'code_verifier',
      'client_assertion',
      'id_token_hint',
      'jwt',
      'X-Amz-Signature',
      'access_token',
    ]) {
      expect(
        HttpSecrets.isSensitiveParameter(parameter),
        isTrue,
        reason: parameter,
      );
    }
    expect(HttpSecrets.isSensitiveParameter('page'), isFalse);
  });
}
