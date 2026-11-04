import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/section.dart';
import 'package:theme_showcase_neon/src/widgets/yaml_box.dart';

/// Loaders: the gate loader of neon_ui with a progress slider, the
/// built-in kinds, a skeleton, and the splash that shows at the start.
class LoadersPage extends StatelessWidget {
  const LoadersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      kicker: 'THEMELOADER',
      title: 'Loaders',
      intro:
          'Loaders are written in the theme and shown by ThemeLoader and '
          'ThemeSkeleton. The gate is a kind of neon_ui (a widget in Dart '
          'that draws everything itself, a look for the web page in HTML); '
          'the app started with it as its splash.',
      children: const [
        Section(
          title: 'The gate',
          note:
              'Dark panels slide in from different sides and close like a '
              'gate, their edges glowing and flickering a little; the red box '
              'fills by the progress with its number, in 2.5 s at least; when '
              'it is done the panels part. Drag the slider, or run a fake '
              'load.',
          child: _GateDemo(),
        ),
        Section(
          title: 'Built-in kinds',
          note:
              'A spinner and dots turn until the work is done; the bar can '
              'show the progress of a fake upload.',
          child: _BuiltIns(),
        ),
        Section(
          title: 'A skeleton',
          note:
              'The shape of the content shows, with a highlight crossing it, '
              'until the content is there (a short wait, then the list).',
          child: _Books(),
        ),
        Section(
          title: 'The splash',
          note:
              'The splash of the active theme: shown while the context '
              'starts, the box follows the start\'s progress and the panels '
              'part over the app when it is ready (reveal). The loader draws '
              'everything itself, so the splash has no image.',
          child: YamlBox(
            label: 'application.yml: splash',
            r'''
splash:
  background: { color: $colors.surface-container-lowest }
  loader: neon-gate
  exit: { transition: 200ms ease-out, reveal: true }''',
          ),
        ),
        Section(
          title: 'The gate, written',
          note:
              'Phases play in order; fill follows the progress and takes its '
              'min-duration at least; the colors are tokens, the times are '
              'animations; web is the look of the page before Flutter runs.',
          child: YamlBox(
            label: 'neon_ui/lib/resources/themes/neon.yml: loaders',
            r'''
neon-gate:
  kind: neon-gate
  phases:
    enter: { duration: $animations.gate-enter.duration, curve: linear }
    fill: { progress: true, min-duration: 2.5s }
    exit: { duration: $animations.gate-exit.duration, curve: linear }
  gate:
    color: $neon.navy
  edge:
    color: $neon.cyan
    accent: $neon.red
  box:
    color: $neon.red
    skew: -18
  label:
    text: LOADING
    size: $typography.label-small.size
  web: loaders/neon-gate.html''',
          ),
        ),
        Section(
          title: 'The built-in kinds, written',
          child: YamlBox(
            label: 'application.yml: loaders',
            r'''
spinner: { kind: spinner, color: $neon.cyan, size: 28, stroke: 3, track: { color: $neon.cyan, alpha: 20% } }
dots: { kind: dots, color: $neon.pink, size: 10, count: 3 }
upload: { kind: bar, color: $neon.yellow, track: { color: $neon.yellow, alpha: 20% }, height: 4, width: 240 }
card:
  kind: skeleton
  base: $colors.surface-container-high
  highlight: $colors.surface-container-highest
  radius: $shape.extra-small
  shimmer: { duration: 1.2s, angle: 20 }''',
          ),
        ),
        Section(
          title: 'In Dart',
          child: NeonCode(
            r'''
ThemeLoader(context.theme.loaders.neonGate, progress: progress)
ThemeLoader(context.theme.loaders.upload, progress: sent)
ThemeSkeleton(context.theme.loaders.card, loading: !loaded, child: list)''',
          ),
        ),
      ],
    );
  }
}

