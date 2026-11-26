// What followed state costs beside plain members (debug / JIT, so slower
// than a release build): a read and an assignment of a @Signal field, a
// kept @Computed value, a method of two assignments, a collection
// followed in place, and what a Spring widget's build pays for being
// followed. Not part of the tests (outside test/); run with
//   flutter test benchmark
//
// November 2026, Apple M5, nanoseconds (flush: immediate unless said): a
// plain field read 3, a @Signal field read 8, a kept @Computed 19, an
// assignment nobody reads 177 (40 through the microtask queue, whose
// schedule hears of every write). A full cycle of 10 writes, the flush and
// the effect that reads them: 1800 per flush in microtask, 1370 in frame,
// 1390 in interval. SignalBuffer.run 2900 more than the call; nothing more
// without a buffer. A debug tool shown: a read 54, a write an effect
// reads 1170. One field out of the build (no probe check) and with the
// probe hidden: a read 9 and 9, a write 181 and 183, alike within noise
// in a JIT build. A context start and close 10 ms.
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_starter_flutter_signals/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show springBootTest;

import '../test/cases/cases.dart';
import '../test/spring_gen/cases/cases.spring.dart';

class Plain {
  int balance = 0;
  List<String> titles = [];
  int get twice => balance * 2;
  void deposit(int amount) => balance += amount;
}

