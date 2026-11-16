import 'package:flutter/foundation.dart';

/// A state of the device or the app under which scenes draw less: what
/// `spring.flutter.scene.when.<name>` names, with the mode scenes take
/// while it holds (`still` or `off`).
///
/// ```yaml
/// spring:
///   flutter:
///     scene:
///       when:
///         touch: still   # a touch screen: one frame that stands
///         slow: off      # frames too slow here: no scenes
/// ```
///
/// A condition is a bean: the starter has `touch` ([TouchSceneCondition])
/// and `slow` ([SlowFramesSceneCondition]); one of the app's is one more
/// bean of this type, named by its [name]. It notifies its listeners when
/// it starts or stops holding, and the scenes follow.
abstract interface class SceneCondition implements Listenable {
  /// Its key under `spring.flutter.scene.when`.
  String get name;

  /// Whether it holds now.
  bool get holds;

  /// What it sees now, in words, for the scenes' debug tab.
  String get state;
}
