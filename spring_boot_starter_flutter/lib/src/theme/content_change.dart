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
/// `fade` and `fade-up`, and the application's own. Registered before the
/// themes are read (the start reads them), as the loader kinds are.
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
  };

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
/// `curve`.
///
/// ```yaml
/// motion:
///   content-change: { type: fade-up, duration: 220ms, curve: ease-out }
/// ```
final class ContentChangeSpec {
  /// A change of [type] over [duration] along [curve].
  const ContentChangeSpec({
    this.type = 'none',
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeOut,
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
    const keys = ['type', 'duration', 'curve'];
    for (final key in children) {
      if (!keys.contains(key)) {
        throw ThemePropertyException(
          p.propertyName('$base.$key'),
          p['$base.$key'] ?? '',
          'type, duration or curve${didYouMean(key, keys)}',
        );
      }
    }
    const defaults = ContentChangeSpec();
    return ContentChangeSpec(
      type: kind('$base.type') ?? defaults.type,
      duration:
          p.read(
            '$base.duration',
            ThemeValues.duration,
            'a duration like 200ms',
          ) ??
          defaults.duration,
      curve:
          p.read(
            '$base.curve',
            ThemeValues.anyCurve,
            'a curve: ${ThemeValues.curveNames.join(', ')}, or four numbers',
          ) ??
          defaults.curve,
    );
  }

  /// The kind, a name of [ContentTransitions].
  final String type;

  /// How long the change takes.
  final Duration duration;

  /// The curve of the change.
  final Curve curve;

  @override
  bool operator ==(Object other) =>
      other is ContentChangeSpec &&
      other.type == type &&
      other.duration == duration &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(type, duration, curve);
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
