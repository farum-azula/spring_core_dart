import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/widgets/page_frame.dart';
import 'package:theme_showcase_cupertino/src/widgets/section.dart';
import 'package:theme_showcase_cupertino/src/widgets/yaml_box.dart';

/// Motion: durations, curves, animations that repeat, reduce motion, and
/// the page transition of a CupertinoApp.
@ScreenRoute('/motion', title: '#{nav.motion}', branch: '/more')
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
    final colors = theme.colors;
    final text = CupertinoTheme.of(context).textTheme;
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
                style: theme.typography.code.copyWith(color: colors.onSurface),
              ),
              SizedBox(height: space.m),
              Wrap(
                spacing: space.l,
                runSpacing: space.l,
                children: [
                  _Demo(
                    'spin  (loop)',
                    SizedBox(
                      width: 150,
                      height: 90,
                      child: Center(
                        child: ThemeAnimation(
                          theme.animations.spin,
                          builder: (context, t) => AnimatedBuilder(
                            animation: t,
                            builder: (context, child) => Transform.rotate(
                              angle: t.value * 2 * math.pi,
                              child: child,
                            ),
                            child: Icon(
                              CupertinoIcons.arrow_2_circlepath,
                              size: 44,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _Demo(
                    'pulse  (reverse)',
                    SizedBox(
                      width: 150,
                      height: 90,
                      child: Center(
                        child: ThemeAnimation(
                          theme.animations.pulse,
                          builder: (context, t) => AnimatedBuilder(
                            animation: t,
                            builder: (context, _) => Container(
                              width: 36 + 24 * t.value,
                              height: 36 + 24 * t.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.tertiary.withValues(
                                  alpha: 0.5 + 0.5 * t.value,
                                ),
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
                      height: 90,
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
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: space.m,
                                vertical: space.s,
                              ),
                              decoration: BoxDecoration(
                                color: colors.secondary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'I arrived',
                                style: text.textStyle.copyWith(
                                  color: colors.onSecondary,
                                ),
                              ),
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
    final small = text.textStyle.copyWith(
      fontSize: 13,
      color: colors.onSurfaceVariant,
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
              'motion.curves.ios a Curve (iOS\'s ease). Press the button: '
              'three dots move with three durations.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const YamlBox(
                'durations:\n'
                '  fast: 120ms\n'
                '  medium: 250ms\n'
                '  slow: 500ms\n'
                'curves:\n'
                '  ios: [0.25, 0.1, 0.25, 1]\n'
                '  out: ease-out\n'
                '  standard: ease-in-out',
                label: 'application.yml: motion',
              ),
              SizedBox(height: space.m),
              CupertinoButton.filled(
                onPressed: () => setState(() => _moved = !_moved),
                child: Text(_moved ? 'Move back' : 'Move'),
              ),
              SizedBox(height: space.m),
              for (final (name, duration, curve) in [
                ('fast', theme.motion.fast, theme.motion.curves.out),
                ('medium', theme.motion.medium, theme.motion.curves.standard),
                ('slow', theme.motion.slow, theme.motion.curves.ios),
              ])
                Padding(
                  padding: EdgeInsets.only(bottom: space.s),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          '$name ${duration.inMilliseconds} ms',
                          style: small,
                        ),
                      ),
                      Expanded(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(height: 3, color: colors.outline),
                            AnimatedAlign(
                              duration: duration,
                              curve: curve,
                              alignment: _moved
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: colors.primary,
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
                'spin: { duration: 2s, curve: linear, repeat: loop }\n'
                'pulse: { duration: 1.4s, curve: ease-in-out, repeat: reverse }\n'
                r'enter: { duration: $motion.durations.slow, curve: ease-out, repeat: none }',
                label: 'application.yml: animations',
              ),
              SizedBox(height: space.m),
              CupertinoButton.tinted(
                onPressed: () => setState(() => _replay++),
                child: const Text('Replay the entrance'),
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
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Pretend the device asks for less motion',
                  style: text.textStyle,
                ),
              ),
              CupertinoSwitch(
                value: _reduce,
                activeTrackColor: colors.secondary,
                onChanged: (value) => setState(() => _reduce = value),
              ),
            ],
          ),
        ),
        Section(
          title: 'Page transitions',
          note:
              'A CupertinoApp pushes CupertinoPageRoute: the iOS slide, and '
              'on iOS and macOS the swipe from the edge to go back. It does '
              'not read motion.page-transition (a MaterialApp does); the '
              'durations and curves above are for your own animations.',
          child: CupertinoButton.tinted(
            onPressed: () => Navigator.of(context).push<void>(
              CupertinoPageRoute(
                settings: const RouteSettings(name: 'motion/detail'),
                builder: (_) => const _DetailPage(),
              ),
            ),
            child: const Text('Open a page'),
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
      Text(
        name,
        style: context.theme.typography.code.copyWith(
          color: context.theme.colors.onSurface,
        ),
      ),
    ],
  );
}

class _DetailPage extends StatelessWidget {
  const _DetailPage();

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('A page')),
    child: Center(
      child: Text(
        'It came in with the iOS slide.',
        style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
      ),
    ),
  );
}
