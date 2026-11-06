import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/loader_hand_off.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stages.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_background.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_background_widget.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_loader.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_loader_widget.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// The `splash` of a theme: what shows while the application starts.
///
/// ```yaml
/// splash:
///   background: { color: $colors.surface-container-lowest }
///   logo: { source: assets/images/logo.png, size: 96 }
///   title: NEON
///   loader: neon-doors              # a loaders.* name
///   animation: splash-in            # an animations.* name, for the logo
///   min-duration: 1.2s
///   exit: { transition: 400ms ease-out, reveal: true }
/// ```
///
/// All keys are optional. `SpringApplicationWidget` shows it from the
/// moment the properties are read until the context is ready (and
/// [minDuration] is over), then fades it out over the exit transition;
/// its own `splash:` builder wins over it. With `exit.reveal` the app
/// shows through as soon as the loader's last phase starts (doors that
/// part over the app, not over the splash's background). Read it with
/// `context.theme.splash`.
@immutable
final class ThemeSplashData {
  /// A splash of the given parts.
  const ThemeSplashData({
    this.background,
    this.logo,
    this.logoSize,
    this.title,
    this.loader,
    this.animation,
    this.minDuration = Duration.zero,
    this.exit = defaultExit,
    this.reveal = false,
  });

  /// The keys a splash takes.
  static const keys = [
    'background',
    'logo',
    'title',
    'loader',
    'animation',
    'min-duration',
    'exit',
  ];

  /// The fade out when the theme sets none: 300 ms, ease-out.
  static const defaultExit = ThemeBackgroundTransition(
    Duration(milliseconds: 300),
    Curves.easeOut,
  );

  /// The background (the keys of the theme's `background`, without
  /// `screens`); `null`: the theme's surface color.
  final ThemeBackgroundData? background;

  /// The logo; `null`: none.
  final ThemeImage? logo;

  /// The width of the logo; `null`: 96.
  final double? logoSize;

  /// The title under the logo; `null`: none.
  final String? title;

  /// The name of the `loaders.*` shown (canonical); `null`: none.
  final String? loader;

  /// The name of the `animations.*` that plays on the logo (canonical);
  /// `null`: none.
  final String? animation;

  /// The splash stays at least this long.
  final Duration minDuration;

  /// The fade out once the app is ready.
  final ThemeBackgroundTransition exit;

  /// `exit.reveal`: when the last phase of a loader with phases of its own
  /// starts, the background, the logo and the title go at once, so the
  /// loader plays its way out over the app (built under the splash by
  /// then), not over the splash. No effect for a built-in loader or none.
  final bool reveal;

  /// Every image of the splash.
  Iterable<ThemeImage> get images sync* {
    yield* background?.images ?? const [];
    if (logo != null) {
      yield logo!;
    }
  }

  /// Reads `splash` of [p]; `null` when the theme has no `splash` map (a
  /// plain `splash: ripple` is the ink splash of taps, not this). Throws a
  /// [ThemePropertyException] for a wrong key or value, a `loader` that is
  /// no `loaders.*` or an `animation` that is no `animations.*`.
  static ThemeSplashData? parse(ThemeProperties p) {
    if (p.children('splash').isEmpty) {
      return null;
    }
    checkThemeKeys(p, 'splash', keys, 'the splash');
    String? named(String key, String group) {
      final text = p['splash.$key'];
      if (text == null) {
        return null;
      }
      final names = p.children(group).toList();
      if (!names.contains(ThemeValues.canonical(text))) {
        throw ThemePropertyException(
          p.propertyName('splash.$key'),
          text,
          names.isEmpty
              ? 'the name of a $group.<name> (this theme has none)'
              : 'the name of a $group.<name>: ${names.join(', ')}'
                    '${didYouMean(text, names)}',
        );
      }
      return ThemeValues.canonical(text);
    }

    final transitionText = p['splash.exit.transition'];
    checkThemeKeys(p, 'splash.exit', [
      'transition',
      'reveal',
    ], 'the exit');
    final logoPath = 'splash.logo';
    return ThemeSplashData(
      background: ThemeBackgroundData.parseAt(p, 'splash.background'),
      logo: p.children(logoPath).isEmpty
          ? null
          : ThemeImage.parse(p, logoPath, extra: const ['size']),
      logoSize: p.read(
        '$logoPath.size',
        ThemeValues.number,
        'a number of logical pixels',
      ),
      title: p['splash.title'],
      loader: named('loader', 'loaders'),
      animation: named('animation', 'animations'),
      minDuration:
          p.read(
            'splash.minduration',
            ThemeValues.duration,
            'a duration like 1.2s or 800ms',
          ) ??
          Duration.zero,
      exit: transitionText == null
          ? defaultExit
          : ThemeBackgroundTransition.parse(transitionText) ??
                (throw ThemePropertyException(
                  p.propertyName('splash.exit.transition'),
                  transitionText,
                  "'<duration> [<curve>]' like 400ms ease-out; curves: "
                  '${ThemeValues.curveNames.join(', ')}',
                )),
      reveal:
          p.read(
            'splash.exit.reveal',
            ThemeValues.boolean,
            'true or false',
          ) ??
          false,
    );
  }
}

