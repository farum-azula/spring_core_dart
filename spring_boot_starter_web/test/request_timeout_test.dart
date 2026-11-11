// server.request-timeout: the total time of a request's filters and
// handler, as a RequestDeadline the code it calls can read (a Feign call),
// and a 503 when it passes. Over real sockets, with handlers written
// inline, so the tests need no code generation.
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_boot_starter_feign/spring_auto_configuration.dart'
    as feign;
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart'
    show FeignCallTimeoutException;
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/io.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'support.dart';
import 'upstream_client.dart';

typedef _Route = FutureOr<void> Function(ServerHttpRequest, ServerHttpResponse);

final class _Routes implements HandlerMapping {
  _Routes(this.routes);

  final Map<String, _Route> routes;

  @override
  HttpHandler? getHandler(ServerHttpRequest request) {
    final route = routes[request.path];
    return route == null
        ? null
        : FunctionHttpHandler((request, response) async {
            await route(request, response);
          });
  }
}

final class _Boom implements Exception {}

final class _SlowFilter implements WebFilter {
  _SlowFilter(this.delay);

  final Duration delay;
  bool passed = false;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    await Future<void>.delayed(delay);
    passed = true;
    await chain.doFilter(request, response);
  }
}

final class _ServedDispatcher {
  _ServedDispatcher(this.dispatcher, this.server);

  final DispatcherHandler dispatcher;
  final IoWebServer server;

  int get port => server.port;
}

/// The test application's dispatcher with [routes] as its only mapping and
/// [filters], serving on a free port; `server.request-timeout` is the
/// context's.
Future<_ServedDispatcher> _serveRoutes(
  ApplicationContext context,
  Map<String, _Route> routes, {
  List<WebFilter> filters = const [],
}) async {
  final base = context.getBean<DispatcherHandler>();
  final dispatcher = DispatcherHandler(
    handlerMappings: [_Routes(routes)],
    requestMapping: base.requestMapping,
    writer: base.writer,
    filters: filters,
    requestTimeout: base.requestTimeout,
  );
  final server = IoWebServer(
    dispatcher,
    const ServerProperties(port: 0, address: '127.0.0.1'),
  );
  await server.start();
  return _ServedDispatcher(dispatcher, server);
}

/// Everything the server sends on one connection until it closes.
Future<String> _raw(int port, String path) async {
  final socket = await io.Socket.connect('127.0.0.1', port)
    ..add(
      latin1.encode(
        'GET $path HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n',
      ),
    );
  final out = BytesBuilder();
  final done = Completer<void>();
  socket.listen(
    out.add,
    onError: (Object _) => done.isCompleted ? null : done.complete(),
    onDone: () => done.isCompleted ? null : done.complete(),
  );
  await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
  socket.destroy();
  return latin1.decode(out.takeBytes());
}

