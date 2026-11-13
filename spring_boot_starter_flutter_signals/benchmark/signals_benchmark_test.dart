// What followed state costs beside plain members (debug / JIT, so slower
// than a release build): a read and an assignment of a @Signal field, a
// kept @Computed value, a method that is one change, a collection
// followed in place, and what a Spring widget's build pays for being
// followed. Not part of the tests (outside test/); run with
//   flutter test benchmark
//
// November 2026, Apple M5, nanoseconds: a plain field read 3, a @Signal
// field read 45, a kept @Computed 53, an assignment nobody reads 68, a
// followed list 4 an element in a for-in and 9 by index, the build of a
// Spring widget 230 more than without the starter.
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

  test('followed state beside plain members', () {
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
    say('bean method (one change, effect)', time(() => ledger.depositTwice(1)));
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
    // ignore: avoid_print
    print(sink);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
