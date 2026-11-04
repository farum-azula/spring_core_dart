import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart'
    show checkThemeKeys;
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// The values of one `loaders.<name>`, read by key
/// (`values.color('seam.fill')`, `values.number('door.edge.width')`; a
/// dot goes one level down; `-`, `_` and case do not matter).
///
/// Props classes the generator writes for a loader kind wrap this; a
/// painter that wants untyped access reads `frame.values`. A value that
/// is missing or of another type throws a [ThemePropertyException] that
/// names the property; the `...OrNull` readers return `null` for a missing
/// one (a wrong one still throws).
final class LoaderValues {
  /// The values below [base] of [properties]; internal to the starter.
  LoaderValues(this._p, this._base);

  final ThemeProperties _p;
  final String _base;

  String _path(String key) => [
    _base,
    for (final part in key.split('.'))
      if (part.isNotEmpty) ThemeValues.canonical(part),
  ].join('.');

  /// Whether the theme gives [key] (a value or a map).
  bool has(String key) {
    final path = _path(key);
    return _p[path] != null || _p.children(path).isNotEmpty;
  }

  /// The names directly below [key] (the loader itself without [key]), in
  /// canonical form.
  Set<String> keys([String key = '']) =>
      _p.children(key.isEmpty ? _base : _path(key));

  /// The values below [key], as a reader of their own.
  LoaderValues at(String key) => LoaderValues(_p, _path(key));

  Never _missing(String key, String expected) => throw ThemePropertyException(
    _p.propertyName(_path(key)),
    '',
    '$expected (the loader needs it)',
  );

  /// The color [key]: a color or a `{ color, mix, alpha }` object.
  Color color(String key) => colorOrNull(key) ?? _missing(key, 'a color');

  /// The color [key], or `null` when the theme does not give it.
  Color? colorOrNull(String key) => _p.color(_path(key));

  /// The number [key].
  double number(String key) => numberOrNull(key) ?? _missing(key, 'a number');

  /// The number [key], or `null`.
  double? numberOrNull(String key) =>
      _p.read(_path(key), ThemeValues.number, 'a number');

  /// The duration [key] (`250ms`, `1.2s`).
  Duration duration(String key) =>
      durationOrNull(key) ?? _missing(key, 'a duration like 250ms or 1.2s');

  /// The duration [key], or `null`.
  Duration? durationOrNull(String key) => _p.read(
    _path(key),
    ThemeValues.duration,
    'a duration like 250ms or 1.2s',
  );

  /// The text [key].
  String text(String key) => textOrNull(key) ?? _missing(key, 'a text');

  /// The text [key], or `null`.
  String? textOrNull(String key) => _p[_path(key)];

  /// The boolean [key] (`true` or `false`).
  bool boolean(String key) =>
      booleanOrNull(key) ?? _missing(key, 'true or false');

  /// The boolean [key], or `null`.
  bool? booleanOrNull(String key) =>
      _p.read(_path(key), ThemeValues.boolean, 'true or false');

  /// The curve [key]: a name or four numbers.
  Curve curve(String key) =>
      curveOrNull(key) ?? _missing(key, 'a curve like ease-out');

  /// The curve [key], or `null`.
  Curve? curveOrNull(String key) => _p.read(
    _path(key),
    ThemeValues.anyCurve,
    'a curve: ${ThemeValues.curveNames.join(', ')}, or four numbers',
  );

  /// The animation [key], written inline (`duration`, `curve`, `repeat`)
  /// or as the name of an `animations.<name>`.
  AnimationSpec animation(String key) =>
      animationOrNull(key) ?? _missing(key, 'an animation');

  /// The animation [key], or `null`.
  AnimationSpec? animationOrNull(String key) {
    final path = _path(key);
    final named = _p[path];
    if (named != null) {
      final name = ThemeValues.canonical(named);
      if (!_p.children('animations').contains(name)) {
        throw ThemePropertyException(
          _p.propertyName(path),
          named,
          'the name of an animations.<name>: '
          '${_p.children('animations').join(', ')}'
          '${didYouMean(named, _p.children('animations'))}',
        );
      }
      return AnimationSpec.parseAt(_p, 'animations.$name');
    }
    return _p.children(path).isEmpty ? null : AnimationSpec.parseAt(_p, path);
  }
}

