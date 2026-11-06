import 'package:spring_boot_starter_flutter/src/markdown/code_tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/src/theme/content_change.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_background.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_loader.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_splash.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_components.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_styles.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// What the properties set for one text style of a theme (font family,
/// size, weight, line height, letter spacing); whatever is left `null`
/// keeps Material's value.
///
/// A theme keeps one per text style the properties touch
/// ([SpringThemeData.textStyles]) and one for `code`. Apps read the
/// finished styles through [SpringThemeData.textStyle] rather than these
/// specs.
///
/// ```yaml
/// spring.flutter.theme.typography:
///   title-large: { weight: 600, size: 22, height: 1.3 }
/// ```
@immutable
final class SpringTextSpec {
  /// A spec of the given values; each `null` one keeps Material's value.
  const SpringTextSpec({
    this.fontFamily,
    this.size,
    this.weight,
    this.height,
    this.letterSpacing,
  });

  /// The font family; `null` for the typography's `font-family`.
  final String? fontFamily;

  /// The size in logical pixels.
  final double? size;

  /// The weight; it is also set on the `wght` axis that variable fonts
  /// use.
  final FontWeight? weight;

  /// The line height as a multiple of the size.
  final double? height;

  /// The letter spacing in logical pixels.
  final double? letterSpacing;

  /// Whether every value is `null`.
  bool get isEmpty =>
      fontFamily == null &&
      size == null &&
      weight == null &&
      height == null &&
      letterSpacing == null;

  /// A spec with [other]'s values where it has some, these elsewhere.
  SpringTextSpec merge(SpringTextSpec other) => SpringTextSpec(
    fontFamily: other.fontFamily ?? fontFamily,
    size: other.size ?? size,
    weight: other.weight ?? weight,
    height: other.height ?? height,
    letterSpacing: other.letterSpacing ?? letterSpacing,
  );

  /// The spec as a [TextStyle] with only the set values; a weight is also
  /// put on the `wght` axis, which variable fonts need.
  TextStyle toStyle() => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    fontVariations: weight == null
        ? null
        : [FontVariation('wght', weight!.value.toDouble())],
  );

  /// [base] (or an empty style) with the set values of this spec over it.
  TextStyle applyTo(TextStyle? base) =>
      (base ?? const TextStyle()).merge(toStyle());
}

/// The corner radii of the Material 3 shape scale, by canonical token
/// name; `full` (infinite) makes a stadium.
const m3ShapeScale = <String, double>{
  'none': 0,
  'extrasmall': 4,
  'small': 8,
  'medium': 12,
  'large': 16,
  'largeincreased': 20,
  'extralarge': 28,
  'extralargeincreased': 32,
  'extraextralarge': 48,
  'full': double.infinity,
};

/// The Material 3 elevation levels, `level0` to `level5`.
const m3Elevations = <String, double>{
  'level0': 0,
  'level1': 1,
  'level2': 3,
  'level3': 6,
  'level4': 8,
  'level5': 12,
};

/// The default spacing scale for the app's own widgets, which
/// `spring.flutter.theme.spacing` can change or extend.
const defaultSpacing = <String, double>{
  'xs': 4,
  's': 8,
  'm': 16,
  'l': 24,
  'xl': 32,
};

/// The 15 text styles of Material's `TextTheme`, by canonical name
/// (`displaylarge` ... `labelsmall`).
const textStyleNames = [
  'displaylarge', 'displaymedium', 'displaysmall', //
  'headlinelarge', 'headlinemedium', 'headlinesmall', //
  'titlelarge', 'titlemedium', 'titlesmall', //
  'bodylarge', 'bodymedium', 'bodysmall', //
  'labellarge', 'labelmedium', 'labelsmall',
];

/// The color roles of `ColorScheme` that `colors.<role>` may set, by
/// canonical name.
const colorRoles = [
  'primary', 'onprimary', 'primarycontainer', 'onprimarycontainer', //
  'primaryfixed',
  'primaryfixeddim',
  'onprimaryfixed',
  'onprimaryfixedvariant', //
  'secondary', 'onsecondary', 'secondarycontainer', 'onsecondarycontainer', //
  'secondaryfixed',
  'secondaryfixeddim',
  'onsecondaryfixed',
  'onsecondaryfixedvariant', //
  'tertiary', 'ontertiary', 'tertiarycontainer', 'ontertiarycontainer', //
  'tertiaryfixed',
  'tertiaryfixeddim',
  'ontertiaryfixed',
  'ontertiaryfixedvariant', //
  'error', 'onerror', 'errorcontainer', 'onerrorcontainer', //
  'surface', 'onsurface', 'onsurfacevariant', 'surfacedim', 'surfacebright', //
  'surfacecontainerlowest', 'surfacecontainerlow', 'surfacecontainer', //
  'surfacecontainerhigh', 'surfacecontainerhighest', 'surfacetint', //
  'inversesurface', 'oninversesurface', 'inverseprimary', //
  'outline', 'outlinevariant', 'shadow', 'scrim',
];

