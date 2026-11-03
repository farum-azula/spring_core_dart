import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/section.dart';
import 'package:theme_showcase_neon/src/widgets/yaml_box.dart';

/// The theme's background, a screen's own, and none.
class BackgroundPage extends StatelessWidget {
  const BackgroundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    return PageFrame(
      kicker: 'THEMEBACKGROUND',
      title: 'Background',
      intro:
          'The picture behind this page is not a widget in the app: the '
          'theme\'s background goes under every screen by itself. Three '
          'tiles show what a screen can ask for instead.',
      children: [
        Section(
          title: 'Three backgrounds',
          note:
              'The picture drifts (animations.background-drift); with less '
              'motion it stands still.',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: const [
              _Tile(
                'ThemeBackground',
                'the theme\'s background',
                ThemeBackground(child: _Caption('the picture and its veil')),
              ),
              _Tile(
                'ThemeBackground.screen',
                'screens.stage over it',
                ThemeBackground.screen(
                  'stage',
                  child: _Caption('a glow in the middle'),
                ),
              ),
              _Tile(
                'ThemeBackground.none',
                'an opaque surface',
                ThemeBackground.none(child: _Caption('no picture')),
              ),
            ],
          ),
        ),
        const Section(
          title: 'In the theme',
          child: YamlBox(
            label: 'neon_ui/lib/resources/themes/neon.yml',
            r'''
background:
  color: $colors.surface-container-lowest
  image:
    source: packages/neon_ui/assets/images/neon-background.jpg
    fit: cover
  overlay:
    gradient: { type: linear, begin: top, end: bottom, colors: [transparent, '#8007080D'] }
  animation: background-drift
  effect: drift
  transition: 400ms ease-out
  screens:
    stage:
      overlay:
        gradient: { type: radial, begin: center, colors: [{ color: $neon.accent, alpha: 22% }, transparent] }''',
          ),
        ),
        Section(
          title: 'Switching the theme changes the picture\'s glow',
          child: Text(
            'Switch to neon-ice on the left: the stage glow follows '
            r'$neon.accent, which follows $colors.primary.',
            style: theme.typography.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.title, this.note, this.background);

  final String title;
  final String note;
  final Widget background;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.typography.code),
          SizedBox(height: theme.spacing.xs),
          NeonLabel(note),
          SizedBox(height: theme.spacing.s),
          Container(
            height: 150,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colors.outline),
              borderRadius: BorderRadius.circular(theme.tokens.neon.radius),
            ),
            clipBehavior: Clip.antiAlias,
            child: background,
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(child: NeonLabel(text));
}