/// One step of a loader: an animation that plays once or loops, or a step
/// that follows the progress the loader is given.
@immutable
final class ThemeLoaderPhase {
  /// A phase that plays [animation].
  const ThemeLoaderPhase.animated(AnimationSpec this.animation)
    : minDuration = Duration.zero;

  /// A phase driven by the progress (`{progress: true}`). With a
  /// [minDuration] the progress it shows is the smaller of the real one and
  /// the time that has passed in the phase (eased) over [minDuration], so
  /// the fill takes at least that long and never jumps to the end when the
  /// work is fast.
  const ThemeLoaderPhase.progress({this.minDuration = Duration.zero})
    : animation = null;

  /// What the phase plays; `null` for a phase that follows the progress.
  final AnimationSpec? animation;

  /// The least time a phase that follows the progress takes to fill
  /// (`min-duration`); zero: it follows the real progress at once.
  final Duration minDuration;

  /// Whether the phase follows the progress, not time.
  bool get followsProgress => animation == null;

  @override
  bool operator ==(Object other) =>
      other is ThemeLoaderPhase &&
      other.animation == animation &&
      other.minDuration == minDuration;

  @override
  int get hashCode => Object.hash(animation, minDuration);
}

/// The look of a built-in loader kind; each kind reads the fields it
/// documents, and leaves the others `null`.
@immutable
final class BuiltInLoaderLook {
  /// A look; internal to the starter.
  const BuiltInLoaderLook({
    this.color,
    this.size,
    this.stroke,
    this.track,
    this.count,
    this.gap,
    this.height,
    this.width,
    this.radius,
    this.base,
    this.highlight,
    this.shimmer,
    this.angle,
  });

  /// The color of the moving part; `null`: the theme's primary color.
  final Color? color;

  /// The diameter (spinner, pulse) or the dot size (dots).
  final double? size;

  /// The line width of a spinner.
  final double? stroke;

  /// The color of the track (spinner, bar); `null`: none.
  final Color? track;

  /// The number of dots.
  final int? count;

  /// The space between dots.
  final double? gap;

  /// The thickness of a bar.
  final double? height;

  /// The length of a bar; `null`: all the room it has.
  final double? width;

  /// The corner radius of a bar or a skeleton.
  final double? radius;

  /// The color of a skeleton.
  final Color? base;

  /// The color of a skeleton's moving highlight.
  final Color? highlight;

  /// How the skeleton's highlight moves: its duration, curve and repeat.
  final AnimationSpec? shimmer;

  /// The slant of the highlight in degrees.
  final double? angle;

  @override
  bool operator ==(Object other) =>
      other is BuiltInLoaderLook &&
      other.color == color &&
      other.size == size &&
      other.stroke == stroke &&
      other.track == track &&
      other.count == count &&
      other.gap == gap &&
      other.height == height &&
      other.width == width &&
      other.radius == radius &&
      other.base == base &&
      other.highlight == highlight &&
      other.shimmer == shimmer &&
      other.angle == angle;

  @override
  int get hashCode => Object.hash(
    color,
    size,
    stroke,
    track,
    count,
    gap,
    height,
    width,
    radius,
    base,
    highlight,
    shimmer,
    angle,
  );
}