/// One theme of the app as the `spring.flutter.theme.*` properties
/// describe it: colors, typography, shapes, elevations, density, motion,
/// spacing, component adjustments and the app's own tokens.
///
/// A theme's values come from the shared part of the properties, then the
/// theme it `extends`, then its own. They are read and checked once, when
/// the theme is made. From them come Material's `ThemeData`
/// ([toMaterial]) and a `CupertinoThemeData` ([toCupertino]). The app's
/// own widgets read the theme shown with `SpringTheme.of(context)`, for
/// what Material's theme has no place for: [space], [textStyle] of `code`,
/// [tokenColor] and the like. Only what the properties set differs from
/// Flutter's defaults: a theme without properties is Flutter's own
/// Material 3 theme.
///
/// Apps do not create it: `SpringThemes` makes one per theme.
///
/// ```dart
/// // A banner sized and colored by the brand's tokens.
/// final theme = SpringTheme.of(context);
/// Container(
///   height: theme.tokenNumber('brand.hero-height'),
///   color: theme.tokenColor('brand.accent'),
///   padding: EdgeInsets.all(theme.space('m')),
///   child: Text('NEON Books', style: theme.textStyle('headlineMedium')),
/// );
/// ```
final class SpringThemeData {
  SpringThemeData._(this.name, ThemeProperties p)
    : brightness = p.read(
        'brightness',
        (v) => ThemeValues.enumValue(Brightness.values, v),
        'light or dark',
      )!,
      seedColor = p.color('seedcolor'),
      schemeVariant = p.read(
        'schemevariant',
        (v) => ThemeValues.enumValue(DynamicSchemeVariant.values, v),
        DynamicSchemeVariant.values.map((v) => v.name).join(', '),
      ),
      contrast = p.read(
        'contrast',
        (v) {
          final n = ThemeValues.number(v);
          return n != null && n >= -1 && n <= 1 ? n : null;
        },
        'a number from -1 to 1',
      ),
      _properties = p {
    for (final role in p.children('colors')) {
      if (!colorRoles.contains(role)) {
        throw ThemePropertyException(
          p.propertyName('colors.$role'),
          p['colors.$role'] ?? '',
          'a color role: ${colorRoles.join(', ')}',
        );
      }
      colors[role] = p.color('colors.$role')!;
    }
    fontFamily = p['typography.fontfamily'];
    fontFamilyFallback = p.list('typography.fontfamilyfallback');
    final defaults = _spec(p, 'typography.defaults');
    for (final style in textStyleNames) {
      final group = style.replaceAll(RegExp('(large|medium|small)\$'), '');
      final spec = defaults
          .merge(_spec(p, 'typography.$group'))
          .merge(_spec(p, 'typography.$style'));
      if (!spec.isEmpty) {
        textStyles[style] = spec;
      }
    }
    code = const SpringTextSpec(
      fontFamily: 'monospace',
      size: 14,
    ).merge(_spec(p, 'typography.code'));
    _checkKeys(p);
    for (final key in p.children('typography')) {
      const known = {
        'fontfamily',
        'fontfamilyfallback',
        'defaults',
        'code',
        'display',
        'headline',
        'title',
        'body',
        'label',
      };
      if (!known.contains(key) && !textStyleNames.contains(key)) {
        throw ThemePropertyException(
          p.propertyName('typography.$key'),
          '',
          'a text style: ${[...textStyleNames, 'display', 'headline', 'title', 'body', 'label', 'code', 'defaults'].join(', ')}',
        );
      }
    }
    for (final token in p.children('shape')) {
      if (!m3ShapeScale.containsKey(token)) {
        throw ThemePropertyException(
          p.propertyName('shape.$token'),
          p['shape.$token'] ?? '',
          'a shape token: ${m3ShapeScale.keys.join(', ')}',
        );
      }
      shapes[token] = p.read(
        'shape.$token',
        ThemeValues.number,
        'a corner radius',
      )!;
    }
    for (final level in p.children('elevation')) {
      if (!m3Elevations.containsKey(level)) {
        throw ThemePropertyException(
          p.propertyName('elevation.$level'),
          p['elevation.$level'] ?? '',
          'level0 … level5',
        );
      }
      elevations[level] = p.read(
        'elevation.$level',
        ThemeValues.number,
        'a number',
      )!;
    }
    for (final key in p.children('spacing')) {
      spacing[key] = p.read('spacing.$key', ThemeValues.number, 'a number')!;
    }
    visualDensity = p.read(
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
    tapTargetSize = p.read(
      'taptargetsize',
      (v) => ThemeValues.enumValue(MaterialTapTargetSize.values, v),
      'padded or shrinkWrap',
    );
    splashFactory = p.read(
      'splash',
      (v) => switch (ThemeValues.canonical(v)) {
        'ripple' => InkRipple.splashFactory,
        'sparkle' => InkSparkle.splashFactory,
        'none' => NoSplash.splashFactory,
        _ => null,
      },
      'ripple, sparkle or none',
    );
    final transition = PageTransitionSpec.parseAt(p, 'motion.pagetransition');
    pageTransitions = transition ?? const PageTransitionSpec();
    textChange =
        TextChangeSpec.parseAt(p, 'motion.textchange') ??
        const TextChangeSpec();
    contentChange =
        ContentChangeSpec.parseAt(p, 'motion.contentchange') ??
        const ContentChangeSpec();
    scrollToTop = switch (p['motion.scrolltotop']) {
      final kind? when ThemeValues.canonical(kind) == 'none' => null,
      final kind? => throw ThemePropertyException(
        p.propertyName('motion.scrolltotop'),
        kind,
        'none, or a map of duration and curve',
      ),
      null when p.children('motion.scrolltotop').isNotEmpty =>
        AnimationSpec.parseAt(p, 'motion.scrolltotop'),
      null => defaultScrollToTop,
    };
    // Not set: none, for Material's own page routes too.
    pageTransition = switch (transition?.type) {
      null => const _NoTransition(),
      PageTransitionType.platform => const _Platform(),
      PageTransitionType.fadeUpwards =>
        const FadeUpwardsPageTransitionsBuilder(),
      PageTransitionType.zoom => const ZoomPageTransitionsBuilder(),
      PageTransitionType.cupertino => const CupertinoPageTransitionsBuilder(),
      PageTransitionType.fade => const _FadeTransition(),
      PageTransitionType.none => const _NoTransition(),
    };
    for (final key in p.children('motion')) {
      if (key == 'durations') {
        for (final name in p.children('motion.durations')) {
          durations[name] = p.read(
            'motion.durations.$name',
            ThemeValues.duration,
            'a duration like 250ms',
          )!;
        }
      } else if (key == 'curves') {
        for (final name in p.children('motion.curves')) {
          final path = 'motion.curves.$name';
          // Four numbers are one text (`0.2, 0, 0, 1`) or a YAML list.
          final text = p[path] ?? p.list(path)?.join(', ') ?? '';
          curves[name] =
              ThemeValues.anyCurve(text) ??
              (throw ThemePropertyException(
                p.propertyName(path),
                text,
                _curveFormats,
              ));
        }
      }
    }
    for (final name in p.children('animations')) {
      animations[name] = AnimationSpec.parse(p, name);
    }
    background = ThemeBackgroundData.parse(p);
    for (final name in p.children('loaders')) {
      loaders[name] = ThemeLoaderSpec.parse(p, name);
    }
    for (final name in p.children('syntax')) {
      final language = CodeSyntax.parse(p, name);
      for (final alias in [name, ...language.aliases]) {
        _syntax[ThemeValues.canonical(alias)] = language;
      }
    }
    splash = ThemeSplashData.parse(p);
    _readImageTokens(p);
    for (final name in p.children('styles')) {
      styles[name] = StateStyle.parse(p, name);
    }
    for (final component in p.children('components')) {
      if (!themeComponents.containsKey(component)) {
        throw ThemePropertyException(
          p.propertyName('components.$component'),
          '',
          'a component: ${themeComponentNames.join(', ')}'
              '${didYouMean(component, themeComponentNames)}',
        );
      }
    }
    for (final MapEntry(:key, :value) in p.values.entries) {
      if (key.startsWith('tokens.')) {
        tokens[key.substring('tokens.'.length)] = value.trim();
      }
    }
    _checkColorTokens(p);
    cupertinoPrimaryColor = _cupertinoReader().color('primaryColor');
    // Checks every component value now, not when a widget needs it.
    toMaterial();
    toCupertino();
  }

  // A token that is a map with a `color` is a color object: it may have
  // `mix` and `alpha` and nothing else. Checked at the start.
  static void _checkColorTokens(ThemeProperties p) {
    final nodes = <String>{};
    for (final key in p.values.keys) {
      if (!key.startsWith('tokens.')) {
        continue;
      }
      final segments = key.split('.');
      for (var i = 2; i < segments.length; i++) {
        if (segments[i] == 'color' &&
            !(segments[i - 1] == 'headers' || segments.contains('headers'))) {
          nodes.add(segments.take(i).join('.'));
        }
      }
    }
    for (final node in nodes) {
      p.colorObject(node);
    }
  }

  /// The top-level properties a theme may have. Any other key fails the
  /// start like a wrong value, so a misspelling is not silently ignored.
  static const themeProperties = [
    'brightness', 'seed-color', 'scheme-variant', 'contrast', 'colors', //
    'typography', 'shape', 'elevation', 'spacing', 'visual-density', //
    'tap-target-size',
    'splash',
    'motion',
    'components',
    'tokens',
    'cupertino',
    'styles', //
    'animations',
    'background',
    'loaders',
    'syntax',
  ];

  static const _textSpecProperties = {
    'fontfamily',
    'size',
    'weight',
    'height',
    'letterspacing',
  };

  static void _checkKeys(ThemeProperties p) {
    final roots = {
      for (final key in themeProperties) ThemeValues.canonical(key),
    };
    for (final key in p.values.keys) {
      final segments = key.split('.');
      if (!roots.contains(segments.first)) {
        throw ThemePropertyException(
          p.propertyName(key),
          p.values[key]!,
          'a theme property: ${themeProperties.join(', ')}'
          '${segments.first == 'themes' ? ' (a theme is themes.<name>.<property>)' : ''}',
        );
      }
      final second = segments.length > 1 ? segments[1] : null;
      switch (segments.first) {
        case 'motion'
            when second != 'pagetransition' &&
                second != 'textchange' &&
                second != 'contentchange' &&
                second != 'scrolltotop' &&
                second != 'durations' &&
                second != 'curves':
          throw ThemePropertyException(
            p.propertyName(key),
            p.values[key]!,
            'motion.page-transition, motion.text-change, '
            'motion.content-change, motion.scroll-to-top, '
            'motion.durations.<name> or motion.curves.<name>',
          );
        case 'typography'
            when segments.length == 3 &&
                second != 'fontfamilyfallback' &&
                !_textSpecProperties.contains(segments[2]):
          throw ThemePropertyException(
            p.propertyName(key),
            p.values[key]!,
            'a text style property: font-family, size, weight, height, letter-spacing',
          );
        case 'typography'
            when segments.length == 2 &&
                second != 'fontfamily' &&
                second != 'fontfamilyfallback':
          throw ThemePropertyException(
            p.propertyName(key),
            p.values[key]!,
            'typography.$second.<font-family | size | weight | height | letter-spacing>',
          );
      }
    }
  }

  /// Reads theme [name] of [config] and checks every value, components
  /// included. Throws a [ThemePropertyException] naming the property when
  /// a value or key is invalid, or a `StateError` for an `extends` cycle
  /// or an unknown parent.
  factory SpringThemeData.of(ThemeConfig config, String name) {
    final resolved = config.nameOf(name) ?? name;
    return SpringThemeData._(
      resolved,
      ThemeProperties(
        resolved,
        config.resolve(resolved),
        addresses: config.addresses,
      ),
    );
  }

  static final _curveFormats =
      'a curve: ${ThemeValues.curveNames.join(', ')}, or four numbers like '
      '0.2, 0, 0, 1';

  final ThemeProperties _properties;

  /// The theme's name as declared (`light`, `dark`, `ocean`).
  final String name;

  /// Whether the theme is light or dark: `dark` for the `dark` theme and
  /// for themes that say so or extend a dark one, else `light`.
  final Brightness brightness;

  /// The color the palette is made from; `null` when not set, which means
  /// Flutter's baseline palette (or its default seed when [schemeVariant]
  /// or [contrast] is set).
  final Color? seedColor;

  /// How the palette is made from the seed; `null` for Material 3's
  /// `tonalSpot`.
  final DynamicSchemeVariant? schemeVariant;

  /// The palette's contrast, from -1 to 1; `null` for 0.
  final double? contrast;

  /// The color roles set explicitly under `colors.*`, by canonical role
  /// name; they replace those of the seed's palette.
  final Map<String, Color> colors = {};

  /// The font family of all text; `null` for the platform's.
  late final String? fontFamily;

  /// The font families used for glyphs the main family lacks (for example
  /// Japanese text); `null` when not set.
  late final List<String>? fontFamilyFallback;

  /// The text styles the properties set, by canonical `TextTheme` name,
  /// with the `defaults` and group (`display`, `title`, ...) values merged
  /// in.
  final Map<String, SpringTextSpec> textStyles = {};

  /// The style of monospaced text, which has no Material role: `monospace`
  /// at size 14 unless `typography.code` says otherwise. Widgets get it
  /// with `SpringTheme.of(context).textStyle('code')`.
  late final SpringTextSpec code;

  /// The corner radii the properties set, by canonical token name; they
  /// replace those of [m3ShapeScale].
  final Map<String, double> shapes = {};

  /// The elevation levels the properties set; they replace those of
  /// [m3Elevations].
  final Map<String, double> elevations = {};

  /// The spacing values the properties set; they replace or extend
  /// [defaultSpacing].
  final Map<String, double> spacing = {};

  /// The visual density; `null` when not set.
  late final VisualDensity? visualDensity;

  /// The minimum tap target size; `null` when not set.
  late final MaterialTapTargetSize? tapTargetSize;

  /// The ink splash of taps (ripple, sparkle or none); `null` when not
  /// set.
  late final InteractiveInkFeatureFactory? splashFactory;

  /// The page transition used on every platform: none when not set, `null`
  /// for `platform` (Flutter's own).
  late final PageTransitionsBuilder? pageTransition;

  /// `motion.page-transition`: the kind, duration and curve of a router's
  /// page transitions (none when not set). The navigation starter reads
  /// it; [pageTransition] is the same for Material's page routes.
  late final PageTransitionSpec pageTransitions;

  /// What a [ThemeText] does when its text changes (another language),
  /// from `motion.text-change`; none when it is not written.
  late final TextChangeSpec textChange;

  /// How a part of a screen shows other content in its place
  /// (`ContentChange`), from `motion.content-change`; none when it is not
  /// written.
  late final ContentChangeSpec contentChange;

  /// How a screen goes back to its top when it shows another page
  /// (`RouteContentView`), from `motion.scroll-to-top`: an animation, or
  /// `null` (`none`) to jump. [defaultScrollToTop] when not written.
  late final AnimationSpec? scrollToTop;

  /// 400ms, ease-out-cubic.
  static const defaultScrollToTop = AnimationSpec(
    duration: Duration(milliseconds: 400),
    curve: Curves.easeOutCubic,
  );

  /// The motion durations the properties set (`motion.durations.medium`),
  /// by canonical name.
  final Map<String, Duration> durations = {};

  /// The motion curves the properties set (`motion.curves.standard`), by
  /// canonical name.
  final Map<String, Curve> curves = {};

  /// The animations of `animations.*` by canonical name
  /// (`borderspin`).
  final Map<String, AnimationSpec> animations = {};

  /// The `background` of the theme (a color, an image, an overlay, an
  /// animation, per-screen overrides); `null` when the theme has none.
  late final ThemeBackgroundData? background;

  /// The loaders of `loaders.*` by canonical name (`neondoors`).
  final Map<String, ThemeLoaderSpec> loaders = {};

  final Map<String, CodeSyntax> _syntax = {};

  /// The language of `syntax.<name>` that [language] (a fenced block's
  /// language: `dart`, `yml`) names, by name or alias; `null` when the
  /// theme has none, and the block is plain text.
  CodeSyntax? syntaxOf(String? language) =>
      language == null ? null : _syntax[ThemeValues.canonical(language)];

  /// The `splash` map of the theme (what shows while the application
  /// starts); `null` when the theme has none. (A plain `splash: ripple` is
  /// the ink splash of taps, [splashFactory].)
  late final ThemeSplashData? splash;

  final Map<String, ThemeImage> _tokenImages = {};

  /// The image token `tokens.<path>` (a token that is a map with
  /// `source`); `null` when there is none.
  ThemeImage? tokenImage(String path) => _tokenImages[_tokenKey(path)];

  /// Every image the theme names: the background's, the screens' and the
  /// image tokens'; the starter loads those from the network.
  Iterable<ThemeImage> get images => [
    ...?background?.images,
    ...?splash?.images,
    ..._tokenImages.values,
  ];

  // A token that is a map with `source` (and only image keys) is an image.
  void _readImageTokens(ThemeProperties p) {
    const imageKeys = {
      'source',
      'refresh',
      'sourcesha256',
      'headers',
      'timeout',
      'fallback',
    };
    for (final key in p.values.keys.toList()) {
      if (!key.startsWith('tokens.') || !key.endsWith('.source')) {
        continue;
      }
      final path = key.substring(0, key.length - '.source'.length);
      if (path == 'tokens' || path.split('.').length < 3) {
        continue;
      }
      if (p.children(path).every(imageKeys.contains)) {
        _tokenImages[path.substring('tokens.'.length)] = ThemeImage.parse(
          p,
          path,
        );
      }
    }
  }

  /// The styles of the app's own widgets, `styles.*`, by canonical name
  /// (`neonchip`).
  final Map<String, StateStyle> styles = {};

  /// The app's own values under `tokens.*`, as text by full path in
  /// canonical form (`brand.accent`, `neon.modal.border.width`); the
  /// items of a list have their index as the last segment
  /// (`neon.modal.border.colors.0`). Read them with [token],
  /// [tokenColor], [tokenNumber], [tokenDuration] and the list reads.
  final Map<String, String> tokens = {};

  /// The primary color of the Cupertino theme; `null` when not set.
  late final Color? cupertinoPrimaryColor;

  ColorScheme? _scheme;

  /// The full palette: the one made from the seed by Material 3's
  /// algorithm (or Flutter's baseline when nothing is set), with the roles
  /// of [colors] over it.
  ColorScheme get colorScheme => _scheme ??= _withColors(
    baseScheme(
      brightness: brightness,
      seedColor: seedColor,
      schemeVariant: schemeVariant,
      contrast: contrast,
    ),
  );

  /// The palette before the explicit `colors.*` roles: made from the seed
  /// by Material 3's algorithm, or Flutter's own baseline when no seed,
  /// variant or contrast is set. The theme's [colorScheme] and the
  /// references to undeclared roles (`$colors.outline`) both come from it.
  static ColorScheme baseScheme({
    required Brightness brightness,
    Color? seedColor,
    DynamicSchemeVariant? schemeVariant,
    double? contrast,
  }) => seedColor == null && schemeVariant == null && contrast == null
      // Flutter's own Material 3 baseline (not quite the seed's).
      ? ThemeData(brightness: brightness).colorScheme
      : ColorScheme.fromSeed(
          seedColor: seedColor ?? const Color(0xFF6750A4),
          brightness: brightness,
          dynamicSchemeVariant: schemeVariant ?? DynamicSchemeVariant.tonalSpot,
          contrastLevel: contrast ?? 0,
        );

  /// The color of [role] (canonical name) in [scheme]; `null` for an
  /// unknown role.
  static Color? roleIn(ColorScheme scheme, String role) => _role(scheme, role);

  /// The corner radius of shape token [token] (`medium`,
  /// `extra-large`), as the properties set it or Material 3's;
  /// `double.infinity` for `full`. Throws an `ArgumentError` for an
  /// unknown token.
  double shape(String token) {
    final key = ThemeValues.canonical(token);
    return shapes[key] ??
        m3ShapeScale[key] ??
        (throw ArgumentError.value(
          token,
          'token',
          'one of ${m3ShapeScale.keys.join(', ')}',
        ));
  }

  /// The elevation of level [level] (`level2`). Throws an `ArgumentError`
  /// for an unknown level.
  double elevation(String level) {
    final key = ThemeValues.canonical(level);
    return elevations[key] ??
        m3Elevations[key] ??
        (throw ArgumentError.value(level, 'level'));
  }

  /// The spacing [size] in logical pixels: `xs`, `s`, `m`, `l`, `xl`, or
  /// a name the properties added. Throws an `ArgumentError` for an unknown
  /// name.
  double space(String size) {
    final key = ThemeValues.canonical(size);
    return spacing[key] ??
        defaultSpacing[key] ??
        (throw ArgumentError.value(size, 'size'));
  }

  /// The durations `short`, `medium` and `long` have when the properties
  /// do not set them. Read a motion duration with
  /// `ThemeKeyReader.motionDuration`, which fails for an unknown name and
  /// follows the reduce-motion setting.
  static const defaultDurations = <String, Duration>{
    'short': Duration(milliseconds: 100),
    'medium': Duration(milliseconds: 250),
    'long': Duration(milliseconds: 450),
  };

  /// The motion curve [name] (`standard`, `emphasized`), as the
  /// properties set it; otherwise Material's standard easing.
  Curve curve(String name) =>
      curves[ThemeValues.canonical(name)] ?? Easing.standard;

  /// A finished text style of the theme: a `TextTheme` style by name
  /// (`titleLarge`, `title-large`) or `code`, with what the properties set.
  /// Throws an `ArgumentError` for another name.
  TextStyle textStyle(String style) => _styleIn(toMaterial().textTheme, style);

  TextStyle _styleIn(TextTheme textTheme, String style) {
    final key = ThemeValues.canonical(style);
    if (key == 'code') {
      // Falls back to the theme's own font where the monospaced one is
      // missing (`monospace` is not a family on every platform).
      return code
          .applyTo(textTheme.bodyMedium)
          .copyWith(
            fontFamily: code.fontFamily,
            fontFamilyFallback: [?fontFamily, ...?fontFamilyFallback],
          );
    }
    return _textThemeStyle(textTheme, key) ??
        (throw ArgumentError.value(
          style,
          'style',
          'a TextTheme style or code',
        ));
  }

  /// Every font family the theme names: the main one, the fallbacks, and
  /// those of the text styles and `code`. At startup the starter logs a
  /// warning for each one it finds neither among the font assets nor under
  /// `flutter: fonts:`.
  Set<String> get fontFamilies => {
    ?fontFamily,
    ...?fontFamilyFallback,
    for (final spec in textStyles.values) ?spec.fontFamily,
    ?code.fontFamily,
  };

  /// The app's token [key] (`brand.accent`) read as a color; `null` when
  /// it is not set or is no color.
  Color? tokenColor(String key) {
    final path = _tokenKey(key);
    return switch (tokens[path]) {
      final value? => ThemeValues.color(value),
      null =>
        _properties.children('tokens.$path').contains('color')
            ? _properties.colorObject('tokens.$path')
            : null,
    };
  }

  /// The app's token [key] (`brand.hero-height`) read as a number; `null`
  /// when it is not set or is no number.
  double? tokenNumber(String key) => switch (tokens[_tokenKey(key)]) {
    final value? => ThemeValues.number(value),
    null => null,
  };

  /// The app's token [key] (`neon.modal.open`) read as a duration; `null`
  /// when it is not set or is no duration.
  Duration? tokenDuration(String key) => switch (tokens[_tokenKey(key)]) {
    final value? => ThemeValues.duration(value),
    null => null,
  };

  /// The app's token [key] as written in the properties; `null` when it is
  /// not set.
  String? token(String key) => tokens[_tokenKey(key)];

  /// The items of the list token [key], as text: a YAML list, or one
  /// comma-separated value; `null` when it is not set.
  List<String>? tokenTexts(String key) {
    final path = _tokenKey(key);
    final indexed = <int, String>{};
    for (final MapEntry(key: other, :value) in tokens.entries) {
      if (other.startsWith('$path.')) {
        final index = int.tryParse(other.substring(path.length + 1));
        if (index != null) {
          indexed[index] = value;
        }
      }
    }
    if (indexed.isNotEmpty) {
      return [
        for (final index in indexed.keys.toList()..sort()) indexed[index]!,
      ];
    }
    final value = tokens[path];
    return value == null
        ? null
        : [
            for (final part in value.split(','))
              if (part.trim().isNotEmpty) part.trim(),
          ];
  }

  /// The list token [key] read as colors, each an item of a YAML list
  /// (a color or a color object) or of one comma-separated value; `null`
  /// when it is not set or an item is no color.
  List<Color>? tokenColors(String key) {
    final path = _tokenKey(key);
    final indexes = <int>{
      for (final child in _properties.children('tokens.$path'))
        ?int.tryParse(child),
    };
    if (indexes.isEmpty) {
      return _parsed(key, ThemeValues.color);
    }
    final colors = [
      for (final index in indexes.toList()..sort()) tokenColor('$key.$index'),
    ];
    return colors.contains(null) ? null : List<Color>.from(colors);
  }

  /// The list token [key] read as numbers; `null` when it is not set or an
  /// item is no number.
  List<double>? tokenNumbers(String key) => _parsed(key, ThemeValues.number);

  List<T>? _parsed<T>(String key, T? Function(String) parse) {
    final items = tokenTexts(key);
    if (items == null) {
      return null;
    }
    final result = [for (final item in items) parse(item)];
    return result.contains(null) ? null : List<T>.from(result);
  }

  static String _tokenKey(String key) =>
      key.split('.').map(ThemeValues.canonical).join('.');

  // ---------------------------------------------------------------------
  // Material
  // ---------------------------------------------------------------------

  ThemeData? _material;

  /// The theme as Material's `ThemeData`, made once; it carries this
  /// theme as a [SpringThemeExtension]. Customizers are not applied here
  /// but in `SpringThemes.material`.
  ThemeData toMaterial() => _material ??= _buildMaterial();

  ThemeData _buildMaterial() {
    final scheme = colorScheme;
    final textTheme = TextTheme(
      displayLarge: _style('displaylarge'),
      displayMedium: _style('displaymedium'),
      displaySmall: _style('displaysmall'),
      headlineLarge: _style('headlinelarge'),
      headlineMedium: _style('headlinemedium'),
      headlineSmall: _style('headlinesmall'),
      titleLarge: _style('titlelarge'),
      titleMedium: _style('titlemedium'),
      titleSmall: _style('titlesmall'),
      bodyLarge: _style('bodylarge'),
      bodyMedium: _style('bodymedium'),
      bodySmall: _style('bodysmall'),
      labelLarge: _style('labellarge'),
      labelMedium: _style('labelmedium'),
      labelSmall: _style('labelsmall'),
    );
    final theme = ThemeData(
      colorScheme: scheme,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      textTheme: textTheme,
      visualDensity: visualDensity,
      materialTapTargetSize: tapTargetSize,
      splashFactory: splashFactory,
      pageTransitionsTheme: switch (pageTransition) {
        _Platform() || null => null,
        final builder => PageTransitionsTheme(
          builders: {
            for (final platform in TargetPlatform.values) platform: builder,
          },
        ),
      },
      // A background shows through the screens.
      scaffoldBackgroundColor: background == null ? null : Colors.transparent,
      extensions: [SpringThemeExtension(this)],
    );
    return _components(theme);
  }

  TextStyle? _style(String name) => textStyles[name]?.toStyle();

  ThemeReader _componentReader(ThemeData theme, ThemeComponent component) =>
      ThemeReader(
        theme: this,
        properties: _properties,
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
          _properties.propertyName(reader.root),
          '',
          "values Flutter accepts together in ${component.name}: ${e.message ?? e}",
        );
      }
      reader.checkUnknown();
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // Cupertino and Widgets
  // ---------------------------------------------------------------------

