import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// Builds a content change: the new content [child] coming in, or the old
/// one going out, as [animation] runs (0 to 1 coming in, 1 to 0 going
/// out).
typedef ContentTransitionBuilder = Widget Function(
  Widget child,
  Animation<double> animation,
);

/// The kinds of `motion.content-change`, by name: the built-in `none`,
/// `fade`, `fade-up` and `morph`, and the application's own. Registered
/// before the themes are read (the start reads them), as the loader kinds
/// are.
///
/// `morph` is the content's own to do: `MarkdownView` types its new page
/// in line after line, as `text-change: morph` types a line; a
/// [ContentChange] of anything else shows the new content at once.
///
/// ```dart
/// // `motion.content-change: scale`
/// ContentTransitions.register(
///   'scale',
///   (child, animation) => ScaleTransition(scale: animation, child: child),
/// );
/// ```
abstract final class ContentTransitions {
  static final _kinds = <String, ContentTransitionBuilder>{};
  static final _names = <String, String>{};

  /// The built-in kinds, by the name a theme writes.
  static final Map<String, ContentTransitionBuilder> builtIn = {
    'none': (child, _) => child,
    'fade': (child, animation) =>
        FadeTransition(opacity: animation, child: child),
    'fade-up': (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    'morph': (child, _) => child,
  };

  /// The kind the content itself plays, line after line.
  static const morph = 'morph';

  static bool _started = false;

  static void _start() {
    if (!_started) {
      _started = true;
      builtIn.forEach(register);
    }
  }

  /// Registers [builder] as the kind [name] (`-`, `_` and case do not
  /// matter); one of the same name replaces the earlier one.
  static void register(String name, ContentTransitionBuilder builder) {
    _start();
    final canonical = ThemeValues.canonical(name);
    _kinds[canonical] = builder;
    _names[canonical] = name;
  }

  /// The kind [name]; `null` when there is none.
  static ContentTransitionBuilder? lookup(String name) {
    _start();
    return _kinds[ThemeValues.canonical(name)];
  }

  /// The names of the kinds, as registered.
  static Iterable<String> get names {
    _start();
    return _names.values;
  }

  /// Forgets the application's kinds; for tests.
  static void reset() {
    _kinds.clear();
    _names.clear();
    _started = false;
  }
}

/// The theme's content change, `motion.content-change`: how a part of a
/// screen shows other content in its place (another page of the docs in
/// `RouteContentView`): a kind alone, or a map of `type`, `duration`,
/// `curve`, and for `morph` `stagger` (how much later each line starts
/// than the one before it) and `delay` (how long the new page waits, blank
/// at its full height, before its first line: the time a `ThemeText` above
/// it takes to morph, so the two go one after the other).
///
/// ```yaml
/// motion:
///   content-change: { type: fade-up, duration: 220ms, curve: ease-out }
///   content-change: { type: morph, duration: 1.2s, stagger: 40ms, delay: 650ms }
/// ```
final class ContentChangeSpec {
  /// A change of [type] over [duration] along [curve]; `morph` the lines
  /// [stagger] apart, after [delay].
  const ContentChangeSpec({
    this.type = 'none',
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeOut,
    this.stagger = const Duration(milliseconds: 30),
    this.delay = Duration.zero,
  });

