import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'catalog.dart';
import 'orders.dart';
import 'support/feign_properties.dart';

typedef _Script = Future<HttpResponse> Function(HttpRequest request, int n);

/// A transport that behaves like a server whose answers the test scripts,
/// and like the real transports in what the timeouts of a request do: a
/// wait longer than `timeout` or `readTimeout` ends in an
/// `HttpTransportException` with `isTimeout` at that time.
final class _ScriptedTransport implements HttpTransport {
  _ScriptedTransport(this.script);

  final _Script script;
  final requests = <HttpRequest>[];

  /// Answers [text] after [delay].
  static _Script slow(Duration delay, [String text = 'pong']) =>
      (request, n) => HttpResponse(
        200,
        body: utf8.encode(text),
        request: request,
      ).after(delay);

  Duration? _limit(HttpRequest request) {
    final limits = [
      ?request.timeout,
      ?request.readTimeout,
    ]..sort();
    return limits.firstOrNull;
  }

  @override
  Future<HttpResponse> send(HttpRequest request) {
    requests.add(request);
    final n = requests.length;
    final limit = _limit(request);
    final answer = script(request, n);
    if (limit == null) {
      return answer;
    }
    return answer.timeout(
      limit,
      onTimeout: () => throw HttpTransportException(
        'no data within ${limit.inMilliseconds} ms',
        request: request,
        isTimeout: true,
      ),
    );
  }

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) {
    requests.add(request);
    final limit = request.timeout;
    final answer = script(request, requests.length).then(
      (response) => StreamedHttpResponse(
        response.statusCode,
        headers: response.headers,
        body: Stream.value(response.bodyBytes),
        request: request,
      ),
    );
    if (limit == null) {
      return answer;
    }
    return answer.timeout(
      limit,
      onTimeout: () => throw HttpTransportException(
        'no response within ${limit.inMilliseconds} ms',
        request: request,
        isTimeout: true,
      ),
    );
  }

  @override
  void close() {}
}

extension on HttpResponse {
  Future<HttpResponse> after(Duration delay) async {
    await Future<void>.delayed(delay);
    return this;
  }
}

HttpTransportException _reset(HttpRequest request) =>
    HttpTransportException('connection reset', request: request);

final class _Pauses implements Retryer {
  _Pauses(this.pause, this.maxAttempts);
  final Duration pause;
  final int maxAttempts;

  @override
  Duration? nextDelay(int attempt, RetryableException error) =>
      attempt >= maxAttempts ? null : pause;
}