  CupertinoThemeData? _cupertino;

  /// The theme as a `CupertinoThemeData`, made once: primary color, text
  /// styles and backgrounds where the properties set them, iOS's
  /// defaults otherwise.
  CupertinoThemeData toCupertino() => _cupertino ??= _buildCupertino();

  // The reader of `cupertino.*`; its text styles are Material's.
  ThemeReader _cupertinoReader() => ThemeReader(
    theme: this,
    properties: _properties,
    root: 'cupertino',
    label: 'cupertino',
    namedStyle: (name) => _styleIn(toMaterial().textTheme, name),
  );

  /// The `cupertino.*` properties the theme reads, for the reference
  /// documentation and tests.
  @visibleForTesting
  List<ThemeProperty> get cupertinoProperties {
    final r = _cupertinoReader();
    _buildCupertino(r);
    return r.asked;
  }

  CupertinoThemeData _buildCupertino([ThemeReader? reader]) {
    final r = reader ?? _cupertinoReader();
    // iOS's own styles, with this theme's primary color in the ones that
    // carry it (actions, nav actions), not iOS blue.
    final defaults = CupertinoTextThemeData(
      primaryColor:
          r.color('primaryColor') ??
          colors['primary'] ??
          (seedColor == null ? null : colorScheme.primary) ??
          CupertinoColors.systemBlue,
    );
    TextStyle text(TextStyle base, String style) {
      final spec = textStyles[style];
      return (spec?.applyTo(base) ?? base).copyWith(
        fontFamily: spec?.fontFamily ?? fontFamily,
        fontFamilyFallback: fontFamilyFallback,
      );
    }

    final typography =
        fontFamily != null ||
        fontFamilyFallback != null ||
        textStyles.isNotEmpty;
    final primary =
        r.color('primaryColor') ??
        colors['primary'] ??
        (seedColor == null ? null : colorScheme.primary);
    final t = r.group('textTheme');
    // The style written under `text-theme`, over the one made from the
    // typography, over iOS's own.
    TextStyle style(String key, TextStyle base, String? from) {
      final own = t.text(key, base: base);
      return own ?? (typography && from != null ? text(base, from) : base);
    }

    final textTheme = CupertinoTextThemeData(
      primaryColor:
          t.color('primaryColor') ?? primary ?? CupertinoColors.systemBlue,
      textStyle: style('textStyle', defaults.textStyle, 'bodylarge'),
      actionTextStyle: style(
        'actionTextStyle',
        defaults.actionTextStyle,
        'labellarge',
      ),
      tabLabelTextStyle: style(
        'tabLabelTextStyle',
        defaults.tabLabelTextStyle,
        'labelsmall',
      ),
      navTitleTextStyle: style(
        'navTitleTextStyle',
        defaults.navTitleTextStyle,
        'titlelarge',
      ),
      navLargeTitleTextStyle: style(
        'navLargeTitleTextStyle',
        defaults.navLargeTitleTextStyle,
        'displaysmall',
      ),
      navActionTextStyle: style(
        'navActionTextStyle',
        defaults.navActionTextStyle,
        'labellarge',
      ),
      pickerTextStyle: style(
        'pickerTextStyle',
        defaults.pickerTextStyle,
        'bodylarge',
      ),
      dateTimePickerTextStyle: style(
        'dateTimePickerTextStyle',
        defaults.dateTimePickerTextStyle,
        'bodylarge',
      ),
    );
    final result = CupertinoThemeData(
      brightness: brightness,
      primaryColor: primary,
      primaryContrastingColor: r.color('primaryContrastingColor'),
      scaffoldBackgroundColor:
          r.color('scaffoldBackgroundColor') ??
          (background == null ? colors['surface'] : Colors.transparent),
      barBackgroundColor:
          r.color('barBackgroundColor') ??
          _componentReader(
            toMaterial(),
            themeComponents['appbar']!,
          ).color('backgroundColor'),
      selectionHandleColor: r.color('selectionHandleColor'),
      applyThemeToAll: r.flag('applyThemeToAll'),
      textTheme: typography || t.has ? textTheme : null,
    );
    r.checkUnknown();
    return result;
  }

