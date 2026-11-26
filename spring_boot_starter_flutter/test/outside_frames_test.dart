// Frames drawn without Flutter (a scene on a canvas of its own): a source
// reports each with its cost, and the frame meter shows a line for it.
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

void main() {
  var now = 0;
  setUp(() {
    now = 0;
    OutsideFrames.clock = () => now;
  });
  tearDown(OutsideFrames.reset);

  // [count] frames of [cost] microseconds, [every] microseconds apart.
  void draw(
    OutsideFrames source,
    int count, {
    int every = 16667,
    int cost = 900,
  }) {
    for (var i = 0; i < count; i++) {
      source.frame(Duration(microseconds: cost));
      now += every;
    }
    now -= every;
  }

  test('one source a name, counting what it reported', () {
    final source = OutsideFrames.of('3D');
    expect(identical(OutsideFrames.of('3D'), source), isTrue);
    expect(OutsideFrames.all, [source]);
    draw(source, 3);
    expect(source.count, 3);
  });

  test('the frames of the last second: how many a second, what one cost', () {
    final source = OutsideFrames.of('3D');
    draw(source, 61, cost: 900);
    expect(source.recent, (rate: 60, cost: 0.9));
  });

  test('a source that draws fewer frames: its own rate', () {
    final source = OutsideFrames.of('3D');
    draw(source, 25, every: 41667, cost: 2000);
    expect(source.recent, (rate: 24, cost: 2.0));
  });

  test('nothing in the last second, or one frame: no line', () {
    final source = OutsideFrames.of('3D');
    expect(source.recent, isNull);
    source.frame(const Duration(milliseconds: 1));
    expect(source.recent, isNull);
    draw(source, 30);
    now += 2000000;
    expect(source.recent, isNull);
  });

  testWidgets('the frame meter: idle for Flutter, a line for the 3D', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: FrameMeter(detailed: true, child: SizedBox()),
      ),
    );
    // A frame of Flutter, so the meter has started counting.
    tester.binding.platformDispatcher.onReportTimings!(<FrameTiming>[
      FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 2000,
        rasterStart: 2000,
        rasterFinish: 5000,
        rasterFinishWallTime: 5000,
      ),
    ]);
    draw(OutsideFrames.of('3D'), 61, cost: 900);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('3D 60 fps · 0.9 ms'), findsOneWidget);
    // The 3D stops: its line goes with the next refresh.
    now += 2000000;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('3D'), findsNothing);
  });
}
