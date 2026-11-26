import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show Ordered;
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';

/// A look of the debug tools (the panel, the console, the frame meter
/// over the app): every colour and font they draw with, as a
/// [DebugStyle]. A bean of this type is a debug theme, offered by its
/// [name] beside those declared under `spring.flutter.debug.themes` and
/// the built-in `default` ([DefaultDebugTheme]);
/// `spring.flutter.debug.theme` selects the one the app starts with, and
/// the debug panel's Theme tab switches them live.
///
/// ```dart
/// @Component()
/// class SolarizedDebugTheme implements DebugTheme {
///   @override
///   String get name => 'solarized';
///
///   @override
///   DebugStyle styleOf(BuildContext context) => DebugStyle.fromApp(
///     context,
///     background: const Color(0xFF002B36),
///     foreground: const Color(0xFF93A1A1),
///     command: const Color(0xFFCB4B16),
///   );
/// }
/// ```
///
/// Debug themes are in the build only with the debug panel or the
/// console: with neither, none of their code is.
///
/// Spring has no counterpart.
abstract interface class DebugTheme {
  /// The name it is selected by (`spring.flutter.debug.theme`).
  String get name;

  /// Its style, under [context] (the app's theme is there, for a theme
  /// that builds on it as [DebugStyle.fromApp] does). Called whenever a
  /// debug tool draws: keep it cheap.
  DebugStyle styleOf(BuildContext context);
}

/// The built-in debug theme, `default` (the `defaultDebugTheme` bean):
/// [DebugStyle.fromApp], the app theme's colours and `code` font, the
/// logs in a terminal's palette for a dark background or a light one, the
/// commands orange. It comes after every other debug theme: one of the
/// same name replaces it.
final class DefaultDebugTheme implements DebugTheme, Ordered {
  /// The theme.
  const DefaultDebugTheme();

  /// Its name, the theme selected when `spring.flutter.debug.theme` is not
  /// set.
  static const String defaultName = 'default';

  @override
  String get name => defaultName;

  @override
  int get order => Ordered.lowestPrecedence;

  @override
  DebugStyle styleOf(BuildContext context) => DebugStyle.fromApp(context);
}