  /// The color the OS uses for the app (in the task switcher): the
  /// palette's primary color.
  Color get appColor => colorScheme.primary;

  /// The default text style of a `WidgetsApp`: Material's body medium in
  /// the theme's font and on-surface color.
  TextStyle get widgetsTextStyle =>
      textStyle('bodyMedium').copyWith(color: colorScheme.onSurface);

  ColorScheme _withColors(ColorScheme s) {
    Color? c(String role) => colors[role];
    return s.copyWith(
      primary: c('primary'),
      onPrimary: c('onprimary'),
      primaryContainer: c('primarycontainer'),
      onPrimaryContainer: c('onprimarycontainer'),
      primaryFixed: c('primaryfixed'),
      primaryFixedDim: c('primaryfixeddim'),
      onPrimaryFixed: c('onprimaryfixed'),
      onPrimaryFixedVariant: c('onprimaryfixedvariant'),
      secondary: c('secondary'),
      onSecondary: c('onsecondary'),
      secondaryContainer: c('secondarycontainer'),
      onSecondaryContainer: c('onsecondarycontainer'),
      secondaryFixed: c('secondaryfixed'),
      secondaryFixedDim: c('secondaryfixeddim'),
      onSecondaryFixed: c('onsecondaryfixed'),
      onSecondaryFixedVariant: c('onsecondaryfixedvariant'),
      tertiary: c('tertiary'),
      onTertiary: c('ontertiary'),
      tertiaryContainer: c('tertiarycontainer'),
      onTertiaryContainer: c('ontertiarycontainer'),
      tertiaryFixed: c('tertiaryfixed'),
      tertiaryFixedDim: c('tertiaryfixeddim'),
      onTertiaryFixed: c('ontertiaryfixed'),
      onTertiaryFixedVariant: c('ontertiaryfixedvariant'),
      error: c('error'),
      onError: c('onerror'),
      errorContainer: c('errorcontainer'),
      onErrorContainer: c('onerrorcontainer'),
      surface: c('surface'),
      onSurface: c('onsurface'),
      onSurfaceVariant: c('onsurfacevariant'),
      surfaceDim: c('surfacedim'),
      surfaceBright: c('surfacebright'),
      surfaceContainerLowest: c('surfacecontainerlowest'),
      surfaceContainerLow: c('surfacecontainerlow'),
      surfaceContainer: c('surfacecontainer'),
      surfaceContainerHigh: c('surfacecontainerhigh'),
      surfaceContainerHighest: c('surfacecontainerhighest'),
      surfaceTint: c('surfacetint'),
      inverseSurface: c('inversesurface'),
      onInverseSurface: c('oninversesurface'),
      inversePrimary: c('inverseprimary'),
      outline: c('outline'),
      outlineVariant: c('outlinevariant'),
      shadow: c('shadow'),
      scrim: c('scrim'),
    );
  }

