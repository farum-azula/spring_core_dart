import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart' show AppType;
import 'package:spring_boot_starter_flutter/src/sqlite_directories.dart'
    show SqliteLocation;

// The settings of the starter that are properties. Each class is the one
// place that names its keys, describes them (the editor metadata is made
// from the fields) and, bound by the Binder, is what the code reads.

/// The app widget `SpringApp` builds, `spring.flutter.app.*`.
@ConfigurationProperties('spring.flutter.app')
final class FlutterAppProperties {
  /// Settings with these values; the defaults are those of an app without
  /// any property.
  const FlutterAppProperties({
    this.type = AppType.widgets,
    this.title,
    this.debugBanner = true,
    this.locales,
  });

  /// The kind of app widget SpringApplicationWidget builds.
  final AppType type;

  /// The title of the app (task switcher, browser tab).
  final String? title;

  /// Whether the debug banner shows in debug builds.
  final bool debugBanner;

  /// The locales the app supports, as language tags. Default: the languages
  /// of the messages files.
  final List<String>? locales;
}

/// Settings of the whole starter that sit directly under `spring.flutter`.
@ConfigurationProperties('spring.flutter')
final class FlutterProperties {
  /// Settings with these values.
  const FlutterProperties({this.scanOsEnvironment = false});

  /// Whether the operating system environment is read as properties. The
  /// application reads it before it has an environment, from the
  /// `--dart-define` values (`scanOsEnvironmentIn`).
  final bool scanOsEnvironment;
}

/// The lifecycle of the app, `spring.flutter.lifecycle.*`.
@ConfigurationProperties('spring.flutter.lifecycle')
final class FlutterLifecycleProperties {
  /// Settings with these values.
  const FlutterLifecycleProperties({this.pauseInBackground = true});

  /// Whether scheduled work pauses while the app is in the background.
  final bool pauseInBackground;
}

/// The loading of the fonts of the app, `spring.flutter.fonts.*`.
@ConfigurationProperties('spring.flutter.fonts')
final class FlutterFontsProperties {
  /// Settings with these values.
  const FlutterFontsProperties({this.autoLoad = true, this.exclude});

  /// Whether the fonts named by the theme are loaded from the assets.
  final bool autoLoad;

  /// Asset globs the font loader skips.
  final List<String>? exclude;
}

/// The desktop window as text, `spring.flutter.desktop.window.*`; the
/// starter turns the sizes and the title bar into `DesktopWindowSettings`.
@ConfigurationProperties('spring.flutter.desktop.window')
final class DesktopWindowProperties {
  /// Settings with these values.
  const DesktopWindowProperties({
    this.title,
    this.titleBar = 'default',
    this.initialSize,
    this.minSize,
    this.maxSize,
  });

  /// The prefix of the properties.
  static const prefix = 'spring.flutter.desktop.window';

  /// The title of the desktop window.
  final String? title;

  /// How the title bar of the desktop window looks: `default` (the
  /// platform's), `transparent` (the app draws under a transparent title
  /// bar) or `hidden` (no title bar; the app draws its own).
  @PropertyValues(['default', 'transparent', 'hidden'])
  final String titleBar;

  /// The size of the window at start, as WIDTHxHEIGHT in logical pixels,
  /// e.g. 1280x800.
  final String? initialSize;

  /// The smallest size of the window, as WIDTHxHEIGHT.
  final String? minSize;

  /// The largest size of the window, as WIDTHxHEIGHT.
  final String? maxSize;
}

/// The dev server of `flutter run` on the web, `spring.flutter.web.*`.
///
/// Nothing reads it at run time: the generator reads these keys from the
/// configuration files at build time and writes `web_dev_config.yaml`. The
/// class describes them for editors.
@ConfigurationProperties('spring.flutter.web')
final class FlutterWebProperties {
  /// Settings with these values; all unset by default.
  const FlutterWebProperties({
    this.host,
    this.port,
    this.baseHref,
    this.https,
    this.headers,
    this.contentSecurityPolicy,
    this.contentSecurityPolicyReportOnly,
    this.contentSecurityPolicyConnectSrc,
    this.proxy,
  });

  /// The address the dev server of flutter run on the web listens on, e.g.
  /// localhost or 0.0.0.0.
  final String? host;

