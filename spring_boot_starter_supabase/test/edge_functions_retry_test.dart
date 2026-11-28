@Tags(['supabase'])
library;

import 'dart:async';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

// The interceptors of the Edge Functions group on a RestClient of their
// own: the retries of a RetryTemplate (no answer, or an error status with
// Retry-After; never another error status), the time limit of a call, and
// the origin the key goes to.
void main() {
  late MockHttpTransport transport;
  late List<String> tokens;
  // The Authorization header of each attempt, as it was sent.
  late List<String?> sent;

  setUp(() {
    transport = MockHttpTransport();
    tokens = [];
    sent = [];
  });

  RestClient client({
    RetryTemplate? retries,
    Duration timeout = const Duration(seconds: 5),
    String base = '$projectUrl/functions/v1',
  }) {
    final credentials = _CountingCredentials(tokens);
    return RestClient.builder()
        .baseUrl(base)
        .transport(transport)
        .requestInterceptor(
          EdgeFunctionsInterceptor(
            timeout: timeout,
            basePath: '/functions/v1',
            retryTemplate: retries,
          ),
        )
        .requestInterceptor(
          SupabaseCredentialsInterceptor(
            credentials: credentials,
            origin: Uri.parse(projectUrl),
          ),
        )
        .build();
  }

  RetryTemplate quick({int maxRetries = 3}) => RetryTemplate(
    retryPolicy: RetryPolicy.builder()
        .maxRetries(maxRetries)
        .delay(const Duration(milliseconds: 1))
        .build(),
  );

  Future<String> call(RestClient rest) =>
      rest.get().uri('/reports/{year}', 2026).retrieve().body<String>();

  void answer(List<Object> answers) {
    var next = 0;
    transport.when(HttpMethod.get, '/functions/v1/reports/2026').respondWith((
      request,
    ) {
      final step = answers[next < answers.length ? next : answers.length - 1];
      next++;
      sent.add(request.headers['Authorization']);
      return switch (step) {
        final HttpResponse response => HttpResponse(
          response.statusCode.value,
          headers: response.headers,
          body: response.bodyBytes,
          request: request,
        ),
        final Exception error => throw error,
        _ => throw ArgumentError.value(step),
      };
    });
  }

  HttpResponse ok() => HttpResponse(200, body: 'report'.codeUnits);

  HttpResponse status(int code, {String? retryAfter}) => HttpResponse(
    code,
    headers: HttpHeaders({'Retry-After': ?retryAfter}),
    body: 'busy'.codeUnits,
  );

  HttpTransportException refused() =>
      HttpTransportException('connection failed: Connection refused');

  group('without a RetryTemplate', () {
    test('a failure is not tried again', () async {
      answer([refused(), ok()]);
      await expectLater(
        call(client()),
        throwsA(isA<ResourceAccessException>()),
      );
      expect(transport.requests, hasLength(1));
    });
  });

  group('with a RetryTemplate', () {
    test('no answer is tried again, each attempt with the token of '
        'that moment', () async {
      answer([refused(), refused(), ok()]);
      expect(await call(client(retries: quick())), 'report');
      expect(transport.requests, hasLength(3));
      expect(sent, ['Bearer token-1', 'Bearer token-2', 'Bearer token-3']);
    });

    test('an error status without Retry-After is not tried again', () async {
      answer([status(503), ok()]);
      await expectLater(
        call(client(retries: quick())),
        throwsA(isA<HttpServerErrorException>()),
      );
      expect(transport.requests, hasLength(1));
    });

    test('an error status with Retry-After is tried again after the pause '
        'it asks for', () async {
      answer([status(503, retryAfter: '0'), ok()]);
      expect(await call(client(retries: quick())), 'report');
      expect(transport.requests, hasLength(2));
    });

    test('the last answer of a call out of retries goes to the status '
        'handlers', () async {
      answer([status(429, retryAfter: '0')]);
      await expectLater(
        call(client(retries: quick(maxRetries: 2))),
        throwsA(
          isA<HttpClientErrorException>().having(
            (e) => e.statusCode.value,
            'status',
            429,
          ),
        ),
      );
      expect(transport.requests, hasLength(3));
    });

    test('a Retry-After past the time limit is not waited for', () async {
      answer([status(503, retryAfter: '120'), ok()]);
      final watch = Stopwatch()..start();
      await expectLater(
        call(client(retries: quick(), timeout: const Duration(seconds: 2))),
        throwsA(isA<HttpServerErrorException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(transport.requests, hasLength(1));
    });

    test('a Retry-After past the deadline of the caller is not waited '
        'for', () async {
      answer([status(503, retryAfter: '3'), ok()]);
      await expectLater(
        RequestDeadline.run(
          const Duration(milliseconds: 500),
          () => call(client(retries: quick())),
        ),
        throwsA(isA<HttpServerErrorException>()),
      );
      expect(transport.requests, hasLength(1));
    });

    test('an address the transport refuses is not tried again', () async {
      answer([
        HttpTransportException('not allowed', isRetryable: false),
        ok(),
      ]);
      await expectLater(
        call(client(retries: quick())),
        throwsA(isA<ResourceAccessException>()),
      );
      expect(transport.requests, hasLength(1));
    });

    test("the application's policy still decides", () async {
      answer([refused(), ok()]);
      final none = RetryTemplate(
        retryPolicy: RetryPolicy.builder()
            .delay(Duration.zero)
            .exclude<ResourceAccessException>()
            .build(),
      );
      await expectLater(
        call(client(retries: none)),
        throwsA(isA<ResourceAccessException>()),
      );
      expect(transport.requests, hasLength(1));
    });
  });

  group('Retry-After', () {
    test('seconds, or an HTTP date', () {
      final now = DateTime.utc(2026, 10, 21, 7, 28);
      expect(
        EdgeFunctionsInterceptor.retryAfter('120'),
        const Duration(seconds: 120),
      );
      expect(
        EdgeFunctionsInterceptor.retryAfter(
          'Wed, 21 Oct 2026 07:28:30 GMT',
          now: now,
        ),
        const Duration(seconds: 30),
      );
      expect(
        EdgeFunctionsInterceptor.retryAfter(
          'Wed, 21 Oct 2026 07:27:00 GMT',
          now: now,
        ),
        Duration.zero,
      );
    });

    test('anything else asks for nothing', () {
      expect(EdgeFunctionsInterceptor.retryAfter(null), isNull);
      expect(EdgeFunctionsInterceptor.retryAfter('-5'), isNull);
      expect(EdgeFunctionsInterceptor.retryAfter('soon'), isNull);
    });
  });

  test('a call is limited by its time limit, under a longer deadline of '
      'the caller too', () async {
    answer([ok()]);
    final sent = client(timeout: const Duration(milliseconds: 100));
    await RequestDeadline.run(const Duration(seconds: 3), () => call(sent));
    final limit = transport.requests.single.timeout;
    expect(limit, isNotNull);
    expect(limit, lessThanOrEqualTo(const Duration(milliseconds: 100)));
  });

  test('the key and the token go to the project only', () async {
    final other = client(base: 'https://elsewhere.example/functions/v1');
    await expectLater(call(other), throwsA(isA<StateError>()));
    expect(transport.requests, isEmpty);
  });
}

// Credentials whose token changes at each call, as after a refresh.
final class _CountingCredentials implements SupabaseCredentials {
  _CountingCredentials(this.tokens);

  final List<String> tokens;

  @override
  String get apiKey => 'anon-key';

  @override
  Future<String> accessToken() async {
    final token = 'token-${tokens.length + 1}';
    tokens.add(token);
    return token;
  }

  @override
  SupabaseCaller get caller => throw UnimplementedError();

  @override
  Future<T> asServiceRole<T>(FutureOr<T> Function() body) async => await body();
}