/// One `loaders.<name>` of the theme.
///
/// ```yaml
/// loaders:
///   dots: { kind: dots, color: $colors.primary, size: 10, count: 3 }
/// ```
///
/// Built-in kinds and their keys (all optional; colors in the theme's
/// color form, durations like `900ms`, `animation` inline or the name of
/// an `animations.*`):
///
/// - `spinner`: `color`, `size` (24), `stroke` (3), `track` (none),
///   `animation` (1s linear loop).
/// - `dots`: `color`, `size` (8), `count` (3), `gap` (half the size),
///   `animation` (900ms ease-in-out loop).
/// - `pulse`: `color`, `size` (24), `animation` (1.2s ease-in-out,
///   back and forth).
/// - `bar`: `color`, `track` (the color at 20 %), `height` (4), `width`
///   (all the room), `radius` (half the height), `animation` (1.4s
///   ease-in-out loop; only for the indeterminate bar).
/// - `skeleton`: `base`, `highlight`, `radius` (8), `shimmer` with
///   `duration` (1.2s), `curve` (linear) and `angle` (20).
///
/// A kind of the app's own (`@ThemeLoaderKind`) takes the keys it
/// registered, `phases` and `web`. Show a loader with `ThemeLoader`, a
/// skeleton with `ThemeSkeleton`.
final class ThemeLoaderSpec {
  const ThemeLoaderSpec._(
    this.name,
    this.kind,
    this.phases,
    this.values,
    this.look,
    this.animation,
    this.web,
  );

  /// The built-in kinds.
  static const builtInKinds = ['spinner', 'dots', 'pulse', 'bar', 'skeleton'];

  /// A loader of a built-in [kind] with the given look; for tests and for
  /// code that builds a loader without a theme.
  ThemeLoaderSpec.builtIn(
    this.kind, {
    this.name = '',
    this.look = const BuiltInLoaderLook(),
    AnimationSpec? animation,
  }) : assert(builtInKinds.contains(kind), 'not a built-in kind'),
       phases = {
         'main': ThemeLoaderPhase.animated(
           animation ?? _defaultAnimation(kind, look),
         ),
       },
       values = null,
       web = null,
       animation = animation ?? _defaultAnimation(kind, look);

  /// The loader's name in canonical form (`neondoors`).
  final String name;

  /// The `kind`, in canonical form.
  final String kind;

  /// The phases in the order they play (a built-in kind has one, `main`).
  final Map<String, ThemeLoaderPhase> phases;

  /// All keys of the loader, for a kind of the app's own and its props.
  final LoaderValues? values;

  /// The look of a built-in kind; `null` for a kind of the app's own.
  final BuiltInLoaderLook? look;

  /// How a built-in kind moves.
  final AnimationSpec? animation;

  /// The `web` key: the HTML file that shows the kind before Flutter runs
  /// (the generator's page loader reads it); `null` when not given.
  final String? web;

  /// Whether the loader has phases of its own (more than the one a
  /// built-in kind has).
  bool get hasPhases => phases.length > 1;

  /// Whether this is one of [builtInKinds].
  bool get isBuiltIn => builtInKinds.contains(kind);

  static AnimationSpec _defaultAnimation(String kind, BuiltInLoaderLook? look) {
    return switch (kind) {
      'spinner' => const AnimationSpec(
        duration: Duration(seconds: 1),
        repeat: AnimationRepeat.loop,
      ),
      'dots' => const AnimationSpec(
        duration: Duration(milliseconds: 900),
        curve: Curves.easeInOut,
        repeat: AnimationRepeat.loop,
      ),
      'pulse' => const AnimationSpec(
        duration: Duration(milliseconds: 1200),
        curve: Curves.easeInOut,
        repeat: AnimationRepeat.reverse,
      ),
      'bar' => const AnimationSpec(
        duration: Duration(milliseconds: 1400),
        curve: Curves.easeInOut,
        repeat: AnimationRepeat.loop,
      ),
      _ =>
        look?.shimmer ??
            const AnimationSpec(
              duration: Duration(milliseconds: 1200),
              repeat: AnimationRepeat.loop,
            ),
    };
  }

  // The keys of each built-in kind.
  static const _keys = {
    'spinner': ['color', 'size', 'stroke', 'track', 'animation'],
    'dots': ['color', 'size', 'count', 'gap', 'animation'],
    'pulse': ['color', 'size', 'animation'],
    'bar': ['color', 'track', 'height', 'width', 'radius', 'animation'],
    'skeleton': ['base', 'highlight', 'radius', 'shimmer'],
  };

