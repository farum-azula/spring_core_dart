// The frames of the moving scenes from one beat (a timer off the web): it
// beats at the highest rate of the views that move, every view on the same
// beat, and stops when none moves; a beat that drew a frame Flutter does not
// draw is the frame meter's 3D.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

void main() {
  testWidgets('beats at the highest rate, every view on one beat', (
    tester,
  ) async {
    final frames = SceneFrames();
    final wall = <Duration>[];
    final header = <Duration>[];
    var now = Duration.zero;
    frames
      ..join(#wall, 24, () {
        wall.add(now);
        return false;
      })
      ..join(#header, 30, () {
        header.add(now);
        return false;
      });
    expect(frames.rate, 30);
    for (var i = 0; i < 30; i++) {
      now += const Duration(microseconds: 33333);
      await tester.pump(const Duration(microseconds: 33333));
    }
    expect(header, hasLength(30));
    expect(wall, header);
    frames.dispose();
  });

  testWidgets('the rate follows the views; none moving, no timer', (
    tester,
  ) async {
    final frames = SceneFrames();
    var beats = 0;
    frames.join(#a, 60, () {
      beats++;
      return false;
    });
    frames.join(#b, 15, () => false);
    expect(frames.rate, 60);
    frames.leave(#a);
    expect(frames.rate, 15);
    frames.leave(#b);
    expect(frames.rate, 0);
    expect(frames.moving, 0);
    final before = beats;
    await tester.pump(const Duration(seconds: 1));
    expect(beats, before);
  });

  testWidgets('a beat that drew is a frame of 3D for the frame meter', (
    tester,
  ) async {
    addTearDown(OutsideFrames.reset);
    final frames = SceneFrames();
    var draws = true;
    frames.join(#scene, 30, () => draws);
    final source = OutsideFrames.of('3D');
    await tester.pump(const Duration(microseconds: 33334));
    await tester.pump(const Duration(microseconds: 33334));
    expect(source.count, 2);
    // Not due, or drawn by Flutter (canvas: page): Flutter's own frame.
    draws = false;
    await tester.pump(const Duration(microseconds: 33334));
    expect(source.count, 2);
    frames.dispose();
  });

  testWidgets('it tells what a beat that drew cost, and when nothing moves', (
    tester,
  ) async {
    final frames = SceneFrames();
    final costs = <Duration>[];
    var rested = 0;
    void drawn(Duration cost) => costs.add(cost);
    void rest() => rested++;
    frames
      ..addDrawnListener(drawn)
      ..addRestListener(rest)
      ..join(#scene, 30, () => true);
    await tester.pump(const Duration(microseconds: 33334));
    await tester.pump(const Duration(microseconds: 33334));
    expect(costs, hasLength(2));
    frames.leave(#scene);
    expect(rested, 1);
    frames
      ..removeDrawnListener(drawn)
      ..removeRestListener(rest)
      ..join(#scene, 30, () => true);
    await tester.pump(const Duration(microseconds: 33334));
    expect(costs, hasLength(2));
    frames.dispose();
    expect(rested, 1);
  });
}
