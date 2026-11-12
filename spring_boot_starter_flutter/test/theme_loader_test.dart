// Loaders of the theme: parsing and its errors, the built-in kinds, kinds
// of the app's own (painter, widget), phases, progress, reduced motion.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

ThemeLoaderSpec _loader(Map<String, String> props, [String name = 'a']) =>
    SpringThemes(props).data('light').loaders[name]!;

Matcher _fails(Pattern text) => throwsA(
  isA<ThemePropertyException>().having(
    (e) => e.toString(),
    'message',
    contains(text),
  ),
);

class _Props {
  _Props(LoaderValues values) : width = values.number('door.width');
  final double width;
}

class _Doors extends ThemeLoaderPainter<_Props> {
  final frames = <LoaderFrame<_Props>>[];

  @override
  void paint(Canvas canvas, Size size, LoaderFrame<_Props> frame) =>
      frames.add(frame);
}

class _Card extends ThemeLoaderWidget<LoaderValues> {
  @override
  Widget build(BuildContext context, LoaderFrame<LoaderValues> frame) => Text(
    'phase ${frame.phase('go').toStringAsFixed(1)}',
    textDirection: TextDirection.ltr,
  );
}

const _phases = {
  'loaders.doors.kind': 'doors',
  'loaders.doors.door.width': '12',
  'loaders.doors.phases.close.duration': '100ms',
  'loaders.doors.phases.fill.progress': 'true',
  'loaders.doors.phases.open.duration': '100ms',
};

