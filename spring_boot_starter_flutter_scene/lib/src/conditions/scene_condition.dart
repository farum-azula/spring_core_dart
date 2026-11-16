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

  /// Whether it knows: `false` while it is still finding out (`slow`
  /// measures the first scenes' frames while their placeholders show).
  /// A scene that moves waits for every condition of
  /// `spring.flutter.scene.when` to know before it shows, so it shows in
  /// the mode it keeps, and is never switched off in front of the user.
  bool get settled;

  /// What it sees now, in words, for the scenes' debug tab.
  String get state;
}
