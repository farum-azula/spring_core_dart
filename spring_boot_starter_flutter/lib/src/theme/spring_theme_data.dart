import 'package:spring_boot_starter_flutter/src/markdown/code_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_color_scheme.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_type_scale.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_design.dart';
import 'package:spring_boot_starter_flutter/src/theme/frame_meter_theme.dart';
import 'package:spring_boot_starter_flutter/src/theme/content_change.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_background.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_loader.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_splash.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_styles.dart';
import 'package:spring_boot_starter_flutter/src/theme/wheel_scroll.dart';
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

/// One theme of the app as the `spring.flutter.theme.*` properties
/// describe it: colors, typography, shapes, elevations, density, motion,
/// spacing, component adjustments and the app's own tokens.
///
/// A theme's values come from the shared part of the properties, then the
/// theme it `extends`, then its own. They are read and checked once, when
/// the theme is made. The class knows no design library: the palette
/// ([colorScheme]), the text styles ([textStyle]) and the scales are the
/// same in an app without one. The Material starter makes Material's
/// `ThemeData` of it (`toMaterial()`), the Cupertino starter a
/// `CupertinoThemeData` (`toCupertino()`). The app's own widgets read the
/// theme shown with `SpringTheme.of(context)`: [space], [textStyle],
/// [tokenColor] and the like. Only what the properties set differs from
/// Flutter's defaults: a theme without properties has the colors and text
/// styles of Flutter's own Material 3 theme.
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
  SpringThemeData._(this.name, ThemeProperties p, this.designs)
    : brightness = p.read(
        'brightness',
        (v) => ThemeValues.enumValue(Brightness.values, v),
        'light or dark',
      )!,
      seedColor = p.color('seedcolor'),
      schemeVariant = p.read(
        'schemevariant',
        designs.schemeVariant,
        designs.schemeVariants,
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
    _checkKeys(p, designs);
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
    final transition = PageTransitionSpec.parseAt(p, 'motion.pagetransition');
    pageTransitions = transition ?? const PageTransitionSpec();
    textChange =
        TextChangeSpec.parseAt(p, 'motion.textchange') ??
        const TextChangeSpec();
    contentChange =
        ContentChangeSpec.parseAt(p, 'motion.contentchange') ??
        const ContentChangeSpec();
    wheelScroll = WheelScrollSpec.parseAt(p, 'motion.wheelscroll');
    motionEnabled =
        p.read('motion.enabled', ThemeValues.boolean, 'true or false') ?? true;
    overscroll =
        p.read(
          'motion.overscroll',
          (v) => ThemeValues.enumValue(OverscrollEffect.values, v),
          'platform or none',
        ) ??
        OverscrollEffect.platform;
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
    // Not set: the platform's, as in Flutter, for Material's own page
    // routes too.
    pageTransition = switch (transition?.type) {
      null => const _Platform(),
      PageTransitionType.platform => const _Platform(),
      PageTransitionType.fadeUpwards =>
        const FadeUpwardsPageTransitionsBuilder(),
      final type && (PageTransitionType.zoom || PageTransitionType.cupertino) =>
        designs.pageTransition(type) ??
            (throw ThemePropertyException(
              p.propertyName('motion.pagetransition.type'),
              type.name,
              'a transition of the application: ${type.name} is '
              "${type == PageTransitionType.zoom ? "Material's" : "Cupertino's"}"
              ', read by spring_boot_starter_flutter_'
              "${type == PageTransitionType.zoom ? 'material' : 'cupertino'}"
              ' (add it to the dependencies), or platform, fade-upwards, '
              'fade, content or none',
            )),
      PageTransitionType.fade => const _FadeTransition(),
      PageTransitionType.content => const ContentPageTransitionsBuilder(),
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
    frameMeter = FrameMeterTheme.parse(p);
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
    // One name, two things: a map is the splash of the start, a single
    // value Material's ink splash, which only the Material starter reads.
    _readImageTokens(p);
    for (final name in p.children('styles')) {
      styles[name] = StateStyle.parse(p, name);
    }
    for (final MapEntry(:key, :value) in p.values.entries) {
      if (key.startsWith('tokens.')) {
        tokens[key.substring('tokens.'.length)] = value.trim();
      }
    }
    _checkColorTokens(p);
    // The palette now: a seed color without a design fails the start.
    colorScheme;
    unreadDesignProperties = designs.unread({
      for (final key in p.values.keys)
        // The splash of the start is a map: only a single value is
        // Material's ink splash.
        if (!key.startsWith('splash.')) key.split('.').first,
    });
    // Each design reads its own part now, not when a widget needs it.
    designs.check(this);
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

  /// The top-level properties a theme may have, whatever its design; a
  /// design adds its own (`ThemeDesign.themeProperties`: `components`,
  /// `visual-density`, `cupertino`). Any other key fails the start like a
  /// wrong value, so a misspelling is not silently ignored.
  static const themeProperties = [
    'brightness', 'seed-color', 'scheme-variant', 'contrast', 'colors', //
    'typography', 'shape', 'elevation', 'spacing', //
    'splash',
    'motion',
    'tokens',
    'styles', //
    'animations',
    'background',
    'loaders',
    'syntax',
    'frame-meter',
  ];

  static const _textSpecProperties = {
    'fontfamily',
    'size',
    'weight',
    'height',
    'letterspacing',
  };

  static void _checkKeys(ThemeProperties p, ThemeDesigns designs) {
    final roots = {
      for (final key in themeProperties) ThemeValues.canonical(key),
      ...designs.themeProperties,
      ...ThemeDesigns.familyProperties,
    };
    for (final key in p.values.keys) {
      final segments = key.split('.');
      if (!roots.contains(segments.first)) {
        throw ThemePropertyException(
          p.propertyName(key),
          p.values[key]!,
          'a theme property: ${[
            ...themeProperties,
            for (final design in designs.all) ...design.themeProperties,
          ].join(', ')}'
          '${segments.first == 'themes' ? ' (a theme is themes.<name>.<property>)' : ''}'
          '${ThemeDesigns.starterOf(segments.first)}',
        );
      }
      final second = segments.length > 1 ? segments[1] : null;
      switch (segments.first) {
        case 'motion'
            when second != 'enabled' &&
                second != 'pagetransition' &&
                second != 'textchange' &&
                second != 'contentchange' &&
                second != 'scrolltotop' &&
                second != 'wheelscroll' &&
                second != 'overscroll' &&
                second != 'durations' &&
                second != 'curves':
          throw ThemePropertyException(
            p.propertyName(key),
            p.values[key]!,
            'motion.enabled, motion.page-transition, motion.text-change, '
            'motion.content-change, motion.scroll-to-top, motion.wheel-scroll, '
            'motion.overscroll, '
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
      config.designs,
    );
  }

  static final _curveFormats =
      'a curve: ${ThemeValues.curveNames.join(', ')}, or four numbers like '
      '0.2, 0, 0, 1';

  final ThemeProperties _properties;

  /// The theme's properties as written, relative to the theme and with
  /// every reference resolved: what a design reads its own part from
  /// (`components.*`, `cupertino.*`).
  ThemeProperties get properties => _properties;

  /// The designs the theme was read with.
  final ThemeDesigns designs;

  /// The theme properties of a design starter the application does not
  /// have (`components`, `cupertino`), with that starter: the theme has
  /// them for apps of that design, this one does not show them, and they
  /// are not checked. `SpringThemes` logs them once.
  late final Map<String, String> unreadDesignProperties;

  // The platform the default fonts are those of: the one the theme was
  // made on.
  final TargetPlatform _platform = defaultTargetPlatform;

  /// The theme's name as declared (`light`, `dark`, `ocean`).
  final String name;

  /// Whether the theme is light or dark: `dark` for the `dark` theme and
  /// for themes that say so or extend a dark one, else `light`.
  final Brightness brightness;

  /// The color the palette is made from; `null` when not set, which means
  /// Flutter's baseline palette (or its default seed when [schemeVariant]
  /// or [contrast] is set).
  final Color? seedColor;

  /// How the palette is made from the seed, as the design that makes it
  /// names the variant (`tonalSpot`, `vibrant`); `null` for the design's
  /// default (Material 3's `tonalSpot`).
  final String? schemeVariant;

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

  /// The page transition used on every platform; when not set, or for
  /// `platform`, the one that leaves the choice to the app's design
  /// ([isPlatformPageTransition]), as Flutter does.
  late final PageTransitionsBuilder? pageTransition;

  /// Whether `motion.page-transition` is `platform` or not set: the
  /// design of the app chooses, per platform.
  bool get isPlatformPageTransition => pageTransition is _Platform;

  /// `motion.page-transition`: the kind, duration and curve of a router's
  /// page transitions (the platform's when not set). The navigation starter reads
  /// it; [pageTransition] is the same for Material's page routes.
  late final PageTransitionSpec pageTransitions;

  /// What a [ThemeText] does when its text changes (another language),
  /// from `motion.text-change`; none when it is not written.
  late final TextChangeSpec textChange;

  /// How a part of a screen shows other content in its place
  /// (`ContentChange`), from `motion.content-change`; none when it is not
  /// written.
  late final ContentChangeSpec contentChange;

  /// What a scrollable shows when pulled past its end, from
  /// `motion.overscroll`: the app type's own (`platform`, the default:
  /// Material's stretch on Android) or nothing (`none`).
  late final OverscrollEffect overscroll;

  /// `motion.enabled` (`true` by default): `false` makes every motion of
  /// the app instant, as the device's "reduce motion" does: page
  /// transitions, text and content changes, the scroll to the top, the
  /// theme's animations and Flutter's own.
  late final bool motionEnabled;

  /// How a mouse wheel scrolls, from `motion.wheel-scroll`: Flutter's own
  /// step at once (`none`, the default), or eased and scaled.
  late final WheelScrollSpec wheelScroll;

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

  /// How the frame meter looks (`frame-meter`), shown with
  /// `spring.flutter.frame-meter.enabled`.
  late final FrameMeterTheme frameMeter;

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

  SpringColorScheme? _scheme;

  /// The full palette: Flutter's baseline, or the one the app's design
  /// makes from the seed color (Material 3's algorithm), with the roles of
  /// [colors] over it.
  SpringColorScheme get colorScheme => _scheme ??= designs
      .colorScheme(
        ColorSchemeSpec(
          brightness: brightness,
          seedColor: seedColor,
          schemeVariant: schemeVariant,
          contrast: contrast,
        ),
        property: _properties.propertyName(
          seedColor != null
              ? 'seedcolor'
              : schemeVariant != null
              ? 'schemevariant'
              : 'contrast',
        ),
        value:
            _properties['seedcolor'] ??
            _properties['schemevariant'] ??
            _properties['contrast'] ??
            '',
      )
      .withRoles(colors);

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
      curves[ThemeValues.canonical(name)] ?? ThemeValues.standardEasing;

  /// A finished text style of the theme: one of the 15 by name
  /// (`titleLarge`, `title-large`) or `code`, with what the properties set
  /// over the platform's font and the palette's on-surface color. It has
  /// the size the properties give it and no other: [localizedTextStyle]
  /// adds the size of the type scale. Throws an `ArgumentError` for
  /// another name.
  TextStyle textStyle(String style) {
    final key = ThemeValues.canonical(style);
    if (key == 'code') {
      // Falls back to the theme's own font where the monospaced one is
      // missing (`monospace` is not a family on every platform).
      return code
          .applyTo(_named('bodymedium'))
          .copyWith(
            fontFamily: code.fontFamily,
            fontFamilyFallback: [?fontFamily, ...?fontFamilyFallback],
          );
    }
    if (!textStyleNames.contains(key)) {
      throw ArgumentError.value(style, 'style', 'a TextTheme style or code');
    }
    return _named(key);
  }

  final _textStyles = <String, TextStyle>{};

  // What Material's `ThemeData.textTheme` has for the style: the
  // platform's font, the on-surface color, then the theme's own values.
  TextStyle _named(String key) => _textStyles[key] ??= TextStyle(
    fontFamily: fontFamily ?? SpringTypeScale.fontFamily(_platform, key),
    fontFamilyFallback:
        fontFamilyFallback ?? SpringTypeScale.fontFamilyFallback(_platform),
    color: colorScheme.onSurface,
    decoration: TextDecoration.none,
    decorationColor: colorScheme.onSurface,
  ).merge(textStyles[key]?.toStyle());

  /// [textStyle] with the size, weight, line height and letter spacing the
  /// Material 3 type scale has for [script] where the properties set none:
  /// what `Theme.of(context).textTheme` gives in a `MaterialApp`. `code`
  /// has no place in the scale and is as [textStyle] gives it.
  TextStyle localizedTextStyle(String style, TextScript script) {
    final own = textStyle(style);
    final geometry = SpringTypeScale.geometry(
      ThemeValues.canonical(style),
      script,
    );
    return geometry?.merge(own) ?? own;
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

  /// The color the OS uses for the app (in the task switcher): the
  /// palette's primary color.
  Color get appColor => colorScheme.primary;

  /// The default text style of a `WidgetsApp`: body medium in the theme's
  /// font and on-surface color.
  TextStyle get widgetsTextStyle =>
      textStyle('bodyMedium').copyWith(color: colorScheme.onSurface);

  /// The color of palette role [name] (`surface-container`,
  /// `onPrimary`); `null` for an unknown role.
  Color? role(String name) => colorScheme.role(name);

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
