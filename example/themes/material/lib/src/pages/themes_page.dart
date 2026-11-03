import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/widgets/styled_widgets.dart';
import 'package:theme_showcase_material/src/widgets/page_frame.dart';
import 'package:theme_showcase_material/src/widgets/section.dart';
import 'package:theme_showcase_material/src/widgets/yaml_box.dart';

typedef ThemesPageBeans = (
  ThemeSelection,
  SpringThemes,
);

/// Every theme of the app, side by side. Picking one is
/// `ThemeSelection.select(AppThemes.neon)`.
class ThemesPage extends SpringStatelessWidget<ThemesPageBeans> {
  const ThemesPage({super.key});

  /// The themes the app shows buttons for, by the constants of `AppThemes`.
  static const shown = [
    AppThemes.light,
    AppThemes.dark,
    AppThemes.ocean,
    AppThemes.oceanNight,
    AppThemes.neon,
    AppThemes.highContrast,
  ];

  @override
  Widget build(BuildContext context) {
    final (
      selection,
      themes,
    ) = beans;
    final space = context.theme.spacing;
    final text = Theme.of(context).textTheme;
    return PageFrame(
      title: context.messages.nav.themes,
      intro:
          'Six themes, one set of widgets. A theme holds only what it '
          'changes; `extends` starts it from another. The constants of '
          'AppThemes are generated, so a renamed theme stops compiling.',
      children: [
        Section(
          title: context.messages.themes.active(selection.active),
          note: 'Tap a card. system follows the device (light or dark).',
          child: Wrap(
            spacing: space.m,
            runSpacing: space.m,
            children: [
              for (final name in shown)
                _ThemeCard(
                  name: name,
                  data: themes.data(name),
                  selected: selection.active == name,
                  onPressed: () => selection.select(name),
                ),
              PillChip(
                'system',
                selected: selection.active == AppThemes.system,
                onPressed: () => selection.select(AppThemes.system),
              ),
            ],
          ),
        ),
        Section(
          title: 'light and dark',
          note:
              'light is the shared root; dark is the root with these '
              'changes.',
          child: const YamlBox(
            "dark:\n  seed-color: '#7986CB'\n  colors:\n    surface-container-low: grey.shade900",
            label: 'application.yml: themes',
          ),
        ),
        Section(
          title: 'extends',
          note:
              'ocean is light with a teal seed; ocean-night is ocean, dark. '
              'Both are in themes/ocean.yml, imported with '
              'spring.config.import.',
          child: const YamlBox(
            'ocean:\n'
            '  extends: light\n'
            '  seed-color: teal\n'
            '  scheme-variant: vibrant\n'
            'ocean-night:\n'
            '  extends: ocean\n'
            '  brightness: dark',
            label: 'themes/ocean.yml',
          ),
        ),
        Section(
          title: 'neon, high contrast, and one theme per file',
          note:
              'neon: dark, yellow, cyan and pink, a glowing border, a '
              'drifting grid. high-contrast: black on white and thick lines.',
          child: const YamlBox(
            'brightness: dark\n'
            "seed-color: '#F5E000'\n"
            'scheme-variant: fidelity\n'
            'contrast: 1',
            label: 'themes/neon.yml and themes/high-contrast.yml',
          ),
        ),
        Section(
          title: 'A theme from a URL',
          note:
              'A theme file can live on a server: it is downloaded, '
              'checked against a hash, cached, and replaced in the '
              'background. This app stays offline; the block is in '
              'application-network.yml, commented out.',
          child: const YamlBox(
            'themes:\n'
            '  brand:\n'
            '    source: https://themes.example.com/theme-showcase-material/brand.yml\n'
            '    refresh: 1h\n'
            '  brand-dark:\n'
            '    extends: brand\n'
            '    brightness: dark',
            label: 'application-network.yml',
          ),
        ),
        Section(
          title: 'Typed messages',
          note:
              'The texts of this page come from messages.properties through '
              'context.messages.themes.active(name), generated like the '
              'theme keys.',
          child: Text(
            context.messages.themes.switch$,
            style: text.titleMedium,
          ),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.name,
    required this.data,
    required this.selected,
    required this.onPressed,
  });

  final String name;
  final SpringThemeData data;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = data.colorScheme;
    return SizedBox(
      width: 200,
      child: TileCard(
        selected: selected,
        onPressed: onPressed,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final color in [
                  scheme.primary,
                  scheme.secondary,
                  scheme.tertiary,
                  scheme.surface,
                ])
                  Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outline),
                    ),
                  ),
              ],
            ),
            SizedBox(height: context.theme.spacing.s),
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            Text(
              data.brightness == Brightness.dark ? 'dark' : 'light',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
