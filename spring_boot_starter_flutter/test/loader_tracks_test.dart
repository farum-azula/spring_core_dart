// The tracks of a loader (tracks.<name>): led by time, a stage or the
// progress (smoothed, never jumping); an application's own driver; wrong
// keys and kinds named.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

Map<String, LoaderTrack> _tracks(Map<String, String> keys) {
  final spec = SpringThemes({
    'loaders.l.kind': 'spinner',
    for (final MapEntry(:key, :value) in keys.entries)
      'loaders.l.tracks.$key': value,
  }).data('light').loaders['l']!;
  return spec.tracks;
}

LoaderValues get _tracksValues => SpringThemes({
  'loaders.l.kind': 'spinner',
}).data('light').loaders['l']!.values!;

LoaderClock _at(
  int ms, {
  int dt = 16,
  double? progress,
  SplashStage? stage,
  Duration? Function(SplashStage)? since,
}) => LoaderClock(
  elapsed: Duration(milliseconds: ms),
  dt: Duration(milliseconds: dt),
  progress: progress,
  stage: stage,
  since: since,
);

final class _Beat implements LoaderTrackDriver, LoaderTrack, LoaderTrackRun {
  const _Beat();

  @override
  String get name => 'beat';

  @override
  List<String> get keys => const ['every'];

  @override
  LoaderTrack parse(LoaderValues values) => this;

  @override
  LoaderTrackRun run() => this;

  @override
  double still(double? progress) => 0;

  @override
  double advance(LoaderClock clock) =>
      clock.elapsed.inMilliseconds % 500 < 100 ? 1 : 0;
}

final class _Reads extends ThemeLoaderWidget<Object?> {
  const _Reads(this.seen);

  final List<double> seen;

  @override
  Widget build(BuildContext context, LoaderFrame<Object?> frame) {
    seen.add(frame.track('draw'));
    return const SizedBox();
  }
}

void main() {
  tearDown(LoaderTrackDrivers.reset);

  test('time: once, looping, back and forth, after a delay', () {
    final tracks = _tracks({
      'once.duration': '1s',
      'spin.duration': '1s',
      'spin.repeat': 'loop',
      'pulse.duration': '1s',
      'pulse.repeat': 'reverse',
      'late.duration': '1s',
      'late.delay': '500ms',
    });
    double at(String name, int ms) => tracks[name]!.run().advance(_at(ms));
    expect(at('once', 500), 0.5);
    expect(at('once', 3000), 1);
    expect(at('spin', 1250), closeTo(0.25, 1e-9));
    expect(at('pulse', 1250), closeTo(0.75, 1e-9));
    expect(at('late', 400), 0);
    expect(at('late', 1000), 0.5);
  });

  test('stage: from the moment its stage is reached', () {
    final run = _tracks({
      'draw.follows': 'stage',
      'draw.from': 'splash',
      'draw.duration': '1s',
    })['draw']!.run();
    expect(run.advance(_at(100, stage: SplashStage.engine)), 0);
    // Reached 200 ms before the loader saw it.
    expect(
      run.advance(
        _at(
          1000,
          stage: SplashStage.starting,
          since: (_) => const Duration(milliseconds: 200),
        ),
      ),
      closeTo(0.2, 1e-9),
    );
    expect(
      run.advance(_at(1500, stage: SplashStage.starting)),
      closeTo(0.7, 1e-9),
    );
  });

  test('progress: smoothed, never jumping; with a curve', () {
    final run = _tracks({
      'fill.follows': 'progress',
      'fill.smoothing': '300ms',
    })['fill']!.run();
    final first = run.advance(_at(0, progress: 1));
    expect(first, greaterThan(0));
    expect(first, lessThan(0.1));
    var value = first;
    for (var t = 16; t < 3000; t += 16) {
      final next = run.advance(_at(t, progress: 1));
      expect(next - value, lessThan(0.06));
      value = next;
    }
    expect(value, 1);
    final curved = _tracks({
      'fill.follows': 'progress',
      'fill.smoothing': '0ms',
      'fill.curve': 'ease-in',
    })['fill']!.run();
    expect(curved.advance(_at(0, progress: 0.5)), Curves.easeIn.transform(0.5));
  });

  test("an application's own driver", () {
    LoaderTrackDrivers.register(const _Beat());
    final run = _tracks({
      'tick.follows': 'beat',
      'tick.every': '500ms',
    })['tick']!.run();
    expect(run.advance(_at(50)), 1);
    expect(run.advance(_at(250)), 0);
  });

  test('wrong tracks name their property', () {
    for (final (keys, problem) in [
      ({'x.follows': 'moon'}, 'what a track follows: time, stage, progress'),
      ({'x.duration': '1s', 'x.speed': '2'}, 'a key of a time track'),
      (
        {'x.follows': 'stage', 'x.duration': '1s'},
        'the stage the track starts at',
      ),
      ({'x.follows': 'time'}, 'a duration like 2s or 400ms'),
    ]) {
      expect(
        () => _tracks(keys),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('spring.flutter.theme.loaders.l.tracks.x'),
              contains(problem),
            ),
          ),
        ),
        reason: '$keys',
      );
    }
  });

  test('a frame gives the tracks by name', () {
    final frame = LoaderFrame<Object?>(
      phases: {},
      props: null,
      values: _tracksValues,
      tracks: {'spin': 0.5},
      stage: SplashStage.starting,
    );
    expect(frame.track('Spin'), 0.5);
    expect(frame.stage, SplashStage.starting);
    expect(() => frame.track('glow'), throwsStateError);
  });

  testWidgets('the tracks are there from the first frame', (tester) async {
    final seen = <double>[];
    ThemeLoaderKinds.register<Object?>('reads', widget: _Reads(seen));
    addTearDown(ThemeLoaderKinds.clear);
    final spec = SpringThemes({
      'loaders.l.kind': 'reads',
      'loaders.l.tracks.draw.duration': '1s',
    }).data('light').loaders['l']!;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ThemeLoader(spec),
      ),
    );
    expect(seen.first, 0);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 250));
    expect(seen.last, greaterThan(0));
  });
}
