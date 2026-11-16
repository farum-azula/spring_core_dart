import 'dart:js_interop';

@JS('matchMedia')
external _MediaQueryList? _matchMedia(String query);

extension type _MediaQueryList._(JSObject _) implements JSObject {
  external bool get matches;
}

/// Whether the device's main pointer is a finger: in a browser, what CSS
/// calls a coarse pointer (a phone, a tablet; not a laptop with a touch
/// screen and a mouse).
bool get touchScreen => _matchMedia('(pointer: coarse)')?.matches ?? false;