/// The splash of [theme] on screen: background, logo, title and loader,
/// following [progress] (0 to 1); when [ready] is set the loader ends,
/// and once [ThemeSplashData.minDuration] is over too, the splash fades
/// out and calls [onExited]. [onShown] is called after the first frame
/// that painted it, its logo included (at most [ThemeSplash.logoWait]
/// later): on the web the page's loader, drawn the same way, goes then, so
/// the hand-over shows nothing move.
///
/// `SpringApplicationWidget` shows it; it is public for tests and for
/// apps that show the splash themselves.
class ThemeSplash extends StatefulWidget {
  /// The splash of [theme]'s `splash`; [theme] must have one.
  const ThemeSplash({
    required this.theme,
    required this.progress,
    required this.ready,
    this.stages,
    this.onShown,
    this.onExiting,
    this.onExited,
    super.key,
  });

  /// The start's stages, given to the loader (`LoaderFrame.stage`, the
  /// tracks that follow a stage).
  final SplashStages? stages;

  /// Called once, when the exit starts (the loader's last phase with
  /// `reveal`, or the fade).
  final VoidCallback? onExiting;

  /// The theme whose `splash` is shown (it also gives the loaders).
  final SpringThemeData theme;

  /// The start's progress, 0 to 1.
  final ValueListenable<double> progress;

  /// Whether the application is ready.
  final bool ready;

  /// Called once, after the first frame that has the splash painted, with
  /// its logo once the logo's image is ready (or [logoWait] has passed).
  final VoidCallback? onShown;

  /// How long [onShown] waits for the logo's image at most.
  static const logoWait = Duration(milliseconds: 1500);

  /// Called once, when the fade out is over.
  final VoidCallback? onExited;

  @override
  State<ThemeSplash> createState() => _ThemeSplashState();
}

