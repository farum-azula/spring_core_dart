import 'package:spring_boot_starter_flutter_security/src/web/browser_page_stub.dart'
    if (dart.library.js_interop) 'package:spring_boot_starter_flutter_security/src/web/browser_page_web.dart'
    as platform;

/// The browser page a Flutter web app runs in: its address, its cookies,
/// and leaving it for another page.
///
/// The web login needs exactly these three things from the browser: the
/// page's origin (is the server another one?), the CSRF token of the
/// server's `XSRF-TOKEN` cookie (scripts may read it; the session cookie
/// is `HttpOnly` and stays out of reach), and navigating the whole page
/// to the server's login and the provider's logout. They sit behind this
/// small interface so the login and the transport run in tests on the
/// VM, with a fake page.
///
/// The package declares the page as a bean on the web (`browserPage`);
/// tests declare their own:
///
/// ```dart
/// final class FakePage implements BrowserPage {
///   final cookies = <String, String>{};
///   final visited = <Uri>[];
///
///   @override
///   Uri get location => Uri.parse('http://localhost:5050/');
///
///   @override
///   String? cookie(String name) => cookies[name];
///
///   @override
///   void navigate(Uri url) => visited.add(url);
/// }
/// ```
///
/// Spring has no counterpart: Java has no browser page.
abstract interface class BrowserPage {
  /// The page the app runs in (`window` and `document` of the browser).
  ///
  /// Throws an [UnsupportedError] outside a browser.
  factory BrowserPage() => platform.createBrowserPage();

  /// The page's address (`window.location.href`).
  Uri get location;

  /// The value of the page's cookie [name] (from `document.cookie`,
  /// percent-decoded), or `null`. `HttpOnly` cookies are never seen.
  String? cookie(String name);

  /// Leaves the app for [url] (`window.location.assign`): the app stops,
  /// and starts again when the browser comes back.
  void navigate(Uri url);
}

/// The value of cookie [name] in [cookies], a `document.cookie` string
/// (`a=1; XSRF-TOKEN=abc`), percent-decoded; `null` when it is missing.
String? cookieValue(String cookies, String name) {
  for (final pair in cookies.split(';')) {
    final equals = pair.indexOf('=');
    if (equals > 0 && pair.substring(0, equals).trim() == name) {
      final value = pair.substring(equals + 1).trim();
      try {
        return Uri.decodeComponent(value);
      } on ArgumentError {
        return value;
      }
    }
  }
  return null;
}
