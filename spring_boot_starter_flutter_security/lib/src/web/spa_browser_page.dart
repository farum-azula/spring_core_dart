import 'package:spring_boot_starter_flutter_security/src/web/browser_page.dart';
import 'package:spring_boot_starter_flutter_security/src/web/spa_browser_page_stub.dart'
    if (dart.library.js_interop) 'package:spring_boot_starter_flutter_security/src/web/spa_browser_page_web.dart'
    as platform;

/// The browser page of a Flutter web app that logs in by itself
/// (`spring.flutter.security.web.mode=spa`): besides the address and the
/// navigation of a [BrowserPage], the app's base address, the address bar
/// without a reload, and the page's two key-value stores.
///
/// The browser login leaves the page for the provider and starts again
/// when the provider sends it back, so it needs a place that survives
/// that round trip (`sessionStorage`, one per tab) for the request it
/// sent, a way to remove the answer's `code` and `state` from the address
/// bar (`history.replaceState`), and a hint that this browser was logged
/// in (`localStorage`), which never holds a token. They sit behind this
/// interface so the login runs in tests on the VM, with a fake page.
///
/// The package declares the page as a bean in spa mode (`spaBrowserPage`);
/// tests declare their own.
///
/// Spring has no counterpart: Java has no browser page.
abstract interface class SpaBrowserPage implements BrowserPage {
  /// The page the app runs in (`window`, `document`, `history` and the
  /// storages of the browser).
  ///
  /// Throws an [UnsupportedError] outside a browser.
  factory SpaBrowserPage() => platform.createSpaBrowserPage();

  /// The address the app is served under (`document.baseURI`: the page's
  /// origin and the `<base href>` of `index.html`), such as
  /// `https://neon.books/shop/`. `{baseUrl}` of the redirect URI templates
  /// is this address without its last `/`.
  Uri get baseUri;

  /// Shows [url] (same origin) in the address bar without loading it
  /// (`history.replaceState`): the app keeps running, and the entry of
  /// the current page in the history is replaced, not added.
  void replaceLocation(Uri url);

  /// The tab's own store (`sessionStorage`): survives reloads and the
  /// round trip to another site, gone with the tab, not shared with other
  /// tabs.
  BrowserStorage get sessionStorage;

  /// The origin's store (`localStorage`): shared by every tab of the
  /// origin, kept after the browser closes. Readable by any script of the
  /// page: never for tokens.
  BrowserStorage get localStorage;
}

/// A key-value store of strings in the browser (`sessionStorage`,
/// `localStorage`).
///
/// A browser may refuse the storages (privacy settings, a sandboxed
/// frame): then [getItem] answers `null` and the writes do nothing, so a
/// login still works within the page, only without what the storage would
/// have kept.
abstract interface class BrowserStorage {
  /// The value of [key], or `null`.
  String? getItem(String key);

  /// Stores [value] under [key].
  void setItem(String key, String value);

  /// Removes [key].
  void removeItem(String key);
}

/// A [BrowserStorage] in memory, for tests and where the browser refuses
/// its storages.
final class InMemoryBrowserStorage implements BrowserStorage {
  /// An empty store.
  InMemoryBrowserStorage();

  /// The entries, for tests.
  final Map<String, String> items = {};

  @override
  String? getItem(String key) => items[key];

  @override
  void setItem(String key, String value) => items[key] = value;

  @override
  void removeItem(String key) => items.remove(key);
}
