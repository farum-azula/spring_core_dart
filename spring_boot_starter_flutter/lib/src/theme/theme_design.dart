import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_color_scheme.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// What a theme's palette is made from when it is not Flutter's baseline:
/// the seed color, the variant of the algorithm and the contrast.
@immutable
final class ColorSchemeSpec {
  /// A palette of [brightness] from [seedColor], [schemeVariant] and
  /// [contrast]; each may be `null` for the design's default.
  const ColorSchemeSpec({
    required this.brightness,
    this.seedColor,
    this.schemeVariant,
    this.contrast,
  });

  /// Whether the palette is light or dark.
  final Brightness brightness;

  /// `seed-color`; `null` when not set.
  final Color? seedColor;

  /// `scheme-variant` as the design names it (`tonalSpot`); `null` when
  /// not set.
  final String? schemeVariant;

  /// `contrast`, from -1 to 1; `null` when not set.
  final double? contrast;

  /// Whether nothing is set: the palette is Flutter's baseline, which
  /// needs no design.
  bool get isBaseline =>
      seedColor == null && schemeVariant == null && contrast == null;
}

/// What a design library adds to the themes read from
/// `spring.flutter.theme.*`: a palette made from a seed color, the theme
/// properties only its widgets have, and its page transitions.
///
/// `spring_boot_starter_flutter` knows no design: an app of
/// `spring.flutter.app.type: widgets` has its themes, its palette and its
/// text styles without Material or Cupertino in the build. A design
/// starter (`spring_boot_starter_flutter_material`,
/// `spring_boot_starter_flutter_cupertino`) adds one of these; a library of
/// your own design can too.
///
/// The themes are read before any bean exists (the splash of the start is
/// in them), so a design is not a bean: its starter lists it in the
/// factories of its module.
///
/// ```dart
/// // lib/spring_auto_configuration.dart of the design's package
/// @AutoConfigurationModule(factories: [OceanDesign()])
/// final BeanModule oceanAutoConfiguration = $oceanBeans;
/// ```
abstract interface class ThemeDesign {
  /// The value of `spring.flutter.app.type` this is the design of
  /// (`material`, `cupertino`).
  String get appType;

  /// The top-level theme properties only this design reads, as written
  /// (`components`, `visual-density`). A theme that has one without the
  /// design in the application fails the start.
  List<String> get themeProperties;

  /// The names `scheme-variant` may have (`tonalSpot`, `vibrant`); empty
  /// when the design has one way to make a palette.
  List<String> get schemeVariants;

  /// The palette [spec] describes. Called only for a spec that sets a seed
  /// color, a variant or a contrast: without them a theme has
  /// [SpringColorScheme.baseline].
  SpringColorScheme colorScheme(ColorSchemeSpec spec);

  /// The page transition of [type] when it is this design's (`zoom` is
  /// Material's, `cupertino` Cupertino's); `null` for the others.
  PageTransitionsBuilder? pageTransition(PageTransitionType type);

  /// Reads the design's part of [theme] now, so that a wrong value fails
  /// the start and not the first screen that uses it. Throws a
  /// [ThemePropertyException] naming the property.
  void check(SpringThemeData theme);
}

/// The designs the themes of an application are read with: the
/// [ThemeDesign]s of its starters and the type of its app.
///
/// `SpringThemes` gets them from the application's factories; a test
/// passes its own (`SpringThemes(properties, designs: ThemeDesigns(all:
/// [MaterialThemeDesign()]))`). Apps do not use it otherwise.
@immutable
final class ThemeDesigns {
  /// The designs [all], for an app of [appType] (`widgets` by default);
  /// `null` for an app whose type is not set, which is the type of its
  /// one design.
  const ThemeDesigns({this.all = const [], this.appType = 'widgets'});

  /// The designs of [factories], for the app type of [environment]
  /// (`spring.flutter.app.type`; not set: the one design's).
  factory ThemeDesigns.of(
    SpringFactories factories,
    PropertyResolver environment,
  ) => ThemeDesigns(
    all: factories.load<ThemeDesign>(),
    appType: switch (environment.getProperty('spring.flutter.app.type')) {
      final type? when type.trim().isNotEmpty => type.trim(),
      _ => null,
    },
  );

  /// No design: Flutter's baseline palette, no design's properties.
  static const none = ThemeDesigns();