/// A fake piece of work: a progress from 0 to 1 over [duration].
mixin _FakeWork<T extends StatefulWidget> on State<T> {
  Timer? _timer;
  double progress = 0;

  /// Runs from 0 to 1 over [duration] in steps of 50 ms.
  void run(Duration duration) {
    _timer?.cancel();
    setState(() => progress = 0);
    final step = 50 / duration.inMilliseconds;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => progress = (progress + step).clamp(0.0, 1.0));
      if (progress >= 1) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _GateDemo extends StatefulWidget {
  const _GateDemo();

  @override
  State<_GateDemo> createState() => _GateDemoState();
}

class _GateDemoState extends State<_GateDemo> with _FakeWork {
  int _round = 0;

  @override
  void initState() {
    super.initState();
    progress = 0.4;
  }

  void _replay() => setState(() {
    _round++;
    progress = 0;
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The stage: the loader draws the panels and the box; when they
        // part, the stage's own color shows.
        Container(
          key: const Key('gate-stage'),
          height: 360,
          decoration: BoxDecoration(
            color: theme.colors.surfaceContainerLowest,
            border: Border.all(color: theme.tokens.neon.panelBorder),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ThemeLoader(
                theme.loaders.neonGate,
                key: ValueKey(_round),
                progress: progress,
              ),
            ],
          ),
        ),
        SizedBox(height: space.m),
        Row(
          children: [
            NeonLabel('progress ${(progress * 100).round()} %'),
            SizedBox(width: space.m),
            Expanded(
              child: _Slider(
                value: progress,
                onChanged: (value) => setState(() => progress = value),
              ),
            ),
          ],
        ),
        SizedBox(height: space.m),
        Wrap(
          spacing: space.s,
          runSpacing: space.s,
          children: [
            SizedBox(
              width: 200,
              child: NeonButton(
                label: 'Run a fake load',
                onPressed: () {
                  setState(() => _round++);
                  run(const Duration(seconds: 4));
                },
              ),
            ),
            SizedBox(
              width: 140,
              child: NeonButton(
                label: 'Replay',
                filled: false,
                onPressed: _replay,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A slider from 0 to 1 made of neon colors: a track, the filled part and a
/// thumb. Drag or tap it.
class _Slider extends StatelessWidget {
  const _Slider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        void move(double dx) => onChanged((dx / width).clamp(0.0, 1.0));
        return Semantics(
          slider: true,
          label: 'Progress',
          value: '${(value * 100).round()}%',
          child: GestureDetector(
            key: const Key('progress-slider'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => move(details.localPosition.dx),
            onHorizontalDragUpdate: (details) => move(details.localPosition.dx),
            child: SizedBox(
              height: 28,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(height: 4, color: theme.colors.outline),
                  Container(
                    height: 4,
                    width: width * value,
                    color: theme.colors.tertiary,
                  ),
                  Positioned(
                    left: (width * value - 7).clamp(0.0, width - 14),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: theme.colors.tertiary,
                        boxShadow: [
                          BoxShadow(
                            color: theme.tokens.neon.glow,
                            blurRadius: theme.tokens.neon.glowBlur,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BuiltIns extends StatefulWidget {
  const _BuiltIns();

  @override
  State<_BuiltIns> createState() => _BuiltInsState();
}

class _BuiltInsState extends State<_BuiltIns> with _FakeWork {
  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ThemeLoader(theme.loaders.spinner),
            SizedBox(width: space.l),
            ThemeLoader(theme.loaders.dots),
          ],
        ),
        SizedBox(height: space.m),
        ThemeLoader(theme.loaders.upload, progress: progress),
        SizedBox(height: space.s),
        NeonLabel('upload ${(progress * 100).round()} %'),
        SizedBox(height: space.m),
        SizedBox(
          width: 200,
          child: NeonButton(
            label: 'Fake upload',
            filled: false,
            onPressed: () => run(const Duration(seconds: 3)),
          ),
        ),
      ],
    );
  }
}

class _Books extends StatefulWidget {
  const _Books();

  @override
  State<_Books> createState() => _BooksState();
}

class _BooksState extends State<_Books> {
  static const _titles = ['First volume', 'Second volume', 'Third volume'];
  Timer? _timer;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _timer?.cancel();
    setState(() => _loaded = false);
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _loaded = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    Widget row(String? title) => Padding(
      padding: EdgeInsets.only(bottom: space.s),
      child: Row(
        children: [
          Container(width: 36, height: 36, color: theme.colors.primary),
          SizedBox(width: space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Without a title: a bar the width of a short line.
                if (title != null)
                  Text(title, style: theme.typography.bodyLarge)
                else
                  Container(
                    height: 12,
                    width: 140,
                    color: theme.colors.primary,
                  ),
                SizedBox(height: space.xs),
                if (title != null)
                  Text(
                    'A line about the book',
                    style: theme.typography.bodySmall.copyWith(
                      color: theme.colors.onSurfaceVariant,
                    ),
                  )
                else
                  Container(
                    height: 10,
                    width: 200,
                    color: theme.colors.primary,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThemeSkeleton(
          theme.loaders.card,
          loading: !_loaded,
          placeholder: Column(
            children: [for (var i = 0; i < 3; i++) row(null)],
          ),
          child: Column(
            key: const Key('books-loaded'),
            children: [for (final title in _titles) row(title)],
          ),
        ),
        SizedBox(height: space.s),
        SizedBox(
          width: 200,
          child: NeonButton(
            label: 'Load again',
            filled: false,
            onPressed: _load,
          ),
        ),
      ],
    );
  }
}
