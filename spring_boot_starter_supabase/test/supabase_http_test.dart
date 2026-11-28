@Tags(['supabase'])
library;

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

// SupabaseHttp on its RestClient: the key and the token last, the time
// limit of a call under the deadline of its caller, the failures as
// SupabaseUnavailableException, and the application's builder.
void main() {
  late MockHttpTransport transport;

  setUp(() {
    transport = MockHttpTransport();
    transport.when(HttpMethod.get, '/rest/v1/todos').respond(200, json: []);
  });

  Future<HttpResponse> select(SupabaseHttp client, {Duration? timeout}) =>
      client.send(
        SupabaseService.rest,
        HttpMethod.get,
        '/todos',
        headers: {'apikey': 'forged', 'X-Trace': 't-1'},
        timeout: timeout,
      );

  test('the key and the token win over the headers of the call, and no '
      'redirect is followed', () async {
    await select(http(transport));
    final request = transport.lastRequest;
    expect(request.headers['apikey'], 'anon-key');
    expect(request.headers['Authorization'], 'Bearer anon-key');
    expect(request.headers['X-Trace'], 't-1');
    expect(request.followRedirects, isFalse);
    expect(request.sensitiveHeaders, contains('apikey'));
  });

  test('a JSON body is sent as JSON, a bearer of the call as the '
      'token', () async {
    transport.when(HttpMethod.post, '/auth/v1/token').respond(200, json: {});
    await http(transport).send(
      SupabaseService.auth,
      HttpMethod.post,
      '/token',
      json: {'grant_type': 'refresh_token'},
      bearer: 'session-token',
    );
    final request = transport.lastRequest;
    expect(request.headers.contentType, 'application/json');
    expect(
      String.fromCharCodes(request.body!),
      '{"grant_type":"refresh_token"}',
    );
    expect(request.headers['Authorization'], 'Bearer session-token');
  });

  group('the time limit of a call', () {
    test('is spring.supabase.timeout, or the one of the call', () async {
      final client = http(transport);
      await select(client);
      expect(transport.lastRequest.timeout, const Duration(seconds: 30));
      await select(client, timeout: const Duration(seconds: 2));
      expect(transport.lastRequest.timeout, const Duration(seconds: 2));
    });

    test('is cut by an earlier deadline of the caller', () async {
      await RequestDeadline.run(
        const Duration(milliseconds: 300),
        () => select(http(transport)),
      );
      expect(
        transport.lastRequest.timeout,
        lessThanOrEqualTo(const Duration(milliseconds: 300)),
      );
    });

    test('stays its own under a later deadline of the caller', () async {
      await RequestDeadline.run(
        const Duration(minutes: 5),
        () => select(http(transport), timeout: const Duration(seconds: 1)),
      );
      expect(
        transport.lastRequest.timeout,
        lessThanOrEqualTo(const Duration(seconds: 1)),
      );
    });

    test('a deadline that has passed sends nothing', () async {
      await expectLater(
        RequestDeadline.run(Duration.zero, () => select(http(transport))),
        throwsA(
          isA<SupabaseUnavailableException>().having(
            (e) => e.isTimeout,
            'isTimeout',
            isTrue,
          ),
        ),
      );
      expect(transport.requests, isEmpty);
    });
  });

  test('no answer is a SupabaseUnavailableException', () async {
    transport
        .when(HttpMethod.get, '/rest/v1/notes')
        .fail(
          HttpTransportException('no data within 10 ms', isTimeout: true),
        );
    await expectLater(
      http(transport).send(SupabaseService.rest, HttpMethod.get, '/notes'),
      throwsA(
        isA<SupabaseUnavailableException>()
            .having((e) => e.isTimeout, 'isTimeout', isTrue)
            .having((e) => e.message, 'message', contains('abcd.supabase.co')),
      ),
    );
  });

  test("the application's builder: its interceptors run first, and "
      'cannot replace the key', () async {
    final seen = <String?>[];
    final builder = RestClient.builder()
        .transport(transport)
        .defaultHeader('X-App', 'neon')
        .requestInterceptor(
          ClientHttpRequestInterceptor.of((request, body, execution) {
            seen.add(request.headers['apikey']);
            request.headers.set('apikey', 'replaced');
            return execution.execute(request, body);
          }),
        );
    final all = properties();
    final client = SupabaseHttp(
      properties: all,
      transport: MockHttpTransport(),
      credentials: DefaultSupabaseCredentials(
        properties: all,
        authentication: () => null,
      ),
      restClientBuilder: builder,
    );
    await select(client);
    final request = transport.lastRequest;
    expect(seen, ['forged']);
    expect(request.headers['apikey'], 'anon-key');
    expect(request.headers['X-App'], 'neon');
  });

  test('a stream carries the key and the token and follows no '
      'redirect', () async {
    transport
        .when(HttpMethod.get, '/storage/v1/object/a.png')
        .respond(200, bytes: [1]);
    final response = await http(
      transport,
    ).stream(SupabaseService.storage, HttpMethod.get, '/object/a.png');
    expect(await response.body.toList(), [
      [1],
    ]);
    final request = transport.lastRequest;
    expect(request.headers['apikey'], 'anon-key');
    expect(request.headers['Authorization'], 'Bearer anon-key');
    expect(request.followRedirects, isFalse);
  });

  test('the host of spring.supabase.url is contributed to the allowed '
      'addresses', () {
    expect(SupabaseAllowedAddresses(properties()).allowedAddresses(), [
      'abcd.supabase.co',
    ]);
    expect(
      SupabaseAllowedAddresses(
        SupabaseProperties()..url = 'http://127.0.0.1:54321',
      ).allowedAddresses(),
      ['127.0.0.1'],
    );
    expect(
      SupabaseAllowedAddresses(SupabaseProperties()).allowedAddresses(),
      isEmpty,
    );
  });
}
