import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'platform_support.dart';
import 'support.dart';

/// What the function of the tests must do on every platform: the same
/// application answers the same way wherever it runs. [client] gives the
/// way to call it, once the platform is up.
///
/// - [platform]: what `spring.edge.runtime` is there;
/// - [greeting]: the value of the environment variable `GREETING` the
///   platform was started with;
/// - [keepsInstance]: whether consecutive requests reach one instance
///   (its memory: the rate limiter's counters).
void platformChecks(
  FunctionClient Function() client, {
  required String platform,
  required String greeting,
  bool keepsInstance = true,
}) {
  Map<String, String> bearer(String value) => {
    'authorization': 'Bearer $value',
  };

  test('a controller answers, with the environment of the platform', () async {
    final answer = await client().get('/hello?name=Ada%20L');
    expect(answer.status, 200);
    expect(answer.header('content-type'), startsWith('application/json'));
    final body = answer.json! as Map;
    expect(body['message'], 'hello Ada L');
    expect(body['platform'], platform);
    expect(body['greeting'], greeting);
    expect(body['path'], '/hello');
  });

  test('a JSON body and a header reach the method', () async {
    final answer = await client().send(
      'POST',
      '/echo',
      headers: {'content-type': 'application/json', 'x-trace': 't-1'},
      body: utf8.encode('{"a":[1,2],"text":"žluťoučký"}'),
    );
    expect(answer.status, 200);
    expect(answer.json, {
      'body': {
        'a': [1, 2],
        'text': 'žluťoučký',
      },
      'trace': 't-1',
    });
  });

  test('a multipart upload is read in memory', () async {
    const boundary = 'xBOUNDARYx';
    const body =
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="title"\r\n\r\n'
        'cover\r\n'
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="a.bin"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n'
        '12345\r\n'
        '--$boundary--\r\n';
    final answer = await client().send(
      'POST',
      '/upload',
      headers: {'content-type': 'multipart/form-data; boundary=$boundary'},
      body: utf8.encode(body),
    );
    expect(answer.status, 200);
    expect(answer.json, {'name': 'a.bin', 'size': 5, 'title': 'cover'});
  });

  test('bytes come back as they are', () async {
    final answer = await client().get('/download');
    expect(answer.status, 200);
    expect(answer.bytes, [0, 159, 146, 150, 255, 1, 2]);
  });

  test('every cookie is a Set-Cookie of its own', () async {
    final answer = await client().get('/cookies');
    expect(answer.headers['set-cookie'], [
      'a=1; Path=/; HttpOnly',
      'b=2; Path=/',
    ]);
  });

  test('a 204 has no body', () async {
    final answer = await client().get('/nothing');
    expect(answer.status, 204);
    expect(answer.bytes, isEmpty);
  });

  test('an event stream arrives', () async {
    final answer = await client().get('/events');
    expect(answer.status, 200);
    expect(answer.header('content-type'), startsWith('text/event-stream'));
    expect(answer.text, contains('data: {"tick":1}'));
    expect(answer.text, contains('data: {"tick":3}'));
  });

  test('work given to waitUntil ends after the answer', () async {
    final before = (await client().get('/later')).json! as int;
    expect((await client().send('POST', '/later')).text, 'accepted');
    var after = before;
    for (var i = 0; i < 40 && after == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      after = (await client().get('/later')).json! as int;
    }
    expect(after, before + 1);
  }, skip: keepsInstance ? null : 'the instances share no memory');

  test('what works differently is named, by its real name', () async {
    final warnings = (await client().get('/warnings')).json! as List;
    // The class of the method, not a name the compiler shortened.
    expect(
      warnings,
      contains(startsWith('@Scheduled Rates.refresh (PeriodicTrigger(')),
    );
    expect(
      warnings,
      contains(startsWith("cached values (bean 'cacheManager')")),
    );
  });

  test('an error nobody handled: 500 without its message', () async {
    final answer = await client().get('/boom');
    expect(answer.status, 500);
    expect(answer.text, isNot(contains('secret')));
  });

  test('a header that cannot be sent: 500, and the function lives', () async {
    expect((await client().get('/bad-header')).status, 500);
    expect((await client().get('/hello')).status, 200);
  });

  test('a body over server.max-http-request-body-size: 413', () async {
    final answer = await client().send(
      'POST',
      '/size',
      headers: {'content-type': 'application/octet-stream'},
      body: Uint8List(100 * 1024),
    );
    expect(answer.status, 413);
    final allowed = await client().send(
      'POST',
      '/size',
      headers: {'content-type': 'application/octet-stream'},
      body: Uint8List(60 * 1024),
    );
    expect(allowed.json, {'bytes': 60 * 1024});
  });

  test('the rate limiter refuses with 429', () async {
    final id = 'c-${DateTime.now().microsecondsSinceEpoch}';
    final statuses = [
      for (var i = 0; i < 3; i++)
        (await client().get('/limited', headers: {'x-client': id})).status,
    ];
    expect(statuses, [200, 200, 429]);
  }, skip: keepsInstance ? null : 'the instances share no memory');

  group('security', () {
    test('no token: 401; a token: the user; a role: by the role', () async {
      expect((await client().get('/api/me')).status, 401);
      final me = await client().get(
        '/api/me',
        headers: bearer(userToken('ada', roles: ['USER'])),
      );
      expect(me.json, {
        'name': 'ada',
        'authorities': ['ROLE_USER'],
      });
      expect(
        (await client().get(
          '/api/admin',
          headers: bearer(userToken('ada', roles: ['USER'])),
        )).status,
        403,
      );
      expect(
        (await client().get(
          '/api/admin',
          headers: bearer(userToken('root', roles: ['ADMIN'])),
        )).text,
        'every report',
      );
    });

    test('tokens that must not pass', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final unsigned = token(
        {'sub': 'ada', 'exp': now + 3600},
        header: const {'alg': 'none', 'typ': 'JWT'},
      );
      final forged = {
        'expired': userToken('ada', expired: true),
        'another secret': userToken(
          'ada',
          secret: 'ffffffffffffffffffffffffffffffff',
        ),
        'alg none': unsigned,
        'alg none, no signature':
            '${unsigned.substring(0, unsigned.lastIndexOf('.'))}.',
        'without exp': token({'sub': 'ada'}),
        'not a token': 'ada',
      };
      for (final MapEntry(:key, :value) in forged.entries) {
        expect(
          (await client().get('/api/me', headers: bearer(value))).status,
          401,
          reason: key,
        );
      }
    });

    test('a protected path under another spelling is never open', () async {
      for (final target in [
        '/api/me/',
        '/api/me;x=1',
        '/api;x/me',
        '//api/me',
        '/API/me',
        '/api/./me',
        '/files/../api/me',
        '/files/%2e%2e/api/me',
        '/files/..%2fapi/me',
        '/files/..%5capi/me',
        '/api/me%20',
        '/api/me%00',
        '/api/me.json',
        '/api%2fme',
      ]) {
        final status = await client().rawStatus(target);
        expect(status, isNot(200), reason: target);
        expect(status, lessThan(500), reason: target);
      }
    });

    test('an encoded separator in a path is refused', () async {
      for (final target in ['/files/a%2Fb', '/files/a%5Cb']) {
        expect(await client().rawStatus(target), 400, reason: target);
      }
    });

    test('the address of the client is not taken from a header', () async {
      final answer = await client().get(
        '/hello',
        headers: {
          'x-forwarded-for': '198.51.100.1',
          'x-real-ip': '198.51.100.1',
          'forwarded': 'for=198.51.100.1',
          'true-client-ip': '198.51.100.1',
        },
      );
      expect((answer.json! as Map)['remote'], isNot('198.51.100.1'));
    });

    test('the security headers of a server are there', () async {
      final answer = await client().get('/hello');
      expect(answer.header('x-content-type-options'), 'nosniff');
      expect(answer.header('x-frame-options'), 'DENY');
    });
  });
}