  static const _common = ['kind', 'web'];
  static const _phaseKeys = ['progress', 'min-duration'];

  /// Reads `loaders.<name>` of [p]. Throws a [ThemePropertyException] for
  /// an unknown kind (naming the kinds, with a did-you-mean), a key the
  /// kind does not take, a value of the wrong type or a malformed phase.
  factory ThemeLoaderSpec.parse(ThemeProperties p, String name) {
    final base = 'loaders.$name';
    final kindText = p['$base.kind'];
    final registered = ThemeLoaderKinds.names;
    final known = [...builtInKinds, ...registered];
    if (kindText == null) {
      throw ThemePropertyException(
        p.propertyName('$base.kind'),
        '',
        'a kind: ${known.join(', ')} (every loader has one)',
      );
    }
    final kind = ThemeValues.canonical(kindText);
    final registration = ThemeLoaderKinds.lookup(kind);
    if (!builtInKinds.contains(kind) && registration == null) {
      throw ThemePropertyException(
        p.propertyName('$base.kind'),
        kindText,
        'a kind: ${known.join(', ')}${didYouMean(kindText, known)}'
        "; a kind of the app's own needs @ThemeLoaderKind('$kindText')",
      );
    }
    final values = LoaderValues(p, base);
    final webText = p['$base.web'];
    if (builtInKinds.contains(kind)) {
      return _builtIn(p, name, kind, base, values, webText);
    }
    final allowed = registration!.keys;
    if (allowed != null) {
      checkThemeKeys(p, base, [
        ..._common,
        'phases',
        ...allowed,
      ], "a '$kindText' loader");
    }
    // A kind that lists no keys takes any; its props check them.
    final phases = _phases(p, base);
    final spec = ThemeLoaderSpec._(
      name,
      kind,
      phases,
      values,
      null,
      null,
      webText,
    );
    registration.makeProps(values); // reads the keys the kind needs now
    return spec;
  }

  static ThemeLoaderSpec _builtIn(
    ThemeProperties p,
    String name,
    String kind,
    String base,
    LoaderValues values,
    String? web,
  ) {
    checkThemeKeys(p, base, [
      ..._common,
      ..._keys[kind]!,
    ], "a '$kind' loader (one implicit phase, no 'phases')");
    final animation = values.animationOrNull('animation');
    final shimmerKeys = ['duration', 'curve', 'angle'];
    AnimationSpec? shimmer;
    double? angle;
    if (kind == 'skeleton' && p.children('$base.shimmer').isNotEmpty) {
      checkThemeKeys(p, '$base.shimmer', shimmerKeys, 'the shimmer');
      shimmer = AnimationSpec(
        duration:
            values.durationOrNull('shimmer.duration') ??
            const Duration(milliseconds: 1200),
        curve: values.curveOrNull('shimmer.curve') ?? Curves.linear,
        repeat: AnimationRepeat.loop,
      );
      angle = values.numberOrNull('shimmer.angle');
    }
    final count = values.numberOrNull('count');
    if (count != null && (count < 1 || count != count.roundToDouble())) {
      throw ThemePropertyException(
        p.propertyName('$base.count'),
        '${p['$base.count']}',
        'a whole number of 1 or more',
      );
    }
    final look = BuiltInLoaderLook(
      color: values.colorOrNull('color'),
      size: values.numberOrNull('size'),
      stroke: values.numberOrNull('stroke'),
      track: values.colorOrNull('track'),
      count: count?.round(),
      gap: values.numberOrNull('gap'),
      height: values.numberOrNull('height'),
      width: values.numberOrNull('width'),
      radius: values.numberOrNull('radius'),
      base: values.colorOrNull('base'),
      highlight: values.colorOrNull('highlight'),
      shimmer: shimmer,
      angle: angle,
    );
    final moving = animation ?? _defaultAnimation(kind, look);
    return ThemeLoaderSpec._(
      name,
      kind,
      {'main': ThemeLoaderPhase.animated(moving)},
      values,
      look,
      moving,
      web,
    );
  }

