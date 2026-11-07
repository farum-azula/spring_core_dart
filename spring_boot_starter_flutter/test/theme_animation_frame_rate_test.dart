// ThemeAnimation(frameRate:): a repeating animation moves on that many
// times a second, not at every frame, and keeps its curve and repeat;
// without a rate, or when the system asks for less motion, as before.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

Widget _animated(
  List<double> seen, {
  double? frameRate,
  AnimationRepeat repeat = AnimationRepeat.reverse,
}) => ThemeAnimation(
  AnimationSpec(duration: const Duration(seconds: 1), repeat: repeat),
  frameRate: frameRate,
  builder: (context, t) => AnimatedBuilder(
    animation: t,
    builder: (context, _) {
      seen.add(t.value);
      return const SizedBox();
    },
  ),
);

void main() {
  testWidgets('10 a second: 10 builds a second, there and back', (
    tester,
  ) async {
    final seen = <double>[];
    await tester.pumpWidget(_animated(seen, frameRate: 10));
    seen.clear();
    // 60 frames of the screen in a second: 10 of them move.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(seen.length, inInclusiveRange(9, 11));
    expect(seen.last, closeTo(1, 0.11));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(seen.last, closeTo(0.5, 0.11), reason: 'on its way back');
  });

  testWidgets('no rate: every frame', (tester) async {
    final seen = <double>[];
    await tester.pumpWidget(_animated(seen));
    seen.clear();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(seen.length, 30);
  });

  testWidgets('a loop starts again; less motion stands still', (
    tester,
  ) async {
    final seen = <double>[];
    await tester.pumpWidget(
      _animated(seen, frameRate: 20, repeat: AnimationRepeat.loop),
    );
    await tester.pump(const Duration(milliseconds: 1260));
    expect(seen.last, closeTo(0.25, 0.06));

    final still = <double>[];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _animated(still, frameRate: 20),
      ),
    );
    still.clear();
    await tester.pump(const Duration(seconds: 1));
    expect(still, isEmpty);
  });
}
