// The page of a Flutter web app in spa mode, through dart:js_interop (no
// package).
import 'dart:js_interop';

import 'package:spring_boot_starter_flutter_security/src/web/browser_page.dart';
import 'package:spring_boot_starter_flutter_security/src/web/spa_browser_page.dart';

@JS('document')
external _Document get _document;

@JS('window')
external _Window get _window;

extension type _Document._(JSObject _) implements JSObject {
  external String get cookie;
  external String get baseURI;
}

extension type _Window._(JSObject _) implements JSObject {
  external _Location get location;
  external _History get history;
  external _Storage get sessionStorage;
  external _Storage get localStorage;
}

extension type _Location._(JSObject _) implements JSObject {
  external String get href;
  external void assign(String url);
}

extension type _History._(JSObject _) implements JSObject {
  external JSAny? get state;
  external void replaceState(JSAny? data, String unused, String url);
}

extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// The page of `window`, `document` and `history`.
SpaBrowserPage createSpaBrowserPage() => _WindowSpaPage();

final class _WindowSpaPage implements SpaBrowserPage {
  _WindowSpaPage();

  @override
  Uri get location => Uri.parse(_window.location.href);

  @override
  Uri get baseUri => Uri.parse(_document.baseURI);

  @override
  String? cookie(String name) => cookieValue(_document.cookie, name);

  @override
  void navigate(Uri url) => _window.location.assign('$url');

  @override
  void replaceLocation(Uri url) {
    final history = _window.history;
    // Keeps the state of Flutter's router, changes only the address.
    history.replaceState(history.state, '', '$url');
  }

  @override
  late final BrowserStorage sessionStorage = _storage(
    () => _window.sessionStorage,
  );

  @override
  late final BrowserStorage localStorage = _storage(() => _window.localStorage);

  // A browser that refuses the storage throws on the access (a
  // SecurityError): the page keeps it in memory instead.
  static BrowserStorage _storage(_Storage Function() storage) {
    try {
      return _WebStorage(storage());
    } on Object {
      return InMemoryBrowserStorage();
    }
  }
}

final class _WebStorage implements BrowserStorage {
  _WebStorage(this._storage);

  final _Storage _storage;

  @override
  String? getItem(String key) {
    try {
      return _storage.getItem(key);
    } on Object {
      return null;
    }
  }

  @override
  void setItem(String key, String value) {
    try {
      _storage.setItem(key, value);
    } on Object {
      // Full or refused: nothing kept.
    }
  }

  @override
  void removeItem(String key) {
    try {
      _storage.removeItem(key);
    } on Object {
      // Refused: nothing to remove.
    }
  }
}