void main() {
  late _ScriptedTransport transport;

  ApplicationContextRunner runner([
    List<String> properties = const [],
    Retryer? retryer,
  ]) {
    var result = const ApplicationContextRunner()
        .withUserConfiguration(appModule)
        .withUserConfiguration(ordersModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withPropertyValues([
          'catalog.url=https://api.neon.test',
          ...properties,
        ])
        .withBean<HttpTransport>(() => transport);
    if (retryer != null) {
      result = result.withBean<Retryer>(() => retryer);
    }
    return result;
  }

  Future<T> timed<T>(
    Future<T> Function() call,
    void Function(Duration) check,
  ) async {
    final watch = Stopwatch()..start();
    try {
      return await call();
    } finally {
      check(watch.elapsed);
    }
  }

  group('FeignClientConfig call-timeout', () {
    Duration? callTimeout(List<String> properties, [String name = 'catalog']) {
      final environment = StandardEnvironment();
      for (final property in properties) {
        final i = property.indexOf('=');
        environment.propertySources.addLast(
          MapPropertySource('t$i${property.hashCode}', {
            property.substring(0, i): property.substring(i + 1),
          }),
        );
      }
      return FeignClientConfig.of(
        bindFeignProperties(environment),
        name,
      ).callTimeout;
    }

    test('is none by default', () {
      expect(callTimeout([]), isNull);
      expect(const FeignClientConfig().callTimeout, isNull);
    });

    test('is read per client, with default for the others', () {
      const key = 'spring.feign.client.config';
      expect(
        callTimeout(['$key.default.call-timeout=5s']),
        const Duration(seconds: 5),
      );
      expect(
        callTimeout([
          '$key.default.call-timeout=5s',
          '$key.catalog.call-timeout=250ms',
        ]),
        const Duration(milliseconds: 250),
      );
      expect(
        callTimeout([
          '$key.default.call-timeout=5s',
          '$key.catalog.call-timeout=250ms',
        ], 'orders'),
        const Duration(seconds: 5),
      );
    });

    test(
      'has relaxed names: callTimeout, CALLTIMEOUT in the environment',
      () async {
        transport = _ScriptedTransport(_ScriptedTransport.slow(Duration.zero));
        await runner([
          'spring.feign.client.config.catalog.callTimeout=2s',
          'spring.feign.client.config.orders.call_timeout=3s',
        ]).runAsync((context) async {
          final properties = context.getBean<FeignProperties>();
          expect(
            FeignClientConfig.of(properties, 'catalog').callTimeout,
            const Duration(seconds: 2),
          );
          expect(
            FeignClientConfig.of(properties, 'orders').callTimeout,
            const Duration(seconds: 3),
          );
        });
      },
    );

    test('0 and a negative duration mean none', () {
      const key = 'spring.feign.client.config';
      expect(callTimeout(['$key.catalog.call-timeout=0']), isNull);
      expect(callTimeout(['$key.catalog.call-timeout=0s']), isNull);
      expect(callTimeout(['$key.catalog.call-timeout=-1']), isNull);
      expect(
        callTimeout([
          '$key.default.call-timeout=5s',
          '$key.catalog.call-timeout=0',
        ]),
        isNull,
      );
    });
  });

  group('call-timeout', () {
    test('a call that answers in time is untouched, and every attempt is '
        'sent with timeouts capped by the call-timeout', () async {
      transport = _ScriptedTransport(
        _ScriptedTransport.slow(const Duration(milliseconds: 20)),
      );
      await runner([
        'spring.feign.client.config.catalog.call-timeout=2s',
      ]).runAsync((context) async {
        expect(await context.getBean<CatalogClient>().ping(), 'pong');
        final request = transport.requests.single;
        expect(request.timeout, isNotNull);
        expect(request.timeout, lessThanOrEqualTo(const Duration(seconds: 2)));
        // The read timeout (60 s) is capped by what remains.
        expect(
          request.readTimeout,
          lessThanOrEqualTo(const Duration(seconds: 2)),
        );
      });
    });

    test('a read timeout shorter than what remains stays', () async {
      transport = _ScriptedTransport(_ScriptedTransport.slow(Duration.zero));
      await runner([
        'spring.feign.client.config.catalog.call-timeout=5s',
        'spring.feign.client.config.catalog.read-timeout=1s',
      ]).runAsync((context) async {
        await context.getBean<CatalogClient>().ping();
        expect(
          transport.requests.single.readTimeout,
          const Duration(seconds: 1),
        );
        expect(
          transport.requests.single.timeout,
          lessThanOrEqualTo(const Duration(seconds: 5)),
        );
      });
    });

    test('without a call-timeout and a deadline nothing is added', () async {
      transport = _ScriptedTransport(_ScriptedTransport.slow(Duration.zero));
      await runner().runAsync((context) async {
        await context.getBean<CatalogClient>().ping();
        expect(transport.requests.single.timeout, isNull);
        expect(
          transport.requests.single.readTimeout,
          const Duration(seconds: 60),
        );
      });
    });

    test('a slow server: the call fails at the call-timeout, not at the '
        'read timeout', () async {
      transport = _ScriptedTransport(
        _ScriptedTransport.slow(const Duration(seconds: 5)),
      );
      await runner([
        'spring.feign.client.config.catalog.call-timeout=300ms',
      ]).runAsync((context) async {
        await timed(
          () => expectLater(
            context.getBean<CatalogClient>().ping(),
            throwsA(
              isA<FeignCallTimeoutException>()
                  .having((e) => e.attempts, 'attempts', 1)
                  .having(
                    (e) => e.enclosingDeadline,
                    'enclosingDeadline',
                    isFalse,
                  )
                  .having((e) => e.status, 'status', -1)
                  .having(
                    (e) => e.message,
                    'message',
                    allOf(
                      contains('300 ms'),
                      contains('CatalogClient#ping()'),
                      contains('/v1/ping'),
                    ),
                  )
                  .having(
                    (e) => e.cause,
                    'cause',
                    isA<HttpTransportException>(),
                  ),
            ),
          ),
          (elapsed) => expect(elapsed, lessThan(const Duration(seconds: 2))),
        );
        expect(transport.requests, hasLength(1));
      });
    });

    test('it covers the retries: a slow server is tried again until the '
        'time is gone, then never again', () async {
      transport = _ScriptedTransport(
        _ScriptedTransport.slow(const Duration(seconds: 5)),
      );
      await runner(
        [
          'spring.feign.client.config.catalog.call-timeout=700ms',
          'spring.feign.client.config.catalog.read-timeout=100ms',
        ],
        _Pauses(const Duration(milliseconds: 50), 100),
      ).runAsync((context) async {
        await timed(
          () => expectLater(
            context.getBean<CatalogClient>().ping(),
            throwsA(
              isA<FeignCallTimeoutException>().having(
                (e) => e.attempts,
                'attempts',
                greaterThan(2),
              ),
            ),
          ),
          (elapsed) {
            expect(elapsed, lessThan(const Duration(milliseconds: 1500)));
            expect(
              elapsed,
              greaterThanOrEqualTo(const Duration(milliseconds: 650)),
            );
          },
        );
        // Every attempt the exception counts was sent; none after it.
        final sent = transport.requests.length;
        expect(sent, greaterThan(2));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(transport.requests, hasLength(sent));
        // Each attempt's read timeout shrinks with what remains.
        expect(
          transport.requests.last.timeout,
          lessThan(const Duration(milliseconds: 700)),
        );
      });
    });

    test('fails, then succeeds within the time: the retry works', () async {
      transport = _ScriptedTransport((request, n) async {
        if (n == 1) {
          throw _reset(request);
        }
        return HttpResponse(200, body: utf8.encode('pong'), request: request);
      });
      await runner(
        ['spring.feign.client.config.catalog.call-timeout=2s'],
        _Pauses(const Duration(milliseconds: 50), 3),
      ).runAsync((context) async {
        expect(await context.getBean<CatalogClient>().ping(), 'pong');
        expect(transport.requests, hasLength(2));
      });
    });

    test(
      'a pause that would end past the limit ends the call at once',
      () async {
        transport = _ScriptedTransport(
          (request, n) async => throw _reset(request),
        );
        await runner(
          ['spring.feign.client.config.catalog.call-timeout=500ms'],
          _Pauses(const Duration(seconds: 30), 3),
        ).runAsync((context) async {
          await timed(
            () => expectLater(
              context.getBean<CatalogClient>().ping(),
              throwsA(
                isA<FeignCallTimeoutException>()
                    .having((e) => e.attempts, 'attempts', 1)
                    .having(
                      (e) => e.message,
                      'message',
                      contains('retry pause is 30000 ms'),
                    ),
              ),
            ),
            (elapsed) =>
                expect(elapsed, lessThan(const Duration(milliseconds: 300))),
          );
          expect(transport.requests, hasLength(1));
        });
      },
    );

    test("failures within the limit are the retryer's: it gives up as "
        'before', () async {
      transport = _ScriptedTransport(
        (request, n) async => throw _reset(request),
      );
      await runner(
        ['spring.feign.client.config.catalog.call-timeout=5s'],
        _Pauses(const Duration(milliseconds: 5), 3),
      ).runAsync((context) async {
        await expectLater(
          context.getBean<CatalogClient>().ping(),
          throwsA(isA<RetryableException>()),
        );
        expect(transport.requests, hasLength(3));
      });
    });

    test('an error status is no timeout', () async {
      transport = _ScriptedTransport(
        (request, n) async => HttpResponse(404, request: request),
      );
      await runner(['spring.feign.client.config.catalog.call-timeout=5s'])
          .runAsync((context) async {
            await expectLater(
              context.getBean<CatalogClient>().ping(),
              throwsA(isA<FeignNotFound>()),
            );
          });
    });

    test('the fallback still answers a call that timed out', () async {
      transport = _ScriptedTransport(
        _ScriptedTransport.slow(const Duration(seconds: 5)),
      );
      await runner([
        'spring.feign.client.config.backup.call-timeout=100ms',
      ]).runAsync((context) async {
        expect(await context.getBean<BackupClient>().motd(), 'offline');
      });
    });
  });

  group('the deadline of the code that makes the call', () {
    test('limits a call that has no call-timeout; never retried', () async {
      transport = _ScriptedTransport(
        _ScriptedTransport.slow(const Duration(seconds: 5)),
      );
      await runner(
        const [],
        _Pauses(const Duration(milliseconds: 10), 100),
      ).runAsync((context) async {
        final client = context.getBean<CatalogClient>();
        await timed(
          () => expectLater(
            RequestDeadline.run(const Duration(milliseconds: 300), client.ping),
            throwsA(
              isA<FeignCallTimeoutException>()
                  .having(
                    (e) => e.enclosingDeadline,
                    'enclosingDeadline',
                    isTrue,
                  )
                  .having(
                    (e) => e.message,
                    'message',
                    contains('enclosing request'),
                  ),
            ),
          ),
          (elapsed) => expect(elapsed, lessThan(const Duration(seconds: 2))),
        );
        // Not retried at the deadline: one attempt was sent.
        expect(transport.requests, hasLength(1));
        expect(
          transport.requests.single.timeout,
          lessThanOrEqualTo(const Duration(milliseconds: 300)),
        );
        expect(
          transport.requests.single.readTimeout,
          lessThanOrEqualTo(const Duration(milliseconds: 300)),
        );
      });
    });

    test('a call-timeout shorter than the deadline wins', () async {
      transport = _ScriptedTransport(
        _ScriptedTransport.slow(const Duration(seconds: 5)),
      );
      await runner(['spring.feign.client.config.catalog.call-timeout=150ms'])
          .runAsync((context) async {
            final client = context.getBean<CatalogClient>();
            await expectLater(
              RequestDeadline.run(const Duration(seconds: 30), client.ping),
              throwsA(
                isA<FeignCallTimeoutException>().having(
                  (e) => e.enclosingDeadline,
                  'enclosingDeadline',
                  isFalse,
                ),
              ),
            );
            expect(
              transport.requests.single.timeout,
              lessThanOrEqualTo(const Duration(milliseconds: 150)),
            );
          });
    });

    test('the deadline wins over a longer call-timeout', () async {
      transport = _ScriptedTransport(
        _ScriptedTransport.slow(const Duration(seconds: 5)),
      );
      await runner([
        'spring.feign.client.config.catalog.call-timeout=30s',
      ]).runAsync((context) async {
        final client = context.getBean<CatalogClient>();
        await expectLater(
          RequestDeadline.run(const Duration(milliseconds: 150), client.ping),
          throwsA(
            isA<FeignCallTimeoutException>().having(
              (e) => e.enclosingDeadline,
              'enclosingDeadline',
              isTrue,
            ),
          ),
        );
        expect(
          transport.requests.single.timeout,
          lessThanOrEqualTo(const Duration(milliseconds: 150)),
        );
      });
    });

    test('a deadline that has passed fails the call before anything is '
        'sent', () async {
      transport = _ScriptedTransport(_ScriptedTransport.slow(Duration.zero));
      await runner().runAsync((context) async {
        final client = context.getBean<CatalogClient>();
        await expectLater(
          RequestDeadline.run(Duration.zero, client.ping),
          throwsA(
            isA<FeignCallTimeoutException>()
                .having((e) => e.attempts, 'attempts', 0)
                .having(
                  (e) => e.enclosingDeadline,
                  'enclosingDeadline',
                  isTrue,
                ),
          ),
        );
        expect(transport.requests, isEmpty);
      });
    });

    test(
      'a call made after the deadline was released is not limited',
      () async {
        transport = _ScriptedTransport(_ScriptedTransport.slow(Duration.zero));
        await runner().runAsync((context) async {
          final client = context.getBean<CatalogClient>();
          await RequestDeadline.run(Duration.zero, () {
            RequestDeadline.current!.release();
            return client.ping();
          });
          expect(transport.requests.single.timeout, isNull);
        });
      },
    );

    test('the interceptors run under it: a slow one uses the time', () async {
      transport = _ScriptedTransport(_ScriptedTransport.slow(Duration.zero));
      await runner()
          .withBean<RequestInterceptor>(_SlowInterceptor.new)
          .runAsync((context) async {
            final client = context.getBean<CatalogClient>();
            await expectLater(
              RequestDeadline.run(
                const Duration(milliseconds: 100),
                client.ping,
              ),
              throwsA(
                isA<FeignCallTimeoutException>().having(
                  (e) => e.attempts,
                  'attempts',
                  0,
                ),
              ),
            );
            expect(transport.requests, isEmpty);
          });
    });
  });

  group('event streams', () {
    test('the call-timeout limits establishing the stream, not its life, '
        'and is not reconnected', () async {
      transport = _ScriptedTransport(
        _ScriptedTransport.slow(const Duration(seconds: 5)),
      );
      await runner([
        'spring.feign.client.config.orders.call-timeout=150ms',
        'spring.feign.client.config.default.event-stream.reconnect-delay=10ms',
      ]).runAsync((context) async {
        final events = context.getBean<OrdersClient>().events('neon');
        await expectLater(
          events.first,
          throwsA(
            isA<FeignCallTimeoutException>().having(
              (e) => e.attempts,
              'attempts',
              1,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(transport.requests, hasLength(1));
        expect(
          transport.requests.single.timeout,
          lessThanOrEqualTo(const Duration(milliseconds: 150)),
        );
      });
    });

    test('a stream that connected in time lives longer than the '
        'call-timeout', () async {
      final controller = StreamController<List<int>>();
      transport = _StreamingTransport(controller.stream);
      await runner([
        'spring.feign.client.config.orders.call-timeout=100ms',
      ]).runAsync((context) async {
        final events = context.getBean<OrdersClient>().events('neon');
        final received = <int>[];
        final subscription = events.listen((order) => received.add(order.id));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        controller.add(utf8.encode('data: {"id":7,"status":"NEW"}\n\n'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(received, [7]);
        await subscription.cancel();
        await controller.close();
      });
    });
  });
}

final class _SlowInterceptor implements RequestInterceptor {
  @override
  FutureOr<void> apply(RequestTemplate template) =>
      Future<void>.delayed(const Duration(milliseconds: 250));
}

final class _StreamingTransport extends _ScriptedTransport {
  _StreamingTransport(this.body)
    : super((request, n) => throw UnimplementedError());

  final Stream<List<int>> body;

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    requests.add(request);
    return StreamedHttpResponse(
      200,
      headers: HttpHeaders({
        HttpHeaders.contentTypeHeader: MediaType.textEventStream,
      }),
      body: body,
      request: request,
    );
  }
}
