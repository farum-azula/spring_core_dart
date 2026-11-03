import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/widgets/styled_widgets.dart';
import 'package:theme_showcase_material/src/widgets/page_frame.dart';
import 'package:theme_showcase_material/src/widgets/section.dart';
import 'package:theme_showcase_material/src/widgets/yaml_box.dart';

/// Motion: durations, curves, animations that repeat, and page transitions.
class MotionPage extends StatefulWidget {
  const MotionPage({super.key});

  @override
  State<MotionPage> createState() => _MotionPageState();
}

class _MotionPageState extends State<MotionPage> {
  bool _moved = false;
  bool _reduce = false;
  int _replay = 0;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final transition = Theme.of(context)
        .pageTransitionsTheme
        .builders[Theme.of(context).platform]
        .runtimeType;
    // "Reduce motion": the device flag is MediaQuery.disableAnimations. The
    // switch sets it for the demos below, as the system setting would.
    final media = MediaQuery.of(context);
    final demo = MediaQuery(
      data: media.copyWith(
        disableAnimations: _reduce || media.disableAnimations,
      ),
      child: Builder(
        builder: (context) {
          final theme = context.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'disableAnimations: ${MediaQuery.disableAnimationsOf(context)}  '
                'motion.fast: ${theme.motion.fast.inMilliseconds} ms',
                style: theme.typography.code,
              ),
              SizedBox(height: space.m),
              Wrap(
                spacing: space.l,
                runSpacing: space.l,
                children: [
                  _Demo(
                    'border-spin  (loop)',
                    GlowBorder(
                      child: SizedBox(
                        width: 190,
                        height: 90,
                        child: Center(
                          child: Text('Glow border', style: text.titleMedium),
                        ),
                      ),
                    ),
                  ),
                  _Demo(
                    'glow-pulse  (reverse)',
                    SizedBox(
                      width: 190,
                      height: 96,
                      child: Center(
                        child: ThemeAnimation(
                          theme.animations.glowPulse,
                          builder: (context, t) => AnimatedBuilder(
                            animation: t,
                            builder: (context, _) => Container(
                              width: 44 + 16 * t.value,
                              height: 44 + 16 * t.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: scheme.tertiary,
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.tertiary.withValues(
                                      alpha: 0.7,
                                    ),
                                    blurRadius: 24 * t.value,
                                    spreadRadius: 6 * t.value,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _Demo(
                    'enter  (none: once)',
                    SizedBox(
                      width: 190,
                      height: 96,
                      child: Center(
                        child: ThemeAnimation(
                          theme.animations.enter,
                          key: ValueKey(_replay),
                          builder: (context, t) => AnimatedBuilder(
                            animation: t,
                            builder: (context, child) => Opacity(
                              opacity: t.value,
                              child: Transform.translate(
                                offset: Offset(0, (1 - t.value) * 40),
                                child: child,
                              ),
                            ),
                            child: Chip(
                              avatar: const Icon(Icons.bolt, size: 18),
                              label: const Text('I arrived'),
                              backgroundColor: scheme.secondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    return PageFrame(
      title: context.messages.nav.motion,
      intro:
          'Motion has names. Durations and curves are yours to define; an '
          'animation says how long, which curve and whether it repeats; '
          'ThemeAnimation plays it. When the device asks for less motion '
          'everything stands still on its own.',
      children: [
        Section(
          title: 'Durations and curves',
          note:
              'context.theme.motion.fast / medium / slow are Durations, '
              'motion.curves.emphasized a Curve. Press the button: three '
              'bars move with three durations.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'durations:\n'
                '  fast: 120ms\n'
                '  medium: 250ms\n'
                '  slow: 600ms\n'
                'curves:\n'
                '  emphasized: [0.2, 0, 0, 1]\n'
                '  out: ease-out\n'
                '  standard: ease-in-out',
                label: 'application.yml: motion',
              ),
              SizedBox(height: space.m),
              FilledButton(
                onPressed: () => setState(() => _moved = !_moved),
                child: Text(_moved ? 'Move back' : 'Move'),
              ),
              SizedBox(height: space.m),
              for (final (name, duration, curve) in [
                ('fast', theme.motion.fast, theme.motion.curves.out),
                ('medium', theme.motion.medium, theme.motion.curves.standard),
                ('slow', theme.motion.slow, theme.motion.curves.emphasized),
              ])
                Padding(
                  padding: EdgeInsets.only(bottom: space.s),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text('$name ${duration.inMilliseconds} ms'),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            Container(height: 4, color: scheme.outlineVariant),
                            AnimatedAlign(
                              duration: duration,
                              curve: curve,
                              alignment: _moved
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Section(
          title: 'Animations: none, loop, reverse',
          note:
              'ThemeAnimation(spec, builder: (context, t) => ...) gives '
              'a value from 0 to 1 along the curve and owns the controller.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'border-spin: { duration: 4s, curve: linear, repeat: loop }\n'
                'glow-pulse: { duration: 1.6s, curve: ease-in-out, repeat: reverse }\n'
                r'enter: { duration: $motion.durations.slow, curve: ease-out, repeat: none }',
                label: 'application.yml: animations',
              ),
              SizedBox(height: space.m),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _replay++),
                    icon: const Icon(Icons.replay),
                    label: const Text('Replay the entrance'),
                  ),
                ],
              ),
              SizedBox(height: space.m),
              demo,
            ],
          ),
        ),
        Section(
          title: 'Reduce motion',
          note:
              'With the device setting on, durations from '
              'context.theme.motion are zero, a once-animation jumps to '
              'its end and loops stand still. This switch sets the flag for '
              'the demos above (a real device sets it for the whole app).',
          child: SwitchListTile(
            title: const Text('Pretend the device asks for less motion'),
            subtitle: const Text('MediaQuery.disableAnimations'),
            value: _reduce,
            onChanged: (value) => setState(() => _reduce = value),
          ),
        ),
        Section(
          title: 'Page transitions',
          note:
              'motion.page-transition: platform, fade-upwards, zoom, '
              'cupertino or none. This theme uses $transition. Neon zooms, '
              'high contrast has none; try them.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'page-transition: fade-upwards',
                label:
                    'application.yml: motion (neon: zoom, high-contrast: none)',
              ),
              SizedBox(height: space.m),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    settings: const RouteSettings(name: 'motion/detail'),
                    builder: (_) => const _DetailPage(),
                  ),
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open a page'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Demo extends StatelessWidget {
  const _Demo(this.name, this.child);

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      child,
      SizedBox(height: context.theme.spacing.s),
      Text(name, style: context.theme.typography.code),
    ],
  );
}

class _DetailPage extends StatelessWidget {
  const _DetailPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('A page')),
    body: Center(
      child: Text(
        'It came in with the theme\'s page transition.',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    ),
  );
}
