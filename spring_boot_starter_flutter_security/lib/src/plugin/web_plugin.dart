import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// The plugin's entry on the web, named in `pubspec.yaml`.
///
/// It registers nothing: a browser has no secure storage for tokens and
/// no login window of its own, so a Flutter web app logs in through its
/// server (`oauth2Login()` of the security starter), which keeps the
/// tokens, or in spa mode from the page itself, through `dart:js_interop`
/// (no platform channel). The entry only declares the web supported.
/// Apps never use it.
class SpringBootStarterFlutterSecurityWeb {
  SpringBootStarterFlutterSecurityWeb._();

  /// Called by Flutter's generated web plugin registrant; does nothing.
  static void registerWith(Registrar registrar) {}
}