  static Map<String, ThemeLoaderPhase> _phases(ThemeProperties p, String base) {
    final result = <String, ThemeLoaderPhase>{};
    for (final phase in p.children('$base.phases')) {
      final path = '$base.phases.$phase';
      final kids = p.children(path);
      if (kids.contains('progress')) {
        checkThemeKeys(p, path, _phaseKeys, 'a phase that follows progress');
        final on = p.read(
          '$path.progress',
          ThemeValues.boolean,
          'true (the phase follows the progress)',
        );
        if (on != true) {
          throw ThemePropertyException(
            p.propertyName('$path.progress'),
            p['$path.progress'] ?? '',
            'true, or an animation (duration, curve, repeat) for the phase',
          );
        }
        final min =
            p.read(
              '$path.minduration',
              ThemeValues.duration,
              'a duration like 2.5s or 800ms',
            ) ??
            Duration.zero;
        if (min.isNegative) {
          throw ThemePropertyException(
            p.propertyName('$path.minduration'),
            p['$path.minduration'] ?? '',
            'a duration of 0 or more',
          );
        }
        result[phase] = ThemeLoaderPhase.progress(minDuration: min);
      } else {
        result[phase] = ThemeLoaderPhase.animated(
          AnimationSpec.parseAt(p, path),
        );
      }
    }
    return result;
  }
}

/// What a loader paints or builds with: where each phase is, the progress
/// and the values of the loader.
///
/// [P] is the props class of the kind (the generator writes one from the
/// loader's keys); [values] is the same data untyped.
final class LoaderFrame<P> {
  /// A frame; the loader widgets make these, tests make their own.
  const LoaderFrame({
    required this.phases,
    required this.props,
    required this.values,
    this.progress,
    this.reduceMotion = false,
    this.elapsed = Duration.zero,
  });

  /// How long the loader has been running; for movement that is not a
  /// phase (a flicker). Zero when the system asks for less motion.
  final Duration elapsed;

  /// Each phase's position, 0 to 1, by canonical name.
  final Map<String, double> phases;

  /// The progress the loader is given, 0 to 1 (the real one); `null` when
  /// it is indeterminate. The phase that follows progress shows the
  /// smaller of this and its `min-duration` clock: read `phase('fill')`
  /// for what to draw.
  final double? progress;

  /// The loader's keys as the kind's props class reads them.
  final P props;

  /// The loader's keys, untyped.
  final LoaderValues values;

  /// Whether the system asks for less motion: every phase is at its end,
  /// and nothing should flicker or shimmer.
  final bool reduceMotion;

  /// How far the phase [name] is, from 0 (not started) to 1 (done). Throws
  /// a [StateError] for a phase the loader does not have.
  double phase(String name) =>
      phases[ThemeValues.canonical(name)] ??
      (throw StateError(
        "The loader has no phase '$name'; it has ${phases.keys.join(', ')}.",
      ));
}

/// A loader kind of the app's own that paints a canvas. Mark the subclass
/// with `@ThemeLoaderKind('name')`.
abstract class ThemeLoaderPainter<P> {
  /// A painter; subclasses are created without arguments by the generated
  /// registration.
  const ThemeLoaderPainter();

  /// Paints the loader in [size] at [frame].
  void paint(Canvas canvas, Size size, LoaderFrame<P> frame);
}

/// A loader kind of the app's own that builds widgets. Mark the subclass
/// with `@ThemeLoaderKind('name')`.
abstract class ThemeLoaderWidget<P> {
  /// A widget builder; subclasses are created without arguments by the
  /// generated registration.
  const ThemeLoaderWidget();

  /// Builds the loader at [frame].
  Widget build(BuildContext context, LoaderFrame<P> frame);
}

