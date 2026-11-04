// The neon-gate loader: what each phase draws (panels from their sides, the
// box with the progress, the panels parting), the look from the theme, the
// flicker of the edges, "reduce motion", the hand-off from the web page and
// the loader inside a ThemeLoader with the fill's min-duration. Pixels are
// read from a frame the way a ThemeLoader draws it.
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

import 'support.dart';

const _size = Size(1280, 800);

/// The pixels of one frame (RGBA, row by row).
class _Picture {
  _Picture(this.bytes);

  final Uint8List bytes;

  /// The RGBA of the pixel at ([x], [y]).
  (int, int, int, int) at(int x, int y) {
    final i = (y * 1280 + x) * 4;
    return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]);
  }

  bool red(int x, int y) {
    final (r, g, b, _) = at(x, y);
    return r > 150 && r > g * 2 && r > b * 1.4;
  }

  bool clear(int x, int y) => at(x, y).$4 == 0;

  /// Whether the pixel is close to [color] and opaque.
  bool near(int x, int y, (int, int, int) color, {int slack = 12}) {
    final (r, g, b, a) = at(x, y);
    return a == 255 &&
        (r - color.$1).abs() <= slack &&
        (g - color.$2).abs() <= slack &&
        (b - color.$3).abs() <= slack;
  }
}

const _navy = (0x06, 0x0B, 0x1E);
const _panel = (0x0C, 0x13, 0x30);

/// Draws the loader at the given phases the way a ThemeLoader does.
Future<_Picture> _draw(
  WidgetTester tester, {
  double enter = 1,
  double fill = 0,
  double exit = 0,
  bool reduce = false,
  Duration elapsed = Duration.zero,
}) async {
  final key = GlobalKey();
  await pumpNeon(
    tester,
    Builder(
      builder: (context) {
        final spec = SpringTheme.of(context).loaders['neongate']!;
        final registration = ThemeLoaderKinds.lookup('neon-gate')!;
        final frame = LoaderFrame<Object?>(
          phases: {'enter': enter, 'fill': fill, 'exit': exit},
          props: registration.makeProps(spec.values!),
          values: spec.values!,
          progress: fill,
          reduceMotion: reduce,
          elapsed: elapsed,
        );
        return RepaintBoundary(
          key: key,
          child: SizedBox.fromSize(
            size: _size,
            child: registration.build(context, frame),
          ),
        );
      },
    ),
    size: _size,
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData();
    return data!.buffer.asUint8List();
  });
  return _Picture(bytes!);
}

/// The loader's own semantics (its label carries the number).
Finder _label(bool Function(String label) test) => find.byWidgetPredicate(
  (w) => w is Semantics && test(w.properties.label ?? ''),
);

