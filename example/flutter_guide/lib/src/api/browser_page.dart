import 'package:neon_books_app/src/api/browser_page_stub.dart'
    if (dart.library.js_interop) 'package:neon_books_app/src/api/browser_page_web.dart'
    as page;
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// The page the web app runs in: its cookies and its address. A bean of
/// the `web` profile only (elsewhere there is no page); tests replace it.
///
/// - [cookie]: the server's `XSRF-TOKEN` cookie. The API (localhost:8080)
///   and the app (localhost:5050) are two origins of one site, and
///   cookies do not care about ports, so the page reads the cookie the
///   server set (`document.cookie`) and sends it back as the CSRF header.
///   The session cookie is `HttpOnly`: no script reads it, the browser
///   sends it by itself.
/// - [open]: leaves the app for another page (`window.location`), for
///   the server's Keycloak login and Keycloak's logout. The app starts
///   again when the browser comes back.
@Component()
@Profile(['web'])
class BrowserPage {
  /// The value of the page's cookie [name], or `null`.
  String? cookie(String name) => page.cookie(name);

  /// Navigates the whole page to [url].
  void open(Uri url) => page.open('$url');
}
