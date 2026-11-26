// The debug tools of followed state: the debug console's segment, the
// recorder behind it and the Signals tab (writes and tells, ticks per
// frame, the tree and its lamps, timings), the activity log, and their
// build switches; no console command of the starter.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';

/// A clock a test moves by hand.
final class _Clock {
  Duration now = Duration.zero;
  Duration call() => now;
}

void main() {
  late _Clock clock;
  late SignalsDebugRecorder recorder;

  setUp(() {
    clock = _Clock();
    recorder = SignalsDebugRecorder(
      readWindow: const Duration(seconds: 5),
      clock: clock.call,
    );
  });

  test('nothing is collected until a tool shows, and after it hides', () {
    expect(SignalProbes.current, isNull);
    final release = recorder.use();
    expect(SignalProbes.current, same(recorder));
    release();
    expect(SignalProbes.current, isNull);
    final member = ProbedValueMember('Basket.count', 0);
    addTearDown(member.dispose);
    member.write(1);
    expect(recorder.writesOf(member), 0);
  });

  testWidgets("the console's segment collects only while the console "
      'shows: ticks, flushes and effects of the last frame', (tester) async {
    final segment = SignalsSegment(recorder);
    expect(SignalProbes.current, isNull);
    var changes = 0;
    final stop = segment.start(() => changes++);
    expect(SignalProbes.current, same(recorder));
    final a = ProbedValueMember('Basket.items', 0);
    addTearDown(a.dispose);
    a
      ..write(1)
      ..write(2);
    recorder.frameEnded();
    await tester.pump(const Duration(milliseconds: 300));
    expect(changes, 1);
    final value = segment.read();
    expect(value.toString(), 'signals 2 ticks · 0 flushes · 0 effects');
    expect(
      [for (final part in value.parts) part.tone],
      [
        DebugConsoleTone.number,
        DebugConsoleTone.muted,
        DebugConsoleTone.muted,
      ],
    );
    stop();
    expect(SignalProbes.current, isNull);
  });

  test('writes and tells of a field while collecting', () {
    final release = recorder.use();
    addTearDown(release);
    final a = ProbedValueMember('Basket.a', 0);
    addTearDown(a.dispose);
    for (var i = 1; i <= 5; i++) {
      a.write(i);
    }
    expect(recorder.writesOf(a), 5);
    expect(recorder.tellsOf(a), 5);
  });

  group('nothing of what ended is kept', () {
    // A bean's field and an effect that reads it, heard by the recorder.
    (SignalBean, ValueMember, EffectFollower) watched() {
      final bean = ProbedSignalBean('Basket');
      final count = bean.field('count', () => 0);
      final effect = EffectFollower(() {}, name: 'Basket.save');
      bean.addEffect(effect.stop);
      effect.track(count.read);
      count.write(1);
      return (bean, count, effect);
    }

    test('the members of a closed bean and its effects: forgotten by '
        'pruneEnded', () {
      final release = recorder.use();
      addTearDown(release);
      final (bean, count, effect) = watched();
      expect(recorder.writesOf(count), 1);
      expect(recorder.readers.keys, contains(effect));

      bean.close();
      recorder.pruneEnded();

      expect(recorder.writesOf(count), 0);
      expect(recorder.tellsOf(count), 0);
      expect(recorder.readers, isEmpty);
      expect(recorder.timingOf(effect), isNull);
    });

    test("the console's segment forgets them as it samples", () {
      final segment = SignalsSegment(recorder);
      final stop = segment.start(() {});
      addTearDown(stop);
      final (bean, count, _) = watched();
      bean.close();

      segment.read();

      expect(recorder.writesOf(count), 0);
      expect(recorder.readers, isEmpty);
    });

    test('the last tool that hides forgets everything', () {
      final release = recorder.use();
      final (_, count, effect) = watched();
      recorder.frameEnded();
      release();

      final again = recorder.use();
      addTearDown(again);
      expect(recorder.writesOf(count), 0);
      expect(recorder.readers, isEmpty);
      expect(recorder.timingOf(effect), isNull);
      expect(recorder.frames, isEmpty);
    });
  });

  test('ticks, flushes and effect runs per frame', () {
    final release = recorder.use();
    addTearDown(release);
    final a = ProbedValueMember('Basket.a', 0);
    addTearDown(a.dispose);
    a
      ..write(1)
      ..write(2)
      ..write(3);
    recorder.ran(
      EffectFollower(() {}, name: 'Basket.save'),
      const Duration(microseconds: 40),
      null,
    );
    recorder.frameEnded();
    expect(recorder.lastFrame.ticks, 3);
    expect(recorder.lastFrame.effects, 1);
    a.write(4);
    recorder.frameEnded();
    expect(recorder.lastFrame.ticks, 1);
    expect(recorder.lastFrame.effects, 0);
  });

  test('reads over the read window', () {
    final release = recorder.use();
    addTearDown(release);
    final a = ProbedValueMember('Basket.a', 0);
    addTearDown(a.dispose);
    for (var i = 0; i < 4; i++) {
      a.read();
    }
    expect(recorder.readsOf(a), 4);
    clock.now = const Duration(seconds: 6);
    expect(recorder.readsOf(a), 0);
  });

  test('the tree: a computed value under the field it read, its lamp lit '
      'when it ran and dark after the fade; its timing', () {
    final release = recorder.use();
    addTearDown(release);
    final count = ProbedValueMember('Basket.count', 2);
    final twice = ProbedComputedMember(
      'Basket.twice',
      () => (count.read()! as int) * 2,
    );
    addTearDown(() {
      twice.dispose();
      count.dispose();
    });
    expect(twice.read(), 4);
    expect(recorder.readBy(twice), {count});
    expect(recorder.lampOf(twice), 1);
    clock.now = const Duration(milliseconds: 500);
    expect(recorder.lampOf(twice), closeTo(0.5, 0.01));
    clock.now = const Duration(seconds: 2);
    expect(recorder.lampOf(twice), 0);
    expect(recorder.timingOf(twice)!.count, 1);
    count.write(3);
    expect(recorder.lampOf(count), 1);
    expect(twice.read(), 6);
    expect(recorder.timingOf(twice)!.count, 2);
  });

  test('the activity log: names, times, failures; never a value', () {
    final lines = <String>[];
    SpringLog.setLevel(
      'spring.flutter.signals.activity',
      SpringLogLevel.debug,
    );
    final stop = SpringLog.listen((record) => lines.add(record.message));
    final log = SignalsDebugLog()..start();
    addTearDown(() {
      log.stop();
      stop();
      SpringLog.setLevel('spring.flutter.signals.activity', null);
    });
    final token = ProbedValueMember('Session.token', 'eyJ.secret');
    addTearDown(token.dispose);
    token.write('eyJ.other');
    log.ran(
      EffectFollower(() {}, name: 'Basket.save'),
      const Duration(microseconds: 12),
      StateError('x'),
    );
    expect(lines, contains('Session.token written'));
    expect(lines, contains('Session.token told its readers'));
    expect(
      lines,
      contains(contains('effect Basket.save failed with StateError')),
    );
    expect(lines.join('\n'), isNot(contains('eyJ')));
  });

  test('every debug module is behind its own build key (false: no code), '
      'within its parents: the panel for the tab, the console for the '
      'segment (when `segments` names it)', () {
    final source = File(
      'lib/spring_auto_configuration.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    expect(
      source,
      contains(
        "AutoConfigurationBuild('spring.flutter.signals.debug.enabled',"
        "parents:[AutoConfigurationBuild('spring.flutter.debug.enabled')],)",
      ),
    );
    const console =
        "parents:[AutoConfigurationBuild('spring.flutter.debug.console.enabled',"
        'whenMissing:BuildInclusion.never,),],)';
    expect(
      source,
      contains(
        "AutoConfigurationBuild.named('spring.flutter.debug.console.segments',"
        "'signals',whenMissing:BuildInclusion.never,$console",
      ),
    );
    expect(source, isNot(contains('console.input')));
    expect(source, isNot(contains('ConsoleCommand')));
    final generated = File(
      'example/spring_gen/example.spring.debug.dart',
    ).readAsStringSync();
    expect(
      generated,
      contains('springBootStarterFlutterSignalsDebugAutoConfiguration'),
    );
    // The console is built only when asked for.
    expect(
      generated,
      isNot(
        contains(
          'springBootStarterFlutterSignalsDebugConsoleAutoConfiguration',
        ),
      ),
    );
  });
}