  /// Reads the change at [base] of [p]; `null` when nothing is written.
  static ContentChangeSpec? parseAt(ThemeProperties p, String base) {
    String? kind(String path) => p.read(
      path,
      (value) => ContentTransitions.lookup(value) == null
          ? null
          : ThemeValues.canonical(value),
      'a kind: ${ContentTransitions.names.join(', ')}; a kind of the '
      "app's own is ContentTransitions.register(...)",
    );

    final children = p.children(base);
    if (children.isEmpty) {
      final type = kind(base);
      return type == null ? null : ContentChangeSpec(type: type);
    }
    const keys = ['type', 'duration', 'curve', 'stagger', 'delay'];
    for (final key in children) {
      if (!keys.contains(key)) {
        throw ThemePropertyException(
          p.propertyName('$base.$key'),
          p['$base.$key'] ?? '',
          'type, duration, curve, stagger or delay${didYouMean(key, keys)}',
        );
      }
    }
    const defaults = ContentChangeSpec();
    Duration? duration(String key, Duration fallback, String example) =>
        p.read('$base.$key', ThemeValues.duration, 'a duration like $example');
    return ContentChangeSpec(
      type: kind('$base.type') ?? defaults.type,
      duration:
          duration('duration', defaults.duration, '200ms') ?? defaults.duration,
      curve:
          p.read(
            '$base.curve',
            ThemeValues.anyCurve,
            'a curve: ${ThemeValues.curveNames.join(', ')}, or four numbers',
          ) ??
          defaults.curve,
      stagger:
          duration('stagger', defaults.stagger, '30ms') ?? defaults.stagger,
      delay: duration('delay', defaults.delay, '650ms') ?? defaults.delay,
    );
  }

  /// The kind, a name of [ContentTransitions].
  final String type;

  /// How long the change takes: for `morph`, the whole page's.
  final Duration duration;

  /// The curve of the change.
  final Curve curve;

  /// For `morph`, how much later each line starts than the one before it;
  /// the lines never take more than 85 percent of [duration] to start, so
  /// a long page is done in [duration] too.
  final Duration stagger;

  /// For `morph`, how long the new content waits before its first line.
  final Duration delay;

  /// Whether the content plays the change itself, line after line.
  bool get morphs => type == ContentTransitions.morph;

  @override
  bool operator ==(Object other) =>
      other is ContentChangeSpec &&
      other.type == type &&
      other.duration == duration &&
      other.curve == curve &&
      other.stagger == stagger &&
      other.delay == delay;

  @override
  int get hashCode => Object.hash(type, duration, curve, stagger, delay);
}

/// The page transition `motion.page-transition: content`: a screen comes
/// in the way `motion.content-change` shows other content (`fade-up`, a
/// kind of the app's own), over the screen before it. The navigation
/// starter's router and Material's own routes use it; `none` and `morph`
/// show the screen at once.
final class ContentPageTransitionsBuilder extends PageTransitionsBuilder {
  /// The builder.
  const ContentPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final spec =
        SpringTheme.maybeOf(context)?.contentChange ??
        const ContentChangeSpec();
    final builder = ContentTransitions.lookup(spec.type);
    if (builder == null || spec.type == 'none' || spec.morphs) {
      return child;
    }
    return builder(child, animation);
  }
}

/// Shows [child], and another content in its place the theme's way
/// (`motion.content-change`) when [id] changes: the old one goes while the
/// new one comes, top-aligned, so a taller or shorter page does not jump.
/// At once with reduced motion or no theme.
class ContentChange extends StatelessWidget {
  /// [child], the content [id].
  const ContentChange({required this.id, required this.child, super.key});

  /// What the content is (a file); another one is a change.
  final Object? id;

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec =
        SpringTheme.maybeOf(context)?.contentChange ??
        const ContentChangeSpec();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final builder = ContentTransitions.lookup(spec.type);
    if (reduce ||
        builder == null ||
        spec.type == 'none' ||
        spec.morphs ||
        spec.duration == Duration.zero) {
      return KeyedSubtree(key: ValueKey(id), child: child);
    }
    return AnimatedSwitcher(
      duration: spec.duration,
      switchInCurve: spec.curve,
      switchOutCurve: spec.curve,
      transitionBuilder: builder,
      // The new content gives the height; the old one, as tall as it
      // was, is cut to it while it goes.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        children: [
          for (final old in previous)
            Positioned(top: 0, left: 0, right: 0, child: old),
          ?current,
        ],
      ),
      child: KeyedSubtree(key: ValueKey(id), child: child),
    );
  }
}
