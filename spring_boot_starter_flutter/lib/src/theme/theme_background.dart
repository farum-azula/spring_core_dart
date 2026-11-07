import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// How the background image moves when the theme gives it an animation.
enum BackgroundEffect {
  /// Slides slowly to and fro.
  drift,

  /// Grows and shrinks slowly.
  zoom,

  /// Fades a little in and out.
  pulse,
}

/// The kind of a background gradient.
enum BackgroundGradientType {
  /// Along a line from `begin` to `end`.
  linear,

  /// Around the point `begin` (the center by default).
  radial,
}

const _alignments = <String, Alignment>{
  'center': Alignment.center,
  'top': Alignment.topCenter,
  'bottom': Alignment.bottomCenter,
  'left': Alignment.centerLeft,
  'right': Alignment.centerRight,
  'topleft': Alignment.topLeft,
  'topright': Alignment.topRight,
  'bottomleft': Alignment.bottomLeft,
  'bottomright': Alignment.bottomRight,
  'topcenter': Alignment.topCenter,
  'bottomcenter': Alignment.bottomCenter,
  'centerleft': Alignment.centerLeft,
  'centerright': Alignment.centerRight,
};

Alignment? _alignment(String raw) {
  final named = _alignments[ThemeValues.canonical(raw)];
  if (named != null) {
    return named;
  }
  final parts = [for (final part in raw.split(',')) double.tryParse(part)];
  return parts.length == 2 && !parts.contains(null)
      ? Alignment(parts[0]!, parts[1]!)
      : null;
}

const _alignmentFormats =
    "an alignment: center, top, bottom, left, right, top-left, top-right, "
    "bottom-left, bottom-right or 'x, y' from -1 to 1";

/// The look of an image in a background: the [image] and how it fills the
/// screen. Values the theme did not set are `null`; read the effective
/// ones with [fitOrDefault] and the like.
@immutable
final class ThemeBackgroundImage {
  /// An image with the given settings.
  const ThemeBackgroundImage({
    this.image,
    this.fit,
    this.alignment,
    this.opacity,
    this.blur,
    this.repeat,
  });

  /// The picture; `null` in a screen's override that keeps the theme's.
  final ThemeImage? image;

  /// How the picture fills the screen; `null`: [fitOrDefault].
  final BoxFit? fit;

  /// Where the picture sits; `null`: [alignmentOrDefault].
  final Alignment? alignment;

  /// How opaque the picture is, from 0 to 1; `null`: 1.
  final double? opacity;

  /// The blur radius in logical pixels; `null`: none.
  final double? blur;

  /// Whether the picture is tiled over the screen: a small texture (grain,
  /// paper, a pattern) repeated at its own size with `fit: none`; `null`:
  /// [repeatOrDefault].
  final ImageRepeat? repeat;

  /// [fit], `cover` when not set.
  BoxFit get fitOrDefault => fit ?? BoxFit.cover;

  /// [alignment], the center when not set.
  Alignment get alignmentOrDefault => alignment ?? Alignment.center;

  /// [opacity], 1 when not set.
  double get opacityOrDefault => opacity ?? 1;

  /// [blur], 0 when not set.
  double get blurOrDefault => blur ?? 0;

  /// [repeat], no repeat when not set.
  ImageRepeat get repeatOrDefault => repeat ?? ImageRepeat.noRepeat;

  /// This image's settings over [base]'s: what [this] sets wins.
  ThemeBackgroundImage over(ThemeBackgroundImage? base) => ThemeBackgroundImage(
    image: image ?? base?.image,
    fit: fit ?? base?.fit,
    alignment: alignment ?? base?.alignment,
    opacity: opacity ?? base?.opacity,
    blur: blur ?? base?.blur,
    repeat: repeat ?? base?.repeat,
  );

  static const _keys = ['fit', 'alignment', 'opacity', 'blur', 'repeat'];

  static const _repeats = {
    'no-repeat': ImageRepeat.noRepeat,
    'repeat': ImageRepeat.repeat,
    'repeat-x': ImageRepeat.repeatX,
    'repeat-y': ImageRepeat.repeatY,
  };