void main() {
  final app = springBootTest(
    SpringApplication(
      [$application],
      autoConfigurations: [
        springBootAutoConfiguration,
        springBootStarterFlutterAutoConfiguration,
        springBootStarterFlutterSignalsAutoConfiguration,
      ],
    ),
  );

  test('followed state beside plain members', () async {
    const n = 300000;
    double time(void Function() body) {
      for (var i = 0; i < 30000; i++) {
        body();
      }
      final watch = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        body();
      }
      watch.stop();
      return watch.elapsedMicroseconds * 1000 / n;
    }

    final plain = Plain();
    final inherited = app.getBean<Inherited>();
    final shapes = app.getBean<Shapes>();
    final ledger = app.getBean<Ledger>();
    final raw = signals.signal(0);
    var sink = 0;
    void say(String what, double ns) =>
        // ignore: avoid_print
        print('${what.padRight(46)} ${ns.toStringAsFixed(0).padLeft(6)} ns');

    say('plain field read', time(() => sink += plain.balance));
    say('raw signal read', time(() => sink += raw.value));
    say('@Signal field read', time(() => sink += inherited.count));
    say(
      'getter of a signal bean, not followed',
      time(() => sink += shapes.hidden),
    );
    say(
      'same read inside an effect run',
      (() {
        late double ns;
        final stop = signals.effect(() {
          ns = time(() => sink += inherited.count);
        });
        stop();
        return ns;
      })(),
    );
    say('plain getter', time(() => sink += plain.twice));
    say('@Computed read (kept)', time(() => sink += inherited.twice));
    var v = 0;
    say('plain field write', time(() => plain.balance = v++));
    say('raw signal write', time(() => raw.value = v++));
    say(
      '@Signal field write (no readers)',
      time(() => inherited.price = (v++).toDouble()),
    );
    say(
      '@Signal field write (effect reads it)',
      time(() => inherited.count = v++),
    );
    say('plain method', time(() => plain.deposit(1)));
    say(
      'bean method, two deposits (two changes), effect',
      time(() => ledger.depositTwice(1)),
    );
    shapes.titles = [for (var i = 0; i < 100; i++) '$i'];
    plain.titles = [for (var i = 0; i < 100; i++) '$i'];
    say(
      'plain list: for-in over 100',
      time(() {
        for (final t in plain.titles) {
          sink += t.length;
        }
      }),
    );
    say(
      'followed list: for-in over 100',
      time(() {
        for (final t in shapes.titles) {
          sink += t.length;
        }
      }),
    );
    say(
      'followed list: [i] over 100',
      time(() {
        final list = shapes.titles;
        for (var i = 0; i < list.length; i++) {
          sink += list[i].length;
        }
      }),
    );
    final tracking = const SignalBuildTracker().attach(() {});
    say(
      'build of a Spring widget, reads nothing',
      time(() => sink += tracking.track(() => 1)),
    );
    say(
      'build of a Spring widget, reads one field',
      time(() => sink += tracking.track(() => inherited.count)),
    );
    tracking.dispose();
    say(
      '@Computed read after a change',
      time(() {
        inherited.count = v++;
        sink += inherited.twice;
      }),
    );
    final runs = signals.signal(0);
    final stopEffect = signals.effect(() => sink += runs.value);
    say('effect re-run by a raw signal', time(() => runs.value = v++));
    stopEffect();
    // The full cycle, by flush schedule: K writes, the flush, the effect
    // that reads the field, all under the stopwatch.
    const k = 10;
    for (final flush in ['microtask', 'frame', 'interval']) {
      final mode = await SpringApplication(
        [$application],
        autoConfigurations: [
          springBootAutoConfiguration,
          springBootStarterFlutterAutoConfiguration,
          springBootStarterFlutterSignalsAutoConfiguration,
        ],
      ).runAsync(['--spring.flutter.signals.queue.flush=$flush']);
      final bean = mode.getBean<Inherited>();
      final queue = mode.getBean<SignalRuntime>().queues.primary;
      say(
        '$flush: @Signal write, no readers',
        time(() => bean.price = (v++).toDouble()),
      );
      queue.flush();
      final runsBefore = bean.seen.length;
      const cycles = 20000;
      final watch = Stopwatch()..start();
      for (var i = 0; i < cycles; i++) {
        for (var j = 0; j < k; j++) {
          bean.count = v++;
        }
        queue.flush();
      }
      watch.stop();
      final effectRuns = bean.seen.length - runsBefore;
      bean.seen.clear();
      final perCycle = watch.elapsedMicroseconds * 1000 / cycles;
      say('$flush: $k writes + flush + effect, per write', perCycle / k);
      say('$flush: per flush (effect runs $effectRuns/$cycles)', perCycle);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      mode.close();
    }
    // The debug probe, one field each: out of the build the bean is a
    // SignalBean (no probe check at all), in it a ProbedSignalBean, which
    // pays one check of a static field while no tool shows. The beans of
    // this test are probed: a debug build has the debug tools.
    final outOfBuild = SignalBean('Bench').field('n', () => 0);
    final probed = ProbedSignalBean('Bench').field('n', () => 0);
    for (var round = 0; round < 2; round++) {
      say(
        'out of the build: field read',
        time(() => sink += outOfBuild.read()! as int),
      );
      say(
        'debug hidden: field read',
        time(() => sink += probed.read()! as int),
      );
      say('out of the build: field write', time(() => outOfBuild.write(v++)));
      say('debug hidden: field write', time(() => probed.write(v++)));
    }
    // While the console's segment or the tab shows, the recorder.
    final recorder = SignalsDebugRecorder();
    final release = recorder.use();
    say(
      'debug shown: field read',
      time(() => sink += probed.read()! as int),
    );
    say('debug shown: field write', time(() => probed.write(v++)));
    say('debug shown: @Signal field read', time(() => sink += inherited.count));
    say(
      'debug shown: @Signal field write (effect reads it)',
      time(() => inherited.count = v++),
    );
    release();
    // A buffer: one runZoned per call; without one nothing more is paid
    // (the reads and writes above run with no buffer open).
    Future<void> empty() async {}
    const calls = 20000;
    final plainCalls = Stopwatch()..start();
    for (var i = 0; i < calls; i++) {
      await empty();
    }
    plainCalls.stop();
    final bufferedCalls = Stopwatch()..start();
    for (var i = 0; i < calls; i++) {
      await SignalBuffer.run(empty);
    }
    bufferedCalls.stop();
    say(
      'SignalBuffer.run, more than the call itself',
      (bufferedCalls.elapsedMicroseconds - plainCalls.elapsedMicroseconds) *
          1000 /
          calls,
    );
    final startup = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      final started = SpringApplication(
        [$application],
        autoConfigurations: [
          springBootAutoConfiguration,
          springBootStarterFlutterAutoConfiguration,
          springBootStarterFlutterSignalsAutoConfiguration,
        ],
      ).run(const ['--logging.level.root=error']);
      // What the start scheduled runs before the close.
      await Future<void>.delayed(Duration.zero);
      started.close();
    }
    startup.stop();
    say('context start and close', startup.elapsedMicroseconds * 1000 / 20);
    // ignore: avoid_print
    print(sink);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
