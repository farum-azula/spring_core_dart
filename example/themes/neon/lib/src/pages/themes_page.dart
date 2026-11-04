import 'package:flutter/widgets.dart';
import 'package:neon_ui/neon_ui.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';
import 'package:theme_showcase_neon/src/app/theme_switcher.dart';
import 'package:theme_showcase_neon/src/widgets/page_frame.dart';
import 'package:theme_showcase_neon/src/widgets/section.dart';
import 'package:theme_showcase_neon/src/widgets/state_tile.dart';
import 'package:theme_showcase_neon/src/widgets/swatch.dart';
import 'package:theme_showcase_neon/src/widgets/yaml_box.dart';

typedef ThemesBeans = (ThemeSelection, SpringThemes);

/// Two themes: the library's `neon` and our `neon-ice`, which extends it.
class ThemesPage extends SpringStatelessWidget<ThemesBeans> {
  const ThemesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final (selection, themes) = beans;
    final theme = context.theme;
    final space = theme.spacing;
    return PageFrame(
      kicker: 'THEMES',
      title: 'Themes',
      intro:
          'neon comes from the library. neon-ice is this app\'s: it extends '
          'neon and changes the primary color, and the glow, the buttons and '
          'the modal border follow. Pick one: the whole app changes at once.',
      children: [
        Section(
          title: 'Switch',
          note:
              'ThemeSelection.select(AppThemes.neonIce): the names are '
              'constants the generator wrote.',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              for (final name in showcaseThemes)
                SizedBox(
                  width: 280,
                  height: theme.tokens.showcase.tileHeight,
                  child: StateTile(
                    selected: selection.active == name,
                    onPressed: () => selection.select(name),
                    child: _ThemeCard(name, themes.data(name)),
                  ),
                ),
            ],
          ),
        ),
        const Section(
          title: 'A theme that extends one',
          note: "Only what changes is written. \$neon.cyan is the library's token.",
          child: YamlBox(
            label: 'lib/resources/application.yml',
            r'''
neon-ice:
  extends: neon
  colors:
    primary: $neon.cyan
    secondary: $neon.yellow''',
          ),
        ),
        const Section(
          title: 'One value, written once',
          note:
              'The accent, the glow and the modal border all name the '
              'primary color, so nothing else changes in neon-ice.',
          child: YamlBox(
            label: 'neon_ui/lib/resources/themes/neon.yml',
            r'''
primary: $neon.yellow
accent: $colors.primary
glow: { color: $neon.accent, alpha: 35% }
colors: [$neon.accent, $neon.cyan, $neon.pink, $neon.lavender]''',
          ),
        ),
        Section(
          title: 'The current theme',
          child: Row(
            children: [
              const NeonLabel('active'),
              SizedBox(width: space.m),
              NeonBadge(selection.active),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard(this.name, this.data);

  final String name;
  final SpringThemeData data;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final scheme = data.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: theme.typography.titleLarge),
        SizedBox(height: theme.spacing.s),
        Text(
          name == AppThemes.neon ? 'from neon_ui' : 'extends neon',
          style: theme.typography.bodySmall.copyWith(
            color: theme.colors.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Wrap(
          spacing: theme.spacing.s,
          children: [
            Swatch('primary', scheme.primary),
            Swatch('secondary', scheme.secondary),
          ],
        ),
      ],
    );
  }
}