  /// The port of the web dev server; 0 picks a free port.
  @Range(0, 65535)
  @WarnValues(
    [
      1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69, 77,
      79, 87, 95, 101, 102, 103, 104, 109, 110, 111, 113, 115, 117, 119, 123,
      135, 137, 139, 143, 161, 179, 389, 427, 465, 512, 513, 514, 515, 526,
      530, 531, 532, 540, 548, 554, 556, 563, 587, 601, 636, 989, 990, 993,
      995, 1719, 1720, 1723, 2049, 3659, 4045, 4190, 5060, 5061, 6000, 6566,
      6665, 6666, 6667, 6668, 6669, 6679, 6697, 10080, //
    ],
    "Browsers refuse to open this port (Chromium's list of blocked ports).",
  )
  final int? port;

  /// The path the app is served under; starts and ends with /.
  final String? baseHref;

  /// TLS for the web dev server.
  final FlutterWebHttps? https;

  /// A header added to every response of the web dev server.
  final Map<String, String>? headers;

  /// The Content-Security-Policy header of the web dev server.
  final String? contentSecurityPolicy;

  /// The report-only Content-Security-Policy header.
  final String? contentSecurityPolicyReportOnly;

  /// Origins added to the `connect-src` of spa mode's ready policy: the APIs
  /// the app calls, a provider's endpoints on other hosts. Default: none.
  final List<String>? contentSecurityPolicyConnectSrc;

  /// Rules that forward requests of the dev server to another server.
  final List<FlutterWebProxyRule>? proxy;
}

/// TLS of the web dev server, `spring.flutter.web.https.*`.
final class FlutterWebHttps {
  /// Settings with these values.
  const FlutterWebHttps({this.certPath, this.certKeyPath});

  /// The TLS certificate (PEM) of the web dev server.
  final String? certPath;

  /// The private key (PEM) of the certificate.
  final String? certKeyPath;
}

/// One forwarding rule of the web dev server, `spring.flutter.web.proxy[n]`.
final class FlutterWebProxyRule {
  /// A rule with these values; each sets exactly one of prefix and regex.
  const FlutterWebProxyRule({
    this.prefix,
    this.regex,
    this.replace,
    this.target,
  });

  /// Rule `n` matches paths starting with it (`/api/`). Default: none.
  final String? prefix;

  /// Or the paths matching it; each rule sets exactly one of `prefix` and
  /// `regex`. Default: none.
  final String? regex;

  /// The forwarded path: the matched part replaced, `$1` for the first
  /// group. Default: the path unchanged.
  final String? replace;

  /// Where requests matching rule `n` are forwarded
  /// (`http://localhost:8080`). Default: none.
  final String? target;
}

/// The development switches under `spring.devtools.restart`.
@ConfigurationProperties('spring.devtools.restart')
final class FlutterRestartProperties {
  /// Settings with these values.
  const FlutterRestartProperties({this.enabled = true});

  /// A hot reload restarts the context when the generated code changed:
  /// beans, annotations or `lib/resources/`.
  final bool enabled;
}

/// The data source properties the starter reads to put SQLite files in the
/// app's directory, `spring.datasource.*`; the rest belongs to
/// `spring_boot_starter_data`.
@ConfigurationProperties('spring.datasource')
final class FlutterDataSourceProperties {
  /// Settings with these values.
  const FlutterDataSourceProperties({
    this.url,
    this.sqlite = const FlutterSqliteProperties(),
  });

  /// The prefix of the unnamed data source.
  static const prefix = 'spring.datasource';

  /// The database URL; the Flutter starter reads it to put SQLite files in
  /// the app's directory (see `spring_boot_starter_data`).
  final String? url;

  /// The SQLite settings the starter provides.
  final FlutterSqliteProperties sqlite;
}

/// The SQLite setting the starter reads, `spring.datasource.sqlite.location`;
/// the others (`base-directory`, `isolate`), which the starter sets, are
/// described by `spring_boot_starter_data`.
final class FlutterSqliteProperties {
  /// Settings with these values.
  const FlutterSqliteProperties({this.location = SqliteLocation.support});

  /// Which directory of the app holds the databases, the one the starter
  /// sets `base-directory` to; any other value stops the start, naming
  /// these three.
  final SqliteLocation location;
}

/// The named data sources, `spring.datasources.<name>.*`.
@ConfigurationProperties('spring')
final class FlutterDataSourcesProperties {
  /// Settings with these values.
  const FlutterDataSourcesProperties({this.datasources});

  /// The prefix of the named data sources.
  static const prefix = 'spring.datasources';

  /// The named databases; each is read like `spring.datasource`.
  final Map<String, FlutterDataSourceProperties>? datasources;
}