  /// The theme properties of the design starters of this family, by
  /// canonical name, with the starter that reads each.
  ///
  /// A theme may have them in an application without that starter: a
  /// theme of a library (a design system) has the values for the apps
  /// that use Material or Cupertino, and an app of another design simply
  /// does not show them, as Flutter shows no `ThemeData` outside a
  /// `MaterialApp`. They are accepted there and not checked; their key is
  /// still checked, so `componets` fails the start.
  ///
  /// `splash` is one of them only as a single value (Material's ink
  /// splash); a map is the splash of the start, which every app reads.
  static const _starters = {
    'components': ('components', 'spring_boot_starter_flutter_material'),
    'visualdensity': ('visual-density', 'spring_boot_starter_flutter_material'),
    'taptargetsize': (
      'tap-target-size',
      'spring_boot_starter_flutter_material',
    ),
    'splash': ('splash', 'spring_boot_starter_flutter_material'),
    'cupertino': ('cupertino', 'spring_boot_starter_flutter_cupertino'),
  };

  /// The canonical names of the theme properties of this family's design
  /// starters ([_starters]): accepted in every theme.
  static Set<String> get familyProperties => _starters.keys.toSet();

  /// The design properties [names] (canonical top-level names) that no
  /// design of the application reads: not shown, not checked. Each with
  /// the starter that reads it.
  Map<String, String> unread(Iterable<String> names) => {
    for (final name in names)
      if (_starters[name] case (final written, final starter) when !reads(name))
        written: starter,
  };

  /// Every design of the application, in the order of its starters.
  final List<ThemeDesign> all;

  /// `spring.flutter.app.type`; `null` when it is not set.
  final String? appType;

  /// The design of the app's type; `null` for `widgets`. When the type is
  /// not set, the one design of the application (the app widget is then
  /// its own too), else none.
  ThemeDesign? get own {
    final appType = this.appType;
    if (appType == null) {
      return all.length == 1 ? all.single : null;
    }
    final type = ThemeValues.canonical(appType);
    for (final design in all) {
      if (ThemeValues.canonical(design.appType) == type) {
        return design;
      }
    }
    return null;
  }

  // The app's own design first.
  List<ThemeDesign> get _ordered => [
    ?own,
    for (final design in all)
      if (!identical(design, own)) design,
  ];

  /// The canonical names of the top-level theme properties the designs
  /// read.
  Set<String> get themeProperties => {
    for (final design in all)
      for (final property in design.themeProperties)
        ThemeValues.canonical(property),
  };

  /// Whether a design reads top-level theme property [name].
  bool reads(String name) =>
      themeProperties.contains(ThemeValues.canonical(name));

  /// What to add for theme property [name] no design here reads, as the
  /// end of an error message; empty when it is no design's property.
  static String starterOf(String name) =>
      switch (_starters[ThemeValues.canonical(name)]) {
        (_, final starter) =>
          ' ($name is read by $starter: add it to the '
              'dependencies)',
        null => '',
      };

  /// `scheme-variant` [value] as the design that makes the palettes names
  /// it; `null` when no design has it.
  String? schemeVariant(String value) {
    final wanted = ThemeValues.canonical(value);
    for (final design in _ordered) {
      for (final variant in design.schemeVariants) {
        if (ThemeValues.canonical(variant) == wanted) {
          return variant;
        }
      }
    }
    return null;
  }

  /// What `scheme-variant` may be, for an error message.
  String get schemeVariants => all.isEmpty
      ? _needsDesign
      : {
          for (final design in _ordered) ...design.schemeVariants,
        }.join(', ');

  static const _needsDesign =
      'a design starter in the dependencies: seed-color, scheme-variant and '
      'contrast make a Material 3 palette, which '
      'spring_boot_starter_flutter_material (or '
      'spring_boot_starter_flutter_cupertino) calculates. Without one, set '
      'the roles under colors';

  /// The palette of [spec] before the roles of `colors.*`: Flutter's
  /// baseline when the spec sets nothing, else the one the app's design
  /// (or, in an app of another type, the first design) makes. Throws a
  /// [ThemePropertyException] for [property] with [value] when the spec
  /// needs a design and the application has none.
  SpringColorScheme colorScheme(
    ColorSchemeSpec spec, {
    required String property,
    required String value,
  }) {
    if (spec.isBaseline) {
      return SpringColorScheme.baseline(spec.brightness);
    }
    final designs = _ordered;
    if (designs.isEmpty) {
      throw ThemePropertyException(property, value, _needsDesign);
    }
    return designs.first.colorScheme(spec);
  }

  /// The page transition of [type] a design has; `null` when none does.
  PageTransitionsBuilder? pageTransition(PageTransitionType type) {
    for (final design in _ordered) {
      final builder = design.pageTransition(type);
      if (builder != null) {
        return builder;
      }
    }
    return null;
  }

  /// Has every design read its part of [theme].
  void check(SpringThemeData theme) {
    for (final design in all) {
      design.check(theme);
    }
  }
}