Widget _host(Widget child, {bool reduce = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduce),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

void main() {
  tearDown(ThemeLoaderKinds.clear);

  group('parsing', () {
    test('built-in kinds read their keys', () {
      final spec = _loader({
        'loaders.a.kind': 'dots',
        'loaders.a.color': '#FF0000',
        'loaders.a.size': '10',
        'loaders.a.count': '4',
        'loaders.a.animation.duration': '900ms',
        'loaders.a.animation.repeat': 'loop',
      });
      expect(spec.kind, 'dots');
      expect(spec.look!.color, const Color(0xFFFF0000));
      expect(spec.look!.count, 4);
      expect(spec.animation!.duration, const Duration(milliseconds: 900));
      expect(spec.phases.keys, ['main']);
    });

    test('the skeleton reads shimmer; the bar a track object', () {
      final skeleton = _loader({
        'loaders.a.kind': 'skeleton',
        'loaders.a.base': '#111111',
        'loaders.a.shimmer.duration': '1.5s',
        'loaders.a.shimmer.angle': '30',
      });
      expect(
        skeleton.look!.shimmer!.duration,
        const Duration(milliseconds: 1500),
      );
      expect(skeleton.look!.angle, 30);
      final bar = _loader({
        'loaders.a.kind': 'bar',
        'loaders.a.track.color': '#FF0000',
        'loaders.a.track.alpha': '20%',
      });
      expect(bar.look!.track!.a, closeTo(0.2, 0.01));
    });

    test('defaults when nothing is given', () {
      final spec = _loader({'loaders.a.kind': 'spinner'});
      expect(spec.animation!.repeat, AnimationRepeat.loop);
      expect(spec.look!.color, isNull);
    });

    test('unknown kind: names the kinds, with a suggestion', () {
      expect(
        () => _loader({'loaders.a.kind': 'spiner'}),
        _fails('did you mean'),
      );
      expect(
        () => _loader({'loaders.a.kind': 'spiner'}),
        _fails('spinner, dots, pulse, bar, skeleton'),
      );
    });

    test('a loader without kind', () {
      expect(() => _loader({'loaders.a.size': '3'}), _fails('every loader'));
    });

    test('unknown key, with a suggestion', () {
      expect(
        () => _loader({'loaders.a.kind': 'spinner', 'loaders.a.colour': 'red'}),
        _fails('color'),
      );
      expect(
        () => _loader({'loaders.a.kind': 'spinner', 'loaders.a.count': '3'}),
        _fails('loaders.a.count'),
      );
    });

    test('built-in kinds take no phases', () {
      expect(
        () => _loader({
          'loaders.a.kind': 'spinner',
          'loaders.a.phases.x.duration': '1s',
        }),
        _fails('phases'),
      );
    });

    test('wrong values name the property', () {
      expect(
        () => _loader({'loaders.a.kind': 'dots', 'loaders.a.size': 'big'}),
        _fails('loaders.a.size'),
      );
      expect(
        () => _loader({'loaders.a.kind': 'dots', 'loaders.a.count': '0'}),
        _fails('whole number'),
      );
      expect(
        () => _loader({
          'loaders.a.kind': 'spinner',
          'loaders.a.animation.duration': 'soon',
        }),
        _fails('duration'),
      );
    });

    test('a kind of the app: registered, phases in order, keys checked', () {
      ThemeLoaderKinds.register<_Props>(
        'doors',
        painter: _Doors(),
        props: _Props.new,
        keys: ['door'],
      );
      final spec = _loader(_phases, 'doors');
      expect(spec.isBuiltIn, isFalse);
      expect(spec.phases.keys, ['close', 'fill', 'open']);
      expect(spec.phases['fill']!.followsProgress, isTrue);
      expect(
        spec.phases['close']!.animation!.duration,
        const Duration(milliseconds: 100),
      );
      expect(
        () => _loader({..._phases, 'loaders.doors.seam': 'x'}, 'doors'),
        _fails('seam'),
      );
      // The props read at the start: a missing key fails it.
      expect(
        () => _loader({
          'loaders.doors.kind': 'doors',
        }, 'doors'),
        _fails('door.width'),
      );
    });

    test('a kind nobody registered stops the start', () {
      expect(
        () => _loader(_phases, 'doors'),
        _fails("@ThemeLoaderKind('doors')"),
      );
    });

    test('a bad phase', () {
      ThemeLoaderKinds.register<LoaderValues>('doors', painter: _Doors2());
      expect(
        () => _loader({
          'loaders.doors.kind': 'doors',
          'loaders.doors.phases.a.progress': 'no',
        }, 'doors'),
        _fails('phases.a.progress'),
      );
      expect(
        () => _loader({
          'loaders.doors.kind': 'doors',
          'loaders.doors.phases.a.curve': 'ease',
        }, 'doors'),
        _fails('duration'),
      );
    });

    test('register needs one of painter and widget; no built-in names', () {
      expect(
        () => ThemeLoaderKinds.register<Object?>('x'),
        throwsArgumentError,
      );
      expect(
        () => ThemeLoaderKinds.register<LoaderValues>(
          'spinner',
          painter: _Doors2(),
        ),
        throwsArgumentError,
      );
    });

    test('ThemeKeyReader.loader reads by any spelling, with a hint', () {
      final data = SpringThemes({
        'loaders.neon-doors.kind': 'pulse',
      }).data('light');
      final reader = ThemeKeyReader(data);
      expect(reader.loader('neon-doors').kind, 'pulse');
      expect(reader.loader('NeonDoors').name, 'neondoors');
      expect(
        () => reader.loader('neon-door'),
        throwsA(
          isA<StateError>().having((e) => '$e', 'm', contains('did you')),
        ),
      );
    });

    test('LoaderValues reads typed values and sub-maps', () {
      ThemeLoaderKinds.register<LoaderValues>('doors', painter: _Doors2());
      final values = _loader({
        'loaders.doors.kind': 'doors',
        'loaders.doors.door.edge.color': '#00FF00',
        'loaders.doors.door.edge.width': '2',
        'loaders.doors.flicker': '120ms',
        'loaders.doors.on': 'true',
      }, 'doors').values!;
      expect(values.color('door.edge.color'), const Color(0xFF00FF00));
      expect(values.at('door').number('edge.width'), 2);
      expect(values.duration('flicker'), const Duration(milliseconds: 120));
      expect(values.boolean('on'), isTrue);
      expect(values.numberOrNull('nothing'), isNull);
      expect(
        () => values.number('nothing'),
        throwsA(isA<ThemePropertyException>()),
      );
      expect(values.keys('door'), {'edge'});
      expect(values.has('door.edge'), isTrue);
    });
  });

  group('timeline', () {
    LoaderTimeline timeline() {
      ThemeLoaderKinds.register<_Props>(
        'doors',
        painter: _Doors(),
        props: _Props.new,
      );
      return LoaderTimeline(_loader(_phases, 'doors').phases);
    }

    test('phases play in order; fill follows progress; open waits ready', () {
      final t = timeline();
      t.advance(const Duration(milliseconds: 50), progress: 0, ready: false);
      expect(t.values['close'], closeTo(0.5, 0.01));
      expect(t.values['fill'], 0);
      t.advance(const Duration(milliseconds: 100), progress: 0.5, ready: false);
      expect(t.values['close'], 1);
      expect(t.values['fill'], greaterThan(0));
      expect(t.values['open'], 0);
      t.advance(const Duration(seconds: 2), progress: 1, ready: false);
      expect(t.values['fill'], 1);
      // Progress is full but the loader is not ready: open waits.
      expect(t.values['open'], 0);
      t.advance(const Duration(milliseconds: 50), progress: 1, ready: true);
      expect(t.values['open'], closeTo(0.5, 0.01));
      expect(t.finished, isFalse);
      t.advance(const Duration(milliseconds: 100), progress: 1, ready: true);
      expect(t.finished, isTrue);
    });

    test('resume: the phases before the progress one are done', () {
      final t = timeline()..resume(0.8);
      expect(t.values['close'], 1);
      expect(t.values['fill'], 0);
      t.advance(const Duration(milliseconds: 1), progress: 0.8, ready: false);
      expect(t.values['fill'], greaterThan(0));
      expect(t.values['open'], 0);
    });

    test('min-duration: the fill waits for its clock, eased', () {
      ThemeLoaderKinds.register<_Props>(
        'doors',
        painter: _Doors(),
        props: _Props.new,
      );
      final spec = _loader({
        ..._phases,
        'loaders.doors.phases.fill.min-duration': '1s',
      }, 'doors');
      expect(spec.phases['fill']!.minDuration, const Duration(seconds: 1));
      final t = LoaderTimeline(spec.phases);
      // The work is done at once; nothing shows while close plays.
      t.advance(const Duration(milliseconds: 50), progress: 1, ready: true);
      expect(t.values['fill'], 0);
      // 50 ms of close are left, then 450 ms of the fill's clock: a little
      // under half way (eased in and out).
      for (var i = 0; i < 50; i++) {
        t.advance(const Duration(milliseconds: 10), progress: 1, ready: true);
      }
      expect(t.values['close'], 1);
      expect(t.values['fill'], closeTo(LoaderTimeline.fillEase(0.45), 0.02));
      expect(t.values['open'], 0);
      // The real progress caps it too.
      final low = LoaderTimeline(spec.phases);
      for (var i = 0; i < 300; i++) {
        low.advance(
          const Duration(milliseconds: 10),
          progress: 0.3,
          ready: false,
        );
      }
      expect(low.values['fill'], closeTo(0.3, 0.001));
      // Past the minimum the fill ends and open plays.
      t
        ..advance(const Duration(milliseconds: 600), progress: 1, ready: true)
        ..advance(const Duration(milliseconds: 50), progress: 1, ready: true);
      expect(t.values['fill'], 1);
      expect(t.values['open'], greaterThan(0));
    });

    test('min-duration: a resumed fill goes on with its clock', () {
      ThemeLoaderKinds.register<_Props>(
        'doors',
        painter: _Doors(),
        props: _Props.new,
      );
      final spec = _loader({
        ..._phases,
        'loaders.doors.phases.fill.min-duration': '1s',
      }, 'doors');
      // The page ran 600 ms: close (100 ms) and 500 ms of the clock.
      final t = LoaderTimeline(spec.phases)
        ..resume(0.5, elapsed: const Duration(milliseconds: 600))
        ..advance(const Duration(milliseconds: 16), progress: 1, ready: true);
      expect(t.values['fill'], closeTo(LoaderTimeline.fillEase(0.516), 0.06));
    });

    test('min-duration must be a duration of 0 or more', () {
      ThemeLoaderKinds.register<_Props>(
        'doors',
        painter: _Doors(),
        props: _Props.new,
      );
      expect(
        () => _loader({
          ..._phases,
          'loaders.doors.phases.fill.min-duration': 'soon',
        }, 'doors'),
        _fails('a duration like 2.5s'),
      );
    });

    test('fillEase: ease in and out, 0 to 1', () {
      expect(LoaderTimeline.fillEase(0), 0);
      expect(LoaderTimeline.fillEase(0.5), 0.5);
      expect(LoaderTimeline.fillEase(1), 1);
      expect(LoaderTimeline.fillEase(0.25), closeTo(0.0625, 1e-9));
    });

    test('still: the end of each phase', () {
      final t = timeline()..still(0.4);
      expect(t.values['close'], 1);
      expect(t.values['fill'], 0.4);
      expect(t.values['open'], 1);
    });
  });

  group('widgets', () {
    testWidgets('each built-in kind renders and animates', (tester) async {
      for (final kind in ThemeLoaderSpec.builtInKinds) {
        final spec = ThemeLoaderSpec.builtIn(kind);
        await tester.pumpWidget(_host(ThemeLoader(spec)));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ThemeLoader), findsOneWidget, reason: kind);
        expect(tester.takeException(), isNull, reason: kind);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the bar follows progress', (tester) async {
      final spec = ThemeLoaderSpec.builtIn(
        'bar',
        look: const BuiltInLoaderLook(width: 100, height: 4),
      );
      await tester.pumpWidget(_host(ThemeLoader(spec, progress: 0.5)));
      await tester.pump();
      expect(tester.getSize(find.byType(ThemeLoader)), const Size(100, 4));
      expect(tester.takeException(), isNull);
      final semantics = tester.getSemantics(find.byType(ThemeLoader));
      expect(semantics.value, '50%');
    });

    testWidgets('custom painter gets phases, props, progress', (tester) async {
      final doors = _Doors();
      ThemeLoaderKinds.register<_Props>(
        'doors',
        painter: doors,
        props: _Props.new,
      );
      final spec = _loader(_phases, 'doors');
      var finished = 0;
      Widget loader(double? progress) => _host(
        SizedBox(
          width: 80,
          height: 60,
          child: ThemeLoader(
            spec,
            progress: progress,
            onFinished: () => finished++,
          ),
        ),
      );
      await tester.pumpWidget(loader(0.3));
      await tester.pump(const Duration(milliseconds: 60));
      final frame = doors.frames.last;
      expect(frame.props.width, 12);
      expect(frame.progress, 0.3);
      expect(frame.phase('close'), greaterThan(0));
      expect(frame.phase('open'), 0);
      expect(frame.values.number('door.width'), 12);
      expect(() => frame.phase('nope'), throwsStateError);
      // Ready by progress 1: fill, then open play, then it finishes.
      await tester.pumpWidget(loader(1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(doors.frames.last.phase('open'), 1);
      expect(finished, 1);
    });

    testWidgets('the frame has the time the loader has run; resumeFrom skips '
        'the first phases', (tester) async {
      final doors = _Doors();
      ThemeLoaderKinds.register<_Props>(
        'doors',
        painter: doors,
        props: _Props.new,
      );
      final spec = _loader(_phases, 'doors');
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 80,
            height: 60,
            child: ThemeLoader(spec, progress: 0.5, resumeFrom: 0.5),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      final frame = doors.frames.last;
      expect(frame.phase('close'), 1);
      expect(frame.phase('fill'), greaterThan(0));
      expect(
        frame.elapsed,
        greaterThanOrEqualTo(
          const Duration(milliseconds: 100),
        ),
      );
    });

    testWidgets('resumeElapsed: the frame goes on from the page loader\'s '
        'time', (tester) async {
      final doors = _Doors();
      ThemeLoaderKinds.register<_Props>(
        'doors',
        painter: doors,
        props: _Props.new,
      );
      final spec = _loader(_phases, 'doors');
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 80,
            height: 60,
            child: ThemeLoader(
              spec,
              progress: 0.5,
              resumeFrom: 0.5,
              resumeElapsed: const Duration(seconds: 3),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        doors.frames.last.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 3100)),
      );
    });

    testWidgets('custom widget kind builds from the frame', (tester) async {
      ThemeLoaderKinds.register<LoaderValues>('card', widget: _Card());
      final spec = _loader({
        'loaders.card.kind': 'card',
        'loaders.card.phases.go.duration': '1s',
      }, 'card');
      await tester.pumpWidget(_host(ThemeLoader(spec)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('phase 0.5'), findsOneWidget);
    });

    testWidgets('reduced motion: end state, nothing moves', (tester) async {
      final doors = _Doors();
      ThemeLoaderKinds.register<_Props>(
        'doors',
        painter: doors,
        props: _Props.new,
      );
      final spec = _loader(_phases, 'doors');
      var finished = 0;
      await tester.pumpWidget(
        _host(
          ThemeLoader(spec, progress: 0.4, onFinished: () => finished++),
          reduce: true,
        ),
      );
      await tester.pump();
      final frame = doors.frames.last;
      expect(frame.reduceMotion, isTrue);
      expect(frame.phase('close'), 1);
      expect(frame.phase('fill'), 0.4);
      expect(frame.phase('open'), 1);
      expect(finished, 1);
      // No ticker runs.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('reduced motion: built-in kinds stand still', (tester) async {
      await tester.pumpWidget(
        _host(ThemeLoader(ThemeLoaderSpec.builtIn('spinner')), reduce: true),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('ThemeSkeleton: content, skeleton, placeholder', (
      tester,
    ) async {
      final spec = ThemeLoaderSpec.builtIn(
        'skeleton',
        look: const BuiltInLoaderLook(
          base: Color(0xFF111111),
          highlight: Color(0xFF999999),
        ),
      );
      Widget skeleton({required bool loading, bool reduce = false}) => _host(
        ThemeSkeleton(
          spec,
          loading: loading,
          placeholder: const SizedBox(width: 50, height: 10, key: Key('ph')),
          child: const Text('content'),
        ),
        reduce: reduce,
      );
      await tester.pumpWidget(skeleton(loading: true));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('ph')), findsOneWidget);
      expect(find.text('content'), findsNothing);
      expect(find.byType(ShaderMask), findsOneWidget);
      await tester.pumpWidget(skeleton(loading: false));
      expect(find.text('content'), findsOneWidget);
      expect(find.byType(ShaderMask), findsNothing);
      // Still: no shimmer frames.
      await tester.pumpWidget(skeleton(loading: true, reduce: true));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a new spec starts over', (tester) async {
      await tester.pumpWidget(
        _host(ThemeLoader(ThemeLoaderSpec.builtIn('dots'))),
      );
      await tester.pumpWidget(
        _host(ThemeLoader(ThemeLoaderSpec.builtIn('pulse'))),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });
  });
}

class _Doors2 extends ThemeLoaderPainter<LoaderValues> {
  @override
  void paint(Canvas canvas, Size size, LoaderFrame<LoaderValues> frame) {}
}