class _ThemeSplashState extends State<ThemeSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exit = AnimationController(vsync: this);
  Timer? _minimum;
  bool _minimumOver = false;
  bool _loaderDone = false;
  bool _exiting = false;
  // The loader's last phase plays with `exit.reveal`: only the loader is
  // drawn, the app shows through.
  bool _revealing = false;
  // How far the web page loader was when this splash took over; the loader
  // goes on from there instead of playing its first phases again.
  final double? _resumed = LoaderHandOff.pageProgress();
  final Duration? _resumedElapsed = LoaderHandOff.pageElapsed();
  // [ThemeSplash.onShown] waits for the logo's image: the web page's
  // loader, which already shows the logo, stays above until then.
  bool _shown = false;
  Timer? _logoTimeout;
  ImageStream? _logoStream;
  ImageStreamListener? _logoListener;

  ThemeSplashData get _data => widget.theme.splash!;

  @override
  void initState() {
    super.initState();
    final min = _data.minDuration;
    if (min == Duration.zero) {
      _minimumOver = true;
    } else {
      _minimum = Timer(min, () {
        _minimumOver = true;
        _maybeExit();
      });
    }
    final logo = _data.logo;
    if (logo == null) {
      _showAfterFrame();
    } else {
      _logoTimeout = Timer(ThemeSplash.logoWait, _showAfterFrame);
      logo.listenable.addListener(_watchLogo);
      WidgetsBinding.instance.addPostFrameCallback((_) => _watchLogo());
    }
  }

  // Calls [ThemeSplash.onShown] after the next frame; once.
  void _showAfterFrame() {
    if (_shown || !mounted) {
      return;
    }
    _shown = true;
    _logoTimeout?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onShown?.call();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  // Shows once the logo's image is decoded (or failed: the page's loader
  // must not wait for it).
  void _watchLogo() {
    final provider = _data.logo?.listenable.value;
    if (_shown || !mounted || provider == null || _logoStream != null) {
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (_, _) => _showAfterFrame(),
      onError: (_, _) => _showAfterFrame(),
    );
    _logoStream = stream..addListener(listener);
    _logoListener = listener;
  }

  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _exit,
    curve: _data.exit.curve,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeExit();
  }

  ThemeLoaderSpec? get _loader {
    final name = _data.loader;
    return name == null ? null : widget.theme.loaders[name];
  }

  @override
  void didUpdateWidget(ThemeSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeExit();
  }

  // The loader plays its last phase when ready; the splash waits for it
  // only when the loader has phases of its own.
  bool get _loaderEnded => _loaderDone || !(_loader?.hasPhases ?? false);

  void _maybeExit() {
    if (_exiting || !widget.ready || !_minimumOver || !_loaderEnded) {
      return;
    }
    _exiting = true;
    _exitingNow();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _exit.duration = reduce ? Duration.zero : _data.exit.duration;
    // Not from a build: the parent changes its state when this is over.
    unawaited(
      _exit.forward().whenComplete(
        () => scheduleMicrotask(() {
          if (mounted) {
            widget.onExited?.call();
          }
        }),
      ),
    );
    if (mounted && _built) {
      setState(() {});
    }
  }

  bool _built = false;
  bool _exitingTold = false;

  void _exitingNow() {
    if (!_exitingTold) {
      _exitingTold = true;
      widget.onExiting?.call();
    }
  }

  @override
  void dispose() {
    _logoTimeout?.cancel();
    _data.logo?.listenable.removeListener(_watchLogo);
    if (_logoListener case final listener?) {
      _logoStream?.removeListener(listener);
    }
    _minimum?.cancel();
    _fade.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _built = true;
    final theme = widget.theme;
    final data = _data;
    final loader = _loader;
    final scheme = theme.colorScheme;
    final custom = loader != null && !loader.isBuiltIn;
    Widget loaderWidget(double progress) => ThemeLoader(
      loader!,
      progress: _resumed == null ? progress : math.max(progress, _resumed),
      resumeFrom: _resumed,
      resumeElapsed: _resumedElapsed,
      ready: widget.ready,
      stages: widget.stages,
      onExiting: () {
        _exitingNow();
        if (data.reveal && mounted && !_revealing) {
          setState(() => _revealing = true);
        }
      },
      onFinished: () {
        _loaderDone = true;
        _maybeExit();
      },
    );
    final animation = data.animation == null
        ? null
        : theme.animations[data.animation!];
    Widget logo = const SizedBox.shrink();
    final image = data.logo;
    if (image != null) {
      // A square box of the logo's size from the first frame, the image
      // contained in it: as the web page's loader lays it out
      // (`object-fit: contain`), so nothing moves when the image arrives
      // or the page's loader hands over.
      final size = data.logoSize ?? 96;
      logo = SizedBox.square(
        dimension: size,
        child: ValueListenableBuilder<ImageProvider?>(
          valueListenable: image.listenable,
          builder: (context, provider, _) => provider == null
              ? const SizedBox.shrink()
              : Image(
                  image: provider,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
        ),
      );
      if (animation != null) {
        final plain = logo;
        logo = ThemeAnimation(
          animation,
          builder: (context, t) => AnimatedBuilder(
            animation: t,
            builder: (context, child) => Opacity(
              opacity: t.value.clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.9 + 0.1 * t.value, child: child),
            ),
            child: plain,
          ),
        );
      }
    }
    // The web page's loader lays out the same column (spring_core_dart's
    // generator, `#spring-loader .sl-body`): a gap of 20 between the
    // parts, the title at 28 with a letter spacing of .04em.
    const gap = 20.0;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (image != null) logo,
        if (data.title != null) ...[
          if (image != null) const SizedBox(height: gap),
          Text(
            data.title!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: 28 * .04,
              decoration: TextDecoration.none,
            ),
          ),
        ],
        if (loader != null && !custom) ...[
          if (image != null || data.title != null) const SizedBox(height: gap),
          ValueListenableBuilder<double>(
            valueListenable: widget.progress,
            builder: (context, progress, _) => loaderWidget(progress),
          ),
        ],
      ],
    );
    // The background, the loader and the logo with the title, in fixed
    // places: with `exit.reveal` the first and the last go and the loader
    // keeps its state.
    final background = data.background == null
        ? ColoredBox(color: scheme.surface)
        : ThemeBackground.data(
            data.background!,
            child: const SizedBox.expand(),
          );
    final body = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Visibility(visible: !_revealing, child: background),
        ),
        // A kind of the app's own may cover the whole splash (doors); the
        // logo and the title stay above it.
        if (custom)
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: widget.progress,
                builder: (context, progress, _) => loaderWidget(progress),
              ),
            ),
          ),
        Center(
          child: Visibility(visible: !_revealing, child: column),
        ),
      ],
    );
    return SpringTheme(
      data: theme,
      child: IgnorePointer(
        ignoring: _exiting || _revealing,
        child: FadeTransition(
          opacity: ReverseAnimation(_fade),
          child: body,
        ),
      ),
    );
  }
}
