import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter_scene/src/conditions/scene_condition.dart';
import 'package:spring_boot_starter_flutter_scene/src/conditions/touch_screen.dart';

/// `touch`: the device's main pointer is a finger. In a browser, a coarse
/// pointer (a phone, a tablet); elsewhere, a phone's or a tablet's system.
final class TouchSceneCondition extends ChangeNotifier
    implements SceneCondition {
  /// The condition of this device; [touch] in place of what the device
  /// says (a test).
  TouchSceneCondition({bool? touch}) : holds = touch ?? touchScreen;

  @override
  String get name => 'touch';

  @override
  final bool holds;

  @override
  String get state => holds ? 'a touch screen' : 'a mouse or none';
}
