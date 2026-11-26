// The debug console's scene-fps segment: the frames a second the scenes
// draw, nothing while none moves.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

void main() {
  tearDown(OutsideFrames.reset);

  test('nothing while no scene moves; then its frames a second', () {
    var now = 0;
    OutsideFrames.clock = () => now;
    const segment = SceneFpsSegment();
    expect(segment.read(), isNull);
    final frames = OutsideFrames.of(SceneFrames.source);
    for (var i = 0; i < 31; i++) {
      frames.frame(const Duration(milliseconds: 1));
      now += 33334;
    }
    expect(segment.read(), const DebugConsoleValue('30', label: '3D'));
    now += 2000000;
    expect(segment.read(), isNull);
  });
}
