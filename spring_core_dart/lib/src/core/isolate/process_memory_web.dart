import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The JavaScript heap in use, in bytes, where the browser tells it
/// (`performance.memory`, Chromium); `null` elsewhere.
int? processMemory() {
  try {
    final performance = globalContext['performance'];
    if (performance.isUndefinedOrNull) {
      return null;
    }
    final memory = (performance! as JSObject)['memory'];
    if (memory.isUndefinedOrNull) {
      return null;
    }
    final used = (memory! as JSObject)['usedJSHeapSize'];
    return used.isA<JSNumber>()
        ? (used! as JSNumber).toDartDouble.toInt()
        : null;
  } on Object {
    return null;
  }
}
