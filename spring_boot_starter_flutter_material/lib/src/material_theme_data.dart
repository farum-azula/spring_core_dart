import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter/theme_design.dart';
import 'package:spring_boot_starter_flutter_material/src/material_color_scheme.dart';
import 'package:spring_boot_starter_flutter_material/src/material_text_theme.dart';
import 'package:spring_boot_starter_flutter_material/src/spring_theme_extension.dart';
import 'package:spring_boot_starter_flutter_material/src/theme_components.dart';

final _themes = Expando<ThemeData>('SpringThemeData.toMaterial');
final _schemes = Expando<ColorScheme>('SpringThemeData.materialColorScheme');

/// A theme of `spring.flutter.theme.*` as Material sees it: its
/// `ThemeData`, its `ColorScheme` and the properties only Material's
/// widgets have (`visual-density`, `tap-target-size`, the ink `splash`).
///
/// An app rarely calls it: `MaterialApp` gets its themes from the
/// `MaterialThemes` bean, and a widget reads `Theme.of(context)`. It is for
/// a theme shown apart from the app's, such as a preview:
///
/// ```dart
/// Theme(
///   data: themes.data('ocean').toMaterial(),
///   child: const BookCard(),
/// );
/// ```
extension MaterialSpringThemeData on SpringThemeData {
  /// The theme as Material's `ThemeData`, made once; it carries this
  /// theme as a [SpringThemeExtension]. The `ThemeCustomizer` beans are
  /// not applied here but by the `MaterialThemes` bean.
  ///
  /// Throws a [ThemePropertyException] naming the property when a value
  /// under `components.*` is invalid.
  ThemeData toMaterial() => _themes[this] ??= _components(_base());

  /// The palette as Material's `ColorScheme`: every role of
  /// [SpringThemeData.colorScheme].
  ColorScheme get materialColorScheme =>
      _schemes[this] ??= MaterialColorSchemes.of(
        ColorSchemeSpec(
          brightness: brightness,
          seedColor: seedColor,
          schemeVariant: schemeVariant,
          contrast: contrast,
        ),
      ).withRolesOf(colorScheme);

  /// `visual-density`: `adaptive`, `standard`, `comfortable` or
  /// `compact`; `null` when not set.
  VisualDensity? get visualDensity => properties.read(
    'visualdensity',
    (v) => switch (ThemeValues.canonical(v)) {
      'adaptive' => VisualDensity.adaptivePlatformDensity,
      'standard' => VisualDensity.standard,
      'comfortable' => VisualDensity.comfortable,
      'compact' => VisualDensity.compact,
      _ => null,
    },
    'adaptive, standard, comfortable or compact',
  );

  /// `tap-target-size`, the minimum size of what can be tapped: `padded`
  /// or `shrinkWrap`; `null` when not set.
  MaterialTapTargetSize? get tapTargetSize => properties.read(
    'taptargetsize',
    (v) => ThemeValues.enumValue(MaterialTapTargetSize.values, v),
    'padded or shrinkWrap',
  );

  /// `splash` as one value, the ink splash of taps: `ripple`, `sparkle`
  /// or `none`; `null` when not set. (A `splash` map is what shows while
  /// the application starts, [SpringThemeData.splash].)
  InteractiveInkFeatureFactory? get splashFactory => properties.read(
    'splash',
    (v) => switch (ThemeValues.canonical(v)) {
      'ripple' => InkRipple.splashFactory,
      'sparkle' => InkSparkle.splashFactory,
      'none' => NoSplash.splashFactory,
      _ => null,
    },
    'ripple, sparkle or none',
  );

  // The theme before its components: only what the properties set
  // differs from Flutter's own Material 3 theme.
  ThemeData _base() {
    TextStyle? style(String name) => textStyles[name]?.toStyle();
    final builder = pageTransition;
    return ThemeData(
      colorScheme: materialColorScheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      textTheme: TextTheme(
        displayLarge: style('displaylarge'),
        displayMedium: style('displaymedium'),
        displaySmall: style('displaysmall'),
        headlineLarge: style('headlinelarge'),
        headlineMedium: style('headlinemedium'),
        headlineSmall: style('headlinesmall'),
        titleLarge: style('titlelarge'),
        titleMedium: style('titlemedium'),
        titleSmall: style('titlesmall'),
        bodyLarge: style('bodylarge'),
        bodyMedium: style('bodymedium'),
        bodySmall: style('bodysmall'),
        labelLarge: style('labellarge'),
        labelMedium: style('labelmedium'),
        labelSmall: style('labelsmall'),
      ),
      visualDensity: visualDensity,
      materialTapTargetSize: tapTargetSize,
      splashFactory: splashFactory,
      // `platform` (and none set by a design): Flutter's own per platform.
      pageTransitionsTheme: builder == null || isPlatformPageTransition
          ? null
          : PageTransitionsTheme(
              builders: {
                for (final platform in TargetPlatform.values) platform: builder,
              },
            ),
      // A background shows through the screens.
      scaffoldBackgroundColor: background == null ? null : Colors.transparent,
      extensions: [SpringThemeExtension(this)],
    );
  }

  // A text style of [textTheme] by name, or `code`: the theme's
  // monospaced style over body medium.
  TextStyle _styleIn(TextTheme textTheme, String style) {
    if (ThemeValues.canonical(style) == 'code') {
      // Falls back to the theme's own font where the monospaced one is
      // missing (`monospace` is not a family on every platform).
      return code
          .applyTo(textTheme.bodyMedium)
          .copyWith(
            fontFamily: code.fontFamily,
            fontFamilyFallback: [?fontFamily, ...?fontFamilyFallback],
          );
    }
    return textTheme.styleNamed(style) ??
        (throw ArgumentError.value(
          style,
          'style',
          'a TextTheme style or code',
        ));
  }

  ThemeReader _componentReader(ThemeData theme, ThemeComponent component) =>
      ThemeReader(
        theme: this,
        properties: properties,
        root: 'components.${ThemeValues.canonical(component.name)}',
        label: component.name,
        namedStyle: (name) => _styleIn(theme.textTheme, name),
        shapeToken: component.shapeToken,
        topShape: component.topShape,
      );

  // Applies each component the properties mention (or that follows a
  // shape token the theme changed), then checks its keys.
  ThemeData _components(ThemeData theme) {
    ThemeReader other(String name) =>
        _componentReader(theme, themeComponents[ThemeValues.canonical(name)]!);
    var result = theme;
    for (final component in themeComponents.values) {
      final reader = _componentReader(theme, component);
      final themed =
          reader.has || (component.base != null && other(component.base!).has);
      if (!themed) {
        continue;
      }
      try {
        result = component.apply(result, reader, other);
      } on AssertionError catch (e) {
        // Flutter's own rule for a combination of values.
        throw ThemePropertyException(
          properties.propertyName(reader.root),
          '',
          'values Flutter accepts together in ${component.name}: '
              '${e.message ?? e}',
        );
      }
      reader.checkUnknown();
    }
    return result;
  }
}