  static ThemeBackgroundImage _parse(ThemeProperties p, String path) {
    const fits = BoxFit.values;
    checkThemeKeys(p, path, [...ThemeImage.keys, ..._keys], 'an image');
    return ThemeBackgroundImage(
      image: p['$path.source'] == null
          ? null
          : ThemeImage.parse(p, path, extra: _keys),
      fit: p.read(
        '$path.fit',
        (v) => ThemeValues.enumValue(fits, v),
        fits.map((f) => f.name).join(', '),
      ),
      alignment: p.read('$path.alignment', _alignment, _alignmentFormats),
      opacity: p.read(
        '$path.opacity',
        (v) {
          final n = double.tryParse(v);
          return n != null && n >= 0 && n <= 1 ? n : null;
        },
        'a number from 0 to 1',
      ),
      blur: p.read(
        '$path.blur',
        (v) {
          final n = double.tryParse(v);
          return n != null && n >= 0 ? n : null;
        },
        'a blur radius of 0 or more',
      ),
      repeat: p.read(
        '$path.repeat',
        (v) => _repeats[v.trim().toLowerCase()],
        _repeats.keys.join(', '),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeBackgroundImage &&
      other.image == image &&
      other.fit == fit &&
      other.alignment == alignment &&
      other.opacity == opacity &&
      other.blur == blur &&
      other.repeat == repeat;

  @override
  int get hashCode => Object.hash(image, fit, alignment, opacity, blur, repeat);
}

/// A gradient over the background: `type`, `begin`, `end`, `colors` and
/// optional `stops`.
@immutable
final class ThemeBackgroundGradient {
  /// A gradient of [colors].
  const ThemeBackgroundGradient({
    required this.colors,
    this.type = BackgroundGradientType.linear,
    this.begin,
    this.end,
    this.stops,
  });

  /// Linear or radial.
  final BackgroundGradientType type;

  /// The start of a linear gradient (top by default), the center of a
  /// radial one (the center by default).
  final Alignment? begin;

  /// The end of a linear gradient (bottom by default); a radial gradient
  /// has none.
  final Alignment? end;

  /// At least two colors.
  final List<Color> colors;

  /// Where each color sits, from 0 to 1; as many as [colors], or `null`
  /// for even spacing.
  final List<double>? stops;

  /// The Flutter gradient.
  Gradient toGradient() => switch (type) {
    BackgroundGradientType.linear => LinearGradient(
      begin: begin ?? Alignment.topCenter,
      end: end ?? Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    ),
    BackgroundGradientType.radial => RadialGradient(
      center: begin ?? Alignment.center,
      radius: 0.8,
      colors: colors,
      stops: stops,
    ),
  };

  static const _keys = ['type', 'begin', 'end', 'colors', 'stops'];

  static ThemeBackgroundGradient _parse(ThemeProperties p, String path) {
    checkThemeKeys(p, path, _keys, 'a gradient');
    final colors = p.colorList('$path.colors') ?? const <Color>[];
    if (colors.length < 2) {
      throw ThemePropertyException(
        p.propertyName('$path.colors'),
        (p.list('$path.colors') ?? const []).join(', '),
        'a list of at least two colors',
      );
    }
    final stops = p.list('$path.stops')?.map(double.tryParse).toList();
    if (stops != null &&
        (stops.length != colors.length ||
            stops.any((s) => s == null || s < 0 || s > 1))) {
      throw ThemePropertyException(
        p.propertyName('$path.stops'),
        p.list('$path.stops')!.join(', '),
        'as many numbers from 0 to 1 as there are colors (${colors.length})',
      );
    }
    final type =
        p.read(
          '$path.type',
          (v) => ThemeValues.enumValue(BackgroundGradientType.values, v),
          'linear or radial',
        ) ??
        BackgroundGradientType.linear;
    final end = p.read('$path.end', _alignment, _alignmentFormats);
    if (type == BackgroundGradientType.radial && end != null) {
      throw ThemePropertyException(
        p.propertyName('$path.end'),
        p['$path.end'] ?? '',
        'no end in a radial gradient: radial uses begin as its center',
      );
    }
    return ThemeBackgroundGradient(
      colors: colors,
      type: type,
      begin: p.read('$path.begin', _alignment, _alignmentFormats),
      end: end,
      stops: stops?.cast<double>(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeBackgroundGradient &&
      other.type == type &&
      other.begin == begin &&
      other.end == end &&
      _same(other.colors, colors) &&
      _same(other.stops, stops);

  @override
  int get hashCode => Object.hash(type, begin, end, Object.hashAll(colors));

  static bool _same<T>(List<T>? a, List<T>? b) {
    if (a == null || b == null) {
      return a == b;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// What is painted over the background image: a [color] or a [gradient].
@immutable
final class ThemeBackgroundOverlay {
  /// An overlay of [color], [gradient] or both (the gradient on top).
  const ThemeBackgroundOverlay({this.color, this.gradient});

  /// A flat color.
  final Color? color;

  /// A gradient.
  final ThemeBackgroundGradient? gradient;

  static ThemeBackgroundOverlay _parse(ThemeProperties p, String path) {
    checkThemeKeys(p, path, const ['color', 'gradient'], 'an overlay');
    return ThemeBackgroundOverlay(
      color: p.color('$path.color'),
      gradient: p.children('$path.gradient').isEmpty
          ? null
          : ThemeBackgroundGradient._parse(p, '$path.gradient'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeBackgroundOverlay &&
      other.color == color &&
      other.gradient == gradient;

  @override
  int get hashCode => Object.hash(color, gradient);
}

/// How a change of the background (a theme switch, a new image) is shown:
/// a cross-fade of [duration] along [curve].
@immutable
final class ThemeBackgroundTransition {
  /// A cross-fade of [duration] along [curve].
  const ThemeBackgroundTransition(this.duration, [this.curve = Curves.linear]);

  /// How long the fade takes.
  final Duration duration;

  /// The curve of the fade.
  final Curve curve;

  /// The transition in `<duration> [<curve>]`, such as `400ms ease-out`;
  /// `null` for text that is none.
  static ThemeBackgroundTransition? parse(String text) {
    final trimmed = text.trim();
    final space = trimmed.indexOf(RegExp(r'\s'));
    final duration = ThemeValues.duration(
      space < 0 ? trimmed : trimmed.substring(0, space),
    );
    if (duration == null) {
      return null;
    }
    if (space < 0) {
      return ThemeBackgroundTransition(duration);
    }
    final curve = ThemeValues.anyCurve(trimmed.substring(space + 1).trim());
    return curve == null ? null : ThemeBackgroundTransition(duration, curve);
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeBackgroundTransition &&
      other.duration == duration &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(duration, curve);
}

/// The `background` of a theme (or of one of its `screens`): a base
/// color, an image, an overlay, an animation of the image and the
/// transition to a new background.
///
/// ```yaml
/// background:
///   color: $colors.surface-container-lowest
///   image: { source: https://cdn.example.com/bg.jpg, fit: cover, blur: 4 }
///   overlay:
///     gradient: { type: linear, colors: [transparent, '#CC0A0C12'] }
///   animation: background-drift      # an animations.* name
///   effect: drift                    # drift | zoom | pulse
///   transition: 400ms ease-out
///   frame-rate: 15                   # or every-frame
///   screens:
///     login: { image: { source: packages/neon_ui/assets/images/login.jpg } }
/// ```
///
/// Read it with `context.theme.background`; show it with
/// `ThemeBackground`. Values a theme does not set are `null`.
@immutable
final class ThemeBackgroundData {
  /// A background of the given parts.
  const ThemeBackgroundData({
    this.color,
    this.image,
    this.overlay,
    this.animation,
    this.effect,
    this.transition,
    this.frameRate,
    this.screens = const {},
  });

  /// The base color below everything; `null`: the theme's surface.
  final Color? color;

  /// The image and how it fills the screen.
  final ThemeBackgroundImage? image;

  /// What is painted over the image.
  final ThemeBackgroundOverlay? overlay;

  /// The name of the `animations.<name>` that moves the image.
  final String? animation;

  /// How the image moves: [BackgroundEffect.drift] when only
  /// [animation] is set.
  final BackgroundEffect? effect;

  /// The cross-fade to a new background; `null`: [defaultTransition].
  final ThemeBackgroundTransition? transition;

  /// How many times a second the moving image is drawn again
  /// (`frame-rate`); [double.infinity] (`every-frame`) at every frame of
  /// the screen; `null`: [defaultFrameRate]. A slow drift moves a pixel or
  /// two a second: drawn at every frame it keeps the whole screen
  /// repainting, which takes the time of scrolling and the battery.
  final double? frameRate;

  /// The frame rate when the theme sets none: 15 a second.
  static const defaultFrameRate = 15.0;

  /// The frame rate to use: [frameRate] or [defaultFrameRate].
  double get frameRateOrDefault => frameRate ?? defaultFrameRate;

  /// The overrides of single screens, by canonical name.
  final Map<String, ThemeBackgroundData> screens;

  /// The fade when the theme sets none: 300 ms, ease-out.
  static const defaultTransition = ThemeBackgroundTransition(
    Duration(milliseconds: 300),
    Curves.easeOut,
  );

  /// The effect to play: [effect], else drift when there is an
  /// [animation], else none.
  BackgroundEffect? get effectiveEffect =>
      animation == null ? null : (effect ?? BackgroundEffect.drift);

  /// The fade to use: [transition] or [defaultTransition].
  ThemeBackgroundTransition get transitionOrDefault =>
      transition ?? defaultTransition;

  /// The background of the screen [name]: the keys of `screens.<name>`
  /// over this background's own; this one when the screen has none. The
  /// name is compared without case, `-` and `_`.
  ThemeBackgroundData screen(String name) {
    final own = screens[ThemeValues.canonical(name)];
    if (own == null) {
      return this;
    }
    return ThemeBackgroundData(
      color: own.color ?? color,
      image: own.image == null ? image : own.image!.over(image),
      overlay: own.overlay ?? overlay,
      animation: own.animation ?? animation,
      effect: own.effect ?? effect,
      transition: own.transition ?? transition,
      frameRate: own.frameRate ?? frameRate,
    );
  }

  /// Every image of the background, the screens' included.
  Iterable<ThemeImage> get images sync* {
    final own = image?.image;
    if (own != null) {
      yield own;
    }
    for (final screen in screens.values) {
      yield* screen.images;
    }
  }

  static const _keys = [
    'color',
    'image',
    'overlay',
    'animation',
    'effect',
    'transition',
    'frame-rate',
  ];

  /// Reads `background` of [p]; `null` when the theme has none. Throws a
  /// [ThemePropertyException] naming the property for a wrong value or
  /// key, an `animation` that is no `animations.*`, or an image without a
  /// source.
  static ThemeBackgroundData? parse(ThemeProperties p) {
    if (p.children('background').isEmpty) {
      return null;
    }
    return _parse(p, 'background', top: true);
  }

  /// Reads the background written at [path] of [p] (the splash's
  /// `background` has the keys of the theme's, without `screens`); `null`
  /// when there is nothing at [path].
  static ThemeBackgroundData? parseAt(ThemeProperties p, String path) =>
      p.children(path).isEmpty ? null : _parse(p, path);

  static ThemeBackgroundData _parse(
    ThemeProperties p,
    String path, {
    bool top = false,
    ThemeBackgroundData? parent,
  }) {
    checkThemeKeys(p, path, [
      ..._keys,
      if (top) 'screens',
    ], top ? 'the background' : 'a screen of the background');
    final animation = p['$path.animation'];
    if (animation != null) {
      final names = p.children('animations').toList();
      if (!names.contains(ThemeValues.canonical(animation))) {
        throw ThemePropertyException(
          p.propertyName('$path.animation'),
          animation,
          names.isEmpty
              ? 'the name of an animations.<name> (this theme has none)'
              : 'the name of an animations.<name>: ${names.join(', ')}'
                    '${didYouMean(animation, names)}',
        );
      }
    }
    final imagePath = '$path.image';
    final image = p.children(imagePath).isEmpty
        ? null
        : ThemeBackgroundImage._parse(p, imagePath);
    if (image != null &&
        image.image == null &&
        (top || parent?.image == null)) {
      throw ThemePropertyException(
        p.propertyName('$imagePath.source'),
        '',
        'an asset path or an https:// URL (every image needs a source)',
      );
    }
    final effectText = p['$path.effect'];
    if (effectText != null && animation == null) {
      throw ThemePropertyException(
        p.propertyName('$path.effect'),
        effectText,
        "an animation to play: effect needs 'animation' (the name of an "
        'animations.<name>) next to it',
      );
    }
    final transitionText = p['$path.transition'];
    final screens = <String, ThemeBackgroundData>{};
    final data = ThemeBackgroundData(
      color: p.color('$path.color'),
      image: image,
      overlay: p.children('$path.overlay').isEmpty
          ? null
          : ThemeBackgroundOverlay._parse(p, '$path.overlay'),
      animation: animation,
      effect: p.read(
        '$path.effect',
        (v) => ThemeValues.enumValue(BackgroundEffect.values, v),
        'drift, zoom or pulse',
      ),
      frameRate: p.read(
        '$path.framerate',
        (v) => ThemeValues.canonical(v) == 'everyframe'
            ? double.infinity
            : switch (ThemeValues.number(v)) {
                final n? when n > 0 => n.toDouble(),
                _ => null,
              },
        'a number of frames a second over zero, or every-frame',
      ),
      transition: transitionText == null
          ? null
          : ThemeBackgroundTransition.parse(transitionText) ??
                (throw ThemePropertyException(
                  p.propertyName('$path.transition'),
                  transitionText,
                  "'<duration> [<curve>]' like 400ms ease-out; curves: "
                  '${ThemeValues.curveNames.join(', ')}',
                )),
      screens: screens,
    );
    if (top) {
      for (final name in p.children('$path.screens')) {
        screens[name] = _parse(p, '$path.screens.$name', parent: data);
      }
    }
    return data;
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeBackgroundData &&
      other.color == color &&
      other.image == image &&
      other.overlay == overlay &&
      other.animation == animation &&
      other.effect == effect &&
      other.transition == transition &&
      other.frameRate == frameRate;

  @override
  int get hashCode => Object.hash(
    color,
    image,
    overlay,
    animation,
    effect,
    transition,
    frameRate,
  );
}