void main() {
  group('the theme', () {
    testWidgets('three phases, the fill takes 2.5 s at least', (tester) async {
      late ThemeLoaderSpec spec;
      await pumpNeon(
        tester,
        Builder(
          builder: (context) {
            spec = SpringTheme.of(context).loaders['neongate']!;
            return const SizedBox();
          },
        ),
      );
      expect(spec.kind, 'neongate');
      expect(spec.phases.keys, ['enter', 'fill', 'exit']);
      final fill = spec.phases['fill']!;
      expect(fill.followsProgress, isTrue);
      expect(fill.minDuration, const Duration(milliseconds: 2500));
      expect(spec.web, 'loaders/neon-gate.html');
      // The times are the theme's animations.
      expect(spec.phases['enter']!.animation!.duration.inMilliseconds, 2000);
      expect(spec.phases['exit']!.animation!.duration.inMilliseconds, 1400);
      final values = spec.values!;
      expect(values.color('gate.color'), const Color(0xFF060B1E));
      expect(values.color('edge.color'), const Color(0xFF4FD8E8));
      expect(values.color('box.color'), const Color(0xFFFF2A55));
      expect(values.text('label.text'), 'LOADING');
    });
  });

  group('phases', () {
    testWidgets('before the panels arrive nothing is drawn', (tester) async {
      final picture = await _draw(tester, enter: 0);
      expect(picture.clear(100, 400), isTrue);
      expect(picture.clear(1180, 400), isTrue);
      expect(picture.clear(640, 400), isTrue);
    });

    testWidgets('the panels come in from their sides, one after the other', (
      tester,
    ) async {
      final early = await _draw(tester, enter: 0.1);
      final late = await _draw(tester, enter: 1);
      // The left half is nearly in; the top platform comes later, from above.
      expect(early.near(100, 50, _navy), isTrue);
      expect(late.near(100, 50, _panel), isTrue);
      // The right half is still on its way: the right edge is not covered.
      expect(early.clear(1270, 400), isTrue);
      expect(late.near(1270, 400, _navy), isTrue);
    });

    testWidgets('closed: the halves, the platforms and the glowing seam', (
      tester,
    ) async {
      final picture = await _draw(tester, fill: 0.5, reduce: true);
      expect(picture.near(100, 400, _navy), isTrue);
      expect(picture.near(1180, 400, _navy), isTrue);
      expect(picture.near(100, 50, _panel), isTrue);
      expect(picture.near(100, 770, _panel), isTrue);
      // The seam at 20 % of the height: cyan on the left half, red a little
      // to the right of it.
      final (r, g, b, _) = picture.at(689, 160);
      expect(g > 150 && b > 150 && r < 150, isTrue, reason: '($r, $g, $b)');
      expect(picture.red(710, 160), isTrue);
    });

    testWidgets('the box fills from the left by the progress', (tester) async {
      final half = await _draw(tester, fill: 0.5, reduce: true);
      final none = await _draw(tester, reduce: true);
      // Under the word and the number, inside the box (420 wide).
      expect(half.red(560, 418), isTrue);
      expect(half.red(780, 418), isFalse);
      expect(none.red(560, 418), isFalse);
    });

    testWidgets('the number follows the progress', (tester) async {
      await _draw(tester, fill: 0.6);
      expect(_label((l) => l == 'LOADING 60 %'), findsOneWidget);
    });

    testWidgets('exit: the box goes, the panels part, nothing is left', (
      tester,
    ) async {
      final early = await _draw(tester, fill: 1, exit: 0.25);
      final parting = await _draw(tester, fill: 1, exit: 0.7);
      final done = await _draw(tester, fill: 1, exit: 1);
      // The box is gone first; the gate is still closed.
      expect(early.red(560, 418), isFalse);
      expect(early.near(100, 400, _navy), isTrue);
      // Then the halves part: the middle shows what is under the loader.
      expect(parting.clear(640, 160), isTrue);
      expect(parting.near(40, 400, _navy), isTrue);
      expect(done.clear(100, 400), isTrue);
      expect(done.clear(1180, 400), isTrue);
      expect(_label((l) => l.startsWith('LOADING')), findsNothing);
    });
  });

  group('motion', () {
    testWidgets('the edges flicker with the time and come back', (
      tester,
    ) async {
      // The left half's edge dims at 56 % of the 2.4 s cycle (its phase is
      // 41 %): 360 ms in.
      const at = (689, 160);
      final full = (await _draw(tester)).at(at.$1, at.$2);
      final dim = (await _draw(
        tester,
        elapsed: const Duration(milliseconds: 360),
      )).at(at.$1, at.$2);
      final again = (await _draw(
        tester,
        elapsed: const Duration(milliseconds: 2400),
      )).at(at.$1, at.$2);
      expect(dim, isNot(full));
      expect(again, full);
    });

    testWidgets('reduce motion: closed, nothing flickers or slides', (
      tester,
    ) async {
      final a = await _draw(tester, fill: 0.5, reduce: true);
      final b = await _draw(
        tester,
        fill: 0.5,
        reduce: true,
        elapsed: const Duration(milliseconds: 360),
      );
      expect(a.bytes, b.bytes);
      // Every phase is at its end for reduce motion, and still the gate
      // stands (the splash goes at once, but a frame of it is whole).
      final ended = await _draw(tester, fill: 0.5, exit: 1, reduce: true);
      expect(ended.bytes, a.bytes);
    });

    testWidgets('a ThemeLoader: enter, a fill of 2.5 s at least, exit', (
      tester,
    ) async {
      var finished = false;
      await pumpNeon(
        tester,
        Builder(
          builder: (context) => SizedBox(
            width: 800,
            height: 500,
            child: ThemeLoader(
              SpringTheme.of(context).loaders['neongate']!,
              progress: 1,
              onFinished: () => finished = true,
            ),
          ),
        ),
      );
      // The work is done at once, but the box fills over its min-duration.
      // pumpNeon took 0.5 s; the enter phase is 2 s.
      Future<void> pumpFor(int ms) async {
        for (var i = 0; i < ms ~/ 50; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await pumpFor(1500);
      expect(_label((l) => l == 'LOADING 0 %'), findsOneWidget);
      await pumpFor(1250);
      final label = tester
          .widgetList<Semantics>(_label((l) => l.startsWith('LOADING')))
          .single
          .properties
          .label!;
      final shown = int.parse(label.split(' ')[1]);
      expect(shown, inExclusiveRange(20, 80));
      expect(finished, isFalse);
      await pumpFor(1500);
      expect(finished, isFalse);
      await pumpFor(1500);
      expect(finished, isTrue);
    });

    testWidgets('a splash taking over from the page goes on from it', (
      tester,
    ) async {
      final key = GlobalKey();
      await pumpNeon(
        tester,
        Builder(
          builder: (context) => RepaintBoundary(
            key: key,
            child: SizedBox.fromSize(
              size: _size,
              child: ThemeLoader(
                SpringTheme.of(context).loaders['neongate']!,
                progress: 0.6,
                resumeFrom: 0.2,
                resumeElapsed: const Duration(seconds: 3),
              ),
            ),
          ),
        ),
        size: _size,
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        return (await image.toByteData())!.buffer.asUint8List();
      });
      // The enter phase is over: the gate is closed at once.
      expect(_Picture(bytes!).near(100, 50, _panel), isTrue);
      // And the number goes on from the page's progress, not from zero.
      expect(
        _label((l) => l.startsWith('LOADING') && l != 'LOADING 0 %'),
        findsOneWidget,
      );
    });
  });
}
