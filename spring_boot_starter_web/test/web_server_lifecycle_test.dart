import 'dart:async';

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

// The start/stop lifecycle of the web server with a server that does
// nothing but record and answer.

class _FakeServer implements WebServer {
  _FakeServer(this.onStart, {this.stopFails = false});

  final Future<void> Function() onStart;
  final bool stopFails;
  int stops = 0;

  @override
  int get port => 4321;

  @override
  Future<void> start() => onStart();

  @override
  Future<void> stop({Duration? timeout}) async {
    stops++;
    if (stopFails) throw StateError('socket stuck');
  }
}

class _FakeFactory implements WebServerFactory {
  _FakeFactory(this.make);

  final _FakeServer Function() make;
  final servers = <_FakeServer>[];

  @override
  WebServer getWebServer(HttpHandler handler) {
    final server = make();
    servers.add(server);
    return server;
  }
}

void main() {
  final handler = FunctionHttpHandler((request, response) async {});

  StandardEnvironment environment() =>
      StandardEnvironment(systemEnvironment: {});

  WebServerStartStopLifecycle lifecycle(
    _FakeFactory factory, {
    StandardEnvironment? env,
    WebMainSettings? main,
    WebTestSettings? test,
  }) => WebServerStartStopLifecycle(
    factory,
    handler,
    env ?? environment(),
    main: main,
    test: test,
  );

  _FakeFactory working() => _FakeFactory(() => _FakeServer(() async {}));

  test('starts the server, records its port and stops it', () async {
    final env = environment();
    final factory = working();
    final lifecycle0 = lifecycle(factory, env: env);
    expect(lifecycle0.isRunning, isFalse);
    lifecycle0.start();
    expect(lifecycle0.isRunning, isTrue);
    final server = await lifecycle0.started;
    expect(server?.port, 4321);
    expect(env.getProperty('local.server.port'), '4321');
    var stopped = false;
    lifecycle0.stopWithCallback(() => stopped = true);
    await pumpEventQueue();
    expect(stopped, isTrue);
    expect(factory.servers.single.stops, 1);
    expect(lifecycle0.isRunning, isFalse);
    expect(lifecycle0.webServer, isNull);
  });

  test('a second start while running does nothing', () async {
    final factory = working();
    final lifecycle0 = lifecycle(factory)..start();
    await lifecycle0.started;
    lifecycle0.start();
    expect(factory.servers, hasLength(1));
  });

  test(
    'the local port keeps what the server.ports source already has',
    () async {
      final env = environment()
        ..propertySources.addFirst(
          const MapPropertySource('server.ports', {
            'local.management.port': '9',
          }),
        );
      final lifecycle0 = lifecycle(working(), env: env)..start();
      await lifecycle0.started;
      expect(env.getProperty('local.server.port'), '4321');
      expect(env.getProperty('local.management.port'), '9');
    },
  );

  test('can start again after a stop with a fresh server', () async {
    final factory = working();
    final lifecycle0 = lifecycle(factory)..start();
    await lifecycle0.started;
    lifecycle0.stop();
    await pumpEventQueue();
    lifecycle0.start();
    await lifecycle0.started;
    expect(factory.servers, hasLength(2));
  });

  group('is disabled', () {
    test('for spring.main.web-application-type=none', () async {
      final factory = working();
      final lifecycle0 = lifecycle(
        factory,
        main: WebMainSettings()..webApplicationType = ' None ',
      )..start();
      expect(lifecycle0.isEnabled, isFalse);
      expect(await lifecycle0.started, isNull);
      expect(factory.servers, isEmpty);
      // Stopping what never ran still calls back.
      var called = false;
      lifecycle0.stopWithCallback(() => called = true);
      expect(called, isTrue);
    });

    test('for the test web environments without a server', () {
      bool enabled(String? web) => lifecycle(
        working(),
        test: WebTestSettings()..webEnvironment = web,
      ).isEnabled;
      expect(enabled(null), isTrue);
      expect(enabled('random-port'), isTrue);
      expect(enabled('defined-port'), isTrue);
      expect(enabled('mock'), isFalse);
      expect(enabled('none'), isFalse);
    });
  });

  test('a stop while the socket is opening leaves no running server', () async {
    final opening = Completer<void>();
    final factory = _FakeFactory(() => _FakeServer(() => opening.future));
    final lifecycle0 = lifecycle(factory)
      ..start()
      ..stop();
    opening.complete();
    expect(await lifecycle0.started, isNull);
    expect(lifecycle0.isRunning, isFalse);
  });

  group('a failed start', () {
    _FakeFactory failing(Object error) =>
        _FakeFactory(() => _FakeServer(() => Future<void>.error(error)));

    test('completes started with the error and stops running', () async {
      final lifecycle0 = lifecycle(failing(PortInUseException(80)))..start();
      await expectLater(
        lifecycle0.started,
        throwsA(isA<PortInUseException>()),
      );
      expect(lifecycle0.isRunning, isFalse);
      expect(lifecycle0.webServer, isNull);
    });

    test(
      'is logged with the port analysis, any other with its error',
      () async {
        final records = <SpringLogRecord>[];
        final cancel = SpringLog.listen(records.add);
        addTearDown(cancel);
        var lifecycle0 = lifecycle(failing(PortInUseException(80)))..start();
        await lifecycle0.started.then<void>((_) {}, onError: (_) {});
        lifecycle0 = lifecycle(failing(StateError('boom')))..start();
        await lifecycle0.started.then<void>((_) {}, onError: (_) {});
        final errors = [
          for (final record in records)
            if (record.level == SpringLogLevel.error) record,
        ];
        expect(errors, hasLength(2));
        expect(errors.first.message, contains('Port 80 was already in use'));
        expect(errors.last.message, 'Web server failed to start');
        expect(errors.last.error, isA<StateError>());
      },
    );

    test('is left to SpringApplication once awaitStartup was called', () async {
      final records = <SpringLogRecord>[];
      final cancel = SpringLog.listen(records.add);
      addTearDown(cancel);
      final lifecycle0 = lifecycle(failing(StateError('claimed')));
      final startup = lifecycle0.awaitStartup();
      lifecycle0.start();
      await expectLater(startup, throwsA(isA<StateError>()));
      expect(
        records.where((r) => r.level == SpringLogLevel.error),
        isEmpty,
      );
    });
  });

  test('a server that fails to stop is logged and still calls back', () async {
    final records = <SpringLogRecord>[];
    final cancel = SpringLog.listen(records.add);
    addTearDown(cancel);
    final lifecycle0 = lifecycle(
      _FakeFactory(() => _FakeServer(() async {}, stopFails: true)),
    )..start();
    await lifecycle0.started;
    final called = Completer<void>();
    lifecycle0.stopWithCallback(called.complete);
    await called.future;
    expect(
      records.any(
        (r) =>
            r.level == SpringLogLevel.warning &&
            r.message == 'Web server failed to stop',
      ),
      isTrue,
    );
  });

  test('starts early and stops late among the lifecycle beans', () {
    expect(
      lifecycle(working()).phase,
      lessThan(SmartLifecycle.defaultPhase),
    );
  });
}
