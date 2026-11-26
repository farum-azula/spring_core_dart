import 'package:flutter/widgets.dart';

/// Whether [route] is leaving: popped (its transition runs back), or
/// covered by the next page coming over it (its secondary transition runs;
/// a dialog does not run it). Its page fades, which the engine's canvas
/// cannot follow, so a scene on it goes at once instead of standing over
/// the next page until the transition ends.
bool sceneRouteLeaving(ModalRoute<Object?>? route) {
  if (route == null) {
    return false;
  }
  final own = route.animation?.status;
  final covered = route.secondaryAnimation?.status;
  return own == AnimationStatus.reverse ||
      (!route.isCurrent &&
          (covered == AnimationStatus.forward ||
              covered == AnimationStatus.completed));
}