/// What `ThemeLoaderKinds` holds for one kind.
final class LoaderKindRegistration {
  const LoaderKindRegistration._(
    this.name,
    this.keys,
    this._props,
    this._paint,
    this._build,
  );

  /// The kind's name in canonical form.
  final String name;

  /// The keys the kind takes besides `kind`, `phases` and `web`; `null`:
  /// any.
  final List<String>? keys;

  final Object? Function(LoaderValues values)? _props;
  final void Function(Canvas canvas, Size size, LoaderFrame<Object?> frame)?
  _paint;
  final Widget Function(BuildContext context, LoaderFrame<Object?> frame)?
  _build;

  /// Whether the kind paints a canvas (else it builds widgets).
  bool get paints => _paint != null;

  /// The props of the loader with [values]: the registered props
  /// function's result, or [values] itself.
  Object? makeProps(LoaderValues values) => _props?.call(values) ?? values;

  /// Paints a kind that [paints]; [frame]'s props are the kind's `P`.
  void paint(Canvas canvas, Size size, LoaderFrame<Object?> frame) =>
      _paint!(canvas, size, frame);

  /// Builds a kind that does not [paints].
  Widget build(BuildContext context, LoaderFrame<Object?> frame) =>
      _build!(context, frame);
}

/// The loader kinds of the app's own, by name: what `kind:` in a theme
/// may name besides the built-in ones.
///
/// The generated `@ThemeLoaderKind` code fills it before the context
/// starts (the themes are read at the start and check the kinds); code
/// without the generator calls [register] itself.
///
/// ```dart
/// ThemeLoaderKinds.register<DoorsLoaderProps>(
///   'doors',
///   painter: DoorsLoader(),
///   props: DoorsLoaderProps.from,
///   keys: ['door', 'seam', 'web'],
/// );
/// ```
abstract final class ThemeLoaderKinds {
  static final _kinds = <String, LoaderKindRegistration>{};

  /// Registers the kind [name] with a [painter] or a [widget] (one of
  /// them), [props] reading its keys into `P` (the loader's
  /// [LoaderValues] are `P` without it) and the [keys] it takes (`null`:
  /// any). A kind registered again replaces the earlier one (a hot
  /// restart runs the registration again).
  static void register<P>(
    String name, {
    ThemeLoaderPainter<P>? painter,
    ThemeLoaderWidget<P>? widget,
    P Function(LoaderValues values)? props,
    Iterable<String>? keys,
  }) {
    if ((painter == null) == (widget == null)) {
      throw ArgumentError(
        "The loader kind '$name' needs a painter or a widget, not both and "
        'not neither.',
      );
    }
    final canonical = ThemeValues.canonical(name);
    if (ThemeLoaderSpec.builtInKinds.contains(canonical)) {
      throw ArgumentError.value(name, 'name', 'is a built-in loader kind');
    }
    _kinds[canonical] = LoaderKindRegistration._(
      canonical,
      keys?.toList(),
      props == null ? null : (values) => props(values),
      painter == null
          ? null
          : (canvas, size, frame) => painter.paint(canvas, size, _typed(frame)),
      widget == null
          ? null
          : (context, frame) => widget.build(context, _typed(frame)),
    );
  }

  // The same frame with the props as the kind's `P`.
  static LoaderFrame<P> _typed<P>(LoaderFrame<Object?> frame) => LoaderFrame<P>(
    phases: frame.phases,
    props: frame.props as P,
    values: frame.values,
    progress: frame.progress,
    reduceMotion: frame.reduceMotion,
    elapsed: frame.elapsed,
  );

  /// The kind [name] (any case, `-`, `_`); `null` when none is
  /// registered.
  static LoaderKindRegistration? lookup(String name) =>
      _kinds[ThemeValues.canonical(name)];

  /// The registered kinds' names in canonical form.
  static List<String> get names => List.unmodifiable(_kinds.keys);

  /// Forgets every kind; for tests.
  @visibleForTesting
  static void clear() => _kinds.clear();
}
