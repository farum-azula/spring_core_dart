import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugConsoleValue, OutsideFrames, SampledDebugConsoleSegment;
import 'package:spring_boot_starter_flutter_scene/src/engine/scene_frames.dart';

/// The debug console's `scene-fps` segment: the frames a second the 3D
/// scenes draw (`3D 60`), read four times a second while the console
/// shows; nothing while no scene moves.
final class SceneFpsSegment extends SampledDebugConsoleSegment {
  /// The segment.
  const SceneFpsSegment();

  @override
  DebugConsoleValue? read() =>
      switch (OutsideFrames.of(SceneFrames.source).recent) {
        null => null,
        final recent => DebugConsoleValue(
          '${recent.rate}',
          label: SceneFrames.source,
        ),
      };
}
