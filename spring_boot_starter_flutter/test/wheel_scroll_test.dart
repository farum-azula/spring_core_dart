// motion.wheel-scroll: none by default; a step of the wheel arrives in
// a step in each frame over the duration, scaled by the speed; other
// pointer data and a trackpad's scroll pass as they came.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

WheelScrollSpec _spec(Map<String, String> values) =>
    SpringThemes(values).data('light').wheelScroll;

void main() {
  test('none by default; a map of duration and speed; wrong values named', () {
    expect(_spec(const {}), WheelScrollSpec.none);
    expect(_spec(const {'motion.wheel-scroll': 'none'}).isNone, isTrue);
    expect(
      _spec(const {
        'motion.wheel-scroll.duration': '300ms',
        'motion.wheel-scroll.speed': '0.5',
      }),
      const WheelScrollSpec(duration: Duration(milliseconds: 300), speed: 0.5),
    );
    for (final values in [
      const {'motion.wheel-scroll': 'smooth'},
      const {'motion.wheel-scroll.speed': '0'},
      const {'motion.wheel-scroll.pace': '1'},
    ]) {
      expect(
        () => _spec(values),
        throwsA(isA<ThemePropertyException>()),
        reason: '$values',
      );
    }
  });

  testWidgets('a wheel step arrives eased and scaled; the rest passes', (
    tester,
  ) async {
    final dispatcher = tester.binding.platformDispatcher;
    final original = dispatcher.onPointerDataPacket;
    addTearDown(() => dispatcher.onPointerDataPacket = original);
    final received = <PointerData>[];
    dispatcher.onPointerDataPacket = (packet) => received.addAll(packet.data);

    final smoother = WheelScrollSmoother.of(dispatcher)
      ..spec = const WheelScrollSpec(
        duration: Duration(milliseconds: 240),
        speed: 0.5,
      );
    dispatcher.onPointerDataPacket!(
      const PointerDataPacket(
        data: [
          PointerData(
            kind: PointerDeviceKind.mouse,
            signalKind: PointerSignalKind.scroll,
            physicalX: 10,
            physicalY: 20,
            scrollDeltaY: 200,
          ),
          PointerData(
            change: PointerChange.hover,
            kind: PointerDeviceKind.mouse,
          ),
        ],
      ),
    );
    // The hover passes at once; the scroll is not one jump.
    expect(received.single.change, PointerChange.hover);
    // A step in each frame.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final scrolls = [
      for (final data in received)
        if (data.signalKind == PointerSignalKind.scroll) data,
    ];
    expect(scrolls.length, greaterThan(4));
    expect(
      scrolls.fold<double>(0, (sum, d) => sum + d.scrollDeltaY),
      closeTo(100, 0.001),
    );
    expect(scrolls.first.scrollDeltaY, lessThan(scrolls[1].scrollDeltaY + 50));
    expect(
      scrolls.every((d) => d.physicalX == 10 && d.physicalY == 20),
      isTrue,
    );
    expect(smoother.spec.speed, 0.5);

    // A trackpad passes as it came, at once.
    received.clear();
    dispatcher.onPointerDataPacket!(
      const PointerDataPacket(
        data: [
          PointerData(
            kind: PointerDeviceKind.trackpad,
            signalKind: PointerSignalKind.scroll,
            scrollDeltaY: 30,
          ),
        ],
      ),
    );
    expect(received.single.scrollDeltaY, 30);
    await tester.pump(const Duration(milliseconds: 16));
    expect(received, hasLength(1));
  });
}