  /// The color of palette role [name] (`surface-container`,
  /// `onPrimary`); `null` for an unknown role.
  Color? role(String name) => _role(colorScheme, ThemeValues.canonical(name));

  static Color? _role(ColorScheme s, String role) => switch (role) {
    'primary' => s.primary,
    'onprimary' => s.onPrimary,
    'primarycontainer' => s.primaryContainer,
    'onprimarycontainer' => s.onPrimaryContainer,
    'primaryfixed' => s.primaryFixed,
    'primaryfixeddim' => s.primaryFixedDim,
    'onprimaryfixed' => s.onPrimaryFixed,
    'onprimaryfixedvariant' => s.onPrimaryFixedVariant,
    'secondary' => s.secondary,
    'onsecondary' => s.onSecondary,
    'secondarycontainer' => s.secondaryContainer,
    'onsecondarycontainer' => s.onSecondaryContainer,
    'secondaryfixed' => s.secondaryFixed,
    'secondaryfixeddim' => s.secondaryFixedDim,
    'onsecondaryfixed' => s.onSecondaryFixed,
    'onsecondaryfixedvariant' => s.onSecondaryFixedVariant,
    'tertiary' => s.tertiary,
    'ontertiary' => s.onTertiary,
    'tertiarycontainer' => s.tertiaryContainer,
    'ontertiarycontainer' => s.onTertiaryContainer,
    'tertiaryfixed' => s.tertiaryFixed,
    'tertiaryfixeddim' => s.tertiaryFixedDim,
    'ontertiaryfixed' => s.onTertiaryFixed,
    'ontertiaryfixedvariant' => s.onTertiaryFixedVariant,
    'error' => s.error,
    'onerror' => s.onError,
    'errorcontainer' => s.errorContainer,
    'onerrorcontainer' => s.onErrorContainer,
    'surface' => s.surface,
    'onsurface' => s.onSurface,
    'onsurfacevariant' => s.onSurfaceVariant,
    'surfacedim' => s.surfaceDim,
    'surfacebright' => s.surfaceBright,
    'surfacecontainerlowest' => s.surfaceContainerLowest,
    'surfacecontainerlow' => s.surfaceContainerLow,
    'surfacecontainer' => s.surfaceContainer,
    'surfacecontainerhigh' => s.surfaceContainerHigh,
    'surfacecontainerhighest' => s.surfaceContainerHighest,
    'surfacetint' => s.surfaceTint,
    'inversesurface' => s.inverseSurface,
    'oninversesurface' => s.onInverseSurface,
    'inverseprimary' => s.inversePrimary,
    'outline' => s.outline,
    'outlinevariant' => s.outlineVariant,
    'shadow' => s.shadow,
    'scrim' => s.scrim,
    _ => null,
  };

