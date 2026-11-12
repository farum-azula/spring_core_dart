import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_cupertino/src/cupertino_theme_data.dart';

/// Changes, in code, every `CupertinoThemeData` made from the theme
/// properties, for apps of type `cupertino`.
///
/// Declare a bean that implements it; every customizer runs, in `@Order`,
/// on each Cupertino theme when it is first made (also on a replacing
/// `CupertinoThemeData` bean).
///
/// ```dart
/// // Bar backgrounds follow the theme's surface color.
/// @Component()
/// class SurfaceBars implements CupertinoThemeCustomizer {
///   @override
///   CupertinoThemeData customize(
///     CupertinoThemeData theme,
///     SpringThemeData spring,
///   ) => theme.copyWith(barBackgroundColor: spring.colorScheme.surface);
/// }
/// ```
///
/// Spring Boot (Java) adjusts its auto-configured objects the same way,
/// for example with a `Jackson2ObjectMapperBuilderCustomizer` bean.
abstract interface class CupertinoThemeCustomizer {
  /// Returns [theme] changed, usually with `copyWith`. [theme] was made
  /// from [spring], whose name, palette and tokens the change may depend
  /// on.
  CupertinoThemeData customize(
    CupertinoThemeData theme,
    SpringThemeData spring,
  );
}

/// The themes of the app as Cupertino's `CupertinoThemeData`: each theme
/// of `spring.flutter.theme.*` ([SpringThemes]) made Cupertino, then
/// changed by the [CupertinoThemeCustomizer] beans.
///
/// The starter creates it as a bean (`cupertinoThemes`), and its
/// `CupertinoApp` shows the theme picked. Inject it where a widget outside
/// that app needs a theme by name, a preview of every theme for example:
///
/// ```dart
/// for (final name in springThemes.names)
///   CupertinoTheme(
///     data: cupertinoThemes.theme(name),
///     child: ThemePreview(name),
///   ),
/// ```
///
/// An application's own `CupertinoThemeData` bean replaces the themes
/// made from the properties; the customizers change it too.
final class CupertinoThemes {
  /// The Cupertino themes of [themes], each changed by [customizers] in
  /// order. With [theme], every theme is that one instead of the one made
  /// from the properties; the starter passes the application's
  /// `CupertinoThemeData` bean here.
  CupertinoThemes(
    this.themes, {
    this.customizers = const [],
    CupertinoThemeData? theme,
  }) : _replacing = theme;

  /// The themes read from the properties.
  final SpringThemes themes;

  /// The customizers applied to every Cupertino theme, in order.
  final List<CupertinoThemeCustomizer> customizers;

  final CupertinoThemeData? _replacing;

  // By the theme as read, not by its name: themes loaded at run time are
  // read again, and are made Cupertino again.
  final _made = Expando<CupertinoThemeData>('CupertinoThemes');

  /// Theme [name] as a `CupertinoThemeData` ([cupertino] of the theme as
  /// read). Throws an `ArgumentError` for an unknown name.
  CupertinoThemeData theme(String name) => cupertino(themes.data(name));

  /// [spring] as a `CupertinoThemeData`: the one made from the properties
  /// (or the replacing one), then changed by the customizers; made once
  /// per theme read.
  CupertinoThemeData cupertino(SpringThemeData spring) =>
      _made[spring] ??= customizers.fold<CupertinoThemeData>(
        _replacing ?? spring.toCupertino(),
        (theme, customizer) => customizer.customize(theme, spring),
      );

  /// The Cupertino themes of [context]: its bean, else, for a context
  /// without the starter's auto-configuration (in a test), the themes of
  /// `SpringThemes.of(context)` made Cupertino, with no customizer.
  static CupertinoThemes of(ApplicationContext context) =>
      context.getBeansOfType<CupertinoThemes>().values.firstOrNull ??
      (_fallback[context] ??= CupertinoThemes(SpringThemes.of(context)));

  static final _fallback = Expando<CupertinoThemes>('CupertinoThemes.of');
}
