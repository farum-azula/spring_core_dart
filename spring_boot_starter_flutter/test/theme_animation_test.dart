// ThemeAnimation: once, loop, reverse, less motion, a new spec.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

void main() {
  Future<List<double>> pumpSpec(
    WidgetTester tester,
    AnimationSpec spec, {
    bool reduce = false,
    Key? key,
  }) async {
    final values = <double>[];
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ThemeAnimation(
            spec,
            key: key,
            builder: (context, animation) => AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                values.add(animation.value);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    return values;
  }

  double last(List<double> values) => values.last;

  const second = Duration(seconds: 1);

  testWidgets('plays once and stays at the end', (tester) async {
    final values = await pumpSpec(
      tester,
      const AnimationSpec(duration: second),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(last(values), closeTo(0.5, 0.01));
    await tester.pump(const Duration(seconds: 2));
    expect(last(values), 1);
  });

  testWidgets('loop starts again', (tester) async {
    final values = await pumpSpec(
      tester,
      const AnimationSpec(duration: second, repeat: AnimationRepeat.loop),
    );
    await tester.pump(const Duration(milliseconds: 750));
    expect(last(values), closeTo(0.75, 0.01));
    await tester.pump(const Duration(milliseconds: 500));
    expect(last(values), closeTo(0.25, 0.01));
  });

  testWidgets('reverse goes back and forth', (tester) async {
    final values = await pumpSpec(
      tester,
      const AnimationSpec(duration: second, repeat: AnimationRepeat.reverse),
    );
    await tester.pump(const Duration(milliseconds: 750));
    expect(last(values), closeTo(0.75, 0.01));
    await tester.pump(const Duration(milliseconds: 500));
    expect(last(values), closeTo(0.75, 0.01));
  });

  testWidgets('the curve shapes the value', (tester) async {
    final values = await pumpSpec(
      tester,
      const AnimationSpec(duration: second, curve: Curves.easeIn),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(last(values), lessThan(0.4));
  });

  testWidgets('less motion stands still at 0', (tester) async {
    final values = await pumpSpec(
      tester,
      const AnimationSpec(duration: second, repeat: AnimationRepeat.loop),
      reduce: true,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(last(values), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduced motion: a one-shot goes to its end', (tester) async {
    final values = await pumpSpec(
      tester,
      const AnimationSpec(duration: second),
      reduce: true,
    );
    expect(last(values), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduced motion: reverse stands still at 0', (tester) async {
    final values = await pumpSpec(
      tester,
      const AnimationSpec(duration: second, repeat: AnimationRepeat.reverse),
      reduce: true,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(last(values), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a new spec changes duration and curve', (tester) async {
    const key = Key('a');
    final values = await pumpSpec(
      tester,
      const AnimationSpec(duration: second, repeat: AnimationRepeat.loop),
      key: key,
    );
    await tester.pump(const Duration(milliseconds: 250));
    final fast = await pumpSpec(
      tester,
      const AnimationSpec(
        duration: Duration(milliseconds: 100),
        repeat: AnimationRepeat.loop,
      ),
      key: key,
    );
    expect(values, isNotEmpty);
    final start = last(fast);
    await tester.pump(const Duration(milliseconds: 50));
    // 50 ms of a 100 ms loop moves by half, not by 5%.
    final moved = (last(fast) - start) % 1;
    expect(moved, closeTo(0.5, 0.05));
  });

  testWidgets('a repeat of none stops the loop', (tester) async {
    const key = Key('a');
    await pumpSpec(
      tester,
      const AnimationSpec(duration: second, repeat: AnimationRepeat.loop),
      key: key,
    );
    final values = await pumpSpec(
      tester,
      const AnimationSpec(duration: second),
      key: key,
    );
    await tester.pump(const Duration(seconds: 3));
    expect(last(values), 1);
  });

  testWidgets('disposes without a running ticker', (tester) async {
    await pumpSpec(
      tester,
      const AnimationSpec(duration: second, repeat: AnimationRepeat.loop),
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.hasRunningAnimations, isFalse);
  });

  test('AnimationSpec compares by value', () {
    expect(
      const AnimationSpec(duration: second),
      const AnimationSpec(duration: second),
    );
    expect(
      const AnimationSpec(duration: second),
      isNot(
        const AnimationSpec(duration: second, repeat: AnimationRepeat.loop),
      ),
    );
  });
}
