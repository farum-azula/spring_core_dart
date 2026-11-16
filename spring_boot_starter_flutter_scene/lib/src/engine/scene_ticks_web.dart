import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Calls [beat] on every frame of the browser (`requestAnimationFrame`)
/// until the returned function is called; [period] is for the views to
/// skip the frames they are not due at.
///
/// A timer beats out of step with the screen: a beat that lands just
/// before the browser shows a frame keeps that frame from being shown in
/// time (an iPhone scrolling a page with two scenes showed 43 frames a
/// second of 60), and Safari fires a timer of 16 ms some 50 times a
/// second. On the frames of the browser the scenes draw with the page's
/// frame, before the browser shows it.
void Function() startSceneTicks(Duration period, void Function() beat) {
  final window = globalContext;
  var on = true;
  JSAny? request;
  late final JSFunction frame;
  frame = ((JSAny? _) {
    if (!on) {
      return;
    }
    request = window.callMethod<JSAny?>('requestAnimationFrame'.toJS, frame);
    beat();
  }).toJS;
  request = window.callMethod<JSAny?>('requestAnimationFrame'.toJS, frame);
  return () {
    on = false;
    window.callMethod<JSAny?>('cancelAnimationFrame'.toJS, request);
  };
}