Future<void> _pause(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void main() {
  group('server.request-timeout, the property', () {
    Duration? timeout(String? value) => ServerProperties.of(
      StandardEnvironment()
        ..propertySources.addFirst(
          MapPropertySource('t', {'server.request-timeout': ?value}),
        ),
    ).requestTimeout;

    test('is a minute by default; no limit for 0 and for a negative '
        'duration', () {
      expect(
        const ServerProperties().requestTimeout,
        const Duration(seconds: 60),
      );
      expect(timeout(null), const Duration(seconds: 60));
      expect(ServerSettings().requestTimeout, const Duration(seconds: 60));
      expect(timeout('0'), isNull);
      expect(timeout('0s'), isNull);
      expect(timeout('-1'), isNull);
      expect(timeout('-5s'), isNull);
    });

    test('reads a duration', () {
      expect(timeout('30s'), const Duration(seconds: 30));
      expect(timeout('500ms'), const Duration(milliseconds: 500));
      expect(timeout('500'), const Duration(milliseconds: 500));
      expect(timeout('PT2S'), const Duration(seconds: 2));
      expect(
        const ServerProperties()
            .copyWith(
              requestTimeout: const Duration(seconds: 3),
            )
            .requestTimeout,
        const Duration(seconds: 3),
      );
    });

    test('reaches the dispatcher', () async {
      await webRunner(['server.request-timeout=1500ms']).runAsync((
        context,
      ) async {
        expect(
          context.context.getBean<DispatcherHandler>().requestTimeout,
          const Duration(milliseconds: 1500),
        );
      });
      await webRunner().runAsync((context) async {
        expect(
          context.context.getBean<DispatcherHandler>().requestTimeout,
          const Duration(seconds: 60),
        );
      });
      await webRunner(['server.request-timeout=0']).runAsync((context) async {
        expect(
          context.context.getBean<DispatcherHandler>().requestTimeout,
          isNull,
        );
      });
    });
  });

  group('by default (a minute)', () {
    test('a handler runs under a deadline of a minute, and one that takes '
        'its time within it is not cut', () async {
      await webRunner().runAsync((context) async {
        Duration? remaining;
        final served = await _serveRoutes(context.context, {
          '/slow': (request, response) async {
            remaining = RequestDeadline.current?.remaining;
            await _pause(300);
            await response.send(200, 'done');
          },
        });
        try {
          final reply = await Client(served.port).get('/slow');
          expect(reply.status, 200);
          expect(reply.body, 'done');
          expect(remaining, isNotNull);
          expect(remaining!.inSeconds, inInclusiveRange(55, 60));
        } finally {
          await served.server.stop();
        }
      });
    });

    test('a body sent a little at a time, without ever being idle, is cut '
        'when the time is up', () async {
      // The same server with a short limit: the body trickles in faster
      // than server.connection-timeout would notice, for longer than
      // server.request-timeout allows.
      await webRunner([
        'server.request-timeout=600ms',
        'server.connection-timeout=10s',
      ]).runAsync((context) async {
        final served = await _serveRoutes(context.context, {
          '/upload': (request, response) async {
            final body = await request.readBodyText();
            await response.send(200, '${body.length}');
          },
        });
        final socket = await io.Socket.connect('127.0.0.1', served.port);
        try {
          socket.write(
            'POST /upload HTTP/1.1\r\nHost: localhost\r\n'
            'Content-Length: 1000\r\nConnection: close\r\n\r\n',
          );
          final answer = StringBuffer();
          final done = socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .listen(answer.write, onError: (Object _) {})
              .asFuture<void>()
              .catchError((Object _) {});
          final watch = Stopwatch()..start();
          // A byte every 50 ms: never idle, never finished.
          while (!answer.toString().contains('\r\n\r\n') &&
              watch.elapsed < const Duration(seconds: 5)) {
            try {
              socket.write('x');
              await socket.flush();
            } on Object {
              break;
            }
            await _pause(50);
          }
          await done.timeout(const Duration(seconds: 5), onTimeout: () {});
          expect(answer.toString(), startsWith('HTTP/1.1 503'));
          expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
        } finally {
          socket.destroy();
          await served.server.stop();
        }
      });
    });
  });

  group('with server.request-timeout=0', () {
    test('a slow handler is not cut and sees no deadline', () async {
      await webRunner(['server.request-timeout=0']).runAsync((context) async {
        var deadline = true;
        final served = await _serveRoutes(context.context, {
          '/slow': (request, response) async {
            deadline = RequestDeadline.current != null;
            await _pause(300);
            await response.send(200, 'done');
          },
        });
        try {
          final reply = await Client(served.port).get('/slow');
          expect(reply.status, 200);
          expect(reply.body, 'done');
          expect(deadline, isFalse);
        } finally {
          await served.server.stop();
        }
      });
    });

    test('a handler that throws RequestDeadlineExceededException is a 503, '
        'not a 500', () async {
      await webRunner().runAsync((context) async {
        final served = await _serveRoutes(context.context, {
          '/check': (request, response) =>
              RequestDeadline.run(Duration.zero, () {
                RequestDeadline.current!.check();
              }),
        });
        try {
          final reply = await Client(served.port).get('/check');
          expect(reply.status, 503);
          expect(
            (reply.json! as Map<String, Object?>)['detail'],
            'The request did not complete in time.',
          );
        } finally {
          await served.server.stop();
        }
      });
    });
  });

  group('with server.request-timeout=300ms', () {
    // Serves [routes] under server.request-timeout=300ms and runs [body].
    Future<void> serving(
      Map<String, _Route> routes,
      Future<void> Function(_ServedDispatcher served, ApplicationContext app)
      body, {
      List<WebFilter> filters = const [],
    }) => webRunner(['server.request-timeout=300ms']).runAsync((context) async {
      final served = await _serveRoutes(
        context.context,
        routes,
        filters: filters,
      );
      try {
        await body(served, context.context);
      } finally {
        await served.server.stop();
      }
    });

    test('a fast handler is untouched, and runs under a deadline of the '
        'configured length', () async {
      Duration? budget;
      await serving(
        {
          '/fast': (request, response) async {
            budget = RequestDeadline.current?.budget;
            await response.send(200, 'quick');
          },
        },
        (served, app) async {
          final reply = await Client(served.port).get('/fast');
          expect(reply.status, 200);
          expect(reply.body, 'quick');
          expect(budget, const Duration(milliseconds: 300));
        },
      );
    });

    test('a slow handler gets a 503 problem at the deadline, with a generic '
        'detail', () async {
      await serving(
        {
          '/slow': (request, response) async {
            await _pause(3000);
            await response.send(200, 'too late');
          },
        },
        (served, app) async {
          final watch = Stopwatch()..start();
          final reply = await Client(served.port).get('/slow');
          expect(reply.status, 503);
          expect(
            watch.elapsed,
            greaterThanOrEqualTo(const Duration(milliseconds: 250)),
          );
          expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
          expect(
            reply.headers.contentType?.mimeType,
            'application/problem+json',
          );
          final problem = reply.json! as Map<String, Object?>;
          expect(problem['status'], 503);
          expect(problem['title'], 'Service Unavailable');
          expect(problem['detail'], 'The request did not complete in time.');
          expect(problem['instance'], '/slow');
          // Neither the limit nor the handler is told.
          expect(reply.body, isNot(contains('300')));
        },
      );
    });

    test('the filters run inside the budget: a slow filter is a 503', () async {
      final filter = _SlowFilter(const Duration(seconds: 2));
      var handled = false;
      await serving(
        {
          '/x': (request, response) async {
            handled = true;
            await response.send(200, 'x');
          },
        },
        (served, app) async {
          final reply = await Client(served.port).get('/x');
          expect(reply.status, 503);
          expect(filter.passed, isFalse);
          // The filter wakes up later and the handler is called (Dart
          // cannot stop either), but nothing they do reaches the client.
          await _until(() => handled);
          expect(filter.passed, isTrue);
        },
        filters: [filter],
      );
    });

    test('time used by a filter is taken from the handler', () async {
      final filter = _SlowFilter(const Duration(milliseconds: 150));
      var left = Duration.zero;
      await serving(
        {
          '/x': (request, response) async {
            left = RequestDeadline.current!.remaining;
            await response.send(200, 'x');
          },
        },
        (served, app) async {
          final reply = await Client(served.port).get('/x');
          expect(reply.status, 200);
          expect(left, lessThan(const Duration(milliseconds: 160)));
        },
        filters: [filter],
      );
    });

    test('what the handler does after the 503 is dropped: one response, no '
        'unhandled error', () async {
      var lateRuns = 0;
      await serving(
        {
          '/late': (request, response) async {
            await _pause(600);
            lateRuns++;
            response
              ..statusCode = 200
              ..headers.contentType = 'text/plain'
              ..write('late body');
            await response.close();
          },
          '/late-error': (request, response) async {
            await _pause(600);
            lateRuns++;
            throw StateError('late failure');
          },
          '/late-problem': (request, response) async {
            await _pause(600);
            lateRuns++;
            throw ResponseStatusException(HttpStatus.badRequest, 'late');
          },
          '/ok': (request, response) => response.send(200, 'ok'),
        },
        (served, app) async {
          for (final path in ['/late', '/late-error', '/late-problem']) {
            final response = await _raw(served.port, path);
            expect(response, startsWith('HTTP/1.1 503'), reason: path);
            // One response on the connection, and it is the problem.
            expect('HTTP/1.1'.allMatches(response), hasLength(1), reason: path);
            expect(response, contains('application/problem+json'));
            expect(response, isNot(contains('late body')));
            expect(response, isNot(contains('late failure')));
          }
          await _until(() => lateRuns == 3);
          await _pause(100);
          // The server is fine afterwards.
          final reply = await Client(served.port).get('/ok');
          expect(reply.status, 200);
        },
      );
    });

    test('an error at the deadline is a 503 whatever it says', () async {
      await serving(
        {
          '/boom': (request, response) async {
            // Fails the moment the deadline passes.
            await _pause(RequestDeadline.current!.remaining.inMilliseconds);
            throw _Boom();
          },
          '/check': (request, response) async {
            await _pause(RequestDeadline.current!.remaining.inMilliseconds + 5);
            RequestDeadline.current!.check();
          },
        },
        (served, app) async {
          for (final path in ['/boom', '/check']) {
            final reply = await Client(served.port).get(path);
            expect(reply.status, 503, reason: path);
            expect(
              (reply.json! as Map<String, Object?>)['detail'],
              'The request did not complete in time.',
            );
          }
        },
      );
    });

    test('an ordinary error is still its own: a 500, a 400', () async {
      await serving(
        {
          '/boom': (request, response) => throw _Boom(),
          '/bad': (request, response) =>
              throw ResponseStatusException(HttpStatus.badRequest, 'no'),
        },
        (served, app) async {
          expect((await Client(served.port).get('/boom')).status, 500);
          expect((await Client(served.port).get('/bad')).status, 400);
        },
      );
    });

    test('a response that is committed is left alone', () async {
      await serving(
        {
          '/partial': (request, response) async {
            response
              ..statusCode = 200
              ..headers.contentType = 'text/plain'
              ..write('part');
            await response.flush();
            await _pause(600);
            response.write('ial');
            await response.close();
          },
        },
        (served, app) async {
          final reply = await Client(served.port).get('/partial');
          expect(reply.status, 200);
          expect(reply.body, 'partial');
        },
      );
    });

    test('an event stream is not cut, and its code runs under no '
        'deadline', () async {
      final deadlines = <RequestDeadline?>[];
      late ResponseWriter writer;
      await serving(
        {
          '/events': (request, response) => writer.writeResult(
            Stream<String>.periodic(
              const Duration(milliseconds: 100),
              (i) => 'event-$i',
            ).take(7).map((event) {
              deadlines.add(RequestDeadline.current);
              return event;
            }),
            request,
            response,
          ),
        },
        (served, app) async {
          writer = app.getBean<DispatcherHandler>().writer;
          final reply = await Client(served.port).get('/events');
          expect(reply.status, 200);
          for (var i = 0; i < 7; i++) {
            expect(reply.body, contains('event-$i'));
          }
          expect(deadlines, hasLength(7));
          expect(deadlines.every((d) => d == null), isTrue);
        },
      );
    });

    test('an SseEmitter is not cut, and its callbacks run under no '
        'deadline', () async {
      var inTimer = true;
      late ResponseWriter writer;
      await serving(
        {
          '/emitter': (request, response) {
            final emitter = SseEmitter();
            Timer(const Duration(milliseconds: 600), () async {
              inTimer = RequestDeadline.current != null;
              await emitter.send('late event');
              emitter.complete();
            });
            return writer.writeResult(emitter, request, response);
          },
        },
        (served, app) async {
          writer = app.getBean<DispatcherHandler>().writer;
          final reply = await Client(served.port).get('/emitter');
          expect(reply.status, 200);
          expect(reply.body, contains('late event'));
          expect(inTimer, isFalse);
        },
      );
    });

    test('a WebSocket handshake is not timed', () async {
      var ran = false;
      var deadline = true;
      await serving(
        {
          '/ws': (request, response) async {
            ran = true;
            deadline = RequestDeadline.current != null;
            await _pause(500);
            await response.send(200, 'handled');
          },
        },
        (served, app) async {
          final request = MockServerHttpRequest(
            HttpMethod.get,
            '/ws',
            headers: HttpHeaders({
              HttpHeaders.connectionHeader: 'Upgrade',
              HttpHeaders.upgradeHeader: 'websocket',
            }),
          );
          final response = MockServerHttpResponse();
          await served.dispatcher.handle(request, response);
          expect(ran, isTrue);
          expect(response.statusCode, 200);
          expect(deadline, isFalse);
        },
      );
    });
  });

  group('a controller calls a slow Feign client inside a request with '
      'server.request-timeout', () {
    late IoWebServer upstream;
    late int upstreamRequests;
    late Duration upstreamDelay;

    setUp(() async {
      upstreamRequests = 0;
      upstreamDelay = const Duration(seconds: 5);
      upstream = IoWebServer(
        FunctionHttpHandler((request, response) async {
          upstreamRequests++;
          await Future<void>.delayed(upstreamDelay);
          await response.send(200, 'work done');
        }),
        const ServerProperties(port: 0, address: '127.0.0.1'),
      );
      await upstream.start();
    });

    tearDown(() => upstream.stop(timeout: Duration.zero));

    ApplicationContextRunner runner(List<String> properties) =>
        webRunner([
              'spring.feign.client.config.upstream.url=http://127.0.0.1:${upstream.port}',
              ...properties,
            ])
            .withAutoConfiguration(
              feign.springBootStarterFeignAutoConfiguration,
            )
            .withUserConfiguration(upstreamModule);

    test('the call fails fast at the request deadline: a 503, not the '
        "Feign client's read timeout", () async {
      Object? failure;
      Duration? budget;
      await runner(['server.request-timeout=500ms']).runAsync((context) async {
        final client = context.context.getBean<UpstreamClient>();
        final served = await _serveRoutes(context.context, {
          '/report': (request, response) async {
            budget = RequestDeadline.current!.budget;
            try {
              final work = await client.work();
              await response.send(200, work);
            } on Object catch (error) {
              failure = error;
              rethrow;
            }
          },
        });
        try {
          final watch = Stopwatch()..start();
          final reply = await Client(served.port).get('/report');
          // The default read timeout is 60 s; the answer came at 500 ms.
          expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
          expect(reply.status, 503);
          expect(
            (reply.json! as Map<String, Object?>)['detail'],
            'The request did not complete in time.',
          );
          expect(upstreamRequests, 1);
          // The call itself gave up (it did not wait for the server's 5 s).
          await _until(() => failure != null);
          expect(budget, const Duration(milliseconds: 500));
          expect(
            failure,
            isA<FeignCallTimeoutException>().having(
              (e) => e.enclosingDeadline,
              'enclosingDeadline',
              isTrue,
            ),
          );
        } finally {
          await served.server.stop();
        }
      });
    });

    test('a call that fits in the budget answers as usual', () async {
      upstreamDelay = const Duration(milliseconds: 50);
      await runner(['server.request-timeout=2s']).runAsync((context) async {
        final client = context.context.getBean<UpstreamClient>();
        final served = await _serveRoutes(context.context, {
          '/report': (request, response) async {
            final work = await client.work();
            await response.send(200, 'report: $work');
          },
        });
        try {
          final reply = await Client(served.port).get('/report');
          expect(reply.status, 200);
          expect(reply.body, 'report: work done');
        } finally {
          await served.server.stop();
        }
      });
    });

    test('with server.request-timeout=0 the call is limited by its own '
        'timeouts only', () async {
      upstreamDelay = const Duration(milliseconds: 100);
      await runner(['server.request-timeout=0']).runAsync((context) async {
        final client = context.context.getBean<UpstreamClient>();
        final served = await _serveRoutes(context.context, {
          '/report': (request, response) async {
            final work = await client.work();
            await response.send(200, work);
          },
        });
        try {
          expect((await Client(served.port).get('/report')).status, 200);
        } finally {
          await served.server.stop();
        }
      });
    });
  });
}

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 10)) {
      fail('timed out');
    }
    await _pause(10);
  }
}
