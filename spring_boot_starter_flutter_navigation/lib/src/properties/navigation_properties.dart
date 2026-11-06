import 'package:spring_boot_dart/spring_boot_dart.dart';

// The settings of the starter that are properties. Each class is the one
// place that names its keys, describes them (the editor metadata is made
// from the fields) and, bound by the Binder, is what the code reads.

/// The app's navigation, `spring.flutter.navigation.*`.
@ConfigurationProperties('spring.flutter.navigation')
final class NavigationProperties {
  /// Settings with these values; the defaults are those of an app without
  /// any property.
  const NavigationProperties({
    this.initial,
    this.login,
    this.redirects,
    this.languages,
    this.web = const NavigationWebProperties(),
    this.deepLinks = const NavigationDeepLinkProperties(),
  });

  /// Where the app starts when the platform gives no address of its own
  /// (`/`), such as `/catalog`.
  final String? initial;

  /// Where a route that needs a logged-in user sends the others, such as
  /// `/login`.
  final String? login;

  /// Addresses that lead elsewhere, from path to path (`"[/]": /catalog`).
  final Map<String, String>? redirects;

  /// The languages with their own addresses, as language tags (`en, ja`):
  /// the first is the default, its addresses have no prefix; the others
  /// put theirs under `/<language>` (`/ja/catalog`). An address of a
  /// language sets the app's locale; the build's pages for search engines
  /// (`spring.flutter.web.seo.*`) are written in each of them.
  final List<String>? languages;

  /// The navigation in a browser.
  final NavigationWebProperties web;

  /// Links from outside the app that open it at a route.
  final NavigationDeepLinkProperties deepLinks;
}

/// Links from outside the app that open it at a route,
/// `spring.flutter.navigation.deep-links.*`.
///
/// The generator writes the platforms' files from these keys (iOS's
/// `Info.plist` and `Runner.entitlements`, Android's manifest, macOS's
/// `Info.plist`) and the files the domains serve
/// (`apple-app-site-association`, `assetlinks.json`); at run time only
/// [exclude] is read. A value for one platform goes into its profile file
/// (`application-ios.yml`, `application-android.yml`).
final class NavigationDeepLinkProperties {
  /// Settings with these values; no deep links by default.
  const NavigationDeepLinkProperties({
    this.enabled = true,
    this.scheme,
    this.domains,
    this.exclude,
    this.appId,
    this.package,
    this.sha256CertFingerprints,
  });

  /// Whether the deep links are written; `false` in a platform's profile
  /// turns them off there.
  final bool enabled;

  /// The app's own URL scheme (`neonbooks` for
  /// `neonbooks://catalog/books/1`). Not verified: another app may claim
  /// it, so links people share go through [domains].
  final String? scheme;

  /// The domains whose `https` links open the app (Universal Links on iOS,
  /// App Links on Android): host names, no scheme or path.
  final List<String>? domains;

  /// Path patterns (Spring's syntax) whose links do not open their screen;
  /// the app opens its first screen instead, as for a screen with
  /// `@RouteInfo(link: false)`.
  final List<String>? exclude;

  /// The iOS app id, Team ID and bundle ID (`ABCDE12345.com.example.app`);
  /// by default from the Xcode project.
  final String? appId;

  /// The Android package; by default the `applicationId` of the Gradle
  /// file.
  final String? package;

  /// The SHA-256 fingerprints of the keys the Android app is signed with
  /// (the upload key's and Google Play's), for `assetlinks.json`.
  final List<String>? sha256CertFingerprints;
}

/// The navigation in a browser, `spring.flutter.navigation.web.*`.
final class NavigationWebProperties {
  /// Settings with these values.
  const NavigationWebProperties({
    this.urlStrategy = NavigationUrlStrategy.path,
  });

  /// How the address bar shows the route: `path` (`/catalog/books/1`, the
  /// server must answer every path with the app) or `hash`
  /// (`/#/catalog/books/1`, Flutter's default).
  final NavigationUrlStrategy urlStrategy;
}

/// How a browser's address bar shows the route.
enum NavigationUrlStrategy {
  /// `/catalog/books/1`; the default. A static host must answer every path
  /// with `index.html` (or the build writes a page per path).
  path,

  /// `/#/catalog/books/1`, Flutter's own default.
  hash,
}
