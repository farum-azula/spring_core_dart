// taps:<n>[+hold:<duration>]: a shortcut done with taps, on every
// platform; the detector only listens, every touch still reaches the app.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

TouchPattern _parse(String text) => (const TouchPatternNotation().parse(
  text,
  TargetPlatform.iOS,
) as ShortcutGesture).pattern;

Future<void> _tap(
  WidgetTester tester, {
  Duration gap = const Duration(milliseconds: 100),
}) async {
  final gesture = await tester.startGesture(const Offset(100, 100));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pump(gap);
}

void main() {
  test('the notation: taps, a hold, wrong values named', () {
    expect(
      _parse('taps:4+hold:3s'),
      const TouchPattern(4, hold: Duration(seconds: 3)),
    );
    expect(_parse('taps:2'), const TouchPattern(2));
    expect(
      _parse('taps:3 + hold:500ms').hold,
      const Duration(milliseconds: 500),
    );
    expect('${_parse('taps:4+hold:3s')}', '4 taps, hold 3 s');
    for (final wrong in [
      'taps:0',
      'taps:11',
      'taps:x',
      'taps:2+hold:0s',
      'taps:2+hold',
    ]) {
      expect(
        () => const TouchPatternNotation().parse(wrong, TargetPlatform.iOS),
        throwsFormatException,
        reason: wrong,
      );
    }
    final keys = ShortcutNotations().parse(
      'taps:4+hold:3s',
      property: 'p',
      platform: TargetPlatform.android,
    );
    expect(keys, isA<ShortcutGesture>());
  });

  group('the detector', () {
    late List<String> matched;
    late int appTaps;

    Future<void> pump(
      WidgetTester tester,
      Map<String, List<TouchPattern>> patterns,
    ) async {
      matched = [];
      appTaps = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TouchPatternDetector(
            patterns: patterns,
            onMatch: (action, _) => matched.add(action),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => appTaps++,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    }

    testWidgets('four taps and a fifth held three seconds', (tester) async {
      await pump(tester, {
        'debug.open': [const TouchPattern(4, hold: Duration(seconds: 3))],
      });
      for (var i = 0; i < 4; i++) {
        await _tap(tester);
      }
      final hold = await tester.startGesture(const Offset(100, 100));
      await tester.pump(const Duration(seconds: 2));
      expect(matched, isEmpty, reason: 'two seconds are not three');
      await tester.pump(const Duration(seconds: 1));
      expect(matched, ['debug.open']);
      await hold.up();
      expect(appTaps, 5, reason: 'it only listens: the app got every touch');
    });

    testWidgets('a pause, a drag or a short hold starts again', (tester) async {
      await pump(tester, {
        'debug.open': [const TouchPattern(4, hold: Duration(seconds: 3))],
      });
      for (var i = 0; i < 3; i++) {
        await _tap(tester);
      }
      await tester.pump(const Duration(seconds: 1)); // too long a pause
      await _tap(tester);
      var hold = await tester.startGesture(const Offset(100, 100));
      await tester.pump(const Duration(seconds: 4));
      await hold.up();
      expect(matched, isEmpty);

      for (var i = 0; i < 4; i++) {
        await _tap(tester);
      }
      hold = await tester.startGesture(const Offset(100, 100));
      await hold.moveBy(const Offset(0, 60)); // a scroll
      await tester.pump(const Duration(seconds: 4));
      await hold.up();
      expect(matched, isEmpty);
    });

    testWidgets('taps alone: the last tap is the shortcut', (tester) async {
      await pump(tester, {
        'refresh': [const TouchPattern(3)],
      });
      for (var i = 0; i < 3; i++) {
        await _tap(tester);
      }
      expect(matched, ['refresh']);
    });
  });
}
