// The server's pool of isolates (server.isolates.*): the policy and the
// counts by themselves, then a real server on several isolates.
import 'dart:async';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'app/app.dart';

// What a pool starts in each isolate: nothing from around it.
SpringApplication _application() => SpringApplication(
  [webTestBeans],
  autoConfigurations: [
    springBootAutoConfiguration,
    springBootStarterLoggingAutoConfiguration,
    springBootStarterWebAutoConfiguration,
  ],
);

// A policy that wants a second isolate, then nothing more.
final class _GrowOnce implements IsolateScalingPolicy {
  @override
  int? decide(IsolateScalingState state, Duration now) =>
      state.count < 2 ? 2 : null;
}

SpringApplication _growing() => SpringApplication(
  [
    webTestBeans,
    BeanModule('policy', [
      BeanDefinition<IsolateScalingPolicy>(
        name: 'growOnce',
        create: (_) => _GrowOnce(),
      ),
    ]),
  ],
  autoConfigurations: [
    springBootAutoConfiguration,
    springBootStarterLoggingAutoConfiguration,
    springBootStarterWebAutoConfiguration,
  ],
);

Future<ConfigurableApplicationContext> _start(List<String> properties) async {
  final context = _application().run([
    '--server.port=0',
    '--server.address=127.0.0.1',
    '--spring.main.banner-mode=off',
    '--logging.level.root=warn',
    for (final property in properties) '--$property',
  ], hotReload: _application);
  addTearDown(() async {
    if (context.isActive) {
      await context.closeAsync();
    }
  });
  await context.getBean<WebServerStartStopLifecycle>().started;
  if (context.containsBean('serverIsolatePool')) {
    await context.getBean<ServerIsolatePool>().awaitStartup();
  }
  return context;
}

// One request on a connection of its own, so the next may reach another
// isolate.
Future<String> _get(ConfigurableApplicationContext context, String path) =>
    _fetch(_port(context), path);

int _port(ConfigurableApplicationContext context) =>
    context.getBean<WebServerStartStopLifecycle>().webServer!.port;

Future<String> _fetch(int port, String path) async {
  final client = io.HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    request.persistentConnection = false;
    final response = await request.close();
    return await response.transform(const io.SystemEncoding().decoder).join();
  } finally {
    client.close(force: true);
  }
}

// The isolates that answer, asked until [expected] have all answered (a
// connection goes to whichever isolate takes it first, so some need more
// tries than others) or [requests] were sent. They are sent from an
// isolate of their own: sent from this one, it would be busy sending
// while the others are free, and they would take every connection.
Future<Set<String>> _names(
  ConfigurableApplicationContext context, {
  Set<String> expected = const {},
  int requests = 600,
}) {
  final port = _port(context);
  final least = expected.isEmpty ? 10 : 40;
  return Isolate.run(() async {
    final names = <String>{};
    for (var i = 0; i < requests; i++) {
      names.add(await _fetch(port, '/isolate/name'));
      if (i >= least && names.containsAll(expected)) {
        break;
      }
    }
    return names;
  });
}

const _two = {'main', 'isolate-1'};
const _three = {'main', 'isolate-1', 'isolate-2'};

IsolateScalingState _state({
  int count = 1,
  int min = 1,
  int max = 8,
  int lagMs = 0,
  int active = 0,
  double rps = 0,
}) => IsolateScalingState(
  count: count,
  min: min,
  max: max,
  lag: Duration(milliseconds: lagMs),
  maxLag: Duration(milliseconds: lagMs),
  activeRequests: active,
  requestsPerSecond: rps,
);