  static TextStyle? _textThemeStyle(TextTheme t, String name) => switch (name) {
    'displaylarge' => t.displayLarge,
    'displaymedium' => t.displayMedium,
    'displaysmall' => t.displaySmall,
    'headlinelarge' => t.headlineLarge,
    'headlinemedium' => t.headlineMedium,
    'headlinesmall' => t.headlineSmall,
    'titlelarge' => t.titleLarge,
    'titlemedium' => t.titleMedium,
    'titlesmall' => t.titleSmall,
    'bodylarge' => t.bodyLarge,
    'bodymedium' => t.bodyMedium,
    'bodysmall' => t.bodySmall,
    'labellarge' => t.labelLarge,
    'labelmedium' => t.labelMedium,
    'labelsmall' => t.labelSmall,
    _ => null,
  };

  static SpringTextSpec _spec(ThemeProperties p, String path) => SpringTextSpec(
    fontFamily: p['$path.fontfamily'],
    size: p.read('$path.size', ThemeValues.number, 'a size'),
    weight: p.read(
      '$path.weight',
      ThemeValues.weight,
      '100 … 900 or a name like semibold',
    ),
    height: p.read(
      '$path.height',
      ThemeValues.number,
      'a line height multiple like 1.4',
    ),
    letterSpacing: p.read(
      '$path.letterspacing',
      ThemeValues.number,
      'a number',
    ),
  );
}

/// Carries a [SpringThemeData] inside Material's `ThemeData`, among its
/// `extensions`.
///
/// Every `ThemeData` made from the properties has one, so code that has
/// only Material's theme at hand still reaches the values Material has no
/// place for (spacing, tokens, the `code` style). Inside the app,
/// `SpringTheme.of(context)` is shorter.
///
/// ```dart
/// // In a widget that only knows Material's theme.
/// final spring =
///     Theme.of(context).extension<SpringThemeExtension>()!.data;
/// final gap = spring.space('s');
/// ```
final class SpringThemeExtension extends ThemeExtension<SpringThemeExtension> {
  /// The extension carrying [data].
  SpringThemeExtension(this.data);

  /// The theme the `ThemeData` was made from.
  final SpringThemeData data;

  @override
  SpringThemeExtension copyWith() => this;

  @override
  SpringThemeExtension lerp(SpringThemeExtension? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

// `motion.page-transition: platform`: Flutter's own per platform.
final class _Platform extends PageTransitionsBuilder {
  const _Platform();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

// `motion.page-transition: fade`.
final class _FadeTransition extends PageTransitionsBuilder {
  const _FadeTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

// `motion.page-transition: none`.
final class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
