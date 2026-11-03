import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/section.dart';
import 'package:theme_showcase_neon/src/widgets/yaml_box.dart';

/// The glow modal, the turning border and "reduce motion".
class MotionPage extends StatefulWidget {
  const MotionPage({super.key});

  @override
  State<MotionPage> createState() => _MotionPageState();
}

class _MotionPageState extends State<MotionPage> {
  bool _reduce = false;
  bool _wide = false;

  @override
  Widget build(BuildContext context) {
    final space = context.theme.spacing;
    // "Reduce motion" is MediaQuery.disableAnimations. The chip sets it for
    // the demos below, as the system setting does for the whole app.
    final media = MediaQuery.of(context);
    return PageFrame(
      kicker: 'THEMEANIMATION',
      title: 'Motion',
      intro:
          'The border around the modal turns once in four seconds: that is '
          'animations.border-spin, played by ThemeAnimation. With less '
          'motion it stands still, and every motion.* duration is zero.',
      children: [
        Section(
          title: 'The glow modal',
          note:
              'showNeonModal: width, barrier and border colors are '
              'tokens.neon.modal.*; tap outside to close.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 200,
              child: NeonButton(
                label: 'Open the modal',
                onPressed: () => showNeonModal<void>(
                  context,
                  builder: (context) => const _ModalBody(),
                ),
              ),
            ),
          ),
        ),
        Section(
          title: 'Reduce motion',
          child: MediaQuery(
            data: media.copyWith(
              disableAnimations: _reduce || media.disableAnimations,
            ),
            child: Builder(
              builder: (context) {
                final theme = context.theme;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NeonChip(
                      label: 'Pretend the device asks for less motion',
                      selected: _reduce,
                      onPressed: () => setState(() => _reduce = !_reduce),
                    ),
                    SizedBox(height: space.m),
                    Text(
                      'disableAnimations: '
                      '${MediaQuery.disableAnimationsOf(context)}   '
                      'motion.medium: ${theme.motion.medium.inMilliseconds} ms',
                      style: theme.typography.code,
                    ),
                    SizedBox(height: space.m),
                    Wrap(
                      spacing: space.l,
                      runSpacing: space.l,
                      children: [
                        const SizedBox(
                          width: 220,
                          height: 100,
                          child: NeonGlowBorder(
                            child: Center(child: NeonLabel('border-spin')),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          height: 100,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const NeonLabel('motion.medium, curve out'),
                              SizedBox(height: space.s),
                              // The bar's change takes the theme's duration.
                              AnimatedContainer(
                                duration: theme.motion.medium,
                                curve: theme.motion.curves.out,
                                width: _wide ? 220 : 60,
                                height: 12,
                                color: theme.colors.primary,
                              ),
                              SizedBox(height: space.s),
                              SizedBox(
                                width: 140,
                                child: NeonButton(
                                  label: 'Move',
                                  filled: false,
                                  onPressed: () =>
                                      setState(() => _wide = !_wide),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const Section(
          title: 'The animation and the durations',
          child: YamlBox(
            label: 'neon_ui/lib/resources/themes/neon.yml',
            r'''
motion:
  durations: { fast: 120ms, medium: 250ms }
  curves: { out: ease-out }
animations:
  border-spin: { duration: 4s, curve: linear, repeat: loop }
  background-drift: { duration: 40s, curve: ease-in-out, repeat: reverse }''',
          ),
        ),
        const Section(
          title: 'The modal\'s group of tokens',
          child: YamlBox(
            label: 'neon_ui/lib/resources/themes/neon.yml',
            r'''
modal:
  width: 460
  barrier: transparent
  border:
    width: 1
    glow: 8
    glow-alpha: 0.6
    colors: [$neon.accent, $neon.cyan, $neon.pink, $neon.lavender]''',
          ),
        ),
      ],
    );
  }
}

class _ModalBody extends StatelessWidget {
  const _ModalBody();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      color: theme.colors.surface,
      padding: EdgeInsets.all(theme.spacing.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NeonLabel('Modal'),
          SizedBox(height: theme.spacing.s),
          Text('Save the changes?', style: theme.typography.titleLarge),
          SizedBox(height: theme.spacing.s),
          Text(
            'The border turns through the four colors of '
            'tokens.neon.modal.border.colors.',
            style: theme.typography.bodyMedium.copyWith(
              color: theme.colors.onSurfaceVariant,
            ),
          ),
          SizedBox(height: theme.spacing.l),
          Row(
            children: [
              Expanded(
                child: NeonButton(
                  label: 'Cancel',
                  filled: false,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              SizedBox(width: theme.spacing.m),
              Expanded(
                child: NeonButton(
                  label: 'Confirm',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
