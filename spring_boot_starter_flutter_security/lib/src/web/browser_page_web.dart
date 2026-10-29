// The page of a Flutter web app, through dart:js_interop (no package).
import 'dart:js_interop';

import 'package:spring_boot_starter_flutter_security/src/web/browser_page.dart';

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
  external String get href;
  external void assign(String url);
}

/// The page of `window` and `document`.
BrowserPage createBrowserPage() => const _WindowPage();

final class _WindowPage implements BrowserPage {
  const _WindowPage();

  @override
  Uri get location => Uri.parse(_window.location.href);

  @override
  String? cookie(String name) => cookieValue(_document.cookie, name);

  @override
  void navigate(Uri url) => _window.location.assign('$url');
}
