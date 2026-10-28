// The page of the web app, through dart:js_interop (no package needed).
import 'dart:js_interop';

@JS('document')
external _Document get _document;

@JS('window')
external _Window get _window;

extension type _Document._(JSObject _) implements JSObject {
  external String get cookie;
}

extension type _Window._(JSObject _) implements JSObject {
  external _Location get location;
}

extension type _Location._(JSObject _) implements JSObject {
  external void assign(String url);
}

/// The cookie [name] of `document.cookie` (`a=1; XSRF-TOKEN=abc`), decoded.
String? cookie(String name) {
  for (final pair in _document.cookie.split(';')) {
    final equals = pair.indexOf('=');
    if (equals > 0 && pair.substring(0, equals).trim() == name) {
      return Uri.decodeComponent(pair.substring(equals + 1).trim());
    }
  }
  return null;
}

void open(String url) => _window.location.assign(url);
