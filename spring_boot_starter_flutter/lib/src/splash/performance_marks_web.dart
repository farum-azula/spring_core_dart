import 'dart:js_interop';

@JS('performance.mark')
external JSAny? _mark(JSString name);

@JS('performance.measure')
external JSAny? _measure(JSString name, JSString start);

/// Marks [name] in the browser's performance timeline.
void performanceMark(String name) {
  try {
    _mark(name.toJS);
  } on Object {
    // A browser without the User Timing API: nothing to mark.
  }
}

/// Measures [name] from [start] (a mark) to now.
void performanceMeasure(String name, String start) {
  try {
    _measure(name.toJS, start.toJS);
  } on Object {
    // A browser without the User Timing API, or no such mark.
  }
}
