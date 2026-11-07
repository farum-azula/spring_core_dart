import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_background.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// The background of the theme under [child]: the theme's `background`
/// (a color, an image, an overlay, a slow animation), cross-fading when
/// the theme or the image changes.
///
/// `SpringApp` puts one around the navigator when the active theme has a
/// `background`, and makes the Material scaffold and the Cupertino page
/// transparent, so every screen shows it. A screen that wants another
/// background uses [ThemeBackground.screen], and a screen that wants a
/// plain surface [ThemeBackground.none]. With the system asking for less
/// motion (`MediaQuery.disableAnimations`) the background stands still and
/// changes without a fade.
///
/// ```dart
/// // The login screen: `background.screens.login` over the theme's own.
/// ThemeBackground.screen('login', child: const LoginForm());
/// ```
class ThemeBackground extends StatefulWidget {
  /// Shows the theme's background under [child]; [child] alone when the
  /// theme has none (or there is no `SpringTheme` above).
  const ThemeBackground({required this.child, super.key})
    : _screen = null,
      _none = false,
      _data = null;

  /// Shows [data] (a background that is not the theme's, such as the
  /// splash's) under [child]. Needs a `SpringTheme` above, for the
  /// animations and the surface color.
  const ThemeBackground.data(
    ThemeBackgroundData this._data, {
    required this.child,
    super.key,
  }) : _screen = null,
       _none = false;

  /// Shows `background.screens.<name>` over the theme's background under
  /// [child]. A name the theme does not have throws a `FlutterError` in
  /// debug (it lists the screens the theme has); in release no background
  /// is shown.
  const ThemeBackground.screen(
    String name, {
    required this.child,
    super.key,
  }) : _screen = name,
       _none = false,
       _data = null;

  /// An opaque surface-colored background under [child], hiding the
  /// theme's background.
  const ThemeBackground.none({required this.child, super.key})
    : _screen = null,
      _none = true,
      _data = null;

  /// What is shown over the background.
  final Widget child;

  final String? _screen;
  final bool _none;
  final ThemeBackgroundData? _data;

  @override
  State<ThemeBackground> createState() => _ThemeBackgroundState();
}

class _ThemeBackgroundState extends State<ThemeBackground> {
  // The image on screen: a new one is loaded first, then faded in.
  ImageProvider? _shown;
  ImageProvider? _wanted;

  @override
  Widget build(BuildContext context) {
    final theme = SpringTheme.maybeOf(context);
    if (widget._none) {
      return _stack(
        ColoredBox(
          color: theme?.colorScheme.surface ?? const Color(0xFF000000),
          child: const SizedBox.expand(),
        ),
      );
    }
    var data = widget._data ?? theme?.background;
    if (data != null && widget._screen != null) {
      final name = ThemeValues.canonical(widget._screen!);
      assert(() {
        if (!data!.screens.containsKey(name)) {
          final known = data.screens.keys.toList();
          throw FlutterError(
            "ThemeBackground.screen('${widget._screen}'): the theme "
            "'${theme!.name}' has no background.screens.${widget._screen}; "
            '${known.isEmpty ? 'it has no screens' : 'its screens are ${known.join(', ')}'}'
            '${didYouMean(widget._screen!, known)}.',
          );
        }
        return true;
      }());
      // In release a screen the theme does not mention shows no background.
      data = data.screens.containsKey(name) ? data.screen(name) : null;
    }
    if (data == null) {
      // The same structure as with a background, so the child keeps its
      // state when a theme switch adds or drops the background.
      return _stack(const SizedBox.shrink());
    }
    final background = data;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final transition = background.transitionOrDefault;
    final listenable = background.image?.image?.listenable;
    return _stack(
      listenable == null
          ? _switcher(theme!, background, null, reduced, transition)
          : ValueListenableBuilder<ImageProvider?>(
              valueListenable: listenable,
              builder: (context, provider, _) => _switcher(
                theme!,
                background,
                _gate(provider),
                reduced,
                transition,
              ),
            ),
    );
  }