void main() {
  group('server.isolates.* worked out', () {
    ServerIsolatesSettings settings({
      String count = '1',
      IsolateScaling scaling = IsolateScaling.manual,
      int min = 1,
      int? max,
    }) => ServerIsolatesSettings()
      ..count = count
      ..scaling = scaling
      ..min = min
      ..max = max;

    test('one isolate, manual, no max: no pool', () {
      expect(settings().pooled, isFalse);
      expect(settings().countFor(8), 1);
    });

    test('a count above one, auto, or a max above one: a pool', () {
      expect(settings(count: '3').pooled, isTrue);
      expect(settings(count: 'auto').pooled, isTrue);
      expect(settings(scaling: IsolateScaling.auto).pooled, isTrue);
      expect(settings(max: 4).pooled, isTrue);
      expect(settings(max: 1).pooled, isFalse);
    });

    test('auto is one per processor; nonsense is one', () {
      expect(settings(count: 'auto').countFor(8), 8);
      expect(settings(count: ' AUTO ').countFor(0), 1);
      expect(settings(count: '0').countFor(8), 1);
      expect(settings(count: 'many').countFor(8), 1);
    });

    test('the most: max, else the processors, never under the count', () {
      expect(settings().maxFor(8), 8);
      expect(settings(max: 3).maxFor(8), 3);
      expect(settings(count: '6', max: 3).maxFor(8), 6);
      expect(settings(count: '12').maxFor(8), 12);
      expect(settings(min: 0).least, 1);
    });
  });

  group('LagScalingPolicy', () {
    // Late at 5 ms for 5 s (the defaults); free for a minute.
    LagScalingPolicy policy() =>
        LagScalingPolicy(scaleDownAfter: const Duration(seconds: 60));
    Duration at(int seconds) => Duration(seconds: seconds);

    test('lag must last before isolates are added, half as many again', () {
      final p = policy();
      expect(p.decide(_state(count: 2, lagMs: 30, rps: 4000), at(0)), isNull);
      expect(p.decide(_state(count: 2, lagMs: 30, rps: 4000), at(4)), isNull);
      expect(p.decide(_state(count: 2, lagMs: 30, rps: 4000), at(5)), 3);
      expect(p.capacity, 2000);
      // The steps: 1 → 2 → 3 → 5 → 8.
      expect(policy().decide(_state(lagMs: 30), at(0)), isNull);
      for (final (count, next) in [(1, 2), (2, 3), (3, 5), (5, 8)]) {
        final p = policy()..decide(_state(count: count, lagMs: 30), at(0));
        expect(p.decide(_state(count: count, lagMs: 30), at(5)), next);
      }
    });

    test('a pause in the lag starts the wait again', () {
      final p = policy()
        ..decide(_state(lagMs: 30), at(0))
        ..decide(_state(lagMs: 4), at(3));
      expect(p.decide(_state(lagMs: 30), at(5)), isNull);
      expect(p.decide(_state(lagMs: 30), at(10)), 2);
    });

    test('free for long enough: one isolate less', () {
      final p = policy();
      expect(p.decide(_state(count: 3), at(0)), isNull);
      expect(p.decide(_state(count: 3), at(59)), isNull);
      expect(p.decide(_state(count: 3), at(60)), 2);
    });

    test('not under the minimum, not while requests fill the isolates', () {
      final p = policy();
      expect(p.decide(_state(count: 2, min: 2), at(0)), isNull);
      expect(p.decide(_state(count: 2, min: 2), at(600)), isNull);
      // As many in flight as isolates: they are in use.
      expect(p.decide(_state(count: 2, active: 2), at(0)), isNull);
      expect(p.decide(_state(count: 2, active: 2), at(600)), isNull);
    });

    test('with a known capacity, the requests must fit in one less', () {
      final p = policy()
        ..decide(_state(count: 2, lagMs: 30, rps: 4000), at(0))
        ..decide(_state(count: 2, lagMs: 30, rps: 4000), at(5));
      expect(p.capacity, 2000);
      // Three isolates, 3000 rps: two would be at 75 %: stay.
      expect(p.decide(_state(count: 3, rps: 3000), at(10)), isNull);
      expect(p.decide(_state(count: 3, rps: 3000), at(100)), isNull);
      // 2000 rps: two would be at 50 %: one leaves.
      expect(p.decide(_state(count: 3, rps: 2000), at(110)), isNull);
      expect(p.decide(_state(count: 3, rps: 2000), at(170)), 2);
    });

    test('a little lag is neither', () {
      final p = policy();
      // A quarter of the threshold or more: not free.
      expect(p.decide(_state(count: 3, lagMs: 3), at(0)), isNull);
      expect(p.decide(_state(count: 3, lagMs: 3), at(600)), isNull);
    });
  });

  group('a server on several isolates', () {
    test('one isolate by default: no pool, the port not shared', () async {
      final context = await _start(const []);
      expect(context.containsBean('serverIsolatePool'), isFalse);
      expect(context.containsBean('serverIsolateWorker'), isFalse);
      expect(await _names(context), {'main'});
      expect(context.getBean<IsolateInfo>().primary, isTrue);
    });

    test('count: every isolate answers on the one port', () async {
      final context = await _start(const ['server.isolates.count=3']);
      final scaler = context.getBean<IsolateScaler>();
      expect(scaler.count, 3);
      expect(await _names(context, expected: _three), _three);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('scaling by hand, down and up; the first is never removed', () async {
      final context = await _start(const [
        'server.isolates.count=2',
        'server.isolates.max=3',
      ]);
      final scaler = context.getBean<IsolateScaler>();
      expect(context.containsBean('isolateScaler'), isTrue);
      expect((scaler.min, scaler.max), (1, 3));
      expect(await scaler.scaleTo(3), 3);
      expect(await _names(context, expected: _three), _three);
      expect(await scaler.scaleBy(-1), 2);
      expect(await _names(context, expected: _two), _two);
      // Kept between min and max.
      expect(await scaler.scaleTo(0), 1);
      expect(await _names(context), {'main'});
      expect(await scaler.scaleTo(10), 3);
      expect(await _names(context, expected: _three), _three);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('an isolate that leaves finishes its requests first', () async {
      final context = await _start(const ['server.isolates.count=2']);
      final scaler = context.getBean<IsolateScaler>();
      // Find a request the other isolate answers, slowly.
      Future<String>? slow;
      for (var i = 0; i < 40 && slow == null; i++) {
        final answer = _get(context, '/isolate/slow?ms=600');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final load = context.getBean<WebServerStartStopLifecycle>().webServer;
        if ((load! as WebServerActivity).activeRequests == 0) {
          slow = answer;
        } else {
          await answer;
        }
      }
      expect(slow, isNotNull, reason: 'no request reached isolate-1');
      expect(await scaler.scaleTo(1), 1);
      expect(await slow, 'isolate-1');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the task manager has a row per isolate', () async {
      final context = await _start(const ['server.isolates.count=2']);
      final loads = context.getBean<IsolateLoads>();
      final port = _port(context);
      await Isolate.run(() async {
        for (var i = 0; i < 10; i++) {
          await _fetch(port, '/isolate/name');
        }
      });
      await context.getBean<IsolateReports>().refresh();
      final rows = {for (final load in loads.all()) load.name: load};
      expect(rows.keys, containsAll(['main', 'isolate-1']));
      expect(rows['main']!.kind, 'main');
      expect(rows['isolate-1']!.kind, 'server');
      expect(rows['isolate-1']!.active, 0);
      final requests =
          (rows['main']!.details['requests']! as int) +
          (rows['isolate-1']!.details['requests']! as int);
      expect(requests, 10);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('an isolate that ends by itself is started again', () async {
      final context = await _start(const ['server.isolates.count=2']);
      final scaler = context.getBean<IsolateScaler>();
      // Until the request reaches the other isolate, which ends.
      final port = _port(context);
      final ended = await Isolate.run(() async {
        for (var i = 0; i < 600; i++) {
          try {
            // An isolate that ends leaves its connections open until the
            // VM collects it: no answer is how it shows.
            await _fetch(
              port,
              '/isolate/exit',
            ).timeout(const Duration(seconds: 2));
          } on Object {
            return true; // the isolate ended before it answered
          }
        }
        return false;
      });
      expect(ended, isTrue, reason: 'no request reached isolate-1');
      for (var i = 0; i < 300 && scaler.count < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(scaler.count, 2);
      expect(await _names(context, expected: _two), _two);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('closing the context stops every isolate', () async {
      final context = await _start(const ['server.isolates.count=3']);
      final scaler = context.getBean<IsolateScaler>();
      final port = _port(context);
      await context.closeAsync();
      expect(scaler.count, 1);
      // Nobody listens any more.
      await expectLater(
        io.Socket.connect('127.0.0.1', port),
        throwsA(isA<io.SocketException>()),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('without what returns the application, none can be added', () async {
      final context = _application().run([
        '--server.port=0',
        '--server.address=127.0.0.1',
        '--spring.main.banner-mode=off',
        '--logging.level.root=off',
        '--server.isolates.max=2',
      ]);
      addTearDown(context.closeAsync);
      await context.getBean<WebServerStartStopLifecycle>().started;
      final scaler = context.getBean<IsolateScaler>();
      await expectLater(
        scaler.scaleTo(2),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('runApplication(args)'),
          ),
        ),
      );
      expect(scaler.count, 1);
    });

    test(
      'scaling and asking the first isolate work in every isolate',
      () async {
        final context = await _start(const [
          'server.isolates.count=2',
          'server.isolates.max=3',
        ]);
        final port = _port(context);
        // What an isolate other than the first answers to [path].
        Future<String?> fromAnother(String path) => Isolate.run(() async {
          for (var i = 0; i < 600; i++) {
            final answer = await _fetch(port, path);
            if (!answer.startsWith('main')) {
              return answer;
            }
          }
          return null;
        });

        // Every isolate knows the pool.
        expect(await _fetch(port, '/isolate/pool'), endsWith(' 2 1 3'));
        expect(await fromAnother('/isolate/pool'), 'isolate-1 2 1 3');
        // The whole picture, asked for in another isolate.
        expect(
          await fromAnother('/isolate/loads'),
          'isolate-1: main,isolate-1',
        );
        expect(
          await fromAnother('/isolate/ask-unknown'),
          'isolate-1: PrimaryIsolateException',
        );
        // A step asked for in another isolate is done by the pool.
        expect(await fromAnother('/isolate/scale?to=3'), endsWith(' 3'));
        expect(context.getBean<IsolateScaler>().count, 3);
        expect(await _names(context, expected: _three), _three);
        expect(await fromAnother('/isolate/pool'), endsWith(' 3 1 3'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('one warning names what each isolate keeps for itself', () async {
      final warnings = <String>[];
      final stop = SpringLog.listen((record) {
        if (record.loggerName == 'spring.web.isolates' &&
            record.level == SpringLogLevel.warning) {
          warnings.add(record.message);
        }
      });
      addTearDown(stop);
      final context = await _start(const [
        'server.isolates.count=2',
        'server.isolates.max=3',
      ]);
      expect(warnings, hasLength(1));
      // The session repository is declared as a repository: it is found
      // by what it is.
      expect(warnings.single, contains('Each isolate keeps its own sessions'));
      expect(warnings.single, contains('a request may reach any isolate'));
      await context.getBean<IsolateScaler>().scaleTo(3);
      expect(warnings, hasLength(1), reason: 'said once');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('scaling: auto follows the policy bean', () async {
      final context = _growing().run([
        '--server.port=0',
        '--server.address=127.0.0.1',
        '--spring.main.banner-mode=off',
        '--logging.level.root=warn',
        '--server.isolates.scaling=auto',
        '--server.isolates.max=2',
        '--server.isolates.cooldown=0s',
      ], hotReload: _growing);
      addTearDown(context.closeAsync);
      await context.getBean<WebServerStartStopLifecycle>().started;
      final scaler = context.getBean<IsolateScaler>();
      expect(scaler.count, 1);
      // The policy looks every two seconds, once the lag is measured.
      for (var i = 0; i < 200 && scaler.count < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(scaler.count, 2);
      expect(await _names(context, expected: _two), _two);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'a count that cannot be reached: said, the first serves alone',
      () async {
        final errors = <SpringLogRecord>[];
        final stop = SpringLog.listen((record) {
          if (record.loggerName == 'spring.web.isolates' &&
              record.level == SpringLogLevel.error) {
            errors.add(record);
          }
        });
        addTearDown(stop);
        // Run without what returns the application: no isolate can be made.
        final context = _application().run([
          '--server.port=0',
          '--server.address=127.0.0.1',
          '--spring.main.banner-mode=off',
          '--logging.level.root=error',
          '--server.isolates.count=3',
        ]);
        addTearDown(context.closeAsync);
        await context.getBean<WebServerStartStopLifecycle>().started;
        await context.getBean<ServerIsolatePool>().awaitStartup();
        expect(errors.single.message, 'The pool of isolates did not start');
        expect('${errors.single.error}', contains('runApplication(args)'));
        expect(context.getBean<IsolateScaler>().count, 1);
        expect(await _names(context), {'main'});
      },
    );

    test('@ConditionalOnPrimaryIsolate and IsolateInfo in each', () async {
      final context = await _start(const ['server.isolates.count=2']);
      expect(context.getBean<IsolateInfo>().name, 'main');
      expect(
        const ConditionalOnPrimaryIsolate().toString(),
        '@ConditionalOnPrimaryIsolate',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