  // The back layer fills the stack, which takes the child's size (the
  // parent's constraints pass to the child, so an unbounded parent works).
  Widget _stack(Widget back) => Stack(
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(child: back),
      widget.child,
    ],
  );

  // Gives the image to show: the first one at once, a changed one after it
  // is decoded, so a swap fades from picture to picture, not from empty.
  ImageProvider? _gate(ImageProvider? provider) {
    if (provider == _wanted) {
      return _shown;
    }
    _wanted = provider;
    if (provider == null || _shown == null) {
      return _shown = provider;
    }
    void arrived() {
      if (mounted && _wanted == provider) {
        setState(() => _shown = provider);
      }
    }

    precacheImage(provider, context, onError: (_, _) => arrived()).then(
      (_) => arrived(),
    );
    return _shown;
  }

  Widget _switcher(
    SpringThemeData theme,
    ThemeBackgroundData data,
    ImageProvider? provider,
    bool reduced,
    ThemeBackgroundTransition transition,
  ) {
    final spec = data.animation == null
        ? null
        : theme.animations[ThemeValues.canonical(data.animation!)];
    final layers = _Layers(
      color: data.color ?? theme.colorScheme.surface,
      provider: provider,
      image: data.image,
      overlay: data.overlay,
      spec: reduced ? null : spec,
      effect: data.effectiveEffect,
      frameRate: data.frameRateOrDefault,
    );
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : transition.duration,
      switchInCurve: transition.curve,
      switchOutCurve: transition.curve,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(
        key: ValueKey((
          layers.color,
          provider,
          data.image?.fit,
          data.image?.alignment,
          data.image?.opacity,
          data.image?.blur,
          data.overlay,
        )),
        child: layers,
      ),
    );
  }
}

// The painted layers: color, image (moving), overlay.
class _Layers extends StatelessWidget {
  const _Layers({
    required this.color,
    required this.provider,
    required this.image,
    required this.overlay,
    required this.spec,
    required this.effect,
    required this.frameRate,
  });

  final Color color;
  final ImageProvider? provider;
  final ThemeBackgroundImage? image;
  final ThemeBackgroundOverlay? overlay;
  final AnimationSpec? spec;
  final BackgroundEffect? effect;
  final double frameRate;

  @override
  Widget build(BuildContext context) {
    final picture = provider == null || image == null
        ? null
        : _picture(image!, provider!);
    final overlay = this.overlay;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: color),
        ?picture,
        if (overlay != null) ...[
          if (overlay.color != null) ColoredBox(color: overlay.color!),
          if (overlay.gradient != null)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: overlay.gradient!.toGradient(),
              ),
            ),
        ],
      ],
    );
  }

  Widget _picture(ThemeBackgroundImage image, ImageProvider provider) {
    Widget build(double extra) {
      Widget result = Image(
        image: provider,
        fit: image.fitOrDefault,
        alignment: image.alignmentOrDefault,
        gaplessPlayback: true,
        excludeFromSemantics: true,
      );
      final opacity = image.opacityOrDefault * extra;
      if (image.blurOrDefault > 0) {
        result = ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: image.blurOrDefault,
            sigmaY: image.blurOrDefault,
          ),
          child: result,
        );
      }
      return opacity < 1 ? Opacity(opacity: opacity, child: result) : result;
    }

    final spec = this.spec;
    final effect = this.effect;
    if (spec == null || effect == null) {
      return SizedBox.expand(child: build(1));
    }
    return ThemeAnimation(
      spec,
      frameRate: frameRate,
      builder: (context, t) => AnimatedBuilder(
        animation: t,
        builder: (context, _) => switch (effect) {
          // Bigger than the screen, so the slide shows no edge.
          BackgroundEffect.drift => Transform.scale(
            scale: 1.12,
            child: FractionalTranslation(
              translation: Offset(
                (t.value - 0.5) * 0.08,
                (t.value - 0.5) * 0.04,
              ),
              child: SizedBox.expand(child: build(1)),
            ),
          ),
          BackgroundEffect.zoom => Transform.scale(
            scale: 1 + 0.12 * t.value,
            child: SizedBox.expand(child: build(1)),
          ),
          BackgroundEffect.pulse => SizedBox.expand(
            child: build(0.7 + 0.3 * t.value),
          ),
        },
      ),
    );
  }
}
